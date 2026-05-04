# rules_farakov_lifecycle

**Status:** Early prototype. Not production-ready.

A domain-agnostic Bazel ruleset for managing Kustomize & Helm manifest
rendering, OCI artifact packaging, and container-registry publishing.
Consuming repositories declare their own environment names and overlay
structures; the ruleset encodes zero opinions about directory layout or
deployment environments.

## What this is

- A library of macros and rules that render Kubernetes manifests, build
  OCI images, and expose `bazel run`-able push targets.
- Configurable from outside: callers define environments, layout prefixes,
  and image references.

## What this is NOT

- A Kubernetes client (`kubectl`, `minikube`, `kind`). Local dev cluster
  operations belong in consumer-repo wrapper scripts.
- A release-automation script. The ruleset produces push targets; a CI
  pipeline decides when and in what order to invoke them.
- An opinionated project scaffold. There is no required directory layout.

## Getting started

Work in progress. See `docs/plan/` for the implementation roadmap and
`docs/ORIGINAL_PRS.md` for the full project specification.

## License

Apache-2.0 — see [LICENSE](./LICENSE).
