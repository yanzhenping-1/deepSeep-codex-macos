#!/usr/bin/env bash
# Minimal fixture shaped like DeepSeek's official Codex setup script.
DEFAULT_BASE_URL="https://api.deepseek.com/"
# wire_api = "responses"
TMP_MODELS="/tmp/models.json"
cat > "$TMP_MODELS" <<'CODEX_MODELS_JSON'
{
  "models": [
    {
      "slug": "deepseek-flash",
      "multi_agent_version": "v2",
      "supports_search_tool": true,
      "input_modalities": ["text", "image"],
      "minimal_client_version": "0.144.0"
    },
    {
      "slug": "deepseek-v4-pro",
      "multi_agent_version": "v2",
      "supports_search_tool": true,
      "input_modalities": ["text"],
      "minimal_client_version": "0.144.0"
    }
  ]
}
CODEX_MODELS_JSON
