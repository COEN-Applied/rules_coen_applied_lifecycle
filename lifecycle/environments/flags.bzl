"""Build-setting rules backing `coen_applied_lifecycle_environments`.

Three string-typed flag rules, each emitting a dedicated provider. These are
the ONLY place in the ruleset where a rule produces a
`Lifecycle{Environment,ImageTag,ImageRegistry}Info`; every downstream rule
consumes them via `providers = [...]` declarations on label attributes.

The `environment` flag is different from the other two in that it validates
its value against a caller-supplied allow-list. The allow-list is baked in
at the flag's declaration site (via the `allowed_values` attribute) by the
`coen_applied_lifecycle_environments` factory macro — this is how we avoid the
hardcoded `["dev","staging","prod"]` assumption from the reference repos.
"""

load(
    "//lifecycle/providers:providers.bzl",
    "LifecycleEnvironmentInfo",
    "LifecycleImageRegistryInfo",
    "LifecycleImageTagInfo",
)

# ------------------------------------------------------------------------
# lifecycle_environment
# ------------------------------------------------------------------------

def _lifecycle_environment_impl(ctx):
    value = ctx.build_setting_value
    allowed = ctx.attr.allowed_values
    if not allowed:
        fail(
            "lifecycle_environment rule at {label} was declared with an " +
            "empty allowed_values list. Did you call " +
            "coen_applied_lifecycle_environments(environments=[...]) with an " +
            "empty list?".format(label = ctx.label),
        )
    if value not in allowed:
        fail(
            "--{flag}={value} is not one of the allowed environments {allowed}.".format(
                flag = str(ctx.label),
                value = value,
                allowed = allowed,
            ),
        )
    return LifecycleEnvironmentInfo(name = value)

lifecycle_environment = rule(
    implementation = _lifecycle_environment_impl,
    attrs = {
        "allowed_values": attr.string_list(
            mandatory = True,
            doc = "Closed set of permissible values. Enforced at analysis " +
                  "time; overriding the flag to a value outside this list " +
                  "is an error.",
        ),
    },
    build_setting = config.string(flag = True),
    doc = "String build flag naming the active deployment environment.",
)

# ------------------------------------------------------------------------
# lifecycle_image_tag
# ------------------------------------------------------------------------

def _lifecycle_image_tag_impl(ctx):
    value = ctx.build_setting_value
    if value == "":
        fail(
            "--{flag} must be a non-empty string (e.g. 'v1.2.3', " +
            "'2025-01-15-abcdef1').".format(flag = str(ctx.label)),
        )
    return LifecycleImageTagInfo(tag = value)

lifecycle_image_tag = rule(
    implementation = _lifecycle_image_tag_impl,
    build_setting = config.string(flag = True),
    doc = "String build flag carrying the image tag for pushed artifacts.",
)

# ------------------------------------------------------------------------
# lifecycle_image_registry
# ------------------------------------------------------------------------

def _lifecycle_image_registry_impl(ctx):
    value = ctx.build_setting_value
    if value == "":
        fail(
            "--{flag} must be a non-empty string (e.g. " +
            "'ghcr.io/acme', 'registry.internal.example.com/platform').".format(
                flag = str(ctx.label),
            ),
        )
    if value.endswith("/"):
        fail(
            "--{flag}={value} must not end with a trailing slash.".format(
                flag = str(ctx.label),
                value = value,
            ),
        )
    return LifecycleImageRegistryInfo(registry = value)

lifecycle_image_registry = rule(
    implementation = _lifecycle_image_registry_impl,
    build_setting = config.string(flag = True),
    doc = "String build flag naming the target registry host + org prefix.",
)
