"""`manifests_oci_layout` — build a `.tar` archive with a caller-configurable
internal directory layout.

Replaces the reference repos' two near-duplicate tar rules
(`_manifests_tar` and `_service_manifests_tar`). The single rule here is
sufficient for both the "fleet bundle" mode (one archive containing every
service under `/manifests/<pkg>/...`) and the "flat per-service" mode
(archive contains `/manifests/*.yaml` with basename-only dedup).

Key decoupling points:

  * Archive layout is a `dict[str, str]` from *source package prefix* to
    *archive path prefix*. There is NO hardcoded `/manifests/` prefix.
    The default wrapper macro supplies one, but the rule itself treats
    the layout as fully caller-defined.
  * `LifecycleManifestsInfo.source_package` is the key material for
    longest-prefix matching — which means manifest producers can be
    arbitrarily placed in the workspace and the layout rule always
    composes them correctly without the packaging rule needing to know
    anything about the producer's location.
  * Kustomization generation is optional, with API version and mount
    point configurable. The reference repo hardcoded
    `kustomize.config.k8s.io/v1beta1` and placed it at archive root.
"""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load(
    "//lifecycle/providers:providers.bzl",
    "LifecycleManifestsInfo",
)

# ------------------------------------------------------------------------
# Internal providers. Declared at module top so implementation functions
# can reference them without load-order gymnastics.
# ------------------------------------------------------------------------

_LayoutPlanInfo = provider(
    doc = "Internal: resolved layout plan (list of File -> archive path).",
    fields = {"entries": "list[struct(file, archive_path)]"},
)

_LayoutStageInfo = provider(
    doc = "Internal: staged TreeArtifact ready to be fed to pkg_tar.",
    fields = {"directory": "File (TreeArtifact) containing the staged layout."},
)

# ------------------------------------------------------------------------
# Layout resolution (pure Starlark; no I/O).
# ------------------------------------------------------------------------

def _longest_prefix_match(layout, source_package):
    """Return the archive prefix for a given source_package.

    The layout dict is keyed by source-package prefixes with the special
    key `"*"` acting as a default. Ambiguity is resolved by longest match.
    """
    best_key = None
    best_len = -1
    for key in layout.keys():
        if key == "*":
            continue
        if source_package == key or source_package.startswith(key + "/"):
            if len(key) > best_len:
                best_key = key
                best_len = len(key)
    if best_key != None:
        return layout[best_key]
    if "*" in layout:
        return layout["*"]
    fail(
        "manifests_oci_layout: no layout entry matches source_package=%r " % source_package +
        "and no '*' default was provided. Layout keys: %s" % layout.keys(),
    )

def _resolve_dest(archive_prefix, source_package, basename, dedup_strategy):
    archive_prefix = archive_prefix.strip("/")
    if dedup_strategy == "basename":
        # Flat mode: no per-package subpath.
        return "%s/%s" % (archive_prefix, basename) if archive_prefix else basename
    elif dedup_strategy == "package_basename":
        parts = [p for p in [archive_prefix, source_package, basename] if p]
        return "/".join(parts)
    else:
        fail("Unknown dedup_strategy=%r" % dedup_strategy)

# ------------------------------------------------------------------------
# Intermediate rule: resolve LifecycleManifestsInfo + layout into a
# structured mapping file, then feed a `pkg_tar` target.
# ------------------------------------------------------------------------

