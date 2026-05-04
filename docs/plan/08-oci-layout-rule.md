# 08 — OCI Layout Rule

Produce a `.tar` artifact containing manifest files at caller-configurable
paths inside the archive. Replaces both `_manifests_tar` and
`_service_manifests_tar` from the reference repos — a single rule that is
flexible enough for both bundle ("fleet") and per-service ("flat") modes.

## Prerequisites
- 04 complete.

## Inputs
- Reference: `pave-infra-monorepo/build_defs/k8s/manifests_oci.bzl`.
- PRS §3 ("Flexible OCI Artifact Layouts").

## Outputs

### File: `lifecycle/oci/layout.bzl`
Exposes an **internal** rule `_manifests_tar` plus a public macro
`manifests_oci_layout`.

### Rule: `_manifests_tar`
Attrs:
- `manifests` — `label_list` of targets that provide
  `LifecycleManifestsInfo` (preferred) **or** files `allow_files = [".yaml",
  ".yml"]` (fallback).
- `layout` — `string_dict` mapping **source token → archive prefix**.
  - Special key `"*"` acts as the default prefix applied to any file whose
    owning package is not otherwise matched.
  - Other keys are matched as prefixes of
    `LifecycleManifestsInfo.source_package` (or `f.owner.package` for raw
    file inputs). The longest matching key wins.
  - Example: `{"*": "manifests", "services/gateway": "bundles/gateway/root"}`
- `layout_callback` — `label` pointing to a `py_binary` taking JSON argv
  describing `{src_path, owner_package}` and returning the target archive
  path. This is the "structural provider" escape hatch from the PRS; when
  set, `layout` is ignored.
- `include_kustomization` — `bool`, default True. When True, a generated
  `kustomization.yaml` lists every archive resource.
- `kustomization_api_version` — `string`, default `"kustomize.config.k8s.io/v1beta1"`.
- `kustomization_prefix` — `string`, default `""`. When set, the generated
  kustomization is placed at `<prefix>/kustomization.yaml`; otherwise at the
  archive root (which means multi-prefix layouts must opt out of the
  auto-kustomization).
- `dedup_strategy` — `string`, one of `"package_basename"` (default, fleet
  mode) or `"basename"` (flat mode). Replaces the duplicated tar rules from
  the reference.
- `out` — output `.tar` file, defaults to `<name>.tar`.

Implementation (all hermetic, no shell out):
1. Walk `ctx.attr.manifests`. For each target:
   - If it provides `LifecycleManifestsInfo`, use `info.files` + `info.directories`.
   - Else use `target.files` (YAML file fallback).
   - Compute the archive prefix via `layout` (longest-prefix match) or
     `layout_callback` (single spawn action).
2. Generate a manifest mapping file `<name>_layout.json` via
   `ctx.actions.write(content = json.encode(...))`.
3. Generate a `kustomization.yaml` if requested, via `ctx.actions.write`.
4. Run a single Starlark-native packaging action using
   `@rules_pkg//pkg:tar.bzl` style internals — specifically, we declare a
   `pkg_filegroup`-equivalent in Starlark that emits `pkg_files` and
   `pkg_tar` actions. **Avoid shelling out to `tar`.** If the final hermetic
   cost of reimplementing `pkg_tar` is too high, re-export it here instead.
   The prototype implementation MAY use `pkg_tar` directly by having the
   macro emit one `pkg_tar` target fed by a computed `pkg_files` set
   (preferred).
5. The rule returns `[DefaultInfo(files = depset([out]))]`.

### Macro: `manifests_oci_layout`
Thin wrapper that:
- Defaults `layout` to `{"*": "manifests"}` (matching the reference repos'
  single-prefix behavior).
- Accepts `flat = True` as syntactic sugar for `dedup_strategy = "basename"`
  and `layout = {"*": "manifests"}`.

## Acceptance criteria
- A caller can produce an archive where service A lives at
  `/bundles/A/manifests/...` and service B lives at `/root/...`.
- A caller using defaults still gets the same layout the reference repos
  produced (`/manifests/<pkg>/*.yaml`).
- `flat = True` produces `/manifests/*.yaml` with basename-only dedup.
- No `tar -czf` subprocess call anywhere. `pkg_tar` is the only path to a tar
  file.
- No hardcoded env strings.

## Checkboxes
- [ ] `_manifests_tar` rule drafted.
- [ ] `manifests_oci_layout` macro drafted.
- [ ] Longest-prefix layout matching implemented.
- [ ] `layout_callback` escape hatch validated.
- [ ] Kustomization generation is optional and path-configurable.
- [ ] Dedup strategies `package_basename` and `basename` both work.
- [ ] No direct `tar` subprocess in the action graph.
