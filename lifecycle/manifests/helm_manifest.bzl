"""`helm_manifest` — render a Helm chart and optionally rewrite images.

Implemented as a macro that composes `@rules_helm//helm:defs.bzl%helm_template`
with the image-rewriter helper and, when needed, the manifest splitter
(for separating CRDs from workloads, a recurring pattern in every upstream
chart that ships CRDs inline).

Design notes vs. the reference repositories (which had NO helm wrapper and
open-coded the `select_env + helm_template` combo in every service
BUILD file):

  * Per-env values files are passed as a simple `values_per_env` dict; the
    macro uses `select_env` to produce the select() for values. The
    ruleset has no opinion about which environments exist.
  * The macro synthesises a tiny Starlark rule around the post-rewrite
    output so it can emit `LifecycleManifestsInfo` — downstream OCI
    layout rules consume that provider rather than raw file labels.
"""

load("@rules_helm//helm:defs.bzl", "helm_template")
load(
    "//lifecycle/environments:select_env.bzl",
    "select_env",
)
load(
    "//lifecycle/manifests:image_rewrite.bzl",
    "IMAGE_REWRITE_ATTRS",
    "run_image_rewrite",
)
load(
    "//lifecycle/providers:providers.bzl",
    "LifecycleEnvironmentInfo",
    "LifecycleManifestsInfo",
)
load(
    "//lifecycle/manifests:split_manifest.bzl",
    "split_manifest_by_kind",
)

# ------------------------------------------------------------------------
# Private terminal rule: wrap a file in LifecycleManifestsInfo.
# ------------------------------------------------------------------------

def _manifests_wrapper_impl(ctx):
    files = depset(ctx.files.srcs)
    directories = depset(ctx.files.directories)
    return [
        DefaultInfo(files = files),
        LifecycleManifestsInfo(
            files = files,
            directories = directories,
            source_package = ctx.label.package,
        ),
    ]

_manifests_wrapper = rule(
    implementation = _manifests_wrapper_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".yaml", ".yml"]),
        "directories": attr.label_list(allow_files = True),
    },
    doc = "Internal: re-emit a set of YAML files as a LifecycleManifestsInfo.",
)

# ------------------------------------------------------------------------
# Private terminal rule: image-rewrite a single YAML file.
#
# We can't call `helm_template` and the rewriter inline in a macro because
# the rewriter needs to be a rule (it must resolve providers from
# tag_flag/registry_flag). So this small rule bridges the two.
# ------------------------------------------------------------------------

def _helm_rewrite_impl(ctx):
    run_image_rewrite(
        ctx = ctx,
        src_yaml = ctx.file.src,
        out_yaml = ctx.outputs.out,
        image_refs = ctx.attr.image_refs,
    )
    return [
        DefaultInfo(files = depset([ctx.outputs.out])),
        LifecycleManifestsInfo(
            files = depset([ctx.outputs.out]),
            directories = depset(),
            source_package = ctx.label.package,
        ),
    ]

_helm_rewrite = rule(
    implementation = _helm_rewrite_impl,
    attrs = dict({
        "src": attr.label(allow_single_file = [".yaml", ".yml"], mandatory = True),
        "out": attr.output(mandatory = True),
    }.items() + IMAGE_REWRITE_ATTRS.items()),
)

# ------------------------------------------------------------------------
# Public macro.
# ------------------------------------------------------------------------

def helm_manifest(
        name,
        chart,
        env_flag,
        tag_flag,
        registry_flag,
        values_per_env = None,
        base_values = None,
        release_name = None,
        namespace = None,
        image_refs = None,
        split_crds = False,
        flag_package = None,
        visibility = None):
    """Render a Helm chart and expose the result as LifecycleManifestsInfo.

    Args:
      name: Target name.
      chart: Label of a chart target (typically an `helm_import` output).
      env_flag: Label of the lifecycle_environment flag (for select_env).
      tag_flag: Label of the lifecycle_image_tag flag.
      registry_flag: Label of the lifecycle_image_registry flag.
      values_per_env: Optional `dict[str, list[label]]` of values files per
        environment. If None, only `base_values` are passed.
      base_values: Optional `list[label]` of values files always included
        beneath the env-specific ones.
      release_name: Helm release name. Forwarded to `helm_template`.
      namespace: Helm namespace. Forwarded to `helm_template`.
      image_refs: Optional `dict[str, str]` of image rewrite rules.
      split_crds: If True, also emits `<name>.crds` and `<name>.workloads`
        targets partitioning the rendered YAML by `kind`.
      flag_package: Required when `values_per_env` is non-empty. The Bazel
        package where `coen_applied_lifecycle_environments` was called. Used by
        select_env to build the correct config_setting labels.
      visibility: Visibility of generated public targets.
    """
    base_values = base_values or []
    values_per_env = values_per_env or {}
    image_refs = image_refs or {}

    if values_per_env:
        if flag_package == None:
            fail("helm_manifest: flag_package is required when values_per_env is non-empty.")
        values = base_values + select_env(
            mapping = values_per_env,
            default = [],
            flag_package = flag_package,
        )
    else:
        values = base_values

    helm_output = name + ".rendered.yaml"
    helm_opts = []
    if release_name:
        helm_opts.extend(["--release-name", release_name])
    if namespace:
        helm_opts.extend(["--namespace", namespace])

    helm_template(
        name = name + "_template",
        chart = chart,
        values = values,
        out = helm_output,
        opts = helm_opts,
        visibility = ["//visibility:private"],
    )

    if image_refs:
        _helm_rewrite(
            name = name + "_rewrite",
            src = ":" + helm_output,
            out = name + ".yaml",
            image_refs = image_refs,
            tag_flag = tag_flag,
            registry_flag = registry_flag,
            visibility = ["//visibility:private"],
        )
        rewritten = name + ".yaml"
        source = ":" + name + "_rewrite"
    else:
        rewritten = helm_output
        source = ":" + name + "_template"

    # Public entry point: a LifecycleManifestsInfo-bearing target named `name`.
    _manifests_wrapper(
        name = name,
        srcs = [source] if not image_refs else [":" + name + "_rewrite"],
        visibility = visibility,
    )

    if split_crds:
        split_manifest_by_kind(
            name = name + "_split",
            src = ":" + rewritten,
            kinds = ["CustomResourceDefinition"],
            match_out = name + ".crds.yaml",
            other_out = name + ".workloads.yaml",
            visibility = visibility,
        )
        _manifests_wrapper(
            name = name + ".crds",
            srcs = [":" + name + ".crds.yaml"],
            visibility = visibility,
        )
        _manifests_wrapper(
            name = name + ".workloads",
            srcs = [":" + name + ".workloads.yaml"],
            visibility = visibility,
        )
