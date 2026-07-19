"""`coen_applied_release_group` — build-time aggregation of push targets.

Replaces the reference repos' runtime pattern of
    bazel query --output=label 'attr(name, "-manifests-push$", //k8s:*)'
followed by `bazel run` of each returned label. That approach is fragile
(requires a well-known label suffix convention and a well-known package),
and it moves target discovery out of the analysis graph — defeating the
point of having a build system.

The `_release_group` rule instead:

  * Takes an explicit `label_list` of push targets, each of which must
    carry `LifecyclePushInfo` (provided by `manifests_oci_push` /
    `application_oci_push`).
  * Checks at analysis time that no two components share the same name.
  * Emits a POSIX-sh launcher referencing each push target's runnable via
    runfiles, so `bazel run //path:release_group` executes every push in
    sequence and exits non-zero on the first failure (after attempting
    every remaining push, so CI logs show all failures in a single run).
"""

load(
    "//lifecycle/providers:providers.bzl",
    "LifecyclePushInfo",
    "LifecycleReleaseGroupInfo",
)

def _escape_shell(s):
    # Wrap a string in single quotes for safe inclusion in a POSIX-sh
    # script. Any literal single quote is closed, escaped, and reopened.
    return "'" + s.replace("'", "'\\''") + "'"

def _release_group_impl(ctx):
    pushes = [t[LifecyclePushInfo] for t in ctx.attr.pushes]

    # Duplicate-component check.
    if not ctx.attr.allow_duplicate_components:
        seen = {}
        for p in pushes:
            if p.component_name in seen:
                fail(
                    "coen_applied_release_group: duplicate component_name %r. " % p.component_name +
                    "Set allow_duplicate_components=True if this is intentional.",
                )
            seen[p.component_name] = True

    # Build the launcher.
    invocations = []
    for p in pushes:
        exe = p.push_executable
        # exe.short_path is the runfiles-relative path. The launcher
        # template cd's into the runfiles root before executing
        # invocations, so the relative path resolves hermetically.
        #
        # The Starlark strings below are written verbatim into the shell
        # script (no `% ()` formatting). That means `%s` in a Starlark
        # string is a single `%s` in the shell script, which `printf`
        # treats as a conversion specifier. We use `.format()` (not `%`)
        # to substitute the Starlark-side values so the shell-side `%s`
        # remains untouched.
        invocations.append(
            "\n".join([
                # Announce the component we're about to push.
                "printf 'release_group: {component} -> {repo}\\n'".format(
                    component = p.component_name,
                    repo = p.repository,
                ),
                # Echo any forwarded extra args on a separate line.
                'if [ -n "$EXTRA_ARGS" ]; then printf \'  extra args: %s\\n\' "$EXTRA_ARGS"; fi',
                "if ! {exe} $EXTRA_ARGS; then".format(exe = _escape_shell(exe.short_path)),
                '    failed_components="$failed_components {component}"'.format(
                    component = p.component_name,
                ),
                "fi",
            ]),
        )

    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = launcher,
        substitutions = {
            "%{PUSH_INVOCATIONS}": "\n\n".join(invocations),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [p.push_executable for p in pushes],
    )
    for t in ctx.attr.pushes:
        runfiles = runfiles.merge(t[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            files = depset([launcher]),
            runfiles = runfiles,
            executable = launcher,
        ),
        LifecycleReleaseGroupInfo(
            components = [p.component_name for p in pushes],
            push_labels = [p.push_label for p in pushes],
        ),
    ]

_release_group = rule(
    implementation = _release_group_impl,
    attrs = {
        "pushes": attr.label_list(
            providers = [LifecyclePushInfo],
            mandatory = True,
        ),
        "allow_duplicate_components": attr.bool(default = False),
        "_template": attr.label(
            default = "//lifecycle/release:release_group.sh.tpl",
            allow_single_file = True,
        ),
    },
    executable = True,
)

def coen_applied_release_group(
        name,
        pushes,
        allow_duplicate_components = False,
        visibility = None,
        **kwargs):
    """Aggregate push targets into a single `bazel run`-able release group.

    Args:
      name: Target name.
      pushes: `list[label]` of push targets (must provide
        `LifecyclePushInfo`).
      allow_duplicate_components: When False (default), fails if any two
        pushes share the same `component_name`.
      visibility: Standard Bazel visibility.
      **kwargs: Forwarded to the rule.
    """
    _release_group(
        name = name,
        pushes = pushes,
        allow_duplicate_components = allow_duplicate_components,
        visibility = visibility,
        **kwargs
    )
