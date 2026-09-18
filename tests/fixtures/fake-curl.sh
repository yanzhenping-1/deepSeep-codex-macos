#!/usr/bin/env bash
set -euo pipefail
output=""
write_code=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -w)
      write_code="$2"
      shift 2
      ;;
    -H|-d|--proto|--connect-timeout|--max-time)
      shift 2
      ;;
    -fL|-sS|--tlsv1.2)
      shift
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

if [ -n "$output" ]; then
  case "$url" in
    *cdn.deepseek.com*) cp "${FAKE_VENDOR_SCRIPT:?}" "$output" ;;
    *) printf '{"id":"resp_test","status":"completed"}\n' > "$output" ;;
  esac
fi
if [ -n "$write_code" ]; then
  printf '200'
fi
