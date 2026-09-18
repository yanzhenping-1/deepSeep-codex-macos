# 设计说明

## 目标

在同一台 Mac 上并存 OpenAI Codex、DeepSeek Flash 和 DeepSeek V4 Pro，同时满足：

1. CLI 日常使用不覆盖 `~/.codex/config.toml`。
2. API Key 不写入仓库、profile 或 shell 历史。
3. 使用 DeepSeek 原生 Responses API，不引入协议代理。
4. 配置变化可审计、可自检、可安全卸载。
5. 桌面端限制明确，不假设它与 CLI profile 能力一致。

## CLI：独立 profile overlay

Codex CLI 0.134.0 起支持放在 `CODEX_HOME` 下的 `<name>.config.toml`，并通过：

```bash
codex --profile <name>
```

加载。profile 是高于用户 `config.toml` 的配置层，因此只需要写入有差异的字段。

本项目创建：

```text
deepseek-flash.config.toml
deepseek-pro.config.toml
```

三个 wrapper 负责：

- `codex-openai`：直接启动原 Codex。
- `codex-deepseek-flash`：校验并加载 Flash profile。
- `codex-deepseek-pro`：校验并加载 Pro profile。

Codex 对不存在的 standalone profile 会静默回退到主配置。因此 wrapper 在启动前检查文件、provider 和精确模型，失败时返回非零状态。

## 强制 API 登录模式

已登录 ChatGPT 的 Codex 可能优先走账号 websocket，即使配置了自定义 `model_provider`。DeepSeek 官方配置明确要求：

```toml
preferred_auth_method = "apikey"
forced_login_method = "api"
```

这两个字段放在每个 DeepSeek profile 中，只在启动该 profile 时覆盖主配置；`codex-openai` 不受影响。

## 认证：Keychain + command-backed auth

profile 使用：

```toml
[model_providers.deepseek.auth]
command = "/usr/bin/security"
args = ["find-generic-password", "-a", "...", "-s", "...", "-w"]
timeout_ms = 5000
refresh_interval_ms = 0
```

Codex 执行该命令并把标准输出作为 Bearer Token。profile 只保存 Keychain service/account，不保存密钥。

这也避免依赖 `.zshrc` 中的环境变量；从 Finder 或终端启动时都能读取相同凭据。

## 模型目录：运行时提取官方版本

将某个时点的完整 `models.json` 固化进仓库容易过期。安装流程改为：

1. 下载 DeepSeek 官方配置脚本到临时文件。
2. 校验 API、Responses wire、当前模型 slug 和 heredoc 标记。
3. 记录 SHA-256。
4. 提取 `CODEX_MODELS_JSON` heredoc。
5. 校验 JSON 和两个目标模型。
6. 保存 `models.vendor.json`。
7. 生成 `models.compat.json`。

CLI 安装不会执行下载到的官方脚本。

## 当前兼容补丁

### Multi-agent V2 → V1

Codex Multi-agent V2 目前会把第三方 provider 的子代理任务正文放入 OpenAI 特有的 `encrypted_content`。DeepSeek Responses API 无法消费该内容，子代理会收到空任务。

兼容目录把：

```json
"multi_agent_version": "v2"
```

改为：

```json
"multi_agent_version": "v1"
```

V1 使用普通用户输入传递任务。

### `supports_search_tool` → false

DeepSeek 官方目录当前组合为：

```json
"supports_search_tool": true,
"tool_mode": null
```

在现行 Codex 中，这可能让 MCP 工具被标记为 Deferred，同时没有把 `tool_search` 暴露给模型，最终所有 `mcp__*` 工具都不可见。

兼容目录把 `supports_search_tool` 改为 `false`，让 MCP 工具直接出现在模型可见工具列表。该字段不控制 DeepSeek 托管 web search；项目另外将 Codex 内置 `web_search` 设为 `disabled`。

## 桌面端

Codex Desktop 当前无法在启动时选择 standalone profile，而且自定义目录会替换内置模型目录而不是合并。

因此桌面端不由项目自行模拟切换器，而是调用 DeepSeek 官方配置器，复用其：

- 原配置备份；
- TOML 冲突字段清理；
- 模型目录生成；
- 恢复默认配置。

项目只在执行前做结构校验与 SHA-256 展示，并在官方脚本结束后对 `models.json` 应用相同的兼容补丁。

## 写入与删除安全

- 文件通过同目录临时文件加 `mv` 原子替换。
- 覆盖非项目管理的同名 profile/wrapper 前先创建时间戳备份。
- 管理目录必须以 `deepseek-codex-macos` 结尾，且不能是符号链接。
- 管理目录内写入所有权 sentinel。
- 卸载只删除带管理标记的 profile/wrapper；递归删除管理目录前必须校验 sentinel。
- `~/.codex/config.toml`、聊天数据库和 sessions 目录不在 CLI 卸载范围。

## 明确不做的事

- 不运行 Chat Completions → Responses 本地转换代理。
- 不修改、注入或重新签名 Codex/ChatGPT 应用包。
- 不直接编辑 `state_*.sqlite` 或 rollout JSONL 来伪造模型、迁移聊天。
- 不把 OpenAI 与 DeepSeek 模型硬拼进一个替换型桌面目录。
- 不提交 API Key、真实用户配置或备份文件。
