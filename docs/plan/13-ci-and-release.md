# 13 — CI & Release

## Prerequisites
- 12 complete.

## Outputs

### File: `.github/workflows/ci.yaml`
Matrix: `ubuntu-24.04`, `macos-14`. Steps:
1. `actions/checkout@v4`.
2. Install Bazelisk (cached).
3. `bazel build //...` at repo root.
4. `bazel build //...` in `tests/`.
5. `bazel test //...` in `tests/`.

No registry credentials required; pushes are never executed in CI.

### File: `.github/workflows/release.yaml`
Triggered on `v*` tags. Steps:
1. Validate the tag matches SemVer (`vMAJOR.MINOR.PATCH` optionally with
   `-rc.N` / `-beta.N`).
2. Generate a release artifact (`.tar.gz` of the repo minus
   `bazel-*`/`.git/`).
3. Compute SHA256.
4. Create a GitHub Release with the artifact, a snippet for
   `bazel_dep`/`archive_override` integration, and release notes pulled
   from `CHANGELOG.md` between the new tag and previous tag.

### File: `CHANGELOG.md`
Follow Keep-A-Changelog format. Every PR touching the ruleset is required
to add a bullet under `## [Unreleased]`.

### File: `docs/versioning.md`
Short note on SemVer rules for the ruleset:
- MAJOR: any change to provider field names, attribute names, or macro
  signatures.
- MINOR: new attributes (with defaults preserving behavior), new macros,
  new providers.
- PATCH: bug fixes, docs, internal refactors invisible to callers.
- Bumping a pinned toolchain (rules_oci/rules_pkg/rules_helm/rules_kustomize)
  is always a MINOR bump minimum, MAJOR if the downstream toolchain has a
  breaking change.

### File: `docs/migrating-from-monorepo.md`
Step-by-step guide for the two reference repos. Includes a mapping table:

| Old symbol | New symbol |
|---|---|
| `k8s_service_manifest` | `kustomize_manifest` |
| `k8s_manifests_oci` | `manifests_oci_push` (with default layout) |
| `k8s_service_manifests_oci` | `manifests_oci_push(flat=True)` |
| `service_oci_push` | `application_oci_push` |
| `select_env(dev=..., staging=..., prod=...)` | `select_env({"dev":..., "staging":..., "prod":...})` (or new env names) |
| `//build_flags:pipeline` | `//<your-flags-pkg>:environment` |

## Acceptance criteria
- PR CI enforces `bazel build //...` and `bazel test //...` in both repo
  root and `tests/`.
- Tag push to `v*` successfully produces a GitHub Release with a consumable
  artifact URL + SHA256.
- Migration guide is accurate enough that a drop-in replacement is
  mechanical.

## Checkboxes
- [x] `ci.yaml` added.
- [x] `release.yaml` added.
- [x] `CHANGELOG.md` populated for `v0.1.0`.
- [x] `versioning.md` written.
- [x] `migrating-from-monorepo.md` written.
- [ ] End-to-end release dry run executed against a staging tag.
