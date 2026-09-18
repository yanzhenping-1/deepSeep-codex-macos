#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="deepseek-codex-macos"
PROGRAM_VERSION="1.0.0"
MIN_CODEX_VERSION="0.144.0"
OFFICIAL_SETUP_URL_DEFAULT="https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh"
KEYCHAIN_SERVICE_DEFAULT="dev.deepseek-codex-macos.api-key"

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
MANAGED_DIR="${DEEPSEEK_CODEX_MANAGED_DIR:-$CODEX_DIR/$PROGRAM_NAME}"
BIN_DIR="${DEEPSEEK_CODEX_BIN_DIR:-$HOME/.local/bin}"
OFFICIAL_SETUP_URL="${DEEPSEEK_CODEX_SETUP_URL:-$OFFICIAL_SETUP_URL_DEFAULT}"
KEYCHAIN_SERVICE="${DEEPSEEK_CODEX_KEYCHAIN_SERVICE:-$KEYCHAIN_SERVICE_DEFAULT}"
KEYCHAIN_ACCOUNT="${DEEPSEEK_CODEX_KEYCHAIN_ACCOUNT:-${USER:-$(id -un)}}"

PROFILE_FLASH="$CODEX_DIR/deepseek-flash.config.toml"
PROFILE_PRO="$CODEX_DIR/deepseek-pro.config.toml"
CATALOG_VENDOR="$MANAGED_DIR/models.vendor.json"
CATALOG_COMPAT="$MANAGED_DIR/models.compat.json"
VENDOR_HASH_FILE="$MANAGED_DIR/vendor-script.sha256"
MANAGED_SENTINEL="$MANAGED_DIR/.managed-by-$PROGRAM_NAME"
WRAPPER_FLASH="$BIN_DIR/codex-deepseek-flash"
WRAPPER_PRO="$BIN_DIR/codex-deepseek-pro"
WRAPPER_OPENAI="$BIN_DIR/codex-openai"

CURL_BIN="${CURL_BIN:-curl}"
SECURITY_BIN="${SECURITY_BIN:-/usr/bin/security}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
CODEX_BIN="${CODEX_BIN:-codex}"

TEMP_DIR=""
umask 077

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

say() { printf '%s\n' "$*"; }
info() { printf '• %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
DeepSeek for Codex on macOS — isolated CLI profiles and an official Desktop switcher

Usage:
  ./deepseek-codex-macos.sh install
  ./deepseek-codex-macos.sh run <openai|flash|pro> [-- <codex args...>]
  ./deepseek-codex-macos.sh desktop
  ./deepseek-codex-macos.sh repair-catalog [path]
  ./deepseek-codex-macos.sh doctor [--api]
  ./deepseek-codex-macos.sh uninstall [--purge-key]
  ./deepseek-codex-macos.sh version

After install:
  codex-openai
  codex-deepseek-flash
  codex-deepseek-pro

The CLI install never edits ~/.codex/config.toml.
USAGE
}

make_temp_dir() {
  if [ -z "$TEMP_DIR" ]; then
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${PROGRAM_NAME}.XXXXXX")"
  fi
}

require_macos() {
  if [ "${DEEPSEEK_CODEX_TEST_MODE:-0}" = "1" ]; then
    return 0
  fi
  [ "$(uname -s)" = "Darwin" ] || die "This utility supports macOS only."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_paths() {
  case "$MANAGED_DIR" in
    ""|/|"$HOME"|"$CODEX_DIR") die "Unsafe managed directory: $MANAGED_DIR" ;;
  esac
  [ "$(basename "$MANAGED_DIR")" = "$PROGRAM_NAME" ] || \
    die "Managed directory must end with /$PROGRAM_NAME: $MANAGED_DIR"
  case "$BIN_DIR" in
    ""|/) die "Unsafe bin directory: $BIN_DIR" ;;
  esac
}

prepare_managed_dir() {
  validate_paths
  if [ -d "$MANAGED_DIR" ] && [ ! -f "$MANAGED_SENTINEL" ]; then
    if [ -n "$(ls -A "$MANAGED_DIR" 2>/dev/null)" ]; then
      die "Refusing to use a non-empty unowned directory: $MANAGED_DIR"
    fi
  fi
  mkdir -p "$MANAGED_DIR"
  printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION" > "$MANAGED_SENTINEL"
  chmod 700 "$MANAGED_DIR"
  chmod 600 "$MANAGED_SENTINEL"
}

