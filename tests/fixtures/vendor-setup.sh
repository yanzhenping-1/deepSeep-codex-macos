#!/usr/bin/env bash
# Minimal fixture shaped like the official DeepSeek Codex setup script.
DEFAULT_BASE_URL="https://api.deepseek.com/"
# wire_api = "responses"
TMP_MODELS="/tmp/models.json"
cat > "$TMP_MODELS" <<'CODEX_MODELS_JSON'
{
  "models": [
    {
      "slug": "deepseek-flash",
      "input_modalities": ["text", "image"],
      "multi_agent_version": "v2",
      "tool_mode": null,
      "supports_search_tool": true
    },
    {
      "slug": "deepseek-v4-pro",
      "input_modalities": ["text"],
      "multi_agent_version": "v2",
      "tool_mode": null,
      "supports_search_tool": true
    }
  ]
}
CODEX_MODELS_JSON
