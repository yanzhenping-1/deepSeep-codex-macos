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
CATALOG_PATH="$MANAGED_DIR/models.json"
HASH_PATH="$MANAGED_DIR/vendor-script.sha256"
SENTINEL_PATH="$MANAGED_DIR/.managed-by-$PROGRAM_NAME"
WRAPPER_OPENAI="$BIN_DIR/codex-openai"
WRAPPER_FLASH="$BIN_DIR/codex-deepseek-flash"
WRAPPER_PRO="$BIN_DIR/codex-deepseek-pro"

CURL_BIN="${CURL_BIN:-curl}"
SECURITY_BIN="${SECURITY_BIN:-/usr/bin/security}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
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
DeepSeek for Codex on macOS

Usage:
  ./deepseek-codex-macos.sh install
  ./deepseek-codex-macos.sh run <openai|flash|pro> [-- <codex args...>]
  ./deepseek-codex-macos.sh refresh-catalog
  ./deepseek-codex-macos.sh desktop
  ./deepseek-codex-macos.sh doctor [--api]
  ./deepseek-codex-macos.sh uninstall [--purge-key]
  ./deepseek-codex-macos.sh version

After install:
  codex-openai
  codex-deepseek-flash
  codex-deepseek-pro
USAGE
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

make_temp_dir() {
  if [ -z "$TEMP_DIR" ]; then
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${PROGRAM_NAME}.XXXXXX")"
  fi
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
  if [ -d "$MANAGED_DIR" ] && [ ! -f "$SENTINEL_PATH" ] && [ -n "$(ls -A "$MANAGED_DIR" 2>/dev/null)" ]; then
    die "Refusing to use a non-empty unowned directory: $MANAGED_DIR"
  fi
  mkdir -p "$MANAGED_DIR"
  printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION" > "$SENTINEL_PATH"
  chmod 700 "$MANAGED_DIR"
  chmod 600 "$SENTINEL_PATH"
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

atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-600}"
  local parent temp
  parent="$(dirname "$destination")"
  mkdir -p "$parent"
  temp="$parent/.${PROGRAM_NAME}.$$.tmp"
  cp "$source" "$temp"
  chmod "$mode" "$temp"
  mv -f "$temp" "$destination"
}

backup_if_unmanaged() {
  local path="$1"
  if [ -e "$path" ] && ! grep -Fq "Managed by $PROGRAM_NAME" "$path" 2>/dev/null; then
    local backup="$path.before-$PROGRAM_NAME-$(date '+%Y%m%d-%H%M%S')"
    cp -p "$path" "$backup"
    warn "Backed up pre-existing file: $backup"
  fi
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

fetch_official_setup() {
  local output="$1"
  "$CURL_BIN" -fL --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 \
    "$OFFICIAL_SETUP_URL" -o "$output"
  [ -s "$output" ] || die "Downloaded DeepSeek setup script is empty."

  grep -q 'api\.deepseek\.com' "$output" || die "Validation failed: DeepSeek API endpoint missing."
  grep -q 'wire_api.*responses' "$output" || die "Validation failed: Responses API marker missing."
  grep -q 'CODEX_MODELS_JSON' "$output" || die "Validation failed: model catalog marker missing."
  grep -q 'deepseek-flash' "$output" || die "Validation failed: deepseek-flash missing."
  grep -q 'deepseek-v4-pro' "$output" || die "Validation failed: deepseek-v4-pro missing."
}

extract_catalog() {
  local setup_script="$1" output="$2"
  awk '
    /CODEX_MODELS_JSON/ && /<</ { capture=1; next }
    capture && /^CODEX_MODELS_JSON[[:space:]]*$/ { exit }
    capture { print }
  ' "$setup_script" > "$output"

  [ -s "$output" ] || die "Could not extract models.json from the DeepSeek setup script."
  json_validate "$output" || die "Extracted model catalog is not valid JSON."
  grep -q '"slug"[[:space:]]*:[[:space:]]*"deepseek-flash"' "$output" || \
    die "Catalog does not contain deepseek-flash."
  grep -q '"slug"[[:space:]]*:[[:space:]]*"deepseek-v4-pro"' "$output" || \
    die "Catalog does not contain deepseek-v4-pro."
}

refresh_catalog() {
  require_macos
  validate_paths
  require_command "$CURL_BIN"
  require_command "$SHASUM_BIN"
  require_command awk
  prepare_managed_dir
  make_temp_dir

  local setup_script="$TEMP_DIR/deepseek-official-setup.sh"
  local catalog="$TEMP_DIR/models.json"
  local digest

  info "Downloading DeepSeek's official Codex setup script"
  fetch_official_setup "$setup_script"
  digest="$(sha256_file "$setup_script")"
  extract_catalog "$setup_script" "$catalog"
  atomic_install_file "$catalog" "$CATALOG_PATH" 600
  printf '%s  %s\n' "$digest" "$OFFICIAL_SETUP_URL" > "$HASH_PATH"
  chmod 600 "$HASH_PATH"
  ok "Official model catalog refreshed"
  info "Source script SHA-256: $digest"
}

keychain_has_key() {
  "$SECURITY_BIN" find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1
}

read_keychain_key() {
  "$SECURITY_BIN" find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w
}

store_keychain_key() {
  local key="$1"
  "$SECURITY_BIN" add-generic-password -U -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w "$key" >/dev/null
}

obtain_api_key() {
  local key="${DEEPSEEK_API_KEY:-}"
  if [ -z "$key" ] && keychain_has_key; then
    return 0
  fi
  if [ -z "$key" ]; then
    [ -r /dev/tty ] || die "No API key found. Set DEEPSEEK_API_KEY for this install."
    printf 'DeepSeek API key (input hidden): ' >/dev/tty
    IFS= read -r -s key </dev/tty || true
    printf '\n' >/dev/tty
  fi
  [ -n "$key" ] || die "No DeepSeek API key provided."
  case "$key" in *$'\n'*|*$'\r'*) die "API key must be a single line." ;; esac
  store_keychain_key "$key"
  unset key DEEPSEEK_API_KEY
  ok "API key stored in macOS Keychain"
}