codex_version() {
  "$CODEX_BIN" --version 2>/dev/null | sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1
}

semver_ge() {
  local current="$1" required="$2"
  local c1 c2 c3 r1 r2 r3
  IFS=. read -r c1 c2 c3 <<EOF_VERSION
$current
EOF_VERSION
  IFS=. read -r r1 r2 r3 <<EOF_VERSION
$required
EOF_VERSION
  case "$c1$c2$c3$r1$r2$r3" in *[!0-9]*) return 1 ;; esac
  [ "$c1" -gt "$r1" ] && return 0
  [ "$c1" -lt "$r1" ] && return 1
  [ "$c2" -gt "$r2" ] && return 0
  [ "$c2" -lt "$r2" ] && return 1
  [ "$c3" -ge "$r3" ]
}

require_codex_version() {
  local current
  current="$(codex_version)"
  [ -n "$current" ] || die "Could not parse Codex version from: $CODEX_BIN --version"
  semver_ge "$current" "$MIN_CODEX_VERSION" || \
    die "Codex $MIN_CODEX_VERSION or newer is required; found $current."
}

sha256_file() {
  "$SHASUM_BIN" -a 256 "$1" | awk '{print $1}'
}

json_validate() {
  local path="$1"
  if [ -x "$PLUTIL_BIN" ] && "$PLUTIL_BIN" -lint "$path" >/dev/null 2>&1; then
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$path" >/dev/null 2>&1
    return $?
  fi
  return 1
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

shell_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

backup_if_unmanaged() {
  local path="$1"
  if [ -e "$path" ] && ! grep -q "Managed by $PROGRAM_NAME" "$path" 2>/dev/null; then
    local backup
    backup="$path.before-$PROGRAM_NAME-$(date '+%Y%m%d-%H%M%S')"
    cp -p "$path" "$backup"
    warn "Backed up pre-existing file: $backup"
  fi
}

atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-600}"
  local parent tmp
  parent="$(dirname "$destination")"
  mkdir -p "$parent"
  tmp="$parent/.${PROGRAM_NAME}.$$.tmp"
  cp "$source" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$destination"
}

fetch_official_setup() {
  local output="$1"
  info "Downloading DeepSeek's official Codex setup script for inspection"
  "$CURL_BIN" -fL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 \
    "$OFFICIAL_SETUP_URL" -o "$output"

  [ -s "$output" ] || die "Downloaded setup script is empty."
  grep -q 'api\.deepseek\.com' "$output" || die "Official script validation failed: API endpoint missing."
  grep -q 'wire_api.*responses' "$output" || die "Official script validation failed: Responses marker missing."
  grep -q 'CODEX_MODELS_JSON' "$output" || die "Official script validation failed: catalog marker missing."
  grep -q 'deepseek-flash' "$output" || die "Official script validation failed: deepseek-flash missing."
  grep -q 'deepseek-v4-pro' "$output" || die "Official script validation failed: deepseek-v4-pro missing."

  local digest
  digest="$(sha256_file "$output")"
  printf '%s  %s\n' "$digest" "$OFFICIAL_SETUP_URL" > "$VENDOR_HASH_FILE"
  chmod 600 "$VENDOR_HASH_FILE"
  ok "Official script inspected; SHA-256: $digest"
}

extract_catalog() {
  local script_path="$1" output="$2"
  awk '
    /CODEX_MODELS_JSON/ && /<</ { capture=1; next }
    capture && /^CODEX_MODELS_JSON[[:space:]]*$/ { exit }
    capture { print }
  ' "$script_path" > "$output"

  [ -s "$output" ] || die "Could not extract models.json from the official script."
  json_validate "$output" || die "Extracted model catalog is not valid JSON."
  grep -q '"slug"[[:space:]]*:[[:space:]]*"deepseek-flash"' "$output" || \
    die "Catalog does not contain deepseek-flash."
  grep -q '"slug"[[:space:]]*:[[:space:]]*"deepseek-v4-pro"' "$output" || \
    die "Catalog does not contain deepseek-v4-pro."
}

