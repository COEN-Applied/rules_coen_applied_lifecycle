#!/usr/bin/env bash
set -euo pipefail

tar_file="$1"
golden_file="$2"

actual="$(tar tf "$tar_file" | sort)"

if [ ! -f "$golden_file" ]; then
  echo "FAIL: golden file $golden_file not found"
  exit 1
fi

expected="$(cat "$golden_file")"

if [ "$actual" = "$expected" ]; then
  echo "PASS: archive layout matches golden listing"
  exit 0
else
  echo "FAIL: archive layout differs"
  echo "--- Expected ---"
  echo "$expected"
  echo "--- Actual ---"
  echo "$actual"
  exit 1
fi
