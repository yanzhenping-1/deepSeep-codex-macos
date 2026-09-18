# DeepSeek × Codex for macOS

在 macOS 上同时保留 **OpenAI Codex、DeepSeek Flash、DeepSeek V4 Pro** 三套运行方式，并避免 CLI 配置覆盖现有 `~/.codex/config.toml`。

> 当前 GitHub 仓库名是 `deepSeep-codex-macos`，其中 `Seep` 是拼写错误；项目脚本、目录和文档统一使用正确的 `DeepSeek`。

## 方案结论

DeepSeek 现在原生支持 Codex 使用的 Responses API，因此无需部署 Chat Completions → Responses 本地代理，也不应修改 Codex 应用包、代码签名、SQLite 会话数据库或聊天记录。

本项目把两种使用场景分开处理：

| 场景 | 方案 | 是否改动 `~/.codex/config.toml` | API Key |
|---|---|---:|---|
| Codex CLI 日常开发 | Codex 独立 profile | 否 | macOS Keychain |
| Codex / ChatGPT 桌面端 | DeepSeek 官方配置器 | 是，官方脚本负责备份与恢复 | 官方脚本当前会写入本机配置文件 |

CLI profile 是推荐主方案。桌面端目前不能像 CLI 一样在启动时选择独立 profile，因此只能使用 DeepSeek 官方全局切换方案，并明确保留回滚路径。

## 环境要求

- macOS
- Codex CLI `0.144.0` 或更高版本
- `curl`、`awk`、`sed`、`shasum` 和 macOS `/usr/bin/security`
- DeepSeek API Key

查看版本：

```bash
codex --version
```

## 推荐安装：CLI 三套配置并存

```bash
git clone https://github.com/yanzhenping-1/deepSeep-codex-macos.git
cd deepSeep-codex-macos
./deepseek-codex-macos.sh install
```

安装时会隐藏输入 DeepSeek API Key，并将其保存到 macOS Keychain。完成后可直接运行：

```bash
codex-openai
codex-deepseek-flash
codex-deepseek-pro
```

也可以使用项目脚本：

```bash
./deepseek-codex-macos.sh run openai
./deepseek-codex-macos.sh run flash
./deepseek-codex-macos.sh run pro
```

如果 `~/.local/bin` 不在 PATH，把下面一行加入 `~/.zshrc`，然后重新打开终端：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 当前模型

- `deepseek-flash`：当前 Flash 模型，官方目录声明支持文本和图片输入。
- `deepseek-v4-pro`：V4 Pro 模型。
- OpenAI：继续使用你原来的 ChatGPT/Codex 登录和配置。

不要在 DeepSeek profile 内使用 `/model` 强行切到 OpenAI 模型。切换供应商时，应退出当前会话后运行上面的对应命令。

### CLI 安装写入的文件

```text
~/.codex/deepseek-flash.config.toml
~/.codex/deepseek-pro.config.toml
~/.codex/deepseek-codex-macos/models.vendor.json
~/.codex/deepseek-codex-macos/models.compat.json
~/.codex/deepseek-codex-macos/vendor-script.sha256
~/.local/bin/codex-openai
~/.local/bin/codex-deepseek-flash
~/.local/bin/codex-deepseek-pro
```

CLI 安装不会修改：

```text
~/.codex/config.toml
~/.codex/state_*.sqlite
~/.codex/sessions/
```

Codex 启动时先读取主配置，再用 `<name>.config.toml` 覆盖 profile 中的字段。因此已有的 MCP、沙箱、可信目录等非冲突设置仍会继承。

DeepSeek profile 会同时设置：

```toml
preferred_auth_method = "apikey"
forced_login_method = "api"
```

这两项很重要：它们确保已登录 ChatGPT 的 Codex 不会忽略自定义 provider 并继续把模型请求发往 OpenAI。

API Key 不写入 profile。Codex 的 command-backed auth 会在请求时直接调用 macOS Keychain。

wrapper 会在启动前检查 profile 是否存在、provider 和模型是否正确，避免缺失 profile 时 Codex 静默回退到主配置。

## 模型目录与兼容修复

安装过程会：