make_compat_catalog() {
  local source="$1" destination="$2"
  local temp
  make_temp_dir
  temp="$TEMP_DIR/models.compat.json"
  cp "$source" "$temp"

  # Current upstream workarounds for custom Responses providers:
  # - V2 subagent payloads arrive as OpenAI-only encrypted_content.
  # - supports_search_tool=true can defer MCP tools without exposing tool_search.
  perl -0pi -e 's/("multi_agent_version"\s*:\s*)"v2"/${1}"v1"/g; s/("supports_search_tool"\s*:\s*)true/${1}false/g' "$temp"

  json_validate "$temp" || die "Compatibility catalog is invalid after patching."
  atomic_install_file "$temp" "$destination" 600
}

keychain_has_key() {
  "$SECURITY_BIN" find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1
}

read_keychain_key() {
  "$SECURITY_BIN" find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w
}

store_keychain_key() {
  local key="$1"
  "$SECURITY_BIN" add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w "$key" -U >/dev/null
}

obtain_api_key() {
  local key="${DEEPSEEK_API_KEY:-}"
  if [ -z "$key" ] && keychain_has_key; then
    key="$(read_keychain_key)"
  fi
  if [ -z "$key" ]; then
    [ -r /dev/tty ] || die "No DeepSeek API key found. Set DEEPSEEK_API_KEY for this install."
    printf 'DeepSeek API key (input hidden): ' >/dev/tty
    IFS= read -r -s key </dev/tty || true
    printf '\n' >/dev/tty
  fi
  [ -n "$key" ] || die "No DeepSeek API key provided."
  case "$key" in *$'\n'*|*$'\r'*) die "API key must be a single line." ;; esac
  case "$key" in sk-*) ;; *) warn "The key does not start with sk-; verify it is a DeepSeek API key." ;; esac
  store_keychain_key "$key"
  unset key DEEPSEEK_API_KEY
  ok "API key stored in macOS Keychain"
}

write_profile() {
  local model="$1" destination="$2"
  local temp catalog_e security_e account_e service_e
  make_temp_dir
  temp="$TEMP_DIR/$(basename "$destination")"
  catalog_e="$(toml_escape "$CATALOG_COMPAT")"
  security_e="$(toml_escape "$SECURITY_BIN")"
  account_e="$(toml_escape "$KEYCHAIN_ACCOUNT")"
  service_e="$(toml_escape "$KEYCHAIN_SERVICE")"

  cat > "$temp" <<EOF_PROFILE
# Managed by $PROGRAM_NAME $PROGRAM_VERSION.
model = "$model"
model_provider = "deepseek"
model_reasoning_effort = "high"
model_catalog_json = "$catalog_e"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
supports_websockets = false

[model_providers.deepseek.auth]
command = "$security_e"
args = ["find-generic-password", "-a", "$account_e", "-s", "$service_e", "-w"]
timeout_ms = 5000
EOF_PROFILE

  backup_if_unmanaged "$destination"
  atomic_install_file "$temp" "$destination" 600
}

write_wrapper() {
  local destination="$1" profile="$2" profile_path="$3" expected_model="$4"
  local temp codex_q profile_q path_q model_line_q
  make_temp_dir
  temp="$TEMP_DIR/$(basename "$destination")"
  codex_q="$(shell_single_quote "$CODEX_BIN")"
  profile_q="$(shell_single_quote "$profile")"
  path_q="$(shell_single_quote "$profile_path")"
  model_line_q="$(shell_single_quote "model = \"$expected_model\"")"

  if [ -n "$profile" ]; then
    cat > "$temp" <<EOF_WRAPPER
#!/usr/bin/env bash
# Managed by $PROGRAM_NAME $PROGRAM_VERSION.
set -euo pipefail
PROFILE_FILE=$path_q
EXPECTED_MODEL_LINE=$model_line_q
if [ ! -r "\$PROFILE_FILE" ]; then
  printf 'DeepSeek Codex profile is missing: %s\nRun deepseek-codex-macos.sh install again.\n' "\$PROFILE_FILE" >&2
  exit 78
