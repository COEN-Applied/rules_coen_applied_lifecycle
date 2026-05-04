"""`kustomize_manifest` — render a Kustomize overlay into a single YAML file.

Design notes vs. the reference `k8s_service_manifest`:

  * No `native.glob(["k8s/**"])`. Callers pass `base_manifests`,
    `overlay_manifests`, and `kustomization` as explicit file targets.
  * No hardcoded `k8s/overlays/<env>` substring match. The overlay's
    location is inferred from the `kustomization` attribute; nothing in
    this file references a specific environment name.
  * `kustomize` is obtained from the rules_kustomize toolchain, not via
    `use_default_shell_env`.
  * Environment flag labels are passed in explicitly. The ruleset has no
    default like `//build_flags:pipeline` — that kind of label baked in
    was the entire category of coupling the PRS instructs us to remove.
  * Optional image rewriting is composed via image_rewrite.bzl so all
    manifest rules share the same rewriter plumbing.
"""

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

_KUSTOMIZE_TOOLCHAIN_TYPE = "@rules_kustomize//tools/kustomize:toolchain_type"

def _stage_path_for(f):
    # Reproduce the file's workspace-relative path inside a staging
    # TreeArtifact so relative references like `../../base/` in
    # `kustomization.yaml` resolve the same way they would in source.
    return f.short_path

def _kustomize_manifest_impl(ctx):
    kustomize_info = ctx.toolchains[_KUSTOMIZE_TOOLCHAIN_TYPE].kustomizeinfo
    kustomize_exe = kustomize_info.tool

    overlay_kust = ctx.file.kustomization

    # Stage every source file into a single TreeArtifact so kustomize sees
    # a coherent filesystem with sibling paths intact.
    staging = ctx.actions.declare_directory(ctx.label.name + "_staging")

    all_sources = (
        list(ctx.files.base_manifests) +
        list(ctx.files.overlay_manifests) +
        [overlay_kust]
    )

    # Build a newline-delimited "src<TAB>dest" manifest consumed by a
    # staging helper. Implemented here as a single `ctx.actions.run_shell`
    # with a tiny, portable POSIX-sh body. This is the only shell snippet
    # in the ruleset and it does NOT depend on any tool outside coreutils.
    staging_plan = ctx.actions.declare_file(ctx.label.name + "_staging_plan.txt")
    plan_lines = []
    seen = {}
    for f in all_sources:
        rel = _stage_path_for(f)
        if rel in seen:
            continue
        seen[rel] = True
        plan_lines.append("%s\t%s" % (f.path, rel))
    ctx.actions.write(staging_plan, "\n".join(plan_lines) + "\n")

    # Stage files into the TreeArtifact.
    ctx.actions.run_shell(
        outputs = [staging],
        inputs = all_sources + [staging_plan],
        command = """
set -euo pipefail
out="$1"
plan="$2"
mkdir -p "$out"
while IFS=$(printf '\\t') read -r src dest; do
  [ -z "$src" ] && continue
  mkdir -p "$out/$(dirname "$dest")"
  cp "$src" "$out/$dest"
done < "$plan"
""",
        arguments = [staging.path, staging_plan.path],
        mnemonic = "LifecycleKustomizeStage",
        progress_message = "Staging kustomize sources for %s" % ctx.label,
    )

    # Run kustomize against the staged overlay directory.
    raw_yaml = ctx.actions.declare_file(ctx.label.name + ".raw.yaml")
    overlay_dir = _stage_path_for(overlay_kust).rsplit("/", 1)[0] if "/" in _stage_path_for(overlay_kust) else "."

    ctx.actions.run_shell(
        outputs = [raw_yaml],
        inputs = [staging],
        tools = [kustomize_exe],
        command = """
set -euo pipefail
"$1" build --load-restrictor LoadRestrictionsNone "$2/$3" > "$4"
""",
        arguments = [kustomize_exe.path, staging.path, overlay_dir, raw_yaml.path],
        mnemonic = "LifecycleKustomizeBuild",
        progress_message = "kustomize build for %s" % ctx.label,
    )

    # Optional image rewriting.
    if ctx.attr.image_refs:
        run_image_rewrite(
            ctx = ctx,
            src_yaml = raw_yaml,
            out_yaml = ctx.outputs.out,
            image_refs = ctx.attr.image_refs,
        )
    else:
        # No rewriting requested: promote the raw kustomize output to the
        # declared output via a trivial symlink action (preferred over
        # `cp` for determinism / inode preservation).
        ctx.actions.symlink(output = ctx.outputs.out, target_file = raw_yaml)

    return [
        DefaultInfo(files = depset([ctx.outputs.out])),
        LifecycleManifestsInfo(
            files = depset([ctx.outputs.out]),
            directories = depset(),
            source_package = ctx.label.package,
        ),
    ]

_kustomize_manifest = rule(
    implementation = _kustomize_manifest_impl,
    attrs = dict({
        "base_manifests": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Files referenced by the overlay's kustomization. Not " +
                  "computed by this rule — callers enumerate them.",
        ),
        "overlay_manifests": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Overlay files (patches, configMapGenerator inputs, etc.) " +
                  "that live next to the kustomization.yaml.",
        ),
        "kustomization": attr.label(
            allow_single_file = ["kustomization.yaml", "kustomization.yml", "Kustomization"],
            mandatory = True,
            doc = "The overlay's top-level kustomization file. Its " +
                  "directory is passed to `kustomize build`.",
        ),
        "env_flag": attr.label(
            mandatory = True,
            providers = [LifecycleEnvironmentInfo],
            doc = "Lifecycle environment flag. Currently consumed only to " +
                  "enforce the flag's presence and validity; downstream " +
                  "callers that need per-env values should use select() " +
                  "on the generated config_setting targets.",
        ),
        "out": attr.output(
            doc = "Rendered (and optionally image-rewritten) YAML file. " +
                  "Defaults to `<name>.yaml` via the wrapper macro.",
        ),
    }.items() + IMAGE_REWRITE_ATTRS.items()),
    toolchains = [_KUSTOMIZE_TOOLCHAIN_TYPE],
    doc = "Render a kustomize overlay and optionally rewrite image refs.",
)

def kustomize_manifest(
        name,
        kustomization,
        env_flag,
        tag_flag,
        registry_flag,
        base_manifests = None,
        overlay_manifests = None,
        image_refs = None,
        out = None,
        visibility = None,
        **kwargs):
    """Ergonomic wrapper around `_kustomize_manifest`.

    All flag labels are required; this macro does NOT supply defaults like
    `//build_flags:pipeline` because such defaults would re-introduce the
    coupling the ruleset exists to eliminate.
    """
    _kustomize_manifest(
        name = name,
        kustomization = kustomization,
        base_manifests = base_manifests or [],
        overlay_manifests = overlay_manifests or [],
        image_refs = image_refs or {},
        env_flag = env_flag,
        tag_flag = tag_flag,
        registry_flag = registry_flag,
        out = out or (name + ".yaml"),
        visibility = visibility,
        **kwargs
    )