def _layout_plan_impl(ctx):
    # Resolve every input target's files into (archive_path -> File) pairs.
    # We also emit a synthetic kustomization.yaml when requested.
    mapping = {}  # dest -> File
    seen_dests = {}

    # Sort manifest targets by label for deterministic output.
    targets = sorted(ctx.attr.manifests, key = lambda t: str(t.label))

    for target in targets:
        if LifecycleManifestsInfo in target:
            info = target[LifecycleManifestsInfo]
            source_package = info.source_package
            files = info.files.to_list()
        else:
            source_package = target.label.package
            files = target.files.to_list()

        archive_prefix = _longest_prefix_match(ctx.attr.layout, source_package)

        for f in files:
            if not f.basename.endswith((".yaml", ".yml")):
                continue
            dest = _resolve_dest(
                archive_prefix = archive_prefix,
                source_package = source_package,
                basename = f.basename,
                dedup_strategy = ctx.attr.dedup_strategy,
            )
            if dest in seen_dests:
                # Silently skip duplicates for "basename" mode (first-wins
                # matches the reference behavior). For "package_basename"
                # a true collision indicates a user error.
                if ctx.attr.dedup_strategy == "package_basename":
                    fail(
                        "manifests_oci_layout: duplicate archive path %r; " % dest +
                        "sources: %s vs %s" % (seen_dests[dest].path, f.path),
                    )
                continue
            seen_dests[dest] = f
            mapping[dest] = f

    # Write the layout plan for the packaging action.
    plan_lines = []
    for dest in sorted(mapping.keys()):
        plan_lines.append("%s\t%s" % (mapping[dest].path, dest))
    plan_file = ctx.actions.declare_file(ctx.label.name + "_plan.tsv")

    outputs = [plan_file]

    # Optionally generate a kustomization.yaml listing all resources.
    kust_file = None
    kust_dest = None
    if ctx.attr.include_kustomization:
        kprefix = ctx.attr.kustomization_prefix.strip("/")
        kust_dest = (kprefix + "/" if kprefix else "") + "kustomization.yaml"
        # Emit relative paths from the kustomization's location.
        kust_base = kprefix
        resources = []
        for dest in sorted(mapping.keys()):
            if kust_base and dest.startswith(kust_base + "/"):
                rel = dest[len(kust_base) + 1:]
            else:
                rel = dest
            resources.append("  - %s" % rel)
        kust_content = (
            "apiVersion: %s\n" % ctx.attr.kustomization_api_version +
            "kind: Kustomization\n" +
            "resources:\n" +
            "\n".join(resources) + ("\n" if resources else "")
        )
        kust_file = ctx.actions.declare_file(ctx.label.name + "_kustomization.yaml")
        ctx.actions.write(kust_file, kust_content)
        outputs.append(kust_file)

        plan_lines.append("%s\t%s" % (kust_file.path, kust_dest))

    # Write the plan file once, after all entries (including kustomization) are collected.
    ctx.actions.write(plan_file, "\n".join(plan_lines) + "\n")

    # Emit a simple provider with the list of (File, archive_path) pairs so
    # the wrapper macro can hand them to pkg_files/pkg_tar.
    return [
        DefaultInfo(files = depset(outputs)),
        _LayoutPlanInfo(
            entries = [
                struct(file = mapping[d], archive_path = d)
                for d in sorted(mapping.keys())
            ] + ([
                struct(file = kust_file, archive_path = kust_dest),
            ] if ctx.attr.include_kustomization else []),
        ),
    ]

_layout_plan = rule(
    implementation = _layout_plan_impl,
    attrs = {
        "manifests": attr.label_list(
            providers = [[LifecycleManifestsInfo], [DefaultInfo]],
            mandatory = True,
        ),
        "layout": attr.string_dict(mandatory = True),
        "dedup_strategy": attr.string(
            values = ["package_basename", "basename"],
            default = "package_basename",
        ),
        "include_kustomization": attr.bool(default = True),
        "kustomization_api_version": attr.string(default = "kustomize.config.k8s.io/v1beta1"),
        "kustomization_prefix": attr.string(default = ""),
    },
)

# ------------------------------------------------------------------------
# Terminal tar rule: consume _LayoutPlanInfo and build a .tar via pkg_tar.
#
# We can't pass a dynamic dict of file→destination directly into
# rules_pkg's `pkg_tar` (it wants analysis-time-known `remap_paths` or a
# fixed `pkg_files` set). So this rule stages every file into a
# TreeArtifact with the intended archive layout, then hands that
# TreeArtifact to `pkg_tar`, which walks it verbatim.
#
# Staging is done via a single hermetic `ctx.actions.run_shell` with a
# tiny POSIX-sh body. The only commands used are `mkdir`, `cp`, and
# `printf` — all POSIX-mandatory. No PATH lookups for `tar` or similar.
# ------------------------------------------------------------------------

