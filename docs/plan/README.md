# `rules_farakov_lifecycle` — Execution Plan

This directory is a **mutable execution plan** for implementing
`rules_farakov_lifecycle`. It is intentionally broken into small, sequentially
numbered, independent tasks so any agent can pause, resume, or hand off the
work at any point.

## Conventions

- Every task file is self-contained: it names its **inputs**, **outputs**,
  **acceptance criteria**, and **checkboxes**.
- Checkboxes (`[ ]` / `[x]`) are the **single source of truth** for progress.
  Agents MUST update them when they finish a step.
- Tasks are numbered by recommended execution order, but any task marked
  *independent* may run out of order once its listed prerequisites are done.
- If you discover a new task mid-stream, add a new file rather than bloating
  an existing one. Use the next free number (gaps are fine).
- Never delete a completed task file; strike it through in the index if it
  becomes obsolete.

## Index

| # | File | Status | Depends on |
|---|---|---|---|
| 01 | [01-initial-setup.md](01-initial-setup.md) | pending | — |
| 02 | [02-module-and-toolchains.md](02-module-and-toolchains.md) | pending | 01 |
| 03 | [03-environment-macros.md](03-environment-macros.md) | pending | 02 |
| 04 | [04-providers.md](04-providers.md) | pending | 02 |
| 05 | [05-image-rewriter.md](05-image-rewriter.md) | pending | 04 |
| 06 | [06-kustomize-manifest-rule.md](06-kustomize-manifest-rule.md) | pending | 04, 05 |
| 07 | [07-helm-manifest-rule.md](07-helm-manifest-rule.md) | pending | 04, 05 |
| 08 | [08-oci-layout-rule.md](08-oci-layout-rule.md) | pending | 04 |
| 09 | [09-oci-push-macros.md](09-oci-push-macros.md) | pending | 08 |
| 10 | [10-release-group.md](10-release-group.md) | pending | 09 |
| 11 | [11-public-api.md](11-public-api.md) | pending | 03, 06, 07, 09, 10 |
| 12 | [12-dummy-workspace-tests.md](12-dummy-workspace-tests.md) | pending | 11 |
| 13 | [13-ci-and-release.md](13-ci-and-release.md) | pending | 12 |

## Out-of-scope (intentionally excluded)

- `minikube` / `kubectl` integration (consumer repos own these).
- Project-specific tag-computation shell scripts.
- YAML merging utilities unrelated to manifest rendering.
- `.tgz`/`.tar.gz` normalization workarounds (fix upstream in `rules_helm`).
