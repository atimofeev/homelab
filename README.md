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
