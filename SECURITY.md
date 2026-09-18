# Security Policy

## 不要提交或粘贴

- DeepSeek/OpenAI API Key 或任何完整 `sk-...` 字符串
- `~/.codex/config.toml` 原文件
- Keychain 导出内容
- 包含私有代码、客户数据、内部 URL 或访问令牌的日志

密钥一旦泄漏，应立即在对应平台撤销并重新生成；只删除 Git 提交或 Issue 不足以消除风险。

## CLI 凭据处理

推荐安装把 DeepSeek API Key 保存到 macOS Keychain。profile 通过 Codex command-backed auth 调用 `/usr/bin/security` 读取密钥，只保存 Keychain service/account 元数据。

密钥不会写入：

- 仓库
- profile
- wrapper
- shell 历史

安装脚本调用 macOS `security add-generic-password` 写入 Keychain。与其他本机命令一样，拥有同一用户会话调试权限的恶意进程仍可能构成本地威胁；本项目不能替代安全的 macOS 账户和终端环境。

## 桌面端风险

`desktop` 命令运行 DeepSeek 官方配置器。按其当前实现，密钥可能以 Bearer Token 形式明文写入 `~/.codex/config.toml`。项目会尝试把该文件权限收紧为 `600`，但这仍属于本机明文存储。

对“密钥不得明文落盘”有硬性要求的环境，应只使用 CLI profile 路线。

## 供应链边界

CLI 安装从 DeepSeek 官方 CDN 下载配置脚本，但不会执行它，只提取并校验模型 JSON，同时记录 SHA-256。

`desktop` 命令必须执行官方配置器。运行前会检查关键结构并展示 SHA-256，但这不是数字签名验证。高安全环境应把经过组织审计的脚本放在内部 HTTPS 地址，并通过：

```bash
DEEPSEEK_CODEX_SETUP_URL=https://internal.example/codex-deepseek-setup.sh \
  ./deepseek-codex-macos.sh desktop
```

指向审核副本。

## 报告问题

创建 Issue 前，请用占位符替换密钥、用户名、绝对路径、私有仓库名和内部网络信息。只提供最小复现，不要上传完整 `.codex` 目录。
