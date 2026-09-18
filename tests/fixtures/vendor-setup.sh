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
      "display_name": "DeepSeek Flash",
      "multi_agent_version": "v2",
      "supports_search_tool": true
    },
    {
      "slug": "deepseek-v4-pro",
      "display_name": "DeepSeek V4 Pro",
      "multi_agent_version": "v2",
      "supports_search_tool": true
    }
  ]
}
CODEX_MODELS_JSON
