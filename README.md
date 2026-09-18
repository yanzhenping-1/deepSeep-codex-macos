# DeepSeek × Codex for macOS

在 macOS 上同时保留 **OpenAI Codex、DeepSeek Flash、DeepSeek V4 Pro** 三套使用方式，并避免直接覆盖已有配置。

> 仓库目前的 GitHub 名称是 `deepSeep-codex-macos`，其中 `Seep` 是拼写错误；项目正文与命令均使用正确的 `DeepSeek`。

## 结论：怎样配置最合理

这个项目采用两条互不混淆的路线：

| 场景 | 推荐方式 | 是否改动 `~/.codex/config.toml` | API Key |
|---|---|---:|---|
| Codex CLI 日常开发 | 独立 profile（默认方案） | 否 | macOS 钥匙串 |
| Codex / ChatGPT 桌面端 | DeepSeek 官方配置器 | 是，官方脚本会备份 | 官方脚本目前会写入本机配置文件 |

CLI profile 是最稳妥的主方案：OpenAI 继续使用原配置，DeepSeek 仅在指定 profile 时生效。桌面端目前没有完善的 provider-aware 模型切换界面，因此采用 DeepSeek 官方配置器，并明确保留回滚路径。

## 为什么不再需要本地代理

DeepSeek 已原生支持 Codex 使用的 OpenAI Responses API，`base_url` 为 `https://api.deepseek.com`。因此本项目不会再部署 Chat Completions → Responses 的本地转换服务，也不会修改 Codex 应用包、SQLite 会话数据库或系统签名。

当前配置提供：

- `deepseek-flash`：当前 Flash 模型，支持图片输入。
- `deepseek-v4-pro`：Pro 模型。
- OpenAI：继续沿用你现有的 ChatGPT / Codex 登录与配置。

## 快速开始：推荐的 CLI 三配置

```bash
git clone https://github.com/yanzhenping-1/deepSeep-codex-macos.git
cd deepSeep-codex-macos
./deepseek-codex-macos.sh install
```

安装过程会隐藏输入 DeepSeek API Key，并将其保存到 macOS 钥匙串。之后可直接运行：

```bash
codex-openai
codex-deepseek-flash
codex-deepseek-pro
```

也可以不依赖 wrapper：

```bash
./deepseek-codex-macos.sh run openai
./deepseek-codex-macos.sh run flash
./deepseek-codex-macos.sh run pro
```

如果 `~/.local/bin` 尚未加入 PATH，把下面一行放入 `~/.zshrc`，然后重新打开终端：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### CLI 安装到底做了什么

脚本只创建这些用户文件：

```text
~/.codex/deepseek-flash.config.toml
~/.codex/deepseek-pro.config.toml
~/.codex/deepseek-codex-macos/models.vendor.json
~/.codex/deepseek-codex-macos/models.compat.json
~/.local/bin/deepseek-codex-token
~/.local/bin/codex-openai
~/.local/bin/codex-deepseek-flash
~/.local/bin/codex-deepseek-pro
```

它不会修改主配置 `~/.codex/config.toml`，也不会碰会话数据库或聊天记录。

模型目录来自 DeepSeek 官方配置脚本，但 CLI 安装流程只下载并提取其中的 JSON，不执行远程脚本。下载脚本的 SHA-256 会记录在：

```text
~/.codex/deepseek-codex-macos/vendor-script.sha256
```

## Mac 桌面端切换

执行：

```bash
./deepseek-codex-macos.sh desktop
```

脚本会先把 DeepSeek 官方配置器下载到临时目录，验证关键标记并显示 SHA-256，然后在本机执行其交互菜单。菜单可选择：

- DeepSeek Flash
- DeepSeek V4 Pro
- 恢复原来的 OpenAI Codex 配置

切换后必须彻底退出并重新打开 Codex / ChatGPT 桌面端。

### 桌面端必须知道的限制

1. 桌面端的自定义供应商模型栏仍不如 CLI profile 完整，可能显示 `Custom`、供应商名或不完整的模型名。
2. 使用 ChatGPT 登录创建的会话与使用第三方 API Key 创建的会话可能分组显示。看似“聊天消失”通常只是当前认证分组不同；恢复 OpenAI 配置并重启后会重新出现。
3. DeepSeek 官方配置器当前会把 API Key 写入 `~/.codex/config.toml`。该文件应保持权限 `600`，绝不能提交到 Git、截图分享或发到聊天中。
4. `model_catalog_json` 是整份模型目录替换，不是追加；所以桌面端不能在同一个模型下拉框里安全、原生地混合全部 OpenAI 与 DeepSeek 模型。

## 兼容性修复

DeepSeek 官方模型目录会随版本变化。本项目保留一份原始副本，并生成兼容副本，当前自动应用两项仍有上游未解决问题的规避措施：

- 将 `multi_agent_version` 从 `v2` 调整为 `v1`，避免自定义供应商的子代理收不到任务正文。
- 将 `supports_search_tool` 调整为 `false`（字段存在时），避免 MCP 工具被延迟隐藏却又没有可用的 `tool_search`。

桌面端官方配置器运行完后，本项目也会对 `~/.codex/models.json` 做同样处理，并在同目录留下时间戳备份。

手动修复任意模型目录：

```bash
./deepseek-codex-macos.sh repair-catalog ~/.codex/models.json
```

## 自检

不调用付费 API：

```bash
./deepseek-codex-macos.sh doctor
```

增加一次极小的真实 Responses API 请求：

```bash
./deepseek-codex-macos.sh doctor --api
```

真实 API 自检会产生极少量 token 费用。

## 卸载

仅移除本项目创建的 CLI profile、wrapper 和模型目录：

```bash
./deepseek-codex-macos.sh uninstall
```

同时删除钥匙串中的 DeepSeek API Key：

```bash
./deepseek-codex-macos.sh uninstall --purge-key
```

卸载命令不会擅自改动全局桌面端配置。需要恢复桌面端时，再次运行：

```bash
./deepseek-codex-macos.sh desktop
```

然后选择 DeepSeek 官方菜单中的恢复选项。

## 安全边界

- DeepSeek 模式下，提示词、所选代码与工具上下文会发送到 DeepSeek 托管 API。先确认项目数据允许交给第三方模型服务处理。
- API Key 不进入仓库，不写入 profile，也不通过命令行参数传递。
- CLI 的 Bearer Token 由 Codex 的 command-backed auth 在运行时从 macOS 钥匙串读取。
- 不修改 Codex `.app`、不重签名、不直接编辑 `state_*.sqlite`。
- 不使用第三方中转站或本地协议翻译代理。

## 命令一览

```text
install                    安装 CLI profiles、钥匙串认证和三个 wrapper
run openai|flash|pro       按指定配置启动 Codex CLI
desktop                    下载并运行 DeepSeek 官方桌面端配置器
repair-catalog [path]      备份并修复模型目录兼容项
doctor [--api]             检查配置；--api 会做一次真实请求
uninstall [--purge-key]    卸载项目文件；可选删除钥匙串密钥
version                    显示版本
```

## 开发与测试

```bash
bash -n deepseek-codex-macos.sh
./tests/test.sh
```

测试只使用临时 HOME、假的钥匙串与假的下载器，不读取或修改真实的 `~/.codex`。

更多设计取舍见 [docs/DESIGN.md](docs/DESIGN.md)，安全说明见 [SECURITY.md](SECURITY.md)。
