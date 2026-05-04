"""Public factory macro: `farakov_lifecycle_environments`.

This macro is the single seam through which a consuming repository declares
its deployment environments. Invoking it in a package (by convention
`//deploy/flags:BUILD.bazel`) generates:

  * One `lifecycle_environment` string flag, constrained to the supplied
    `environments` list, with the supplied `default_environment` as its
    build_setting_default.
  * One `config_setting` per environment, each matching the flag to that
    environment name.
  * One `lifecycle_image_tag` string flag.
  * One `lifecycle_image_registry` string flag.

CRITICAL CONTRACT: the reference repositories hardcoded the environment set
`["dev","staging","prod"]` in *five* different `.bzl` files. This macro
replaces all of them. Downstream rules in rules_farakov_lifecycle NEVER
reference a specific environment name; they consume the flags and their
providers by label, with the labels passed in explicitly by the caller.

Usage:

    # //deploy/flags/BUILD.bazel
    load(
        "@rules_farakov_lifecycle//lifecycle:defs.bzl",
        "farakov_lifecycle_environments",
    )

    farakov_lifecycle_environments(
        environments = ["dev", "qa", "prod"],
        default_environment = "dev",
        default_image_tag = "latest",
        default_image_registry = "ghcr.io/acme",
    )

After which callers pass flag labels to downstream rules as:

    kustomize_manifest(
        ...,
        env_flag      = "//deploy/flags:environment",
        tag_flag      = "//deploy/flags:image_tag",
        registry_flag = "//deploy/flags:image_registry",
    )
"""

load(
    ":flags.bzl",
    "lifecycle_environment",
    "lifecycle_image_registry",
    "lifecycle_image_tag",
)

# Canonical target names generated inside the caller's package. Exposed as
# module-level constants so tooling (release scripts, stardoc, etc.) can
# reference them without duplication.
ENVIRONMENT_FLAG_NAME = "environment"
IMAGE_TAG_FLAG_NAME = "image_tag"
IMAGE_REGISTRY_FLAG_NAME = "image_registry"

def _dedup_preserve_order(xs):
    seen = {}
    out = []
    for x in xs:
        if x in seen:
            continue
        seen[x] = True
        out.append(x)
    return out

def _validate_env_name(name):
    # Keep env names to the lowercase DNS-label character set so they can
    # safely appear in image tags, config_setting names, and k8s
    # namespaces. Intentionally stricter than Bazel target-name rules.
    if not name:
        fail("farakov_lifecycle_environments: environment names must be non-empty.")
    if name != name.lower():
        fail("farakov_lifecycle_environments: environment '%s' must be lowercase." % name)
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
    for ch in name.elems():
        if ch not in allowed:
            fail(
                "farakov_lifecycle_environments: environment name '%s' " % name +
                "contains invalid character %r. Allowed: [a-z0-9-]." % ch,
            )
    if name[0] == "-" or name[-1] == "-":
        fail("farakov_lifecycle_environments: environment '%s' must not start or end with '-'." % name)

def farakov_lifecycle_environments(
        environments,
        default_environment,
        default_image_tag = "latest",
        default_image_registry = "",
        visibility = None):
    """Generate the environment/tag/registry flags + config_settings.

    Args:
      environments: `list[str]`. Non-empty, deduplicated, lowercase
        DNS-label-compatible identifiers. The set of environments this
        repository recognizes. No default; callers must decide.
      default_environment: `str`. The initial value of the environment
        flag. MUST be an element of `environments`.
      default_image_tag: `str`. Initial value of the image_tag flag.
        Defaults to `"latest"`; consumers should typically override via
        `--//<pkg>:image_tag=<sha>` at build time.
      default_image_registry: `str`. Initial value of the image_registry
        flag. Defaults to the empty string, which is a *safe default* in
        the sense that the image_registry rule will fail analysis unless
        overridden — callers are thereby forced to make registry choice
        explicit on the command line or in `.bazelrc`.
      visibility: `list[str]` or `None`. Visibility of the generated
        targets. Defaults to the package's default_visibility.
    """
    if type(environments) != "list":
        fail("farakov_lifecycle_environments: `environments` must be a list, got %s." % type(environments))
    if not environments:
        fail("farakov_lifecycle_environments: `environments` must be non-empty.")

    envs = _dedup_preserve_order(environments)
    for env in envs:
        _validate_env_name(env)

    if default_environment not in envs:
        fail(
            "farakov_lifecycle_environments: default_environment='%s' " % default_environment +
            "is not a member of environments=%s." % envs,
        )

    # The environment flag itself, with its allow-list baked in.
    lifecycle_environment(
        name = ENVIRONMENT_FLAG_NAME,
        build_setting_default = default_environment,
        allowed_values = envs,
        visibility = visibility,
    )

    # One config_setting per environment, keyed on the flag above. These are
    # what `select_env` matches on.
    for env in envs:
        native.config_setting(
            name = env,
            flag_values = {":" + ENVIRONMENT_FLAG_NAME: env},
            visibility = visibility,
        )

    lifecycle_image_tag(
        name = IMAGE_TAG_FLAG_NAME,
        build_setting_default = default_image_tag,
        visibility = visibility,
    )

    lifecycle_image_registry(
        name = IMAGE_REGISTRY_FLAG_NAME,
        build_setting_default = default_image_registry,
        visibility = visibility,
    )
