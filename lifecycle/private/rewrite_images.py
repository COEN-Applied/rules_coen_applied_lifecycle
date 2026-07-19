#!/usr/bin/env python3
"""Image-reference rewriter for rendered Kubernetes YAML.

Reads a YAML file, rewrites `image:` references according to a set of
`SOURCE=DST` rules, and writes the result to another file. Kept as a
standalone file-in / file-out tool (as opposed to stdin/stdout) so the
Bazel action can be a plain `ctx.actions.run` rather than `run_shell` — no
shell redirection, no platform-specific pipe semantics, fully hermetic
under the rules_python toolchain.

Contract:
  argv[1] = path to input YAML
  argv[2] = path to output YAML (overwritten)
  argv[3:] = zero or more SOURCE=DST rules

SOURCE is matched literally (not as a regex) against the image reference
captured between optional quotes and an optional `:TAG` suffix. DST is
written verbatim — callers are expected to pass a fully-qualified
`registry/repo:tag` or `registry/repo@sha256:...` string. The Starlark
helper (lifecycle/manifests/image_rewrite.bzl) auto-qualifies bare repo
names before reaching this tool.

First-match-wins: rules are applied in the order given; each line is
rewritten by at most one rule.
"""

from __future__ import annotations

import re
import sys
from typing import Iterable


# Anchored pattern:
#   - leading whitespace (captured so it is preserved verbatim)
#   - optional YAML list marker `- `
#   - `image:` key
#   - separating whitespace
#   - optional quote (matched symmetrically via back-reference)
#   - the image reference (captured)
#   - optional `:TAG` suffix (captured separately so we know where the ref
#     ends regardless of whether the caller included a tag)
#   - optional close-quote
#   - optional trailing whitespace + comment
_IMAGE_LINE = re.compile(
    r"""^
        (?P<indent>[ \t]*)
        (?P<bullet>-\ )?
        image:\s*
        (?P<openq>['\"])?
        (?P<ref>[^\s'\":@]+(?:@sha256:[0-9a-f]+)?)
        (?::(?P<tag>[^\s'\"#]+))?
        (?P=openq)?
        (?P<trailing>\s*(?:\#.*)?)?
        $
    """,
    re.VERBOSE,
)


def _parse_rules(argv: Iterable[str]) -> list[tuple[str, str]]:
    rules: list[tuple[str, str]] = []
    for raw in argv:
        if "=" not in raw:
            raise SystemExit(
                f"rewrite_images: rule {raw!r} is not of the form SOURCE=DST"
            )
        # str.partition preserves any '=' characters that appear in DST
        # (which may contain `sha256:...@...` or registry paths that
        # legitimately include other characters, though not '=').
        src, _, dst = raw.partition("=")
        if not src or not dst:
            raise SystemExit(
                f"rewrite_images: rule {raw!r} has empty SOURCE or DST"
            )
        rules.append((src, dst))
    return rules


def _rewrite_line(line: str, rules: list[tuple[str, str]]) -> str:
    match = _IMAGE_LINE.match(line.rstrip("\n"))
    if not match:
        return line
    ref = match.group("ref")
    for src, dst in rules:
        if ref != src:
            continue
        indent = match.group("indent") or ""
        bullet = match.group("bullet") or ""
        openq = match.group("openq") or ""
        closeq = openq  # symmetric
        trailing = match.group("trailing") or ""
        new = f"{indent}{bullet}image: {openq}{dst}{closeq}{trailing}"
        # Preserve original line ending.
        if line.endswith("\n"):
            new += "\n"
        return new
    return line


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        raise SystemExit(
            "usage: rewrite_images.py SRC_YAML DST_YAML [SOURCE=DST ...]"
        )
    src_path = argv[1]
    dst_path = argv[2]
    rules = _parse_rules(argv[3:])

    with open(src_path, "r", encoding="utf-8", newline="") as f:
        content = f.readlines()

    rewritten = [_rewrite_line(l, rules) for l in content]

    with open(dst_path, "w", encoding="utf-8", newline="") as f:
        f.writelines(rewritten)

    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main(sys.argv))
