# 设计说明

## 目标

本项目解决同一台 Mac 上并存原 Codex 配置、DeepSeek Flash 与 DeepSeek V4 Pro 的问题，优先保证：

1. CLI 安装不覆盖 `~/.codex/config.toml`。
2. API Key 不写入仓库、profile 或 wrapper。
3. 不引入 DeepSeek 已不再需要的 Responses 协议代理。
4. 不修改 Codex 应用包、签名、会话数据库与历史文件。
5. 所有项目写入均可识别、可诊断、可卸载。

## 为什么使用 profile 文件

Codex 支持位于 `$CODEX_HOME/<name>.config.toml` 的 profile 文件，并通过 `codex --profile <name>` 选择。profile 的优先级高于用户主配置，同时仍可继承主配置中的 MCP、沙箱、可信目录等共享设置。

项目创建两个 profile：

```text
deepseek-flash.config.toml
deepseek-pro.config.toml
```

三个 wrapper 分别启动现有默认配置、Flash profile 与 Pro profile。DeepSeek wrapper 在启动前检查 profile，避免文件丢失后静默回退到错误 provider。

## Keychain 认证

Codex 自定义 provider 支持 command-backed bearer token。profile 配置 `/usr/bin/security` 为 token command，并把 Keychain account/service 作为参数。Codex 发起请求时读取 token；TOML 文件中只有 Keychain 条目标识，没有 API Key。

## 官方模型目录

Codex 自定义模型需要 `model_catalog_json`。项目不在仓库内固定一份容易过期的完整目录，而是在安装或刷新时：

1. 下载 DeepSeek 官方 Codex 配置脚本。
2. 检查 `api.deepseek.com`、Responses API、两个模型标识和 `CODEX_MODELS_JSON`。
3. 从 heredoc 提取 `models.json`。
4. 校验 JSON 和模型 slug。
5. 保存目录并记录源脚本 SHA-256。

CLI 路线不会执行下载到的官方脚本，也不会擅自重写模型目录字段。

## 桌面端

Codex Desktop 与 CLI 共用用户配置，但 Desktop 对自定义 provider 的模型选择和会话呈现仍有限制。项目不模拟或修改 Desktop 内部数据库，而是把全局切换交给 DeepSeek 官方配置器。

`desktop` 命令执行前会先下载到临时文件、校验结构并显示 SHA-256。该路线会修改 `~/.codex/config.toml`，因此与完全隔离的 CLI profile 明确分开。

## 写入与删除安全

- 文件先写入同目录临时文件，再原子替换。
- 覆盖非项目管理的同名文件前创建时间戳备份。
- 管理目录必须以 `deepseek-codex-macos` 结尾。
- 管理目录包含 ownership sentinel。
- 卸载只删除带管理标记的 profile/wrapper；递归删除目录前必须验证 sentinel。
- 主配置、`auth.json`、数据库和 session 文件不属于 CLI 卸载范围。
