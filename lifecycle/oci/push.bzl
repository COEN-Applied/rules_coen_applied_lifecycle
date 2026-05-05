"""OCI push macros wired to lifecycle flags.

Consolidates the reference repos' duplicated `_repository_file` and
`_tag_file` rules into a single `_flag_value_file` and wires it to
`rules_oci`'s `oci_push`. Two public macros cover the two push scenarios:

  * `manifests_oci_push` — builds a data-only OCI image wrapping a
    manifest archive (replaces `k8s_manifests_oci` /
    `k8s_service_manifests_oci`).
  * `application_oci_push` — wraps an existing `oci_image` or
    `oci_image_index` with flag-driven repository/tag (replaces
    `service_oci_push`).

Both expose their resulting push target to the release aggregator via
`LifecyclePushInfo`.
"""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_push")
load(
    "//lifecycle/oci:layout.bzl",
    "manifests_oci_layout",
)
load(
    "//lifecycle/providers:providers.bzl",
    "LifecycleImageRegistryInfo",
    "LifecycleImageTagInfo",
    "LifecyclePushInfo",
)

# ------------------------------------------------------------------------
# _flag_value_file — materialize a flag into a single-line file.
# Also used to compose registry+suffix and (primary-tag + extra-tags)
# sources without spawning a shell action.
# ------------------------------------------------------------------------

_VALID_SOURCES = ["tag", "registry", "registry_slash_suffix", "tags_list"]

def _flag_value_file_impl(ctx):
    source = ctx.attr.source
    if source == "tag":
        if not ctx.attr.tag_flag:
            fail("_flag_value_file(source='tag') requires tag_flag.")
        value = ctx.attr.tag_flag[LifecycleImageTagInfo].tag
    elif source == "registry":
        if not ctx.attr.registry_flag:
            fail("_flag_value_file(source='registry') requires registry_flag.")
        value = ctx.attr.registry_flag[LifecycleImageRegistryInfo].registry
    elif source == "registry_slash_suffix":
        if not ctx.attr.registry_flag:
            fail("_flag_value_file(source='registry_slash_suffix') requires registry_flag.")
        if not ctx.attr.suffix:
            fail("_flag_value_file(source='registry_slash_suffix') requires suffix.")
        registry = ctx.attr.registry_flag[LifecycleImageRegistryInfo].registry
        value = "%s%s%s" % (registry, ctx.attr.join_char, ctx.attr.suffix)
    elif source == "tags_list":
        if not ctx.attr.tag_flag:
            fail("_flag_value_file(source='tags_list') requires tag_flag.")
        primary = ctx.attr.tag_flag[LifecycleImageTagInfo].tag
        all_tags = [primary] + list(ctx.attr.extra_tags)
        # crane tag reads one tag per line; trailing newline is idiomatic
        # here (not required by crane, but matches upstream examples).
        value = "\n".join(all_tags) + "\n"
    else:
        fail("_flag_value_file: invalid source=%r (valid: %s)" % (source, _VALID_SOURCES))

    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(out, value)
    return [DefaultInfo(files = depset([out]))]

_flag_value_file = rule(
    implementation = _flag_value_file_impl,
    attrs = {
        "source": attr.string(mandatory = True, values = _VALID_SOURCES),
        "suffix": attr.string(),
        "join_char": attr.string(default = "/"),
        "extra_tags": attr.string_list(),
        "tag_flag": attr.label(providers = [LifecycleImageTagInfo]),
        "registry_flag": attr.label(providers = [LifecycleImageRegistryInfo]),
    },
    doc = "Emit a single-line (or multi-line, for tag lists) file carrying " +
          "flag-derived content. Replaces the reference repos' duplicated " +
          "_repository_file / _tag_file rules.",
)

# ------------------------------------------------------------------------
# _push_shim — re-export DefaultInfo + emit LifecyclePushInfo so the
# release_group rule can aggregate push targets without string munging.
# ------------------------------------------------------------------------

def _push_shim_impl(ctx):
    inner = ctx.attr.push
    return [
        DefaultInfo(files = inner[DefaultInfo].files),
        LifecyclePushInfo(
            push_executable = inner[DefaultInfo].files_to_run.executable,
            push_label = ctx.attr.push.label,
            component_name = ctx.attr.component_name,
            repository = ctx.attr.repository,
        ),
    ]

_push_shim = rule(
    implementation = _push_shim_impl,
    attrs = {
        "push": attr.label(mandatory = True, executable = True, cfg = "target"),
        "component_name": attr.string(mandatory = True),
        "repository": attr.string(mandatory = True),
    },
)

# ------------------------------------------------------------------------
# Shared wiring between manifests_oci_push and application_oci_push.
# Both macros end with the same sequence:
#   <name>.repo    — repository_file for oci_push
#   <name>.tag     — remote_tags file (primary + any extras)
#   <name>._raw_push — rules_oci's oci_push
#   <name>.push    — _push_shim exposing LifecyclePushInfo
# ------------------------------------------------------------------------

