#!/usr/bin/env bash
# Verify the release_group target's runfiles tree contains the transitive
# tool dependencies of each push (jq, crane).
#
# Regression test for the bug where `_push_shim` dropped
# `DefaultInfo.default_runfiles` on the floor, causing the release_group
# launcher to fail at run time with
# `../aspect_bazel_lib.../jq: No such file or directory`.
#
# We drive the check by consuming the release_group as `data` in an
# sh_test. That data dependency causes Bazel to materialise the target's
# runfiles tree at `$RUNFILES_DIR/`, and we assert the presence of the
# repos each push shim must forward.
set -uo pipefail

launcher="$1"
shift

runfiles_root=""
if [ -n "${RUNFILES_DIR:-}" ]; then
  runfiles_root="$RUNFILES_DIR"
elif [ -n "${TEST_SRCDIR:-}" ]; then
  runfiles_root="$TEST_SRCDIR"
else
  # Fall back to derivation from the launcher path (in case this is
  # invoked outside `bazel test`).
  runfiles_root="$(dirname "$launcher")/../.."
fi

# The canonical repo names for the two tools each oci_push depends on.
# Derived at runtime by globbing to stay robust against rules_oci /
# aspect_bazel_lib bumping module versions.
required_patterns=(
  "aspect_bazel_lib*toolchains*jq_*"
  "rules_oci*oci*oci_crane_*"
)

missing=()
for pat in "${required_patterns[@]}"; do
  matches=$(find "$runfiles_root" -maxdepth 2 -name "$pat" -type d 2>/dev/null | head -1)
  if [ -z "$matches" ]; then
    missing+=("$pat")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "FAIL: release_group runfiles tree is missing transitive tool repos:"
  printf '  - %s\n' "${missing[@]}"
  echo "---- runfiles tree (top-level) ----"
  ls -la "$runfiles_root" 2>&1 || true
  echo "---- runfiles tree (inside _main) ----"
  ls -la "$runfiles_root/_main" 2>&1 || true
  exit 1
fi

# Also assert the launcher itself is present and executable so we catch
# drift in the rule's DefaultInfo.files.
if [ ! -x "$launcher" ]; then
  echo "FAIL: launcher is not executable at '$launcher'"
  exit 1
fi

echo "PASS: release_group runfiles tree contains every transitive tool repo"
exit 0
