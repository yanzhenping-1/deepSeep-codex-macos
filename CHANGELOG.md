# Changelog

## 1.0.0 — 2026-09-18

- Added isolated Codex profiles for OpenAI, DeepSeek Flash, and DeepSeek V4 Pro.
- Added macOS Keychain-backed DeepSeek authentication without storing the API key in CLI profiles.
- Forced DeepSeek profiles into API-key authentication so an existing ChatGPT login cannot silently route requests back to OpenAI.
- Added an auditable official model catalog plus compatibility patches for custom-provider subagents and MCP tool visibility.
- Added guarded install, diagnostics, API smoke testing, rollback, and uninstall commands.
- Added isolated macOS CI tests and detailed design and security documentation.