fi
if ! grep -Fqx 'model_provider = "deepseek"' "\$PROFILE_FILE"; then
  printf 'DeepSeek Codex profile is invalid: %s\nRun deepseek-codex-macos.sh install again.\n' "\$PROFILE_FILE" >&2
  exit 78
fi
if ! grep -Fqx "\$EXPECTED_MODEL_LINE" "\$PROFILE_FILE"; then
  printf 'DeepSeek Codex profile has the wrong model: %s\nRun deepseek-codex-macos.sh install again.\n' "\$PROFILE_FILE" >&2
  exit 78
fi
exec $codex_q --profile $profile_q "\$@"
EOF_WRAPPER
  else
    cat > "$temp" <<EOF_WRAPPER
#!/usr/bin/env bash
# Managed by $PROGRAM_NAME $PROGRAM_VERSION.
set -euo pipefail
exec $codex_q "\$@"
EOF_WRAPPER
  fi

  backup_if_unmanaged "$destination"
  atomic_install_file "$temp" "$destination" 700
}

profile_check() {
  local profile="$1" expected_model="$2"
  [ -f "$profile" ] || return 1
  grep -Fqx "model = \"$expected_model\"" "$profile" || return 1
  grep -Fqx 'model_provider = "deepseek"' "$profile" || return 1
  grep -Fqx 'wire_api = "responses"' "$profile" || return 1
  grep -Fqx '[model_providers.deepseek.auth]' "$profile" || return 1
}

install_profiles() {
  require_macos
  validate_paths
  require_command "$CODEX_BIN"
  require_command "$CURL_BIN"
  require_command "$SECURITY_BIN"
  require_command "$SHASUM_BIN"
  require_command awk
  require_command sed
  require_command perl
  require_codex_version

  mkdir -p "$CODEX_DIR" "$BIN_DIR"
  prepare_managed_dir
  obtain_api_key

  make_temp_dir
  local vendor_script extracted
  vendor_script="$TEMP_DIR/deepseek-official-setup.sh"
  extracted="$TEMP_DIR/models.vendor.json"
  fetch_official_setup "$vendor_script"
  extract_catalog "$vendor_script" "$extracted"
  atomic_install_file "$extracted" "$CATALOG_VENDOR" 600
  make_compat_catalog "$CATALOG_VENDOR" "$CATALOG_COMPAT"

  write_profile "deepseek-flash" "$PROFILE_FLASH"
  write_profile "deepseek-v4-pro" "$PROFILE_PRO"
  write_wrapper "$WRAPPER_FLASH" "deepseek-flash" "$PROFILE_FLASH" "deepseek-flash"
  write_wrapper "$WRAPPER_PRO" "deepseek-pro" "$PROFILE_PRO" "deepseek-v4-pro"
  write_wrapper "$WRAPPER_OPENAI" "" "" ""

  ok "Installed isolated DeepSeek Codex profiles"
  say ""
  say "Commands:"
  say "  $WRAPPER_OPENAI"
  say "  $WRAPPER_FLASH"
  say "  $WRAPPER_PRO"
  if ! printf '%s' ":$PATH:" | grep -Fq ":$BIN_DIR:"; then
    warn "$BIN_DIR is not in PATH. Add this to ~/.zshrc:"
    say "  export PATH=\"$BIN_DIR:\$PATH\""
  fi
  say ""
  say "Existing $CODEX_DIR/config.toml was not changed."
}

run_codex() {
  local target="${1:-}"
  [ -n "$target" ] || die "run requires one of: openai, flash, pro"
  shift || true
  if [ "${1:-}" = "--" ]; then shift; fi
  case "$target" in
    openai) exec "$CODEX_BIN" "$@" ;;
    flash)
      profile_check "$PROFILE_FLASH" "deepseek-flash" || die "Flash profile is missing or invalid; run install."
      exec "$CODEX_BIN" --profile deepseek-flash "$@"
      ;;
    pro)
      profile_check "$PROFILE_PRO" "deepseek-v4-pro" || die "Pro profile is missing or invalid; run install."
      exec "$CODEX_BIN" --profile deepseek-pro "$@"
      ;;
    *) die "Unknown run target: $target" ;;
  esac
}

