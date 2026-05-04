# 02 — `MODULE.bazel` & Pinned Toolchains

Wire up the four ruleset dependencies at the versions mandated by the PRS.

## Prerequisites
- 01 complete.

## Inputs
- PRS §6 (Toolchains & Dependencies) — pinned versions MUST match exactly.

## Outputs
- `MODULE.bazel` declares the following `bazel_dep` entries:
  | name | version |
  |---|---|
  | `rules_oci` | `2.2.6` |
  | `rules_pkg` | `1.1.0` |
  | `rules_helm` | `0.22.1` |
  | `rules_kustomize` | `0.5.3` |
  | `bazel_skylib` | latest minor compatible with the above (≥ 1.7.0) |
  | `rules_python` | compatible with `rules_helm`/`rules_kustomize`; used ONLY for test infra |
- `kustomize` extension is instantiated in `MODULE.bazel` with
  `kustomize.download(version = "v5.8.0")`. A comment above the call
  documents that bumps are a conscious library-version change.
- No `oci.pull` calls at the ruleset level. Base images are the **consumer's**
  responsibility; the ruleset only consumes `@rules_oci//oci:defs.bzl`
  symbols.
- A `MODULE.bazel.lock` file is generated and committed.

## Non-goals
- No dev-time tool pulls (kubectl, minikube, helm CLI, etc.).
- No `http_file` for Helm charts — chart acquisition is the consumer's job.

## Acceptance criteria
- `bazel mod graph` reports exactly the four deps above plus transitive deps.
- Downgrading any single pinned dep by one minor version causes `bazel build
  //...` to either succeed or fail **consistently** (document in CHANGELOG if
  tolerance windows exist).

## Checkboxes
- [x] `bazel_dep(name="rules_oci", version="2.2.6")` added.
- [x] `bazel_dep(name="rules_pkg", version="1.1.0")` added.
- [x] `bazel_dep(name="rules_helm", version="0.22.1")` added.
- [x] `bazel_dep(name="rules_kustomize", version="0.5.3")` added.
- [x] `bazel_skylib` dep added.
- [x] `kustomize.download(version = "v5.8.0")` declared.
- [x] `MODULE.bazel.lock` committed.
- [x] `bazel mod graph` clean.
