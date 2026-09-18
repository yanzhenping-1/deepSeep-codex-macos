#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-codex-macos-test.XXXXXX")"
cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT INT TERM

export HOME="$TEST_ROOT/home"
export USER="fixture-user"
export CODEX_HOME="$HOME/.codex"
export DEEPSEEK_CODEX_BIN_DIR="$HOME/.local/bin"
export DEEPSEEK_CODEX_TEST_MODE=1
export CURL_BIN="$ROOT/tests/fixtures/fake-curl.sh"
export SECURITY_BIN="$ROOT/tests/fixtures/fake-security.sh"
export SHASUM_BIN="$(command -v shasum)"
export PLUTIL_BIN="$TEST_ROOT/no-plutil"
export FAKE_VENDOR_SCRIPT="$ROOT/tests/fixtures/vendor-setup.sh"
export FAKE_KEYCHAIN_FILE="$TEST_ROOT/keychain-secret"

mkdir -p "$CODEX_HOME" "$TEST_ROOT/fake-bin"
cat > "$TEST_ROOT/fake-bin/codex" <<'CODEX'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'codex-cli 0.154.0-test\n'
else
  printf 'fake-codex:'
  printf ' <%s>' "$@"
  printf '\n'
fi
CODEX
chmod +x "$TEST_ROOT/fake-bin/codex"
export CODEX_BIN="$TEST_ROOT/fake-bin/codex"
export PATH="$TEST_ROOT/fake-bin:$DEEPSEEK_CODEX_BIN_DIR:$PATH"

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
[ -f "$CODEX_HOME/deepseek-codex-macos/models.json" ]
[ -x "$DEEPSEEK_CODEX_BIN_DIR/codex-openai" ]
[ -x "$DEEPSEEK_CODEX_BIN_DIR/codex-deepseek-flash" ]
[ -x "$DEEPSEEK_CODEX_BIN_DIR/codex-deepseek-pro" ]

grep -Fqx 'model = "deepseek-flash"' "$CODEX_HOME/deepseek-flash.config.toml"
grep -Fqx 'model = "deepseek-v4-pro"' "$CODEX_HOME/deepseek-pro.config.toml"
grep -Fqx 'command = "'$SECURITY_BIN'"' "$CODEX_HOME/deepseek-flash.config.toml"
! grep -R 'sk-test-secret' "$CODEX_HOME" "$DEEPSEEK_CODEX_BIN_DIR" >/dev/null

"$ROOT/deepseek-codex-macos.sh" doctor >/dev/null

FLASH_OUTPUT="$(codex-deepseek-flash hello)"
PRO_OUTPUT="$(codex-deepseek-pro hello)"
OPENAI_OUTPUT="$(codex-openai hello)"
case "$FLASH_OUTPUT" in *'<--profile> <deepseek-flash> <hello>'*) ;; *) echo "flash wrapper failed: $FLASH_OUTPUT" >&2; exit 1 ;; esac
case "$PRO_OUTPUT" in *'<--profile> <deepseek-pro> <hello>'*) ;; *) echo "pro wrapper failed: $PRO_OUTPUT" >&2; exit 1 ;; esac
case "$OPENAI_OUTPUT" in *'<hello>'*) ;; *) echo "openai wrapper failed: $OPENAI_OUTPUT" >&2; exit 1 ;; esac

"$ROOT/deepseek-codex-macos.sh" uninstall >/dev/null
[ -f "$CODEX_HOME/config.toml" ]
[ -f "$FAKE_KEYCHAIN_FILE" ]
[ ! -e "$CODEX_HOME/deepseek-flash.config.toml" ]
[ ! -e "$DEEPSEEK_CODEX_BIN_DIR/codex-deepseek-flash" ]

"$ROOT/deepseek-codex-macos.sh" install >/dev/null
"$ROOT/deepseek-codex-macos.sh" uninstall --purge-key >/dev/null
[ ! -e "$FAKE_KEYCHAIN_FILE" ]
[ -f "$CODEX_HOME/config.toml" ]

printf 'All isolated tests passed.\n'