1. 从 DeepSeek 官方 CDN 下载当前 Codex 配置脚本到临时目录。
2. 校验 DeepSeek API、Responses API、当前模型标识和模型目录标记。
3. 记录下载脚本 SHA-256。
4. 只提取官方 `models.json`；CLI 安装阶段不会执行远程脚本。
5. 保存官方原始目录 `models.vendor.json`。
6. 生成实际使用的 `models.compat.json`。

兼容目录当前应用两个仍未在 Codex 上游解决的规避措施：

- `multi_agent_version: "v2"` → `"v1"`：避免第三方 Responses provider 的子代理收到空任务正文。
- `supports_search_tool: true` → `false`：避免 MCP 工具被延迟隐藏，但模型又拿不到可用的 `tool_search`。

官方原始目录始终保留，便于审计和未来移除补丁。

手动修复任意模型目录：

```bash
./deepseek-codex-macos.sh repair-catalog ~/.codex/models.json
```

脚本会先创建带时间戳的备份。

## Mac 桌面端

```bash
./deepseek-codex-macos.sh desktop
```

该命令会先下载 DeepSeek 官方配置器到临时目录，验证关键结构并显示 SHA-256，然后才执行本地文件。官方交互菜单可选择：

- DeepSeek Flash
- DeepSeek V4 Pro
- 选项 `9`：恢复安装前的 OpenAI Codex 配置

切换后必须彻底退出并重新打开 Codex/ChatGPT 桌面应用。

### 桌面端限制

1. 桌面端目前没有 CLI 那样的 `--profile` 启动入口。
2. 自定义 provider 可能显示为 `Custom`、供应商名或不完整模型名。
3. ChatGPT 登录会话与第三方 API Key 会话可能分组显示；看似“聊天消失”通常只是当前认证分组不同，并没有被删除。
4. `model_catalog_json` 是整份目录替换，不是追加，不能在一个模型下拉框里可靠地混合全部 OpenAI 与 DeepSeek 模型。
5. DeepSeek 官方配置器当前可能把 API Key 明文写入 `~/.codex/config.toml`。该文件应保持 `600` 权限，禁止提交到 Git、截图分享或粘贴到聊天。

因此，CLI profile 是推荐主方案；桌面端切换属于兼容方案。

## 自检

只检查本机配置，不调用付费 API：

```bash
./deepseek-codex-macos.sh doctor
```

增加一次极小的真实 Responses API 请求：

```bash
./deepseek-codex-macos.sh doctor --api
```

`--api` 会产生极少量 token 费用。

## 卸载

仅移除本项目管理的 CLI 文件，并保留 Keychain 密钥：

```bash
./deepseek-codex-macos.sh uninstall
```

同时删除 Keychain 中的 DeepSeek API Key：

```bash
./deepseek-codex-macos.sh uninstall --purge-key
```

卸载只删除带项目管理标记的 profile/wrapper，并要求管理目录存在所有权标记。无法识别的文件或目录会原样保留。

卸载不会擅自改写全局桌面配置。需要恢复桌面端时，运行 `desktop`，然后选择官方菜单的 `9`。

## 命令一览

```text
install                    安装 CLI profiles、Keychain 认证和三个 wrapper
run openai|flash|pro       按指定配置启动 Codex CLI
desktop                    下载并运行 DeepSeek 官方桌面配置器
repair-catalog [path]      备份并修复模型目录兼容项
doctor [--api]             检查本机配置；--api 额外做真实请求
uninstall [--purge-key]    卸载项目文件；可选删除 Keychain 密钥
version                    显示版本
```

## 安全边界

- DeepSeek 模式下，提示词、代码上下文和工具输入会发送到 DeepSeek 托管 API。
- API Key 不写入仓库、wrapper、shell 参数或 CLI profile。
- CLI 安装只解析 DeepSeek 官方脚本中的模型 JSON，不执行下载脚本。
- `desktop` 命令会执行官方配置器，因为桌面端需要其备份/恢复逻辑；运行前会做结构校验并显示 SHA-256。
- 不使用第三方中转站，不修改应用签名，不直接编辑聊天数据库。

详细设计见 [docs/DESIGN.md](docs/DESIGN.md)，安全说明见 [SECURITY.md](SECURITY.md)。

## 开发与测试

```bash
bash -n deepseek-codex-macos.sh
./tests/test.sh
```

测试使用临时目录、假 Keychain、假 Codex 和假下载器，不读取或修改真实的 `~/.codex`。
