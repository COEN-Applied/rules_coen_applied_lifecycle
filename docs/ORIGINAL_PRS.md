## Project Requirement Specification (PRS): `rules_farakov_lifecycle`

### 1. Project Overview & Identity
This project aims to extract, generalize, and encapsulate the Kubernetes manifest rendering and OCI image deployment logic currently coupled within specific company repositories. 

* **Repository Name:** `rules_farakov_lifecycle`
* **Purpose:** A domain-agnostic Bazel ruleset for managing Kustomize/Helm manifest rendering, OCI artifact packaging, and container registry publishing.
* **Distribution:** Initially targeting GitHub Container Registry (GHCR), with an architecture that allows seamless transition to a private enterprise registry.
* **Versioning:** Strict adherence to Semantic Versioning (SemVer) for all releases of the ruleset.

---

### 2. Migration & Reference Material
To ensure the generalized rules account for all current company use cases, the implementation agents must analyze the existing implementations.

* **Primary Reference (`pave-infra-monorepo`):** This repository is the primary source of truth for the current implementation. Agents should extract the core logic from its `build_defs/k8s/` and `build_defs/oci/` directories, specifically focusing on the `rewrite_images.py`, `service_manifest.bzl`, and `manifests_oci.bzl` workflows.
* **Secondary Reference (`pave-monorepo`):** This repository serves as the secondary reference. Agents must review how application-specific deployments (e.g., standard microservices vs. infrastructure components) utilize the deployment logic to ensure the new library's configurability fully supports application-tier edge cases.
* **Goal:** The final library must successfully act as a drop-in replacement (once configured) for the deployment logic in both of these repositories, without leaking domain-specific concepts from either into the `rules_farakov_lifecycle` codebase.

---

### 3. Core Architecture & Configurability
The library must abandon all hardcoded assumptions regarding directory structures, project layouts, and deployment pipelines.

* **Dynamic Environment Flags:** The library will expose a Starlark macro (e.g., `farakov_lifecycle_environments(environments = ["dev", "prod"])`) allowing consuming repositories to generate their own `config_setting` rules and build flags. The hardcoded `dev`, `staging`, and `prod` logic must be completely removed.
* **Parameterized Manifest Pathing:** Manifest rendering rules (like the current `k8s_service_manifest`) must not hardcode lookups to `k8s/overlays/{env}`. Instead, rules will accept explicit file targets or filegroups via attributes (e.g., `base_manifests`, `overlay_manifests`). The Starlark implementation will dynamically compute the execution paths using Bazel's `ctx.label.package` context or explicit attribute mapping.
* **Flexible OCI Artifact Layouts:** The structure inside the final OCI container must be configurable. Instead of forcing files into a strict `/manifests/<package_path>` directory, the packaging rules will accept a mapping (dictionary) or use structural providers to let the consuming repository define exactly where files are placed inside the deployment tarball.

---

### 4. Execution & Orchestration
The library will eliminate reliance on runtime Bash scripting for core deployment logic, favoring native Bazel action graphs and Starlark rule definitions.

* **Starlark-Native Pushing:** The core logic of bundling and pushing to OCI registries will be handled entirely via `@rules_oci` push targets wrapped in Starlark macros. 
* **Target Aggregation (Discovery):** The library will replace runtime `bazel query` discovery with build-time target aggregation. A macro or custom rule (e.g., `farakov_release_group`) will be created to link individual service push targets together at analysis time, creating a single runnable executable that pushes the entire fleet.
* **Local Development Decoupling:** Non-hermetic, machine-local tools (`kubectl`, `minikube`) will be excluded from the library. The library will expose standard Bazel targets (like `.tar` archives or `oci_image` labels). Consuming repositories will be responsible for maintaining their own minimal, repository-specific wrapper scripts to hook these hermetic outputs into their local development clusters.

---

### 5. Testing & Quality Assurance
To ensure long-term stability and prevent regressions across consuming repositories, the ruleset must include its own hermetic testing pipeline.

* **Dummy Workspace:** A dedicated `tests/` directory must be created at the root of `rules_farakov_lifecycle`. This directory will act as a standalone, dummy Bazel workspace that consumes the local ruleset.
* **Structural Testing:** The dummy workspace will implement mock services using the library's macros. Tests (using Bazel's `sh_test` or equivalent native testing rules) will verify that:
    * Kustomize and Helm manifests are rendered and stitched correctly.
    * Image string rewriting functions accurately under various configurations.
    * The internal directory structures of the generated OCI `.tar` archives match the configured layouts.
* **CI Integration:** Continuous Integration (e.g., GitHub Actions) must execute `bazel build //...` and `bazel test //...` within this dummy workspace on every Pull Request to validate the library's logic without actually pushing artifacts to a remote registry.

---

### 6. Toolchains & Dependencies
The ruleset will utilize pinned versions of standard Bazel rules to ensure stability, requiring manual bumps during library updates.

| Dependency Name | Target Version | Primary Purpose |
| :--- | :--- | :--- |
| `rules_oci` | 2.2.6 | OCI image packaging and remote registry publishing. |
| `rules_pkg` | 1.1.0 | Tarball generation and artifact layout manipulation. |
| `rules_helm` | 0.22.1 | Helm chart rendering. |
| `rules_kustomize` | 0.5.3 | Kustomize overlay resolution and manifest generation. |

---

### 7. Agent Implementation Instructions
Using this specification, initialize the project workspace. Before writing code, generate a series of concise, modular Markdown files to serve as a mutable execution plan. These files must break the project into independent, sequential tasks, ensuring strict state tracking is maintained. This structure must allow any implementation agent to pause, resume, or hand off the work at any point without losing context or duplicating effort.