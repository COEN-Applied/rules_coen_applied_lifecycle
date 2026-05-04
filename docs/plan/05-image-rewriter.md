# 05 — Image Rewriter (Starlark-Native)

Replace the Python-based `rewrite_images.py` with a pure-Starlark rule.
Rationale: the current Python tool is a ~100-line regex wrapper; doing the
rewrite via `ctx.actions.run_shell` pulls in a non-hermetic `python3`
dependency. We eliminate it by using `jq`/`yq`-free Starlark substitution
emitted into a small shell action, OR by using `rules_pkg`'s
`pkg_files.renames` mechanism where applicable.

**Decision (to validate during implementation):** implement the rewriter as a
regular Starlark rule that, for each input YAML file, emits an action calling
a bundled tool. Because Starlark cannot read+write file contents at analysis
time, the action must be executed. We pick **one** of the following; agents
must pick and document the decision before writing code:

1. **Option A — tiny Go tool.** Ship a `go_binary` (via `rules_go` — but that
   adds a dep not in the PRS). **Rejected.**
2. **Option B — tiny Python tool shipped as `py_binary`.** Uses
   `rules_python`'s hermetic interpreter toolchain. **Selected** — it is the
   lowest-risk path that stays hermetic and keeps the rewriter debuggable.
3. **Option C — `sed` via `use_default_shell_env`.** Non-hermetic across
   macOS/Linux. **Rejected.**

## Prerequisites
- 04 complete.
- `rules_python` declared as a `bazel_dep` in `MODULE.bazel` (allowed because
  it's infrastructure, not a consumer-visible toolchain — the generated
  rewriter binary consumes the hermetic interpreter under the hood).

## Inputs
- Reference: `pave-infra-monorepo/build_defs/k8s/rewrite_images.py` for the
  regex specification.

## Outputs

### File: `lifecycle/private/rewrite_images.py`
Standalone `__main__` script. Accepts `SRC=DST` pairs on argv, reads stdin,
writes rewritten YAML to stdout. Supports:
- Tag or digest in DST (`repo:tag` or `repo@sha256:…`).
- Optional quoting (`'` or `"`) preserved symmetrically.
- Optional YAML list marker (`- image:`).
- Optional trailing comment.
- Rejects rewrite rules containing a literal `=` in the SRC by using
  `str.partition('=')`.

### File: `lifecycle/private/BUILD.bazel`
Declares `py_binary(name = "rewrite_images", srcs = ["rewrite_images.py"],
visibility = ["//visibility:public"])` and a `bzl_library`.

### File: `lifecycle/manifests/image_rewrite.bzl`
Exposes an **internal** helper `_rewrite_action(ctx, src_yaml, out_yaml,
rules_dict, registry, tag)`:
- Accepts a `dict[str, str]` mapping `src_image_ref -> dst_image_ref`.
- If a DST value does NOT contain `/`, treats it as a bare repo name and
  prepends `registry + "/"`.
- If a DST value does NOT contain `:` or `@`, appends `":" + tag`.
- Validates that neither SRC nor DST contains `'` (single-quote) — this
  keeps argv parsing simple on both BSD & GNU shells.
- Emits a single `ctx.actions.run` (NOT `run_shell`) invoking the
  `rewrite_images` py_binary with argv = `[src_yaml.path] + [dst_yaml.path] +
  ["SRC=DST", ...]`. The py_binary reads from argv[1] and writes to argv[2]
  instead of stdin/stdout — refactor the tool accordingly so we avoid shell
  redirection.
- Declares `inputs = [src_yaml]`, `outputs = [out_yaml]`, `tools =
  [ctx.executable._rewriter]`.

### Helper constants
- `IMAGE_REWRITE_ATTRS` — a dict added to any rule that wants to opt into
  rewriting (`image_refs`, `_rewriter`). Rules unpack with `**
  IMAGE_REWRITE_ATTRS`.

## Acceptance criteria
- No rule shells out via `run_shell` for the rewrite step.
- A YAML containing `image: localhost/myorg/svc:dev` with rule `{"localhost/myorg/svc": "ghcr.io/acme/svc"}` and tag `"1.2.3"` is rewritten to `image: ghcr.io/acme/svc:1.2.3`.
- A DST like `"ghcr.io/acme/svc@sha256:deadbeef…"` is passed through unchanged
  (digest preserved).
- A DST like `"my-svc"` with registry `"ghcr.io/acme"` and tag `"v1"`
  produces `ghcr.io/acme/my-svc:v1`.

## Checkboxes
- [ ] `rewrite_images.py` tool written with argv-in / argv-out I/O.
- [ ] `py_binary` target declared in `lifecycle/private/BUILD.bazel`.
- [ ] `image_rewrite.bzl` helper written.
- [ ] Validation of `'` in rules implemented at analysis time.
- [ ] Auto-qualification of bare repo DSTs implemented.
- [ ] Manual smoke test with tag, digest, and bare-repo DSTs passes.
