#!/usr/bin/env bash
set -euo pipefail
store="${FAKE_KEYCHAIN_FILE:?FAKE_KEYCHAIN_FILE is required}"
action="${1:-}"
shift || true
case "$action" in
  add-generic-password)
    value=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -w) value="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$value" ]
    printf '%s' "$value" > "$store"
    chmod 600 "$store"
    ;;
  find-generic-password)
    [ -f "$store" ] || exit 44
    cat "$store"
    ;;
  delete-generic-password)
    rm -f "$store"
    ;;
  *)
    printf 'unsupported fake security action: %s\n' "$action" >&2
    exit 2
    ;;
esac
