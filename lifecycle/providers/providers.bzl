"""Public providers for rules_farakov_lifecycle.

All providers are defined once, here, so every rule in the ruleset imports
from a single source of truth. Consumers writing custom rules may also
import these.

Provider field names deliberately avoid domain-specific terminology such as
`type` (which the reference implementation used for a pipeline-environment
name); the new ruleset uses `name` / `tag` / `registry` / etc. to keep the
surface area self-documenting and decoupled from any consumer's CI lexicon.
"""

LifecycleEnvironmentInfo = provider(
    doc = "Current value of the lifecycle environment build flag.",
    fields = {
        "name": "string. Selected environment name (e.g. 'dev', 'qa'). " +
                "Always a member of the caller-provided `environments` list.",
    },
)

LifecycleImageTagInfo = provider(
    doc = "Current value of the lifecycle image tag build flag.",
    fields = {
        "tag": "string. Non-empty image tag to apply to pushed artifacts. " +
               "Digests (`@sha256:...`) belong in per-image overrides, not here.",
    },
)

LifecycleImageRegistryInfo = provider(
    doc = "Current value of the lifecycle image registry build flag.",
    fields = {
        "registry": "string. Registry host plus any fixed org/project " +
                    "prefix, e.g. 'ghcr.io/acme'. No trailing slash.",
    },
)

LifecycleManifestsInfo = provider(
    doc = "A set of rendered Kubernetes manifests produced by a " +
          "kustomize_manifest / helm_manifest rule. Used by OCI layout " +
          "rules to compose tarballs without coupling to on-disk conventions.",
    fields = {
        "files": "depset[File]. Rendered YAML files.",
        "directories": "depset[File]. TreeArtifact directories of YAML, " +
                       "typically CRDs extracted from upstream charts.",
        "source_package": "string. The Bazel package this manifest set " +
                          "originated from. Layout rules use this as a key " +
                          "for longest-prefix path resolution.",
    },
)

LifecyclePushInfo = provider(
    doc = "Metadata a release_group uses to aggregate push targets at " +
          "analysis time (replaces runtime `bazel query` discovery).",
    fields = {
        "push_executable": "File. Runnable push binary (the underlying " +
                           "oci_push's DefaultInfo.files_to_run.executable).",
        "push_label": "Label. Canonical label of the push target.",
        "component_name": "string. Logical component identifier " +
                          "(e.g. 'gateway'). Uniqueness key inside a " +
                          "release_group.",
        "repository": "string. Logical repository path inside the target " +
                      "registry, e.g. 'manifests/gateway'.",
    },
)

LifecycleReleaseGroupInfo = provider(
    doc = "Emitted by farakov_release_group so groups may themselves be " +
          "composed into larger groups.",
    fields = {
        "components": "list[string]. Component names aggregated by this " +
                      "group (flattened across any nested groups).",
        "push_labels": "list[Label]. The underlying push-target labels.",
    },
)
