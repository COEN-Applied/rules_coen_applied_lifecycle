# 07 — Helm Manifest Rule

Provide the `helm_manifest` wrapper that reference repos hand-rolled in each
service BUILD file (values selection via `select_env`, then `helm_template`,
then optional image rewriting).

## Prerequisites
- 04, 05 complete.

## Inputs
- Existing usage in `pave-infra-monorepo/services/vault/BUILD.bazel`,
  `gateway/BUILD.bazel`, `external-secrets/BUILD.bazel`.

## Outputs

### File: `lifecycle/manifests/helm_manifest.bzl`
Exposes a macro `helm_manifest` (since it composes multiple rules: a
`helm_template` from `rules_helm` plus optional image rewriting plus
optional CRD/non-CRD split).

Signature:
```
helm_manifest(
    name,
    chart,                          # label → .tgz chart target
    values_per_env = None,          # dict[str, list[label]]; optional
    base_values = None,             # list[label]; always included, below env overlays
    release_name = None,
    namespace = None,
    image_refs = None,
    env_flag, tag_flag, registry_flag,  # same keyword-required as kustomize
    split_crds = False,             # bool; see CRD split below
    out = None,
    visibility = None,
)
```

Implementation:
1. Compute values list with `select_env(values_per_env or {}, default =
   base_values or [], flag = env_flag)`. The macro delegates to task 03's
   `select_env` utility; the ruleset itself never names `dev`/`prod`.
2. Instantiate `@rules_helm//helm:defs.bzl%helm_template` with `values =
   (base_values or []) + <selected_values_list>` and output =
   `<name>.rendered.yaml`.
3. If `image_refs` non-empty, run the rewriter (task 05) and write
   `<name>.yaml`. Otherwise rename the helm output to `<name>.yaml` via an
   alias rule.
4. If `split_crds == True`, emit additional targets `<name>.crds.yaml` and
   `<name>.workloads.yaml` using a small Starlark-native splitter rule
   (see 07a below). Their targets also appear in the returned
   `LifecycleManifestsInfo`.

### File: `lifecycle/manifests/split_manifest.bzl`  (7a)
Internal rule `split_manifest_by_kind` that reads a rendered YAML and writes
two outputs partitioned by YAML document `kind` field matching a caller list
(default: `["CustomResourceDefinition"]`). Implemented as a `py_binary`
invoked via `ctx.actions.run` (reuse the hermetic python toolchain from 05).
No bash.

## Acceptance criteria
- Callers can render a Helm chart and get back a `LifecycleManifestsInfo` the
  OCI rules consume.
- CRD split works on real-world charts (Vault, external-secrets) without
  shell helpers.
- No hardcoded env names.

## Checkboxes
- [ ] `helm_manifest` macro written.
- [ ] `split_manifest_by_kind` rule written (if `split_crds = True` callers
      exist).
- [ ] Returns or synthesises a target providing `LifecycleManifestsInfo`.
- [ ] `env_flag` / `tag_flag` / `registry_flag` threaded through.
