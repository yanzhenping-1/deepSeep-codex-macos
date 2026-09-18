#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-codex-macos-test.XXXXXX")"
cleanup() { rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT INT TERM

export HOME="$TMP_ROOT/home"
export USER="fixture-user"
export CODEX_HOME="$HOME/.codex"
export DEEPSEEK_CODEX_BIN_DIR="$HOME/.local/bin"
export DEEPSEEK_CODEX_TEST_MODE=1
export CURL_BIN="$ROOT/tests/fixtures/fake-curl.sh"
export SECURITY_BIN="$ROOT/tests/fixtures/fake-security.sh"
export PLUTIL_BIN="$TMP_ROOT/no-plutil"
export SHASUM_BIN="$(command -v shasum)"
export FAKE_VENDOR_SCRIPT="$ROOT/tests/fixtures/vendor-setup.sh"
export FAKE_KEYCHAIN_FILE="$TMP_ROOT/keychain-secret"

mkdir -p "$CODEX_HOME" "$TMP_ROOT/fake-bin"
cat > "$TMP_ROOT/fake-bin/codex" <<'CODEX'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'codex-cli 0.154.0-test\n'
else
  printf 'fake-codex:'
  for arg in "$@"; do printf ' <%s>' "$arg"; done
  printf '\n'
fi
CODEX
chmod +x "$TMP_ROOT/fake-bin/codex"
export CODEX_BIN="$TMP_ROOT/fake-bin/codex"
export PATH="$TMP_ROOT/fake-bin:$DEEPSEEK_CODEX_BIN_DIR:$PATH"

cat > "$CODEX_HOME/config.toml" <<'CONFIG'
# User-owned config sentinel.
[mcp_servers.demo]
command = "demo"
CONFIG
BEFORE_HASH="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"

export DEEPSEEK_API_KEY="sk-test-secret-never-print"
"$ROOT/deepseek-codex-macos.sh" install >/dev/null
unset DEEPSEEK_API_KEY

AFTER_HASH="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
[ "$BEFORE_HASH" = "$AFTER_HASH" ] || { echo "main config was modified" >&2; exit 1; }

[ -f "$CODEX_HOME/deepseek-flash.config.toml" ]
[ -f "$CODEX_HOME/deepseek-pro.config.toml" ]
[ -f "$CODEX_HOME/deepseek-codex-macos/.managed-by-deepseek-codex-macos" ]
[ -x "$DEEPSEEK_CODEX_BIN_DIR/codex-deepseek-flash" ]
[ -x "$DEEPSEEK_CODEX_BIN_DIR/codex-deepseek-pro" ]
[ -x "$DEEPSEEK_CODEX_BIN_DIR/codex-openai" ]

! grep -R 'sk-test-secret' "$CODEX_HOME" "$DEEPSEEK_CODEX_BIN_DIR" >/dev/null

grep -Fq '[model_providers.deepseek.auth]' "$CODEX_HOME/deepseek-flash.config.toml"
grep -Fq "command = \"$SECURITY_BIN\"" "$CODEX_HOME/deepseek-flash.config.toml"
grep -Fq '"multi_agent_version": "v2"' "$CODEX_HOME/deepseek-codex-macos/models.vendor.json"
grep -Fq '"supports_search_tool": true' "$CODEX_HOME/deepseek-codex-macos/models.vendor.json"
! grep -Fq '"multi_agent_version": "v2"' "$CODEX_HOME/deepseek-codex-macos/models.compat.json"
! grep -Fq '"supports_search_tool": true' "$CODEX_HOME/deepseek-codex-macos/models.compat.json"
grep -Fq '"multi_agent_version": "v1"' "$CODEX_HOME/deepseek-codex-macos/models.compat.json"
grep -Fq '"supports_search_tool": false' "$CODEX_HOME/deepseek-codex-macos/models.compat.json"

"$ROOT/deepseek-codex-macos.sh" doctor >/dev/null
"$ROOT/deepseek-codex-macos.sh" doctor --api >/dev/null

FLASH_OUTPUT="$(codex-deepseek-flash hello)"
PRO_OUTPUT="$(codex-deepseek-pro hello)"
OPENAI_OUTPUT="$(codex-openai hello)"
case "$FLASH_OUTPUT" in *'<--profile> <deepseek-flash> <hello>'*) ;; *) echo "flash wrapper failed: $FLASH_OUTPUT" >&2; exit 1 ;; esac
case "$PRO_OUTPUT" in *'<--profile> <deepseek-pro> <hello>'*) ;; *) echo "pro wrapper failed: $PRO_OUTPUT" >&2; exit 1 ;; esac
case "$OPENAI_OUTPUT" in *'<hello>'*) ;; *) echo "openai wrapper failed: $OPENAI_OUTPUT" >&2; exit 1 ;; esac

