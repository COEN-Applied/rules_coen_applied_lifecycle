# 09 — OCI Push Macros

Wrap `@rules_oci//oci:defs.bzl%oci_image` + `%oci_push` in a Starlark macro
that wires registry/tag from lifecycle flags.

## Prerequisites
- 08 complete.

## Inputs
- Reference: `pave-infra-monorepo/build_defs/k8s/manifests_oci.bzl`,
  `oci/service_image.bzl`.
- PRS §4.

## Outputs

### File: `lifecycle/oci/push.bzl`
Exposes **two** public macros and one private helper rule.

### Helper rule: `_flag_value_file`
A single-output rule that reads a `LifecycleImageTagInfo`,
`LifecycleImageRegistryInfo` (via `providers`), or composes
`<registry>/<suffix>` where suffix is a macro-supplied string. Emits a text
file with no trailing newline. Consolidates the `_repository_file` +
`_tag_file` duplication from the reference.

Attrs:
- `source` — `string`, one of `"tag"`, `"registry"`, `"registry_slash_suffix"`.
- `suffix` — `string`, required when `source == "registry_slash_suffix"`.
- `tag_flag`, `registry_flag` — `label` attrs, each optional but required by
  the corresponding `source` mode.
- `join_char` — `string`, default `"/"`. Allows registries that disallow
  multi-segment paths (Docker Hub) to swap in `"-"` or similar.

### Macro: `manifests_oci_push`
```
manifests_oci_push(
    name,
    manifests,                # label_list of LifecycleManifestsInfo providers
    repository,               # string, e.g. "manifests/gateway"
    tag_flag, registry_flag,  # required
    layout = None,            # same as layout rule
    layout_callback = None,
    base = None,              # optional oci_image base; when None emits a
                              # zero-layer data image
    flat = False,
    extra_tags = [],          # list of strings; static additional tags
    visibility = None,
)
```
Generates:
- `<name>.tar` — the layout tarball (via `manifests_oci_layout`).
- `<name>` — `oci_image` with `tars = [":<name>.tar"]`. If `base` is None,
  uses a zero-layer scratch base constructed via `oci_image` with no
  `base` AND `os/arch` left to the default.
- `<name>.repo` — `_flag_value_file(source="registry_slash_suffix",
  suffix=repository, registry_flag=registry_flag)`.
- `<name>.tag` — `_flag_value_file(source="tag", tag_flag=tag_flag)`.
- `<name>.push` — `oci_push(image = ":<name>", repository_file =
  ":<name>.repo", remote_tags = ":<name>.tag")`.
  - Extra static tags appended as additional `remote_tags` label entries
    produced by `write_file`.
- Emits `LifecyclePushInfo` on `<name>.push` for release_group aggregation.
  (If `oci_push` doesn't emit arbitrary providers directly, wrap it in a
  trivial `_push_alias` rule that re-exports DefaultInfo + adds
  `LifecyclePushInfo`.)

### Macro: `application_oci_push`
The application-image analog. Takes an existing `oci_image` (or
`oci_image_index`) label, a `repository`, and the lifecycle flags; produces
the `<name>.push` target. This was `service_oci_push` in the reference.
Minimal:
```
application_oci_push(
    name, image, repository,
    tag_flag, registry_flag,
    extra_tags = [],
    visibility = None,
)
```

## Acceptance criteria
- Zero duplicated `_repository_file`/`_tag_file` rules anywhere in the
  ruleset.
- A single `tag_flag` / `registry_flag` passes through every push macro.
- The push target is runnable via `bazel run` and picks up flag values at
  runtime (i.e., `--//path/to:environment=prod` flows through into the
  actual registry path).
- Multiple tags are supported.

## Checkboxes
- [ ] `_flag_value_file` rule written.
- [ ] `_push_alias` wrapper written (if required to emit `LifecyclePushInfo`).
- [ ] `manifests_oci_push` macro written.
- [ ] `application_oci_push` macro written.
- [ ] `extra_tags` wiring verified.
- [ ] `join_char` attribute honored in repository composition.