write_profile() {
  local model="$1" destination="$2"
  local temp catalog_e security_e account_e service_e
  make_temp_dir
  temp="$TEMP_DIR/$(basename "$destination")"
  catalog_e="$(toml_escape "$CATALOG_PATH")"
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
base_url = "https://api.deepseek.com"
wire_api = "responses"
supports_websockets = false
request_max_retries = 4
stream_max_retries = 5
stream_idle_timeout_ms = 300000

[model_providers.deepseek.auth]
command = "$security_e"
args = ["find-generic-password", "-a", "$account_e", "-s", "$service_e", "-w"]
timeout_ms = 5000
refresh_interval_ms = 0
EOF_PROFILE

  backup_if_unmanaged "$destination"
  atomic_install_file "$temp" "$destination" 600
}

write_wrapper() {
  local destination="$1" profile="$2" profile_path="$3"
  local temp codex_q profile_q profile_path_q
  make_temp_dir
  temp="$TEMP_DIR/$(basename "$destination")"
  codex_q="$(shell_single_quote "$CODEX_BIN")"
  profile_q="$(shell_single_quote "$profile")"
  profile_path_q="$(shell_single_quote "$profile_path")"

  if [ -n "$profile" ]; then
    cat > "$temp" <<EOF_WRAPPER
#!/usr/bin/env bash
# Managed by $PROGRAM_NAME $PROGRAM_VERSION.
set -euo pipefail
PROFILE_FILE=$profile_path_q
if [ ! -r "\$PROFILE_FILE" ]; then
  printf 'Missing Codex profile: %s\nRun deepseek-codex-macos.sh install again.\n' "\$PROFILE_FILE" >&2
  exit 78
fi
if ! grep -Fqx 'model_provider = "deepseek"' "\$PROFILE_FILE"; then
  printf 'Invalid DeepSeek profile: %s\nRun deepseek-codex-macos.sh install again.\n' "\$PROFILE_FILE" >&2
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

profile_is_valid() {
  local path="$1" model="$2"
  [ -f "$path" ] || return 1
  grep -Fqx "model = \"$model\"" "$path" || return 1
  grep -Fqx 'model_provider = "deepseek"' "$path" || return 1
  grep -Fqx 'wire_api = "responses"' "$path" || return 1
  grep -Fqx '[model_providers.deepseek.auth]' "$path" || return 1
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
  require_codex_version

  mkdir -p "$CODEX_DIR" "$BIN_DIR"
  refresh_catalog
  obtain_api_key
  write_profile "deepseek-flash" "$PROFILE_FLASH"
  write_profile "deepseek-v4-pro" "$PROFILE_PRO"
  write_wrapper "$WRAPPER_OPENAI" "" ""
  write_wrapper "$WRAPPER_FLASH" "deepseek-flash" "$PROFILE_FLASH"
  write_wrapper "$WRAPPER_PRO" "deepseek-pro" "$PROFILE_PRO"

  ok "Installed isolated Codex profiles"
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
  [ "${1:-}" = "--" ] && shift || true
  case "$target" in
    openai) exec "$CODEX_BIN" "$@" ;;
    flash)
      profile_is_valid "$PROFILE_FLASH" "deepseek-flash" || die "Flash profile missing or invalid; run install."
      exec "$CODEX_BIN" --profile deepseek-flash "$@"
      ;;
    pro)
      profile_is_valid "$PROFILE_PRO" "deepseek-v4-pro" || die "Pro profile missing or invalid; run install."
      exec "$CODEX_BIN" --profile deepseek-pro "$@"
      ;;
    *) die "Unknown run target: $target" ;;
  esac
}

