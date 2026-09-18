#!/usr/bin/env bash
set -euo pipefail

output=""
write_format=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      write_format="$2"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

case "$url" in
  */responses)
    [ -n "$output" ] && printf '{"id":"resp_test","status":"completed"}\n' > "$output"
    [ -n "$write_format" ] && printf '200'
    ;;
  *)
    [ -n "${FAKE_VENDOR_SCRIPT:-}" ] || { printf 'FAKE_VENDOR_SCRIPT is required\n' >&2; exit 2; }
    [ -n "$output" ] || { printf 'fake curl requires -o for fixture download\n' >&2; exit 2; }
    cp "$FAKE_VENDOR_SCRIPT" "$output"
    ;;
esac