repair_catalog() {
  require_command perl
  local path="${1:-$CODEX_DIR/models.json}"
  [ -f "$path" ] || die "Catalog not found: $path"
  json_validate "$path" || die "Catalog is not valid JSON: $path"

  local backup temp
  backup="$path.before-$PROGRAM_NAME-$(date '+%Y%m%d-%H%M%S')"
  cp -p "$path" "$backup"
  make_temp_dir
  temp="$TEMP_DIR/repaired-models.json"
  cp "$path" "$temp"
  perl -0pi -e 's/("multi_agent_version"\s*:\s*)"v2"/${1}"v1"/g; s/("supports_search_tool"\s*:\s*)true/${1}false/g' "$temp"
  json_validate "$temp" || die "Catalog repair produced invalid JSON; original is untouched."
  atomic_install_file "$temp" "$path" 600
  ok "Catalog compatibility fixes applied"
  info "Backup: $backup"
}

run_desktop_setup() {
  require_macos
  validate_paths
  require_command "$CURL_BIN"
  require_command "$SHASUM_BIN"
  prepare_managed_dir
  make_temp_dir
  local vendor_script
  vendor_script="$TEMP_DIR/deepseek-official-setup.sh"
  fetch_official_setup "$vendor_script"
  chmod 700 "$vendor_script"

  say ""
  warn "Desktop mode changes the shared $CODEX_DIR/config.toml through DeepSeek's official installer."
  warn "The official installer may store the DeepSeek key as plaintext in that file (mode 600)."
  warn "Fully quit and reopen the Codex/ChatGPT app after switching."
  say ""
  bash "$vendor_script"

  if [ -f "$CODEX_DIR/models.json" ]; then
    repair_catalog "$CODEX_DIR/models.json"
  fi
  chmod 600 "$CODEX_DIR/config.toml" 2>/dev/null || true
  ok "Desktop setup finished. Fully quit and reopen the app."
}

api_smoke_test() {
  keychain_has_key || die "No DeepSeek key is stored in Keychain. Run install first."
  local key response_file code
  key="$(read_keychain_key)"
  make_temp_dir
  response_file="$TEMP_DIR/api-response.json"
  code="$("$CURL_BIN" -sS -o "$response_file" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $key" \
    -d '{"model":"deepseek-flash","input":"Reply with OK only.","max_output_tokens":16}' \
    'https://api.deepseek.com/responses')"
  unset key
  if [ "$code" != "200" ]; then
    warn "DeepSeek API smoke test returned HTTP $code"
    if [ -s "$response_file" ]; then
      sed -E 's/(sk-[A-Za-z0-9_-]{8})[A-Za-z0-9_-]+/\1…/g' "$response_file" >&2
    fi
    return 1
  fi
  ok "DeepSeek Responses API smoke test passed (HTTP 200)"
}

doctor() {
  require_macos
  validate_paths
  local failures=0 api=0 current=""
  [ "${1:-}" = "--api" ] && api=1

  say "$PROGRAM_NAME doctor"
  say ""
  if command -v "$CODEX_BIN" >/dev/null 2>&1; then
    current="$(codex_version)"
    if [ -n "$current" ] && semver_ge "$current" "$MIN_CODEX_VERSION"; then
      ok "Codex version $current"
    else
      warn "Codex $MIN_CODEX_VERSION or newer is required; found ${current:-unknown}"
      failures=$((failures+1))
    fi
  else
    warn "Codex CLI not found: $CODEX_BIN"
    failures=$((failures+1))
  fi

  if keychain_has_key; then ok "DeepSeek key exists in Keychain"; else warn "DeepSeek key is missing from Keychain"; failures=$((failures+1)); fi
  if [ -f "$MANAGED_SENTINEL" ]; then ok "Managed directory ownership marker exists"; else warn "Managed directory marker is missing"; failures=$((failures+1)); fi
  if [ -f "$CATALOG_COMPAT" ] && json_validate "$CATALOG_COMPAT"; then ok "Compatibility model catalog is valid"; else warn "Compatibility catalog missing or invalid"; failures=$((failures+1)); fi
  if profile_check "$PROFILE_FLASH" "deepseek-flash"; then ok "Flash profile is valid"; else warn "Flash profile missing or invalid"; failures=$((failures+1)); fi
  if profile_check "$PROFILE_PRO" "deepseek-v4-pro"; then ok "Pro profile is valid"; else warn "Pro profile missing or invalid"; failures=$((failures+1)); fi
  if [ -x "$WRAPPER_FLASH" ] && [ -x "$WRAPPER_PRO" ] && [ -x "$WRAPPER_OPENAI" ]; then ok "Command wrappers are installed"; else warn "One or more wrappers are missing"; failures=$((failures+1)); fi

  if [ -f "$CATALOG_COMPAT" ]; then
    if grep -q '"multi_agent_version"[[:space:]]*:[[:space:]]*"v2"' "$CATALOG_COMPAT"; then
      warn "Catalog still contains multi_agent_version v2"; failures=$((failures+1))
    else
      ok "Subagent compatibility is set to v1"
    fi
    if grep -q '"supports_search_tool"[[:space:]]*:[[:space:]]*true' "$CATALOG_COMPAT"; then
      warn "Catalog still defers MCP tools through search_tool"; failures=$((failures+1))
    else
      ok "MCP tool compatibility patch is applied"
    fi
  fi

  if [ "$api" -eq 1 ]; then
    require_command "$CURL_BIN"
    api_smoke_test || failures=$((failures+1))
  fi

  say ""
  if [ "$failures" -eq 0 ]; then
    ok "All checks passed"
  else
    die "$failures check(s) failed. Run install again, then rerun doctor."
  fi
}

