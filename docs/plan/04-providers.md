# 04 — Providers

All providers live in a single file so the rest of the ruleset imports from
exactly one place.

## Prerequisites
- 02 complete.

## Inputs
- PRS §3, §4.

## Outputs

### File: `lifecycle/providers/providers.bzl`

```starlark
LifecycleEnvironmentInfo = provider(
    doc = "Current value of the lifecycle environment flag.",
    fields = {"name": "string — selected environment, e.g. 'dev'."},
)

LifecycleImageTagInfo = provider(
    doc = "Current value of the lifecycle image tag flag.",
    fields = {"tag": "string — the tag to apply to pushed images."},
)

LifecycleImageRegistryInfo = provider(
    doc = "Current value of the lifecycle image registry flag.",
    fields = {"registry": "string — the registry host + org prefix."},
)

LifecycleManifestsInfo = provider(
    doc = "A set of rendered Kubernetes manifests, unordered by env.",
    fields = {
        "files": "depset[File] of rendered YAML files.",
        "directories": "depset[File] of TreeArtifact directories of YAML.",
        "source_package": "string — the package the manifests belong to; " +
                          "used by OCI layout rules to compute default paths.",
    },
)

LifecyclePushInfo = provider(
    doc = "Metadata a release_group uses to aggregate push targets.",
    fields = {
        "push_executable": "File — the runnable `oci_push` binary.",
        "push_label": "Label — the actual push target label.",
        "component_name": "string — logical component name " +
                          "(e.g. 'gateway', 'vault'); uniqueness key.",
        "repository": "string — logical repo path inside the registry.",
    },
)
```

## Acceptance criteria
- Every rule that returns environment/tag/registry or manifest/push
  information imports these providers from this file.
- No provider is defined twice in the ruleset.

## Checkboxes
- [x] `providers.bzl` written.
- [x] `BUILD.bazel` in the same dir exports a `bzl_library`.
- [x] Grep confirms zero duplicate `provider(` definitions for these names.
