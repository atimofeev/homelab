# Homelab Project Context

This project manages a Kubernetes-based homelab environment using a declarative approach with OpenTofu and ArgoCD.

## Architecture

- **Infrastructure as Code (IaC):** OpenTofu is used to provision the underlying infrastructure.
  - **Talos Linux:** The operating system for Kubernetes nodes, managed via the `siderolabs/talos` provider.
  - **MikroTik:** Network configuration managed via the `terraform-routeros/routeros` provider.
  - **Cloudflare:** DNS records and external connectivity managed via the `cloudflare/cloudflare` provider.
- **GitOps:** ArgoCD watches this repository to sync applications into the cluster.
  - **Bootstrap:** ArgoCD itself is deployed via OpenTofu (`argocd.tf`) using Helm charts.
  - **Waves:** Application deployment is organized into waves (`argo-system-wave-*.yaml`) to ensure dependencies are met.

## Directory Structure

- **`/` (Root):** Contains project-wide OpenTofu configurations (ArgoCD bootstrap) and ArgoCD application definitions.
- **`/infra`:** OpenTofu configurations specifically for provisioning the physical/cloud infrastructure (Talos, Cloudflare, MikroTik).
- **`/apps`:** Kubernetes manifests for individual applications, organized by service name.
  - `bento-pdf/`, `blocky/`, `cert-manager/`, `longhorn/`, `metallb/`, `vert/`

## Key Files

- `infra/providers.tf`: Defines required providers (Cloudflare, RouterOS, Talos).
- `argocd.tf`: Bootstraps ArgoCD and the App of Apps pattern using Helm.
- `argo-system-wave-*.yaml`: Defines the order in which system applications are deployed.
- `argo-general.yaml`: Defines general application deployments.
- `infra/talos.tf`, `infra/cloudflare.tf`, `infra/mikrotik.tf`: Specific infrastructure configurations.

## Workflows

### Infrastructure Updates

To update physical infrastructure or cluster nodes:

1. Navigate to `infra/`.
2. Run `tofu init` (if needed).
3. Run `tofu plan` to review changes.
4. Run `tofu apply` to execute.

### Application Deployment

To add or update applications:

1. Create or modify manifests in `apps/<application-name>/`.
2. Update `argo-*.yaml` files if adding a new application to the GitOps sync.
3. Commit and push changes. ArgoCD will automatically sync the state.

## Tech Stack & Tools

- **OpenTofu**: Infrastructure provisioning (fork of Terraform).
- **Kubernetes**: Container orchestration.
- **Talos Linux**: Immutable Kubernetes OS.
- **ArgoCD**: GitOps continuous delivery.
- **Helm**: Package management for Kubernetes (used for bootstrapping).
- **Cloudflare**: DNS provider.
- **MikroTik RouterOS**: Network hardware.
