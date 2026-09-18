# DeepSeek × Codex for macOS

在同一台 Mac 上并存以下三种启动方式：

- 现有 Codex / ChatGPT 默认配置
- DeepSeek Flash（当前模型名：`deepseek-flash`）
- DeepSeek V4 Pro（`deepseek-v4-pro`）

> 仓库当前名称是 `deepSeep-codex-macos`，其中 `Seep` 是拼写错误；代码与文档统一使用正确的 `DeepSeek`。

## 审查结论

合理的方案应区分 **Codex CLI** 与 **Codex / ChatGPT 桌面端**：

| 场景 | 方案 | 是否改动 `~/.codex/config.toml` | API Key |
|---|---|---:|---|
| CLI 日常开发 | Codex 独立 profile | 否 | macOS Keychain |
| 桌面端切换 | DeepSeek 官方配置器 | 是，官方脚本负责备份/恢复 | 官方配置器管理 |

本项目默认采用 CLI profile。它不部署协议转换代理，不修改应用包、代码签名、聊天数据库或会话文件，也不对 DeepSeek 官方模型目录做未经验证的“兼容补丁”。

DeepSeek 已原生支持 Codex 所需的 Responses API；当前官方 Codex 配置使用 `deepseek-flash` 与 `deepseek-v4-pro`。Flash 支持图片输入。

## 环境要求

- macOS
- Codex CLI `0.144.0` 或更高版本
- DeepSeek API Key
- 系统自带的 `security`、`curl`、`shasum`、`awk`、`sed`

检查 Codex 版本：

```bash
codex --version
```

## 安装

```bash
git clone https://github.com/yanzhenping-1/deepSeep-codex-macos.git
cd deepSeep-codex-macos
./deepseek-codex-macos.sh install
```

安装时会隐藏输入 DeepSeek API Key，并保存到 macOS Keychain。随后可运行：

```bash
codex-openai
codex-deepseek-flash
codex-deepseek-pro
```

也可以直接调用项目脚本：

```bash
./deepseek-codex-macos.sh run openai
./deepseek-codex-macos.sh run flash
./deepseek-codex-macos.sh run pro
```

`codex-openai` 不复制或改写 OpenAI 凭据；它直接启动你原来的默认 Codex 配置。如果你此前运行过桌面端 DeepSeek 配置器并切换了全局配置，应先在官方菜单中选择恢复默认配置。

如果 `~/.local/bin` 尚未加入 PATH，把以下内容加入 `~/.zshrc`：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

然后重新打开终端。

## 安装内容

CLI 安装只创建或管理以下文件：

```text
~/.codex/deepseek-flash.config.toml
~/.codex/deepseek-pro.config.toml
~/.codex/deepseek-codex-macos/models.json
~/.codex/deepseek-codex-macos/vendor-script.sha256
~/.local/bin/codex-openai
~/.local/bin/codex-deepseek-flash
~/.local/bin/codex-deepseek-pro
```

不会修改：

```text
~/.codex/config.toml
~/.codex/auth.json
~/.codex/state_*.sqlite
~/.codex/sessions/
```

Codex 运行 DeepSeek profile 时，会通过 command-backed authentication 调用 macOS `security` 命令，从 Keychain 读取 Bearer Token；API Key 不写入 profile 或 wrapper。

模型目录来自 DeepSeek 官方一键配置脚本。安装流程只下载、校验并提取其中的 `models.json`，不会执行远程脚本。脚本 SHA-256 会记录到：

```text
~/.codex/deepseek-codex-macos/vendor-script.sha256
```

## 更新官方模型目录

DeepSeek 模型信息变化后可执行：

```bash
./deepseek-codex-macos.sh refresh-catalog
```

该命令重新下载官方配置脚本、校验关键标记、提取模型目录并记录 SHA-256；不会修改 API Key 或主配置。

## 桌面端切换

```bash
./deepseek-codex-macos.sh desktop
```

此命令会：

1. 把 DeepSeek 官方配置器下载到临时目录。
2. 校验 API 地址、Responses API、模型标识与模型目录标记。
3. 显示 SHA-256。
4. 在本机执行官方交互式配置器。

官方菜单可选择 DeepSeek Flash、DeepSeek V4 Pro，或恢复默认 Codex 配置。切换后需彻底退出并重新打开 Codex / ChatGPT 桌面应用。

### 桌面端边界

Codex Desktop 的第三方 provider 体验仍不等同于 CLI profile：自定义模型可能不会像内置 OpenAI 模型一样完整出现在模型选择器中；全局模型目录切换也可能影响当前会话分组。因此，本项目把 CLI profile 作为主方案，把官方配置器作为明确知晓影响后的桌面兼容方案。

官方配置器会改动共享的 `~/.codex/config.toml`，并可能把 API Key 写入该本机文件。不要提交、截图或分享该文件；脚本结束后本项目会尽量把权限收紧为 `600`。

## 自检

只检查本机配置，不产生 API 调用：

```bash
./deepseek-codex-macos.sh doctor
```

额外执行一次极小的真实 Responses API 请求：

```bash
./deepseek-codex-macos.sh doctor --api
```

`--api` 会产生少量 token 费用。

## 卸载

删除本项目管理的 CLI profile、wrapper 与模型目录，保留 Keychain 密钥：

```bash
./deepseek-codex-macos.sh uninstall
```

同时删除 Keychain 中的 DeepSeek API Key：

```bash
./deepseek-codex-macos.sh uninstall --purge-key
```

卸载仅删除带项目管理标记的文件；无法识别的同名文件会保留。卸载不会擅自改写桌面端全局配置。

## 命令一览

```text
install                    安装 CLI profiles、Keychain 认证和启动命令
run openai|flash|pro       按指定配置启动 Codex CLI
refresh-catalog            刷新 DeepSeek 官方模型目录
desktop                    运行 DeepSeek 官方桌面端配置器
doctor [--api]             检查配置；--api 额外发起真实请求
uninstall [--purge-key]    卸载项目文件；可选删除 Keychain 密钥
version                    显示项目版本
```

## 开发与测试

```bash
bash -n deepseek-codex-macos.sh tests/test.sh tests/fixtures/*.sh
./tests/test.sh
```

测试使用临时 HOME、假 Keychain、假 Codex 和假下载器，不读取或修改真实的 `~/.codex`。

设计取舍见 [docs/DESIGN.md](docs/DESIGN.md)，安全说明见 [SECURITY.md](SECURITY.md)。
