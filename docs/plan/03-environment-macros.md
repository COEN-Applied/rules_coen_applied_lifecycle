# 03 — Dynamic Environment Macros

Replace the hardcoded `{"dev","staging","prod"}` envs with a caller-driven
set. Consumers call one macro, get back: `config_setting` targets, build-flag
rules, and a `select_env`-style helper.

## Prerequisites
- 02 complete.

## Inputs
- PRS §3 ("Dynamic Environment Flags").
- Analysis of `pave-infra-monorepo/build_flags/flags.bzl` (do NOT copy env
  names).

## Outputs

### File: `lifecycle/environments/flags.bzl`
Defines three rule-based build settings (all string-typed, all `flag = True`):
  1. `lifecycle_environment` — value validated against caller-provided list.
     Emits `LifecycleEnvironmentInfo(name = str)`.
  2. `lifecycle_image_tag` — emits `LifecycleImageTagInfo(tag = str)`. Impl
     rejects empty strings.
  3. `lifecycle_image_registry` — emits `LifecycleImageRegistryInfo(registry =
     str)`. Impl rejects empty strings.
Notes:
- Provider field names are `name` / `tag` / `registry` — NOT `type` (PRS
  explicitly calls out removal of domain-specific naming).
- The `lifecycle_environment` rule takes an `allowed_values` attribute (list
  of strings) and fails analysis if the flag's value is not in that list. The
  factory macro below supplies the list.

### File: `lifecycle/environments/select_env.bzl`
Exposes a single helper `select_env(mapping, default = None, flag =
LABEL_OF_ENV_FLAG)`:
  - Takes a `dict[str, Any]` keyed by environment name.
  - Builds `select({"@@//<pkg>:<env>": v for env, v in mapping.items()})`
    where each `<env>` is the `config_setting` name produced by the factory.
  - If `default` is supplied, uses it for `//conditions:default`; otherwise
    omits the default branch.
  - Does NOT assume `dev` is a default fallback (that was a leak of
    company-specific policy).

### File: `lifecycle/environments/defs.bzl`
Exposes the public factory macro:
```
farakov_lifecycle_environments(
    name,                     # unused but required by Bazel convention; pass ""
    environments,             # list[str], non-empty, deduped, lowercase
    default_environment,      # str, must be in environments
    default_image_tag = "latest",
    default_image_registry = "",  # empty string OK only if callers always override
    visibility = None,
)
```
Generates in the caller's package:
  - `:<env>` `config_setting` for each env with `flag_values =
    {":environment": env}`.
  - `:environment` (the `lifecycle_environment` instance; `allowed_values =
    environments`, `build_setting_default = default_environment`).
  - `:image_tag` (`lifecycle_image_tag`).
  - `:image_registry` (`lifecycle_image_registry`).
  - `:envs.bzl`-like runtime-accessible list? **No** — use a text file
    `:environments.txt` only if needed for debugging; the canonical source is
    the Starlark list.

### File: `lifecycle/environments/BUILD.bazel`
Exports only the `.bzl` files via `bzl_library` (skylib). No targets.

## Acceptance criteria
- A consuming workspace can call `farakov_lifecycle_environments(environments
  = ["dev","prod"], default_environment = "dev")` and immediately use
  `--//build_flags:environment=prod` on the command line.
- A consumer calling with `environments = ["foo","bar","baz"]` gets three
  working `config_setting`s and zero references to `dev`/`staging`/`prod`
  anywhere in the generated graph.
- `select_env({"dev": ["a.yaml"], "prod": ["b.yaml"]}, default = [])` returns
  a well-formed `select()` expression.
- Passing an invalid env on the command line
  (`--//build_flags:environment=qa` when only `["dev","prod"]` are allowed)
  fails analysis with a clear message.

## Checkboxes
- [ ] `flags.bzl` rules + providers written.
- [ ] `select_env.bzl` helper written.
- [ ] `defs.bzl` factory macro written.
- [ ] `BUILD.bazel` bzl_library targets declared.
- [ ] Label references to the three flags are routed through a single
      module-level struct (no duplication in sibling files).
- [ ] Manual smoke test with `environments = ["foo","bar"]` verified.
