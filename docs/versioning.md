# Versioning

`rules_coen_applied_lifecycle` follows [Semantic Versioning 2.0.0](https://semver.org/).

## What bumps MAJOR

- Renaming or removing a public symbol re-exported from
  `//lifecycle:defs.bzl`.
- Renaming or removing a field from any of the public providers
  (`LifecycleEnvironmentInfo`, `LifecycleImageTagInfo`,
  `LifecycleImageRegistryInfo`, `LifecycleManifestsInfo`,
  `LifecyclePushInfo`, `LifecycleReleaseGroupInfo`).
- Changing the meaning of an existing attribute in a way that breaks
  previously-valid consumer BUILD files.
- Removing or renaming a keyword argument on a public macro (e.g. the
  `flag_package` argument of `select_env`).

## What bumps MINOR

- Adding a new macro, rule, or provider re-exported from the public API.
- Adding a new attribute to an existing rule or macro with a default that
  preserves prior behavior.
- Bumping any pinned toolchain dep (`rules_oci`, `rules_pkg`, `rules_helm`,
  `rules_kustomize`) when the downstream bump is backwards-compatible for
  our consumers.

## What bumps PATCH

- Bug fixes.
- Documentation and error-message improvements.
- Internal refactors invisible to callers (e.g. reorganising
  `lifecycle/private/`).

## Toolchain bumps

Bumping a pinned toolchain is always a MINOR bump at minimum. If the
upstream toolchain has a breaking change that forces consumer BUILD-file
edits, the bump is MAJOR.

## Pre-release tags

Pre-release identifiers follow SemVer's `-rc.N`, `-beta.N`, and `-alpha.N`
conventions. CI's `release.yaml` workflow accepts tags in any of:

- `vMAJOR.MINOR.PATCH`
- `vMAJOR.MINOR.PATCH-rc.N`
- `vMAJOR.MINOR.PATCH-beta.N`
- `vMAJOR.MINOR.PATCH-alpha.N`
