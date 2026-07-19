# Changelog

All notable changes to `rules_coen_applied_lifecycle` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-07-19

### Changed
- **BREAKING:** The ruleset now ships under COEN Applied LLC as
  `rules_coen_applied_lifecycle`, and both public macros carry the matching
  prefix: `coen_applied_lifecycle_environments` and
  `coen_applied_release_group`.

  Consumers on an earlier release must update the module name in their
  `bazel_dep`/`archive_override`, the `@rules_coen_applied_lifecycle//`
  prefix on every `load(...)` of `//lifecycle:defs.bzl`, and the two macro
  names at their call sites. Rule behaviour and attributes are otherwise
  unchanged — this release is a pure rename, so those substitutions are a
  complete migration.

### Removed
- Releases `0.1.0`–`0.1.2` and their tags have been withdrawn. They were
  published under the project's previous name and are no longer available.

## [0.1.2] - 2026-05-06

### Fixed
- `manifests_oci_layout` now produces a **gzip-compressed** tar archive
  (`extension = "tar.gz"` instead of `"tar"`). Previously the rule emitted
  a plain `application/vnd.oci.image.layer.v1.tar` layer; Flux's
  `source-controller` `OCIRepository` reconciler refuses to extract such
  layers and reports
  `failed to extract layer contents from artifact: requires gzip-compressed
  body: gzip: invalid header` for every artifact pushed via
  `manifests_oci_push`. With the fix, `@rules_oci`'s descriptor synthesis
  detects the gzip magic at offset 0 of the layer file and stamps the
  layer's mediaType as `application/vnd.oci.image.layer.v1.tar+gzip`,
  matching Flux's expectation. Test references that pointed at the
  implicit pkg_tar output (`svc_*_layout.tar`) were updated to the new
  filename (`svc_*_layout.tar.gz`); `tar tf` transparently reads
  gzip-compressed archives, so the layout assertions are unchanged.
- `_push_shim` (internal rule backing `<name>.push` targets from
  `manifests_oci_push` / `application_oci_push`) now propagates the inner
  `oci_push` target's `default_runfiles`. Without this, a
  `coen_applied_release_group` whose launcher invokes each push by runfiles path
  failed at runtime with
  `../aspect_bazel_lib.../jq: No such file or directory` — the jq and crane
  toolchain repos from `rules_oci` were not reachable from the release
  group's runfiles tree, even though each push worked when invoked directly
  via `bazel run //path:svc-push._raw_push`. Added
  `//tests:release_group_runfiles_test` as a regression guard.

## [0.1.1] - 2026-05-05

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
- Dynamic environment macro `coen_applied_lifecycle_environments` replacing hardcoded
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
- `coen_applied_release_group` rule for build-time aggregation of push targets,
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
