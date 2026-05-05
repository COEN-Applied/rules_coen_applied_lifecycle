# Changelog

All notable changes to `rules_farakov_lifecycle` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- The `rules_helm` toolchain (pinned to helm 3.17.3) is now registered by the
  ruleset itself, matching the existing treatment of the kustomize and
  rules_python toolchains. Consumer `MODULE.bazel` files no longer need to
  declare `helm.toolchain(...)` + `register_toolchains("@helm_toolchains//:all")`
  to use `helm_manifest`. Backwards-compatible: consumers that already register
  their own helm toolchain keep working; Bazel's toolchain resolution picks the
  first matching registration, so a consumer-side registration placed ahead of
  the ruleset's module still wins.

### Removed
- The "Forgetting to register the `rules_helm` toolchain in the consuming
  workspace" entry under common pitfalls in `docs/migrating-from-monorepo.md`,
  now that consumers don't need to register it.

## [0.1.0] - 2026-05-04

### Added
- Initial public release.
- Dynamic environment macro `farakov_lifecycle_environments` replacing hardcoded
  `dev/staging/prod` environment set; callers supply their own environment list,
  default, image tag default, and image registry default.
- `select_env` helper for building `select()` expressions keyed on
  caller-declared environments; no built-in fallback to any specific env name.
- `kustomize_manifest` rule (+ macro) accepting explicit `base_manifests`,
  `overlay_manifests`, and `kustomization` attributes, replacing implicit
  `k8s/overlays/<env>` globbing.
- `helm_manifest` macro composing `@rules_helm//helm:defs.bzl%helm_template`
  with image rewriting and optional CRD-vs-workload splitting.
- `manifests_oci_layout` rule for flexible OCI archive layouts with
  longest-prefix source-package matching and a `layout_callback` escape hatch.
- `manifests_oci_push` and `application_oci_push` macros wrapping
  `@rules_oci//oci:defs.bzl%oci_push` with lifecycle-flag-driven tag and
  registry resolution.
- `farakov_release_group` rule for build-time aggregation of push targets,
  replacing runtime `bazel query` discovery.
- Providers: `LifecycleEnvironmentInfo`, `LifecycleImageTagInfo`,
  `LifecycleImageRegistryInfo`, `LifecycleManifestsInfo`, `LifecyclePushInfo`,
  `LifecycleReleaseGroupInfo`.
- Hermetic `rewrite_images.py` and `split_manifest.py` tools shipped as
  `py_binary` targets under `lifecycle/private/`.
- Dummy test workspace under `tests/` exercising every public macro with
  non-canonical environments (`alpha`/`beta`/`gamma`) and golden-file-based
  `diff_test` + `sh_test` coverage.

### Pinned dependencies
- `rules_oci` 2.2.6
- `rules_pkg` 1.1.0
- `rules_helm` 0.22.1
- `rules_kustomize` 0.5.3
- Kustomize toolchain v5.8.0
