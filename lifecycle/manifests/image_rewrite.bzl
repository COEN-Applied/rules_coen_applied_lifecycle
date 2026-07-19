"""Starlark helper for invoking the image-rewriter py_binary.

This module is the single seam between any manifest-rendering rule
(kustomize_manifest, helm_manifest, ...) and the rewriter tool. It
encapsulates:

  * Validation of image_refs at analysis time (rejecting values that would
    confuse the argv-based tool).
  * Auto-qualification of bare repo names into
    `<registry>/<repo>:<tag>` using the values carried by
    LifecycleImageRegistryInfo and LifecycleImageTagInfo.
  * Assembly of the `ctx.actions.run` call itself.

Attribute contributions are exported as IMAGE_REWRITE_ATTRS so any rule
that opts into rewriting adds them with `**IMAGE_REWRITE_ATTRS`.
"""

load(
    "//lifecycle/providers:providers.bzl",
    "LifecycleImageRegistryInfo",
    "LifecycleImageTagInfo",
)

# Attributes every manifest-rendering rule that supports image rewriting
# should mix in. Deliberately does NOT include the environment flag (which
# is consumed by the rendering step, not the rewrite step).
IMAGE_REWRITE_ATTRS = {
    "image_refs": attr.string_dict(
        doc = "Mapping of source image references to destination references. " +
              "Destination values may be a full `registry/repo[:tag|@digest]` " +
              "string (used verbatim) or a bare repo name (auto-qualified " +
              "using the registry_flag and tag_flag providers).",
    ),
    "tag_flag": attr.label(
        mandatory = True,
        providers = [LifecycleImageTagInfo],
        doc = "Label of the lifecycle_image_tag flag.",
    ),
    "registry_flag": attr.label(
        mandatory = True,
        providers = [LifecycleImageRegistryInfo],
        doc = "Label of the lifecycle_image_registry flag.",
    ),
    "_rewriter": attr.label(
        default = "//lifecycle/private:rewrite_images",
        executable = True,
        cfg = "exec",
    ),
}

def _is_fully_qualified(dst):
    # A destination is considered fully-qualified if it already contains
    # a path separator or a tag/digest suffix. Bare repo names (like
    # "my-service") trigger auto-qualification.
    return "/" in dst or ":" in dst or "@" in dst

def _qualify_dst(dst, registry, tag):
    if _is_fully_qualified(dst):
        # If no tag or digest, append the tag.
        if ":" not in dst and "@" not in dst:
            return dst + ":" + tag
        return dst
    # Bare repo name — prepend registry, append tag.
    return "%s/%s:%s" % (registry, dst, tag)

def validate_image_refs(image_refs):
    """Fail analysis if any rule cannot be safely passed to the rewriter."""
    for src, dst in image_refs.items():
        if not src:
            fail("image_refs: source keys must be non-empty.")
        if not dst:
            fail("image_refs: destination values must be non-empty.")
        if "=" in src or "=" in dst:
            fail(
                "image_refs: rule %s=%s contains '=' which breaks " % (src, dst) +
                "the SRC=DST argv encoding used by the rewriter.",
            )
        if "'" in src or "'" in dst:
            fail(
                "image_refs: rule %s=%s contains a single quote; " % (src, dst) +
                "not permitted to keep argv encoding simple across shells.",
            )

def run_image_rewrite(ctx, src_yaml, out_yaml, image_refs):
    """Emit an action that rewrites image refs in `src_yaml` into `out_yaml`.

    Args:
      ctx: rule context. Must expose `_rewriter`, `tag_flag`, `registry_flag`.
      src_yaml: `File`. Input YAML.
      out_yaml: `File`. Output YAML (declared by the caller).
      image_refs: `dict[str, str]`. Rewrite rules as declared by the caller.
    """
    validate_image_refs(image_refs)
    tag = ctx.attr.tag_flag[LifecycleImageTagInfo].tag
    registry = ctx.attr.registry_flag[LifecycleImageRegistryInfo].registry

    args = ctx.actions.args()
    args.add(src_yaml.path)
    args.add(out_yaml.path)
    for src, raw_dst in image_refs.items():
        dst = _qualify_dst(raw_dst, registry, tag)
        args.add("%s=%s" % (src, dst))

    ctx.actions.run(
        executable = ctx.executable._rewriter,
        arguments = [args],
        inputs = [src_yaml],
        outputs = [out_yaml],
        mnemonic = "LifecycleRewriteImages",
        progress_message = "Rewriting image references in %s" % src_yaml.short_path,
    )
