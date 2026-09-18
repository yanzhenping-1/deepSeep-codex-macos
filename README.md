# DeepSeek × Codex for macOS

在 macOS 上同时保留 **OpenAI Codex、DeepSeek Flash、DeepSeek V4 Pro** 三套使用方式，并尽量不破坏现有配置和聊天记录。

> 当前 GitHub 仓库名是 `deepSeep-codex-macos`，其中 `Seep` 是拼写错误；项目中的脚本、目录和文档均使用正确的 `DeepSeek`。

## 方案结论

推荐把 CLI 与桌面端分开处理：

| 场景 | 方案 | 是否改动 `~/.codex/config.toml` | API Key 保存位置 |
|---|---|---:|---|
| Codex CLI 日常开发 | 独立 profile | 否 | macOS Keychain |
| Codex / ChatGPT 桌面端 | DeepSeek 官方配置器 | 是，官方脚本负责备份/恢复 | 官方脚本当前会写入本机配置文件 |

DeepSeek 已原生提供 Codex 所需的 Responses API，因此本项目不部署 Chat Completions → Responses 转换代理，也不修改 Codex `.app`、代码签名、`state_*.sqlite` 或聊天记录。

## 环境要求

- macOS
- Codex CLI `0.144.0` 或更高版本
- `curl`、`perl`、`awk`、`sed`、`shasum` 和 macOS `security`
- DeepSeek API Key

查看 Codex 版本：

```bash
codex --version
```

## 推荐安装：CLI 三套配置并存

```bash
git clone https://github.com/yanzhenping-1/deepSeep-codex-macos.git
cd deepSeep-codex-macos
./deepseek-codex-macos.sh install
```

安装过程会隐藏输入 DeepSeek API Key，并保存到 macOS Keychain。安装完成后：

```bash
codex-openai
codex-deepseek-flash
codex-deepseek-pro
```

也可以直接使用脚本：

```bash
./deepseek-codex-macos.sh run openai
./deepseek-codex-macos.sh run flash
./deepseek-codex-macos.sh run pro
```

如果 `~/.local/bin` 不在 PATH，加入 `~/.zshrc`：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

然后重新打开终端。

### CLI 安装写入的文件

```text
~/.codex/deepseek-flash.config.toml
~/.codex/deepseek-pro.config.toml
~/.codex/deepseek-codex-macos/models.vendor.json
~/.codex/deepseek-codex-macos/models.compat.json
~/.codex/deepseek-codex-macos/vendor-script.sha256
~/.local/bin/deepseek-codex-token
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

profile 通过 Codex 的 command-backed auth 在运行时调用本地 helper，从 macOS Keychain 读取 Bearer Token；TOML 和 wrapper 中均没有明文密钥。

wrapper 会在启动前检查 profile 是否存在、供应商和模型是否匹配，避免 profile 丢失时 Codex 静默回退到主配置并误用另一套额度。

> DeepSeek profile 内不建议用 `/model` 切换到 OpenAI 模型。需要切换供应商时，退出后运行对应的三个命令之一。

## 模型目录与兼容修复

安装时会：

1. 从 DeepSeek 官方 CDN 下载当前 Codex 配置脚本到临时目录。
2. 校验 DeepSeek API、Responses API、模型标识和模型目录标记。
3. 记录下载脚本的 SHA-256。
4. 只提取官方 `models.json`；CLI 安装阶段不会执行远程脚本。
5. 保存官方原始目录和一份兼容目录。

兼容目录当前应用两项上游规避措施：

- `multi_agent_version: "v2"` → `"v1"`：避免非 OpenAI Responses 供应商的子代理收到空任务。
- `supports_search_tool: true` → `false`：避免 MCP 工具被标记为 deferred，却没有可用的 `tool_search`。

官方原始目录始终保留，便于审计和在上游修复后移除补丁。

手动修复任意目录：

```bash
./deepseek-codex-macos.sh repair-catalog ~/.codex/models.json
```

脚本会先创建带时间戳的备份。

## Mac 桌面端

```bash
./deepseek-codex-macos.sh desktop
```

该命令会先下载、验证并显示 DeepSeek 官方配置器的 SHA-256，然后执行本机临时文件。官方交互菜单可切换：

- DeepSeek Flash（当前 `deepseek-flash`，支持图片输入）
- DeepSeek V4 Pro
- 恢复安装前的 OpenAI Codex 配置

切换后必须彻底退出并重新打开 Codex / ChatGPT 桌面应用。

### 桌面端限制

Codex Desktop 当前仍没有完整的 provider-aware 模型切换体验：

1. 自定义供应商可能显示为 `Custom`、供应商名或不完整模型名。
2. ChatGPT 登录会话与第三方 API Key 会话可能分组显示；“聊天消失”通常是当前认证/供应商分组不同。
3. `model_catalog_json` 是整份目录替换，不是追加，不能安全地在同一模型下拉框内混合全部 OpenAI 与 DeepSeek 模型。
4. DeepSeek 官方配置器当前可能把 API Key 明文写入 `~/.codex/config.toml`，文件权限应保持 `600`，不得提交到 Git 或截图分享。

因此，CLI profile 是推荐主方案；桌面端切换只作为明确了解这些边界时的兼容方案。

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

只移除本项目管理的 CLI 文件，保留 Keychain 密钥：

```bash
./deepseek-codex-macos.sh uninstall
```

同时删除 Keychain 中的 DeepSeek API Key：

```bash
./deepseek-codex-macos.sh uninstall --purge-key
```

卸载命令只删除带有项目管理标记的文件，并要求管理目录存在所有权 sentinel；无法识别的文件或目录会原样保留。

全局桌面端配置不会被卸载命令擅自改写。需要恢复桌面端时，运行 `desktop` 并选择 DeepSeek 官方恢复选项。

## 命令一览

```text
install                    安装 CLI profiles、Keychain 认证和三个 wrapper
run openai|flash|pro       按指定配置启动 Codex CLI
desktop                    下载并运行 DeepSeek 官方桌面端配置器
repair-catalog [path]      备份并修复模型目录兼容项
doctor [--api]             检查本机配置；--api 额外做真实请求
uninstall [--purge-key]    卸载项目文件；可选删除 Keychain 密钥
version                    显示版本
```

## 安全边界

- DeepSeek 模式下，提示词、代码上下文和工具输入会发送到 DeepSeek 托管 API。
- API Key 不写入仓库、wrapper、shell 参数或 CLI profile。
- CLI 安装只解析 DeepSeek 官方脚本中的模型 JSON；不会执行下载脚本。
- `desktop` 命令会执行官方配置器，因为桌面端需要其备份/恢复逻辑；运行前会做结构校验并显示 SHA-256。
- 不使用第三方中转站，不修改应用签名，不直接编辑聊天数据库。

详细设计见 [docs/DESIGN.md](docs/DESIGN.md)，安全说明见 [SECURITY.md](SECURITY.md)。

## 开发与测试

```bash
bash -n deepseek-codex-macos.sh
./tests/test.sh
```

测试使用临时目录、假 Keychain、假 Codex 和假下载器，不读取或修改真实的 `~/.codex`。