remove_if_managed() {
  local path="$1"
  if [ -f "$path" ] && grep -q "Managed by $PROGRAM_NAME" "$path" 2>/dev/null; then
    rm -f -- "$path"
    ok "Removed $path"
  elif [ -e "$path" ]; then
    warn "Left unrecognized file untouched: $path"
  fi
}

uninstall_profiles() {
  require_macos
  validate_paths
  local purge=0
  [ "${1:-}" = "--purge-key" ] && purge=1
  if [ "$purge" -eq 1 ]; then
    require_command "$SECURITY_BIN"
  fi

  remove_if_managed "$PROFILE_FLASH"
  remove_if_managed "$PROFILE_PRO"
  remove_if_managed "$WRAPPER_FLASH"
  remove_if_managed "$WRAPPER_PRO"
  remove_if_managed "$WRAPPER_OPENAI"

  if [ -d "$MANAGED_DIR" ]; then
    if [ -f "$MANAGED_SENTINEL" ] && grep -Fq "$PROGRAM_NAME" "$MANAGED_SENTINEL"; then
      rm -rf -- "$MANAGED_DIR"
      ok "Removed $MANAGED_DIR"
    else
      warn "Left unowned directory untouched: $MANAGED_DIR"
    fi
  fi

  if [ "$purge" -eq 1 ]; then
    "$SECURITY_BIN" delete-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
    ok "Removed DeepSeek API key from Keychain"
  else
    info "Keychain entry kept. Use uninstall --purge-key to remove it."
  fi

  info "Desktop global config was not touched. Use desktop and choose the official restore option if needed."
}

main() {
  local command="${1:-help}"
  shift || true
  case "$command" in
    install) [ "$#" -eq 0 ] || die "install takes no arguments"; install_profiles ;;
    run) run_codex "$@" ;;
    desktop) [ "$#" -eq 0 ] || die "desktop takes no arguments"; run_desktop_setup ;;
    repair-catalog) [ "$#" -le 1 ] || die "repair-catalog accepts at most one path"; repair_catalog "${1:-}" ;;
    doctor) [ "$#" -le 1 ] || die "doctor accepts only --api"; [ "$#" -eq 0 ] || [ "$1" = "--api" ] || die "Unknown doctor option: $1"; doctor "${1:-}" ;;
    uninstall) [ "$#" -le 1 ] || die "uninstall accepts only --purge-key"; [ "$#" -eq 0 ] || [ "$1" = "--purge-key" ] || die "Unknown uninstall option: $1"; uninstall_profiles "${1:-}" ;;
    version|--version|-v) say "$PROGRAM_NAME $PROGRAM_VERSION" ;;
    help|--help|-h) usage ;;
    *) usage; die "Unknown command: $command" ;;
  esac
}

main "$@"