def _manifests_tar_impl(ctx):
    plan = ctx.attr.plan[_LayoutPlanInfo]
    staging = ctx.actions.declare_directory(ctx.label.name)

    # Produce the staging TreeArtifact by delegating to the hermetic
    # Python stager. Python 3.12 is registered by MODULE.bazel, so this
    # runs identically on macOS and Linux with no shell-dialect pitfalls.
    tsv_lines = []
    input_files = []
    for e in plan.entries:
        tsv_lines.append("%s\t%s" % (e.file.path, e.archive_path))
        input_files.append(e.file)
    tsv = ctx.actions.declare_file(ctx.label.name + "_entries.tsv")
    ctx.actions.write(tsv, "\n".join(tsv_lines) + ("\n" if tsv_lines else ""))

    args = ctx.actions.args()
    args.add(tsv.path)
    args.add(staging.path)
    ctx.actions.run(
        executable = ctx.executable._stager,
        arguments = [args],
        inputs = input_files + [tsv],
        outputs = [staging],
        mnemonic = "LifecycleLayoutStage",
        progress_message = "Staging OCI layout for %s" % ctx.label,
    )

    return [
        DefaultInfo(files = depset([staging])),
        _LayoutStageInfo(directory = staging),
    ]

_manifests_stage = rule(
    implementation = _manifests_tar_impl,
    attrs = {
        "plan": attr.label(providers = [_LayoutPlanInfo], mandatory = True),
        "_stager": attr.label(
            default = "//lifecycle/private:stage_tree",
            executable = True,
            cfg = "exec",
        ),
    },
)

# ------------------------------------------------------------------------
# Public macro: `manifests_oci_layout`.
# ------------------------------------------------------------------------

_DEFAULT_LAYOUT = {"*": "manifests"}

def manifests_oci_layout(
        name,
        manifests,
        layout = None,
        dedup_strategy = None,
        flat = False,
        include_kustomization = True,
        kustomization_api_version = "kustomize.config.k8s.io/v1beta1",
        kustomization_prefix = "",
        visibility = None):
    """Assemble a `.tar` archive containing rendered manifests.

    Args:
      name: Target name. Produces `<name>.tar`.
      manifests: `list[label]` of targets providing `LifecycleManifestsInfo`
        (preferred) or raw YAML files (fallback).
      layout: Optional `dict[str, str]` mapping source-package prefixes to
        archive-path prefixes. Key `"*"` is the default. Defaults to
        `{"*": "manifests"}` — matching the reference repos' single-prefix
        behavior. Pass an explicit layout for multi-prefix archives.
      dedup_strategy: `"package_basename"` (default, fleet mode) or
        `"basename"` (flat mode). Governs archive path resolution and
        duplicate handling.
      flat: Convenience flag. When True: sets layout=`{"*": "manifests"}`
        and dedup_strategy=`"basename"`. Equivalent to the reference
        `k8s_service_manifests_oci`.
      include_kustomization: When True, a `kustomization.yaml` is
        generated listing every included manifest.
      kustomization_api_version: Emitted as the `apiVersion:` field.
      kustomization_prefix: Archive path prefix where the kustomization
        file should live. Empty string = archive root.
      visibility: Standard Bazel visibility.
    """
    if flat:
        layout = layout or {"*": "manifests"}
        dedup_strategy = dedup_strategy or "basename"
    else:
        layout = layout or _DEFAULT_LAYOUT
        dedup_strategy = dedup_strategy or "package_basename"

    _layout_plan(
        name = name + "_plan",
        manifests = manifests,
        layout = layout,
        dedup_strategy = dedup_strategy,
        include_kustomization = include_kustomization,
        kustomization_api_version = kustomization_api_version,
        kustomization_prefix = kustomization_prefix,
        visibility = ["//visibility:private"],
    )

    _manifests_stage(
        name = name + "_stage",
        plan = ":" + name + "_plan",
        visibility = ["//visibility:private"],
    )

    # Final .tar via rules_pkg. pkg_tar accepts a TreeArtifact as a source
    # and archives it verbatim.
    pkg_tar(
        name = name,
        srcs = [":" + name + "_stage"],
        strip_prefix = name + "_stage",
        extension = "tar",
        visibility = visibility,
    )
