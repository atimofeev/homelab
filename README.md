# Homelab

Automated infrastructure and application management for my home laboratory.

## Overview

This repository manages a Kubernetes-based homelab environment using a declarative approach. It leverages **OpenTofu** for infrastructure provisioning and **ArgoCD** for continuous delivery of applications.

## Architecture

- **Infrastructure (IaC):**
  - **Talos Linux:** Secure, immutable, and minimal Linux distribution for Kubernetes, managed via the `siderolabs/talos` provider.
  - **MikroTik:** Network infrastructure configuration via the `terraform-routeros/routeros` provider.
  - **Cloudflare:** DNS and external connectivity management via the `cloudflare/cloudflare` provider.
- **GitOps:**
  - **ArgoCD:** Deployed via Helm charts in `argocd.tf`. It watches this repository to sync applications located in the `apps/` directory.

## Repository Structure

- `/infra`: OpenTofu configurations for provisioning physical/network infrastructure (Talos, MikroTik, Cloudflare).
- `/apps`: Kubernetes manifests for applications, organized by service name.
- `argocd.tf`: Bootstraps ArgoCD and the App of Apps pattern.
- `providers.tf`: Global provider configuration (Kubernetes, Helm).

## Getting Started

1. **Infrastructure:** Navigate to `infra/`, initialize with `tofu init`, and apply configurations.
2. **Cluster Access:** Use the appropriate `talosconfig` to interact with nodes.
3. **GitOps:** ArgoCD is bootstrapped via `argocd.tf`. It synchronizes applications in `apps/` based on defined sync waves:
   - **-25** External Secrets Operator, cert-manager
   - **-20** Secrets & Cert resources
   - **-15** Ingress & Gateway-API
   - **-10** Core operators
   - **-5** Core resources
   - **0** Applications

## Dependency Updates

Install the hosted Renovate GitHub App for this repository to enable dependency PRs. `renovate.json` supplies the configuration; no self-hosted workflow is needed. App installation is a separate setup step.

Renovate uses the recommended preset, limits concurrent PRs to five, and disables automerge. Extraction covers ArgoCD chart references and Helm values in `apps/**/main.yaml`, Kubernetes images in `apps/**/*.yaml` and `apps/**/*.yml`, and the default Helm values, Terraform/OpenTofu, and Helm chart file patterns. Two scoped regex managers track `talos_version` and `kubernetes_version` in `infra/terraform.tfvars` against their upstream GitHub releases.

Provider and module lookups use the OpenTofu registry, and `required_version` constraints track OpenTofu releases rather than Terraform releases. For OCI chart URLs that already include the chart name, a lookup rule removes the duplicate suffix added by the ArgoCD manager.

Dependencies under `apps/` are grouped dynamically by application directory, with major updates split from minor/patch updates. Review and merge PRs manually: merging application changes can trigger automatic ArgoCD deployment.

Infrastructure updates remain separate from application groups and require manual review and apply. Follow supported Talos and Kubernetes upgrade procedures, compatibility requirements, and upgrade order rather than treating version PRs as automatic cluster upgrades.

`sha-*` image tags are not automatically ordered, and this configuration does not make `latest` tags reproducible.
