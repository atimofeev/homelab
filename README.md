# Homelab

Automated infrastructure and application management for my home laboratory.

## Overview

This repository manages a Kubernetes-based homelab environment using a declarative approach. It leverages Terraform for infrastructure provisioning and ArgoCD for continuous delivery of applications.

## Architecture

- **Infrastructure (IAC):**
  - **Talos Linux:** Secure, immutable, and minimal Linux distribution for Kubernetes.
  - **MikroTik:** Network infrastructure configuration via Terraform.
  - **Cloudflare:** DNS and external connectivity management.
- **GitOps:**
  - **ArgoCD:** Manages the deployment of all cluster applications located in the `apps/` directory.
- **Key Applications:**
  - **Networking:** MetalLB for LoadBalancer support, Cert-Manager for TLS.
  - **Storage:** Longhorn for distributed block storage.
  - **Services:** Blocky (DNS/Ad-blocker), Bento PDF, and more.

## Repository Structure

- `/infra`: Terraform configurations for provisioning the underlying infrastructure.
- `/apps`: Kubernetes manifests for applications, organized by service.
- `argo-*.yaml`: ArgoCD Application manifests defining the deployment waves.

## Getting Started

1. **Infrastructure:** Navigate to `infra/`, initialize with `terraform init`, and apply configurations.
2. **Cluster Access:** Use the generated `talosconfig` to interact with the nodes.
3. **GitOps:** ArgoCD is bootstrapped via `argocd.tf` to monitor this repository.
