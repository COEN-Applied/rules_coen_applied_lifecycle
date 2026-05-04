#!/usr/bin/env python3
"""Partition a multi-document YAML file by each document's `kind` field.

Contract:
  argv[1] = input YAML
  argv[2] = output path for documents matching any kind in argv[4:]
  argv[3] = output path for remaining documents
  argv[4:] = one or more kind strings to match

The implementation is a small state machine over YAML document separators
(`---`) and top-level `kind:` lines. No PyYAML dep — we never want to
introduce a dependency on the PyPI ecosystem for a rule that runs in a
hermetic action.
"""

from __future__ import annotations

import re
import sys


_DOC_SEPARATOR = re.compile(r"^---\s*$")
# Match only top-level `kind:` lines (no leading whitespace). Tracking
# indentation would require YAML parsing; the top-level form is the
# overwhelmingly common case for `kind:` in Kubernetes manifests and is
# sufficient for CRD-vs-workload partitioning.
_TOPLEVEL_KIND = re.compile(r"^kind:\s*(?P<k>[A-Za-z0-9_.-]+)\s*$")


def _split(text: str, match_kinds: set[str]) -> tuple[list[str], list[str]]:
    matched: list[str] = []
    other: list[str] = []
    docs: list[list[str]] = [[]]
    for line in text.splitlines(keepends=True):
        if _DOC_SEPARATOR.match(line):
            docs.append([])
            continue
        docs[-1].append(line)

    for doc_lines in docs:
        if not doc_lines:
            continue
        kind = None
        for line in doc_lines:
            m = _TOPLEVEL_KIND.match(line)
            if m:
                kind = m.group("k")
                break
        target = matched if kind in match_kinds else other
        # Preserve the `---` separator between docs on output.
        if target:
            target.append("---\n")
        target.extend(doc_lines)

    return matched, other


def main(argv: list[str]) -> int:
    if len(argv) < 5:
        raise SystemExit(
            "usage: split_manifest.py SRC MATCH_OUT OTHER_OUT KIND [KIND ...]"
        )
    src, match_out, other_out = argv[1], argv[2], argv[3]
    kinds = set(argv[4:])

    with open(src, "r", encoding="utf-8") as f:
        text = f.read()

    matched, other = _split(text, kinds)

    with open(match_out, "w", encoding="utf-8") as f:
        f.writelines(matched)
    with open(other_out, "w", encoding="utf-8") as f:
        f.writelines(other)

    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main(sys.argv))
