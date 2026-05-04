#!/usr/bin/env bash
# Verify the release_group launcher script includes every expected component.
# Proves build-time aggregation works without runtime `bazel query`.
set -euo pipefail

launcher="$1"
shift
expected_components=("$@")

if [ ! -f "$launcher" ]; then
  echo "FAIL: launcher not found at $launcher"
  exit 1
fi

missing=""
for comp in "${expected_components[@]}"; do
  if ! grep -q "release_group: ${comp} " "$launcher"; then
    missing="${missing} ${comp}"
  fi
done

if [ -n "$missing" ]; then
  echo "FAIL: missing components in launcher:${missing}"
  echo "--- Launcher contents ---"
  cat "$launcher"
  exit 1
fi

echo "PASS: launcher enumerates all expected components: ${expected_components[*]}"
exit 0
