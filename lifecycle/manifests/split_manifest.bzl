"""`split_manifest_by_kind` — partition a multi-doc YAML by document kind.

Used by `helm_manifest(split_crds = True)` but exposed as a standalone rule
because the same need arises whenever a consumer wants to apply CRDs
before workloads (GitOps prerequisite for most Flux/Argo setups).

Implementation: delegates to a tiny Python helper so we don't maintain a
shell-script parser. The python helper is a simple state machine over YAML
document separators (`---`) and `kind:` lines — no PyYAML dep.
"""

def _split_manifest_impl(ctx):
    args = ctx.actions.args()
    args.add(ctx.file.src.path)
    args.add(ctx.outputs.match_out.path)
    args.add(ctx.outputs.other_out.path)
    for k in ctx.attr.kinds:
        args.add(k)

    ctx.actions.run(
        executable = ctx.executable._splitter,
        arguments = [args],
        inputs = [ctx.file.src],
        outputs = [ctx.outputs.match_out, ctx.outputs.other_out],
        mnemonic = "LifecycleSplitManifest",
        progress_message = "Splitting %s by kind" % ctx.file.src.short_path,
    )

    return [DefaultInfo(files = depset([ctx.outputs.match_out, ctx.outputs.other_out]))]

split_manifest_by_kind = rule(
    implementation = _split_manifest_impl,
    attrs = {
        "src": attr.label(allow_single_file = [".yaml", ".yml"], mandatory = True),
        "kinds": attr.string_list(
            mandatory = True,
            doc = "List of YAML `kind:` values that should be routed to " +
                  "`match_out`. All other documents go to `other_out`.",
        ),
        "match_out": attr.output(mandatory = True),
        "other_out": attr.output(mandatory = True),
        "_splitter": attr.label(
            default = "//lifecycle/private:split_manifest",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Partition a multi-document YAML file into two outputs by `kind`.",
)
