# 11 — Public API Surface

Re-export the subset of symbols that consumers are expected to load. Keep the
private/internal surface small.

## Prerequisites
- 03, 06, 07, 09, 10 complete.

## Outputs

### File: `lifecycle/defs.bzl`
The **only** file consumers are expected to `load()`. Re-exports:

```starlark
# Environments
load("//lifecycle/environments:defs.bzl", _farakov_lifecycle_environments = "farakov_lifecycle_environments")
load("//lifecycle/environments:select_env.bzl", _select_env = "select_env")

# Providers (public for consumers who want to write their own rules)
load("//lifecycle/providers:providers.bzl",
     _LifecycleEnvironmentInfo = "LifecycleEnvironmentInfo",
     _LifecycleImageTagInfo = "LifecycleImageTagInfo",
     _LifecycleImageRegistryInfo = "LifecycleImageRegistryInfo",
     _LifecycleManifestsInfo = "LifecycleManifestsInfo",
     _LifecyclePushInfo = "LifecyclePushInfo",
     _LifecycleReleaseGroupInfo = "LifecycleReleaseGroupInfo")

# Manifests
load("//lifecycle/manifests:kustomize_manifest.bzl", _kustomize_manifest = "kustomize_manifest")
load("//lifecycle/manifests:helm_manifest.bzl", _helm_manifest = "helm_manifest")

# OCI
load("//lifecycle/oci:push.bzl",
     _manifests_oci_push = "manifests_oci_push",
     _application_oci_push = "application_oci_push")
load("//lifecycle/oci:layout.bzl", _manifests_oci_layout = "manifests_oci_layout")

# Release
load("//lifecycle/release:release_group.bzl", _farakov_release_group = "farakov_release_group")

farakov_lifecycle_environments = _farakov_lifecycle_environments
select_env = _select_env
LifecycleEnvironmentInfo = _LifecycleEnvironmentInfo
LifecycleImageTagInfo = _LifecycleImageTagInfo
LifecycleImageRegistryInfo = _LifecycleImageRegistryInfo
LifecycleManifestsInfo = _LifecycleManifestsInfo
LifecyclePushInfo = _LifecyclePushInfo
LifecycleReleaseGroupInfo = _LifecycleReleaseGroupInfo
kustomize_manifest = _kustomize_manifest
helm_manifest = _helm_manifest
manifests_oci_layout = _manifests_oci_layout
manifests_oci_push = _manifests_oci_push
application_oci_push = _application_oci_push
farakov_release_group = _farakov_release_group
```

### Documentation
Generate `docs/api.md` via `stardoc` for every `.bzl` file under
`lifecycle/`, except those in `lifecycle/private/`.

## Acceptance criteria
- A consumer only needs `load("@rules_farakov_lifecycle//lifecycle:defs.bzl",
  ...)` for typical usage.
- `stardoc` renders `docs/api.md` with no missing-docstring warnings.
- No private symbols (prefixed `_`) are re-exported from `defs.bzl`.

## Checkboxes
- [x] `lifecycle/defs.bzl` created.
- [ ] `stardoc` wired into root `BUILD.bazel` (stardoc target only, not run
      at build time by default).
- [ ] `docs/api.md` generated and committed.
