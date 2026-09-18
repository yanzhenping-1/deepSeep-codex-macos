#!/usr/bin/env bash
DEFAULT_BASE_URL="https://api.deepseek.com"
# wire_api = "responses"
cat > /tmp/models.json <<'CODEX_MODELS_JSON'
{
  "models": [
    {
      "slug": "deepseek-flash",
      "display_name": "DeepSeek V4.1 Flash",
      "minimal_client_version": "0.144.0"
    },
    {
      "slug": "deepseek-v4-pro",
      "display_name": "DeepSeek V4 Pro",
      "minimal_client_version": "0.144.0"
    }
  ]
}
CODEX_MODELS_JSON
