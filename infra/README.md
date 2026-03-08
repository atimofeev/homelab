# Homelab Infrastructure (Work In Progress)

This directory contains the OpenTofu / Terraform configuration for automating the deployment and management of the homelab's core infrastructure.

## Overview

The infrastructure management is divided into several components:

- **Cloudflare**: Manages DNS records and domain settings.
- **Mikrotik (RouterOS)**: Configures networking, including Dynamic DNS (IP Cloud).
- **Talos OS**: Handles machine secrets, image configurations, and cluster access (kubeconfig).

## Inspiration

- https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/
