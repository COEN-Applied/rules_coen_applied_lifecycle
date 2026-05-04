# 12 — Dummy Workspace & Hermetic Tests

Per PRS §5, ship a `tests/` workspace that consumes the ruleset locally and
exercises every public macro end-to-end.

## Prerequisites
- 11 complete.

## Outputs

### Dir: `tests/`
A standalone Bazel workspace:
- `tests/MODULE.bazel` with `bazel_dep(name="rules_farakov_lifecycle",
  version="0.0.0"); local_path_override(module_name="rules_farakov_lifecycle",
  path="..")`.
- `tests/.bazelrc` same skeleton as the main repo's.
- `tests/BUILD.bazel` invoking `farakov_lifecycle_environments(environments =
  ["alpha", "beta", "gamma"], default_environment = "alpha")` in a nested
  `//flags` package — crucially the envs are **not** `dev/staging/prod` to
  prove the library is domain-agnostic.

### Mock services under `tests/services/`
- `tests/services/svc_a/` — kustomize-based service with base + two overlays.
  Exercises: `kustomize_manifest`, `manifests_oci_layout` (flat layout),
  `manifests_oci_push`.
- `tests/services/svc_b/` — helm-based service with a fake chart tarball
  checked into the workspace (≤5 kB). Exercises: `helm_manifest`, CRD
  splitting.
- `tests/services/svc_c/` — multi-prefix layout (`{"*": "manifests",
  "services/svc_c/special": "overrides"}`). Exercises layout attribute.

### Aggregator `tests/release/BUILD.bazel`
Calls `farakov_release_group` over all three pushes.

### Tests `tests/tests/`
Implemented as **`diff_test`** from `bazel_skylib` + a couple of custom
`sh_test` driving `tar tf` to inspect archive layouts. Categories:

1. **Manifest rendering tests**
   - `svc_a_dev_manifests_diff_test` — compares the kustomize-rendered YAML
     against a golden file for `--//flags:environment=alpha`.
   - Same for `beta` and `gamma`.

2. **Image rewriting tests**
   - `svc_a_image_rewrite_test` — greps the rendered YAML for the expected
     rewritten image:tag pair.

3. **OCI layout tests**
   - `svc_a_flat_layout_test` — `tar tf` output compared to golden listing.
   - `svc_c_multi_prefix_layout_test` — verifies both `/manifests/…` and
     `/overrides/…` paths exist.

4. **Release group tests**
   - `release_group_enumeration_test` — `bazel cquery` executed via a
     wrapper `sh_test` to enumerate release_group's `pushes` and compare
     against a golden list.
   - Does NOT actually push (no registry contact).

## Hermeticity constraints
- No test may shell out to `kubectl`, `minikube`, `docker`, `helm`, `kustomize`
  (the last two are invoked only via the rule toolchains).
- No network fetches during test execution; all chart artifacts live in-tree.

## Acceptance criteria
- `bazel build //...` in `tests/` succeeds.
- `bazel test //...` in `tests/` passes green on macOS arm64 and Linux
  amd64.
- Removing any env from `farakov_lifecycle_environments` causes the
  corresponding diff_test to fail with a clean missing-flag error.

## Checkboxes
- [x] Dummy workspace scaffolded with `local_path_override`.
- [x] Non-canonical env names `["alpha","beta","gamma"]` wired up.
- [x] Three mock services exercising kustomize + helm + multi-prefix layouts.
- [x] Golden files committed.
- [x] `diff_test` + archive-layout tests green.
- [x] Release_group enumeration test green.
