# 设计说明

## 目标

在同一台 Mac 上并存 OpenAI Codex、DeepSeek Flash 和 DeepSeek V4 Pro，同时满足：

1. CLI 日常使用不覆盖 `~/.codex/config.toml`。
2. API Key 不写入仓库、profile 或 shell 历史。
3. 使用 DeepSeek 原生 Responses API，不引入无必要的协议代理。
4. 配置变化可审计、可自检、可安全卸载。
5. 桌面端限制明确，不伪装成和 CLI 一样成熟。

## CLI：独立 profile

Codex 支持在 `CODEX_HOME` 下放置 `<name>.config.toml`，并通过：

```bash
codex --profile <name>
```

加载。项目创建：

```text
deepseek-flash.config.toml
deepseek-pro.config.toml
```

两份 profile 只覆盖模型、供应商、模型目录和供应商认证；其余配置继续继承主配置。因此 MCP、沙箱、可信目录等用户设置仍可复用，而主配置不需要被重写。

三个 wrapper 负责：

- `codex-openai`：直接启动原 Codex。
- `codex-deepseek-flash`：检查 Flash profile 存在后加载。
- `codex-deepseek-pro`：检查 Pro profile 存在后加载。

profile 缺失时 wrapper 失败关闭，而不是让 Codex 静默回退到主配置。

## 认证：Keychain + command-backed auth

profile 使用：

```toml
[model_providers.deepseek.auth]
command = "/usr/bin/security"
args = ["find-generic-password", "-a", "...", "-s", "...", "-w"]
```

Codex 在请求前执行该命令，并把标准输出作为 Bearer Token。profile 只保存 Keychain 条目的 service/account，不保存密钥。

这样不依赖 `.zshrc` 导出环境变量，也不会把密钥作为长期环境变量传给子进程。

## 模型目录：运行时提取官方版本

把某个时点的完整 `models.json` 固化到仓库容易过期。安装流程改为：

1. 下载 DeepSeek 官方配置脚本到临时文件。
2. 校验预期 API、Responses wire、模型 slug 和 heredoc 标记。
3. 记录 SHA-256。
4. 提取 `CODEX_MODELS_JSON` heredoc。
5. 校验 JSON 和两个目标模型。
6. 保存 `models.vendor.json`。
7. 生成 `models.compat.json`。

CLI 安装不会执行下载到的官方脚本。

## 当前兼容补丁

### Multi-agent V2 → V1

非 OpenAI Responses 供应商当前无法消费 Codex Multi-agent V2 的 OpenAI 特有 `encrypted_content`/`agent_message` 任务载荷。结果是子代理创建成功，但收到空任务。

兼容目录把：

```json
"multi_agent_version": "v2"
```

改为：

```json
"multi_agent_version": "v1"
```

V1 使用普通用户输入传递任务，可避免该兼容问题。

### `supports_search_tool` → false

官方 DeepSeek 目录当前会把 `supports_search_tool` 设为 true，同时 `tool_mode` 不是可用的 code-mode 工具发现路径。Codex 因此会把 MCP 工具标记为 Deferred，却没有向模型暴露可用 `tool_search`，导致 MCP 工具静默不可见。

兼容目录把该字段改为 false，使 MCP 工具直接进入模型可见工具列表。该字段不控制 DeepSeek 托管 web search 本身。

## 桌面端

Codex Desktop 当前没有完整的供应商选择器，也不能自然使用 CLI 的 `--profile`。`model_catalog_json` 又是替换整份目录而非追加。

因此桌面端不由本项目自行“模拟切换器”，而是调用 DeepSeek 官方配置器，复用其：

- 原配置备份；
- TOML 清理和写入；
- 模型目录生成；
- 恢复默认配置。

本项目只在执行前做结构校验与 SHA-256 展示，并在官方脚本结束后应用同样的模型目录兼容补丁。

## 写入与删除安全

- 文件通过同目录临时文件 + `mv` 原子替换。
- 覆盖非本项目管理的同名文件前先创建时间戳备份。
- 管理目录必须以 `deepseek-codex-macos` 结尾。
- 管理目录内写入所有权 sentinel。
- 卸载只删除带管理标记的 profile/wrapper；递归删除管理目录前必须校验 sentinel。
- `~/.codex/config.toml`、聊天数据库和 sessions 目录不在 CLI 卸载范围。

## 明确不做的事

- 不运行 Chat Completions → Responses 本地转换代理。
- 不修改、注入或重新签名 Codex / ChatGPT 应用包。
- 不直接编辑 `state_*.sqlite` 或 rollout JSONL 来伪造模型/迁移聊天。
- 不把 OpenAI 与 DeepSeek 模型硬拼进同一个替换型桌面目录。
- 不提交 API Key、真实用户配置或备份文件。
