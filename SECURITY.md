# Security Policy

## 不要提交或分享

- DeepSeek/OpenAI API Key 或完整 `sk-...` 字符串
- `~/.codex/config.toml` 原文件
- Keychain 导出内容
- 含私有代码、客户数据、内部 URL 或访问令牌的日志

密钥一旦泄漏，应立即在对应平台撤销并重新生成；只删除 Git 提交或 Issue 不足以消除风险。

## CLI 凭据处理

推荐安装将 DeepSeek API Key 保存到 macOS Keychain。profile 使用 Codex 的 command-backed authentication 调用 `/usr/bin/security`，不会把密钥写入仓库、profile、wrapper 或 shell 历史。

安装时调用 `security add-generic-password` 将密钥写入 Keychain；`doctor --api` 会把密钥临时用于一次本机 `curl` 请求。高安全环境可只运行不带 `--api` 的本地检查。

## 桌面端风险

`desktop` 命令运行 DeepSeek 官方配置器。按照官方配置方式，它会修改共享的 `~/.codex/config.toml`，并可能把 API Key 存入该本机文件。脚本会尝试把权限设为 `600`，但这仍属于本机明文存储。

对“密钥不得明文落盘”有硬性要求的环境，应只使用 CLI profile 路线。

## 供应链边界

CLI 安装会从 DeepSeek 官方 CDN 下载配置脚本，但不会执行它，只提取并校验模型 JSON，并记录 SHA-256。

`desktop` 命令会执行官方配置器。关键标记检查与 SHA-256 展示可以帮助审计，但不等同于数字签名验证。高安全环境应先独立审核下载内容，或通过 `DEEPSEEK_CODEX_SETUP_URL` 指向组织内部审核过的 HTTPS 副本。

## 报告问题

创建 Issue 前请替换密钥、用户名、绝对路径、私有仓库名与内部网络信息。仅提供最小复现，不要上传完整 `.codex` 目录。
