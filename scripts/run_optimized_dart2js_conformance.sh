#!/usr/bin/env bash
set -euo pipefail

TASK_TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TASK_TMP"
}
trap cleanup EXIT

dart compile js -O4 \
  -o "$TASK_TMP/official_stats_dart2js_conformance.js" \
  tool/official_stats_dart2js_conformance.dart
cp tool/official_stats_dart2js_harness.html "$TASK_TMP/"

if command -v google-chrome >/dev/null 2>&1; then
  TASK_CHROME="$(command -v google-chrome)"
elif command -v chromium >/dev/null 2>&1; then
  TASK_CHROME="$(command -v chromium)"
elif [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
  TASK_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
else
  echo "Chrome or Chromium is required for optimized dart2js conformance." >&2
  exit 1
fi

python3 scripts/run_chrome_conformance.py \
  "$TASK_CHROME" \
  "$TASK_TMP/official_stats_dart2js_harness.html"
