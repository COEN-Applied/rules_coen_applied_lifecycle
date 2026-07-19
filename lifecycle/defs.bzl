"""Public API surface of rules_coen_applied_lifecycle.

This is the only file consumers are expected to `load()` from. Everything
re-exported here is semver-stable; anything under lifecycle/private/ or
prefixed with `_` is not.

Typical consumer usage:

    load(
        "@rules_coen_applied_lifecycle//lifecycle:defs.bzl",
        "coen_applied_lifecycle_environments",
        "kustomize_manifest",
        "helm_manifest",
        "manifests_oci_push",
        "application_oci_push",
        "coen_applied_release_group",
        "select_env",
    )
"""

load(
    "//lifecycle/environments:defs.bzl",
    _coen_applied_lifecycle_environments = "coen_applied_lifecycle_environments",
)
load(
    "//lifecycle/environments:select_env.bzl",
    _select_env = "select_env",
)
load(
    "//lifecycle/manifests:kustomize_manifest.bzl",
    _kustomize_manifest = "kustomize_manifest",
)
load(
    "//lifecycle/manifests:helm_manifest.bzl",
    _helm_manifest = "helm_manifest",
)
load(
    "//lifecycle/manifests:split_manifest.bzl",
    _split_manifest_by_kind = "split_manifest_by_kind",
)
load(
    "//lifecycle/oci:layout.bzl",
    _manifests_oci_layout = "manifests_oci_layout",
)
load(
    "//lifecycle/oci:push.bzl",
    _application_oci_push = "application_oci_push",
    _manifests_oci_push = "manifests_oci_push",
)
load(
    "//lifecycle/release:release_group.bzl",
    _coen_applied_release_group = "coen_applied_release_group",
)
load(
    "//lifecycle/providers:providers.bzl",
    _LifecycleEnvironmentInfo = "LifecycleEnvironmentInfo",
    _LifecycleImageRegistryInfo = "LifecycleImageRegistryInfo",
    _LifecycleImageTagInfo = "LifecycleImageTagInfo",
    _LifecycleManifestsInfo = "LifecycleManifestsInfo",
    _LifecyclePushInfo = "LifecyclePushInfo",
    _LifecycleReleaseGroupInfo = "LifecycleReleaseGroupInfo",
)

# Environments
coen_applied_lifecycle_environments = _coen_applied_lifecycle_environments
select_env = _select_env

# Manifest rendering
kustomize_manifest = _kustomize_manifest
helm_manifest = _helm_manifest
split_manifest_by_kind = _split_manifest_by_kind

# OCI
manifests_oci_layout = _manifests_oci_layout
manifests_oci_push = _manifests_oci_push
application_oci_push = _application_oci_push

# Release
coen_applied_release_group = _coen_applied_release_group

# Providers (re-exported so consumers can author their own rules that
# interoperate with the ruleset's rules).
LifecycleEnvironmentInfo = _LifecycleEnvironmentInfo
LifecycleImageTagInfo = _LifecycleImageTagInfo
LifecycleImageRegistryInfo = _LifecycleImageRegistryInfo
LifecycleManifestsInfo = _LifecycleManifestsInfo
LifecyclePushInfo = _LifecyclePushInfo
LifecycleReleaseGroupInfo = _LifecycleReleaseGroupInfo
