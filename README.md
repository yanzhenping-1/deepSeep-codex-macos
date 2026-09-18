# DeepSeek × Codex for macOS

在 macOS 上并存 **OpenAI Codex、DeepSeek Flash、DeepSeek V4 Pro** 三套使用方式，同时尽量不破坏现有配置、MCP 和聊天记录。

> 当前 GitHub 仓库名是 `deepSeep-codex-macos`，其中 `Seep` 是拼写错误；脚本、目录和文档均使用正确的 `DeepSeek`。

## 方案结论

最稳妥的实现不是本地协议代理，也不是修改 Codex 应用包或会话数据库，而是分成两条路径：

| 场景 | 方案 | 是否改动 `~/.codex/config.toml` | API Key 保存位置 |
|---|---|---:|---|
| Codex CLI 日常开发 | 独立 profile 文件 | 否 | macOS Keychain |
| Codex / ChatGPT 桌面端 | DeepSeek 官方配置器 | 是，官方脚本负责备份/恢复 | 官方脚本当前会写入本机配置文件 |

Codex 0.134+ 支持把 `$CODEX_HOME/<name>.config.toml` 叠加到主配置，并通过 `codex --profile <name>` 选择。本项目要求 Codex CLI **0.144.0 或更高版本**，既满足该 profile 格式，也满足 DeepSeek 当前模型目录声明的最低客户端版本。

DeepSeek 已原生支持 Codex 使用的 Responses API，因此本项目不部署 Chat Completions → Responses 转换代理，不修改 `.app`、代码签名、`state_*.sqlite` 或聊天记录。

## 环境要求

- macOS
- Codex CLI `0.144.0` 或更高版本
- `curl`、`perl`、`awk`、`sed`、`shasum` 和 macOS `security`
- DeepSeek API Key

查看 Codex 版本：

```bash
codex --version
```

## 推荐安装：CLI 三套入口

```bash
git clone https://github.com/yanzhenping-1/deepSeep-codex-macos.git
cd deepSeep-codex-macos
./deepseek-codex-macos.sh install
```

安装过程会隐藏输入 DeepSeek API Key，并保存到 macOS Keychain。完成后使用：

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

### 三个入口分别做什么

- `codex-openai`：直接启动你的基础 Codex 配置。本项目安装时不会修改该配置，所以在正常 CLI 用法下它仍是原有 OpenAI/ChatGPT 配置。
- `codex-deepseek-flash`：加载 `~/.codex/deepseek-flash.config.toml`，使用当前标准模型名 `deepseek-flash`。
- `codex-deepseek-pro`：加载 `~/.codex/deepseek-pro.config.toml`，模型名为 `deepseek-v4-pro`。

`codex-openai` 本质上是“未叠加 DeepSeek profile 的基础配置”。如果你另外执行过本项目的 `desktop` 命令，DeepSeek 官方配置器会修改全局主配置；此时应先在官方菜单中选择恢复，再使用 `codex-openai`。

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

profile 通过 Codex 的 command-backed auth 在运行时直接调用 macOS Keychain，不在 TOML 或 wrapper 中保存明文密钥。

DeepSeek wrapper 会在启动前校验 profile 是否存在、供应商和模型是否匹配。这样能避免 profile 丢失时 Codex 静默回退到基础配置，导致请求被发往错误供应商。

> 在 DeepSeek profile 内不建议通过 `/model` 切换到 OpenAI 模型。需要切换供应商时，退出当前会话并运行对应入口。

## 模型目录与兼容修复

安装时会：

1. 从 DeepSeek 官方 CDN 下载当前 Codex 配置脚本到临时目录。
2. 校验 DeepSeek API、Responses API、模型标识和模型目录标记。
3. 记录下载脚本的 SHA-256。
4. 只提取官方 `models.json`；CLI 安装阶段不会执行下载脚本。
5. 保存官方原始目录和一份兼容目录。

兼容目录当前应用两项针对已知 Codex 上游问题的规避措施：

- `multi_agent_version: "v2"` → `"v1"`：避免非 OpenAI Responses 供应商的子代理收不到任务正文。
- `supports_search_tool: true` → `false`：避免 MCP 工具被延迟隐藏，但会话中又没有可用 `tool_search`。

官方原始目录始终保留，便于审计以及上游修复后移除补丁。

手动修复任意模型目录：

```bash
./deepseek-codex-macos.sh repair-catalog ~/.codex/models.json
```

脚本会先创建带时间戳的备份。

## Mac 桌面端

```bash
./deepseek-codex-macos.sh desktop
```

该命令会先下载、验证并显示 DeepSeek 官方配置器的 SHA-256，然后执行本机临时文件。官方交互菜单可切换：

- DeepSeek Flash
- DeepSeek V4 Pro
- 恢复安装前的 OpenAI Codex 配置（当前官方菜单为选项 9）

切换后必须彻底退出并重新打开 Codex / ChatGPT 桌面应用。

### 桌面端限制

Codex Desktop 当前仍没有完整的 provider-aware 切换体验：

1. 自定义供应商可能显示为 `Custom`、供应商名或模型名，具体取决于客户端版本。
2. ChatGPT 登录会话与第三方 API Key 会话可能分组显示；看似“聊天消失”通常只是当前认证分组不同，并非数据被删除。
3. `model_catalog_json` 是整份目录替换，不是追加，不能安全地在同一模型下拉框内混合全部 OpenAI 与 DeepSeek 模型。
4. DeepSeek 官方配置器当前可能把 API Key 明文写入 `~/.codex/config.toml`；文件权限应保持 `600`，不得提交到 Git 或截图分享。

因此，CLI profile 是推荐主方案；桌面端切换只作为明确理解这些边界时的兼容方案。

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

卸载只删除带项目管理标记的文件，并要求管理目录存在所有权 sentinel；无法识别的文件或目录会原样保留。

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

## 参考

- [OpenAI Codex configuration reference](https://developers.openai.com/codex/config-reference/)
- [DeepSeek: Integrate with Codex](https://api-docs.deepseek.com/quick_start/agent_integrations/codex/)