run_desktop_setup() {
  require_macos
  validate_paths
  require_command "$CURL_BIN"
  require_command "$SHASUM_BIN"
  prepare_managed_dir
  make_temp_dir

  local setup_script="$TEMP_DIR/deepseek-official-setup.sh"
  local digest
  fetch_official_setup "$setup_script"
  digest="$(sha256_file "$setup_script")"
  chmod 700 "$setup_script"

  say ""
  warn "Desktop mode runs DeepSeek's official installer and changes $CODEX_DIR/config.toml."
  warn "The official installer may store the API key in that local file; review the displayed SHA-256 first."
  info "Source script SHA-256: $digest"
  say ""
  bash "$setup_script"
  chmod 600 "$CODEX_DIR/config.toml" 2>/dev/null || true
  ok "Desktop setup finished. Fully quit and reopen the Codex/ChatGPT app."
}

api_smoke_test() {
  require_command "$CURL_BIN"
  keychain_has_key || die "No DeepSeek key exists in Keychain. Run install first."
  local key response code
  key="$(read_keychain_key)"
  make_temp_dir
  response="$TEMP_DIR/api-response.json"
  code="$("$CURL_BIN" -sS -o "$response" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $key" \
    -d '{"model":"deepseek-flash","input":"Reply with OK only.","max_output_tokens":16}' \
    'https://api.deepseek.com/responses')"
  unset key
  if [ "$code" != "200" ]; then
    warn "DeepSeek API smoke test returned HTTP $code"
    if [ -s "$response" ]; then
      sed -E 's/(sk-[A-Za-z0-9_-]{8})[A-Za-z0-9_-]+/\1…/g' "$response" >&2
    fi
    return 1
  fi
  ok "DeepSeek Responses API smoke test passed"
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

  if keychain_has_key; then ok "DeepSeek API key exists in Keychain"; else warn "DeepSeek API key is missing"; failures=$((failures+1)); fi
  if [ -f "$CATALOG_PATH" ] && json_validate "$CATALOG_PATH"; then ok "Official model catalog is valid"; else warn "Model catalog missing or invalid"; failures=$((failures+1)); fi
  if profile_is_valid "$PROFILE_FLASH" "deepseek-flash"; then ok "Flash profile is valid"; else warn "Flash profile missing or invalid"; failures=$((failures+1)); fi
  if profile_is_valid "$PROFILE_PRO" "deepseek-v4-pro"; then ok "Pro profile is valid"; else warn "Pro profile missing or invalid"; failures=$((failures+1)); fi
  if [ -x "$WRAPPER_OPENAI" ] && [ -x "$WRAPPER_FLASH" ] && [ -x "$WRAPPER_PRO" ]; then ok "Command wrappers are installed"; else warn "One or more wrappers are missing"; failures=$((failures+1)); fi

  if [ "$api" -eq 1 ]; then
    api_smoke_test || failures=$((failures+1))
  fi

  say ""
  [ "$failures" -eq 0 ] || die "$failures check(s) failed."
  ok "All checks passed"
}

remove_if_managed() {
  local path="$1"
  if [ -f "$path" ] && grep -Fq "Managed by $PROGRAM_NAME" "$path" 2>/dev/null; then
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
  [ "$purge" -eq 0 ] || require_command "$SECURITY_BIN"

  remove_if_managed "$PROFILE_FLASH"
  remove_if_managed "$PROFILE_PRO"
  remove_if_managed "$WRAPPER_OPENAI"
  remove_if_managed "$WRAPPER_FLASH"
  remove_if_managed "$WRAPPER_PRO"

  if [ -d "$MANAGED_DIR" ]; then
    if [ -f "$SENTINEL_PATH" ] && grep -Fq "$PROGRAM_NAME" "$SENTINEL_PATH"; then
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
  info "Desktop global config was not changed by uninstall."
}

main() {
  local command="${1:-help}"
  shift || true
  case "$command" in
    install) [ "$#" -eq 0 ] || die "install takes no arguments"; install_profiles ;;
    run) run_codex "$@" ;;
    refresh-catalog) [ "$#" -eq 0 ] || die "refresh-catalog takes no arguments"; refresh_catalog ;;
    desktop) [ "$#" -eq 0 ] || die "desktop takes no arguments"; run_desktop_setup ;;
    doctor) [ "$#" -le 1 ] || die "doctor accepts only --api"; [ "$#" -eq 0 ] || [ "$1" = "--api" ] || die "Unknown doctor option: $1"; doctor "${1:-}" ;;
    uninstall) [ "$#" -le 1 ] || die "uninstall accepts only --purge-key"; [ "$#" -eq 0 ] || [ "$1" = "--purge-key" ] || die "Unknown uninstall option: $1"; uninstall_profiles "${1:-}" ;;
    version|--version|-v) say "$PROGRAM_NAME $PROGRAM_VERSION" ;;
    help|--help|-h) usage ;;
    *) usage; die "Unknown command: $command" ;;
  esac
}

main "$@"