# Missing profiles must fail closed instead of silently falling back.
mv "$CODEX_HOME/deepseek-flash.config.toml" "$CODEX_HOME/deepseek-flash.config.toml.saved"
set +e
MISSING_OUTPUT="$(codex-deepseek-flash hello 2>&1)"
MISSING_STATUS=$?
set -e
[ "$MISSING_STATUS" -eq 78 ] || { echo "missing profile did not fail closed" >&2; exit 1; }
case "$MISSING_OUTPUT" in *'profile is missing'*) ;; *) echo "missing profile message absent" >&2; exit 1 ;; esac
mv "$CODEX_HOME/deepseek-flash.config.toml.saved" "$CODEX_HOME/deepseek-flash.config.toml"

# Catalog repair must create a backup and preserve valid JSON.
cp "$CODEX_HOME/deepseek-codex-macos/models.vendor.json" "$TMP_ROOT/manual-models.json"
"$ROOT/deepseek-codex-macos.sh" repair-catalog "$TMP_ROOT/manual-models.json" >/dev/null
! grep -Fq '"multi_agent_version": "v2"' "$TMP_ROOT/manual-models.json"
ls "$TMP_ROOT"/manual-models.json.before-deepseek-codex-macos-* >/dev/null

"$ROOT/deepseek-codex-macos.sh" uninstall >/dev/null
[ -f "$CODEX_HOME/config.toml" ]
[ -f "$FAKE_KEYCHAIN_FILE" ]
[ ! -e "$CODEX_HOME/deepseek-flash.config.toml" ]
[ ! -e "$DEEPSEEK_CODEX_BIN_DIR/codex-deepseek-flash" ]
[ ! -e "$CODEX_HOME/deepseek-codex-macos" ]

# Reinstall from retained Keychain entry, then purge it.
"$ROOT/deepseek-codex-macos.sh" install >/dev/null
"$ROOT/deepseek-codex-macos.sh" uninstall --purge-key >/dev/null
[ ! -e "$FAKE_KEYCHAIN_FILE" ]
[ -f "$CODEX_HOME/config.toml" ]

# Refuse a non-empty managed directory that lacks the ownership sentinel.
mkdir -p "$CODEX_HOME/deepseek-codex-macos"
printf 'foreign-data\n' > "$CODEX_HOME/deepseek-codex-macos/foreign.txt"
export DEEPSEEK_API_KEY="sk-test-second"
set +e
REFUSE_OUTPUT="$("$ROOT/deepseek-codex-macos.sh" install 2>&1)"
REFUSE_STATUS=$?
set -e
unset DEEPSEEK_API_KEY
[ "$REFUSE_STATUS" -ne 0 ]
case "$REFUSE_OUTPUT" in *'non-empty unowned directory'*) ;; *) echo "ownership refusal message absent" >&2; exit 1 ;; esac
[ -f "$CODEX_HOME/deepseek-codex-macos/foreign.txt" ]

printf 'All isolated tests passed.\n'