def _wire_flag_driven_push(
        name,
        image,
        repository,
        tag_flag,
        registry_flag,
        extra_tags,
        registry_join_char,
        component_name,
        visibility):
    _flag_value_file(
        name = name + ".repo",
        source = "registry_slash_suffix",
        registry_flag = registry_flag,
        suffix = repository,
        join_char = registry_join_char,
        visibility = ["//visibility:private"],
    )
    _flag_value_file(
        name = name + ".tag",
        source = "tags_list",
        tag_flag = tag_flag,
        extra_tags = extra_tags,
        visibility = ["//visibility:private"],
    )
    oci_push(
        name = name + "._raw_push",
        image = image,
        repository_file = ":" + name + ".repo",
        remote_tags = ":" + name + ".tag",
        visibility = ["//visibility:private"],
    )
    _push_shim(
        name = name + ".push",
        push = ":" + name + "._raw_push",
        component_name = component_name or name,
        repository = repository,
        visibility = visibility,
    )

# ------------------------------------------------------------------------
# manifests_oci_push — data-image + push wrapper around a layout tar.
# ------------------------------------------------------------------------

def manifests_oci_push(
        name,
        manifests,
        repository,
        tag_flag,
        registry_flag,
        layout = None,
        dedup_strategy = None,
        flat = False,
        include_kustomization = True,
        kustomization_api_version = "kustomize.config.k8s.io/v1beta1",
        kustomization_prefix = "",
        component_name = None,
        extra_tags = [],
        registry_join_char = "/",
        os = "linux",
        architecture = "amd64",
        visibility = None):
    """Wrap a manifests layout tar into an OCI image and expose a push target.

    The generated `<name>.push` target is `bazel run`-able. Registry and
    tag resolve at action time from the lifecycle flags; the same target
    therefore can be used across environments via `--//flags:environment=<env>`
    etc. (whatever flag labels were passed in).

    Args:
      name: Target name. Produces `<name>`, `<name>.tar`, `<name>.push`,
        `<name>.repo`, `<name>.tag` (latter two are internal).
      manifests: `list[label]` as described in manifests_oci_layout.
      repository: `str`. Suffix appended to the registry value to form the
        repository path (e.g. "manifests/gateway").
      tag_flag: Label of the lifecycle_image_tag flag.
      registry_flag: Label of the lifecycle_image_registry flag.
      layout, dedup_strategy, flat, include_kustomization,
        kustomization_api_version, kustomization_prefix: see
        `manifests_oci_layout`.
      component_name: Logical component name for release aggregation.
        Defaults to `name`.
      extra_tags: `list[str]` of additional static tags applied in
        addition to the flag-driven primary tag. Typical uses: `"latest"`,
        a promotion alias like `"stable"`, etc.
      registry_join_char: Character between registry and repository.
        Default `"/"`; rare registries that disallow sub-paths may want
        `"-"` or similar.
      os, architecture: Platform stamped into the data-only image
        manifest. Defaults to `linux`/`amd64`; manifests are
        arch-agnostic so the choice is mostly cosmetic.
      visibility: Standard Bazel visibility.
    """
    manifests_oci_layout(
        name = name + ".tar",
        manifests = manifests,
        layout = layout,
        dedup_strategy = dedup_strategy,
        flat = flat,
        include_kustomization = include_kustomization,
        kustomization_api_version = kustomization_api_version,
        kustomization_prefix = kustomization_prefix,
        visibility = ["//visibility:private"],
    )

    oci_image(
        name = name,
        tars = [":" + name + ".tar"],
        os = os,
        architecture = architecture,
        visibility = visibility,
    )

    _wire_flag_driven_push(
        name = name,
        image = ":" + name,
        repository = repository,
        tag_flag = tag_flag,
        registry_flag = registry_flag,
        extra_tags = extra_tags,
        registry_join_char = registry_join_char,
        component_name = component_name,
        visibility = visibility,
    )

# ------------------------------------------------------------------------
# application_oci_push — flag-driven push wrapper around any oci image.
# ------------------------------------------------------------------------

def application_oci_push(
        name,
        image,
        repository,
        tag_flag,
        registry_flag,
        component_name = None,
        extra_tags = [],
        registry_join_char = "/",
        visibility = None):
    """Expose `bazel run`-able push for an existing oci_image / oci_image_index.

    Args:
      name: Target name. Produces `<name>.push`.
      image: Label of an `oci_image` or `oci_image_index`.
      repository: `str`. Suffix appended to the registry.
      tag_flag: Label of the lifecycle_image_tag flag.
      registry_flag: Label of the lifecycle_image_registry flag.
      component_name: Logical component name for release aggregation.
      extra_tags: `list[str]` of additional static tags. See
        manifests_oci_push.
      registry_join_char: See manifests_oci_push.
      visibility: Standard Bazel visibility.
    """
    _wire_flag_driven_push(
        name = name,
        image = image,
        repository = repository,
        tag_flag = tag_flag,
        registry_flag = registry_flag,
        extra_tags = extra_tags,
        registry_join_char = registry_join_char,
        component_name = component_name,
        visibility = visibility,
    )
