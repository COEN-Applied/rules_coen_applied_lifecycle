#!/usr/bin/env python3
"""Stage a set of source files into a TreeArtifact with declared paths.

Reads a newline-delimited TSV file where each line is `<src_path>\t<dest_rel>`.
Each source file is copied to `<stage_dir>/<dest_rel>`, creating parent
directories as needed. Exists because doing this in `ctx.actions.run_shell`
relies on POSIX-but-not-really shell behaviour (IFS tab-quoting, set -e
semantics) that differs between /bin/sh dialects on macOS and Linux CI.

Contract:
  argv[1] = path to the TSV plan
  argv[2] = path to the staging directory (must be a TreeArtifact; dir is
            created if missing)
"""

from __future__ import annotations

import os
import shutil
import sys


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        raise SystemExit(
            "usage: stage_tree.py PLAN_TSV STAGE_DIR"
        )
    plan_path = argv[1]
    stage_dir = argv[2]

    os.makedirs(stage_dir, exist_ok=True)

    with open(plan_path, "r", encoding="utf-8") as plan:
        for lineno, raw in enumerate(plan, start=1):
            line = raw.rstrip("\n")
            if not line:
                continue
            if "\t" not in line:
                raise SystemExit(
                    f"stage_tree: malformed line {lineno}: expected 'src\\tdest', got {line!r}"
                )
            src, dest = line.split("\t", 1)
            if not src or not dest:
                raise SystemExit(
                    f"stage_tree: empty src or dest on line {lineno}: {line!r}"
                )
            out_path = os.path.join(stage_dir, dest)
            os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
            shutil.copyfile(src, out_path)

    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main(sys.argv))
