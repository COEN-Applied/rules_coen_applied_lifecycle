# 01 — Initial Setup

Bootstrap the repository skeleton. No Starlark logic yet; only files required
to make the workspace loadable by Bazel.

## Prerequisites
- None.

## Inputs
- The PRS document (repository root).

## Outputs
- `MODULE.bazel` with `module(name = "rules_farakov_lifecycle", version = "0.0.0")`
  and zero external deps. Deps arrive in task 02.
- `BUILD.bazel` at the repository root with only:
  - `exports_files(["MODULE.bazel"])`
  - `package(default_visibility = ["//visibility:public"])`
- `.bazelversion` pinned to a Bazel 7.x release (Bzlmod-stable).
- `.bazelrc` with:
  - `common --enable_bzlmod`
  - `build --incompatible_strict_action_env`
  - `build --nolegacy_external_runfiles`
  - `test --test_output=errors`
- `.gitignore` covering `bazel-*`, `.DS_Store`, `__pycache__`, `.idea/`,
  `.vscode/`.
- `README.md` with a short "what this is / what this is not" blurb and a
  pointer to `docs/plan/`.
- `LICENSE` placeholder (Apache-2.0 boilerplate; confirm with stakeholders).
- `CHANGELOG.md` with a single `## [Unreleased]` header.

## Acceptance criteria
- `bazel mod graph` runs without errors from the repo root.
- `bazel build //...` succeeds (will be a no-op until later tasks).

## Checkboxes
- [ ] `MODULE.bazel` stub committed.
- [ ] Root `BUILD.bazel` committed.
- [ ] `.bazelversion`, `.bazelrc`, `.gitignore` committed.
- [ ] `README.md`, `LICENSE`, `CHANGELOG.md` committed.
- [ ] `bazel mod graph` verified.
