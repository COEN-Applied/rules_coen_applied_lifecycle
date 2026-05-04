# 10 — Release Group (Target Aggregation)

Replace the reference repo's `bazel query 'attr(name,"-manifests-push$",...)'`
release-time discovery with build-time target aggregation.

## Prerequisites
- 09 complete.

## Inputs
- PRS §4 ("Target Aggregation (Discovery)").
- Reference: `pave-infra-monorepo/k8s/manifests_push_all.sh`.

## Outputs

### File: `lifecycle/release/release_group.bzl`

### Rule: `_release_group`
Attrs:
- `pushes` — `label_list(providers = [LifecyclePushInfo])`.
- `allow_duplicate_components` — `bool`, default False. When False, fails
  analysis if any two `pushes` share the same `component_name`.
- `out` — output executable file.

Impl:
1. Gather the `push_executable` from each dep.
2. Emit a launcher script via `ctx.actions.expand_template` (no handwritten
   bash) — template is shipped in-tree as
   `lifecycle/release/release_group.sh.tpl` and contains portable POSIX sh
   (works on macOS + Linux CI). The template is **pure placeholder
   substitution** — no runtime logic invents paths.
3. Mark the script executable via `is_executable = True` on
   `declare_file()`.
4. `DefaultInfo(files = depset([out]), runfiles =
   ctx.runfiles(files = [<each push executable>]))` with
   `executable = out`.

Return `[DefaultInfo(...),
         LifecycleReleaseGroupInfo(components = [...])]` so that
release_groups may themselves be composed into larger release_groups.

### Macro: `farakov_release_group`
```
farakov_release_group(
    name,
    pushes,             # list of labels from manifests_oci_push / application_oci_push
    allow_duplicate_components = False,
    tags = None,
    visibility = None,
)
```
Thin wrapper. Exposes a `bazel run //path:release_group -- [extra args]`
entrypoint that runs every push sequentially, forwarding any user-supplied
args to every push. Exit status = first non-zero push.

### Optional sub-macro: `farakov_release_group_per_env`
For consumers that want one release_group per env without writing the
cartesian product by hand:
```
farakov_release_group_per_env(
    name,
    pushes,
    environments,   # list[str] — must match the ones in farakov_lifecycle_environments
)
```
Generates `<name>.<env>` targets that each carry the same `pushes` but are
invoked with pre-set flag values via `sh_binary` `args = ["--//.../
environment=<env>"]`. Keep this optional — it's a convenience, not core.

## Acceptance criteria
- No runtime `bazel query` in release plumbing.
- Release discovery is a pure analysis-time graph: `bazel cquery
  'kind("_release_group", //...)'` reveals every release group explicitly.
- A release_group containing N pushes exits with the first non-zero status.
- Duplicate-component detection catches a human error at analysis time.

## Checkboxes
- [ ] `_release_group` rule implemented.
- [ ] Launcher template committed.
- [ ] Runfiles correctly populated so `bazel run` finds each child push.
- [ ] `farakov_release_group` macro exposed.
- [ ] `LifecycleReleaseGroupInfo` provider added to `providers.bzl`.
- [ ] Duplicate detection verified.
