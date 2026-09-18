#!/usr/bin/env bash
set -euo pipefail
output=""
write_code=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -w) write_code="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$output" ]; then
  if [ -n "${FAKE_VENDOR_SCRIPT:-}" ]; then
    cp "$FAKE_VENDOR_SCRIPT" "$output"
  else
    printf '{"id":"resp_test","status":"completed"}\n' > "$output"
  fi
fi
[ -z "$write_code" ] || printf '200'
