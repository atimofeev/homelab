# PR validation

`.github/workflows/validate.yaml` runs on every PR, pushes to main, and manual dispatch.
No path filters: every PR receives the same three checks, including Renovate PRs.
Jobs have read-only repository access, no infrastructure secrets, and no persisted
checkout credentials.

## Tool containers

Never install validation tools at pipeline runtime. Use prebuilt images, pinned by
version and digest. GitHub's hosted Ubuntu runner only supplies Docker and runs
checkout; all validation commands execute in containers:

- `quay.io/helmpack/chart-testing:v3.15.0`: preinstalled yamllint, Helm, Python and
  PyYAML. Shared by YAML linting and chart/resource preparation.
- `ghcr.io/yannh/kubeconform:v0.8.0`: official kubeconform image.
- `ghcr.io/opentofu/opentofu:1.13.10`: official OpenTofu image for both init and validate.

No setup actions, pip/apk/apt installs, or executable downloads in the workflow.
Public chart/schema data and OpenTofu provider schemas still require network access.

## Checks

- `yamllint`: relaxed YAML linting, unlimited line length, GitHub's `on` key
  supported. Helm templates are excluded because they are not plain YAML.
- `kubeconform`: strict schema validation of application manifests, including
  self-managed ArgoCD and its policies, and all declared Helm charts rendered with their
  configured release names, namespaces, values and tracked Kubernetes version.
  Helm values schema validation stays enabled. Unsupported Helm options fail
  explicitly rather than silently omitting values.
- `tofu (infra)`: `tofu init -backend=false -input=false`, then
  `tofu validate`, inside the same pinned official image. Fresh containers
  need init to download provider schemas; there is no backend/state access, plan,
  apply, data-source read, or provider configuration against live services.

The rendering helper prepares `.validation/manifests` and `.validation/schemas` for
kubeconform's separate container. It derives custom-resource schemas from served
CRDs in pinned Helm output, checking served versions before public catalog fallback.
An old catalog schema cannot resurrect an API removed by those charts. CRD objects
use the matching Kubernetes release's official OpenAPI schema.

Defaulted required fields are optional for offline checks, matching API-server
ordering; explicit values still undergo type/constraint validation. Duplicate YAML
keys and missing schemas fail. No blanket `ignore-missing-schemas` or kind skips.

## Automerge and limits

The `apps/**` patch rule uses Renovate-managed PR merging
(`platformAutomerge: false`), retaining the default requirement for green checks.
ArgoCD is excluded by a later rule: `apps/argocd/**` and `infra/argocd.tf` share
the `argocd dependencies` group and always require manual review, including patches.
Other application minor/major and infrastructure updates also remain manual.
No dependency on GitHub native automerge or unconfigured branch protection for
Renovate's CI gate.
Require these three checks in GitHub branch protection to protect manual merges.
Remove the retired `tofu (.)` requirement if configured; the workflow does not
alter repository settings.

Remote Git sources (currently the Gateway API CRD bundle) are logged but not
rendered. Kustomize inputs are schema-checked, but builds/generated assets are not
rendered. The self-managed ArgoCD chart is rendered like other Applications,
including its CRDs. Kubeconform does not execute CEL,
admission webhooks, Helm hooks, or live rollout/storage/migration checks.

Local verification should use the workflow's exact images and commands in a clean
disposable repository copy. Never initialize over an existing local backend cache
or mount live state/credentials into validation containers.
