#!/usr/bin/env bash
set -euo pipefail

rendered="$1"

if grep -q 'image: ghcr.io/testorg/svc-a:test-tag' "$rendered"; then
  echo "PASS: image reference correctly rewritten"
  exit 0
else
  echo "FAIL: expected rewritten image reference not found in $rendered"
  cat "$rendered"
  exit 1
fi
