# Homelab Infrastructure (Work In Progress)

This directory contains the OpenTofu / Terraform configuration for automating the deployment and management of the homelab's core infrastructure.

## Overview

The infrastructure management is divided into several components:

- **Cloudflare**: Manages DNS records and domain settings.
- **Mikrotik (RouterOS)**: Configures networking, including Dynamic DNS (IP Cloud).
- **Talos OS**: Handles machine secrets, image configurations, and cluster access (kubeconfig).

## Kubernetes API Floating VIP

`talos_api_vip` in `terraform.tfvars` defines the Kubernetes API VIP;
`var.nodes` defines the real node addresses. The VIP must remain outside the
DHCP range managed by `routeros_ip_pool.default_dhcp` in `mikrotik.tf` and the
MetalLB pools in `../apps/metallb-l2-addresspool/`. Node-address collisions are
validated; DHCP and MetalLB overlaps require separate review. Machine resources
depend on the managed DHCP pool, but this ordering does not validate address
exclusions.

Control-plane nodes must share the VIP's L2 network and retain etcd quorum.
Talos elects a VIP owner; the VIP is not an independent load balancer and does
not replace control-plane quorum. Each control-plane patch selects its NIC by
the configured MAC, keeps DHCP enabled, and adds the VIP. Workers receive no
VIP patch. API server certificate SANs include the VIP and real node addresses,
preserving direct Kubernetes API access for recovery.

The generated local kubeconfig rewrites cluster server URLs to the VIP,
preserving CA, users and contexts. Other kubeconfig copies are not automatically
rewritten. Talos management endpoints, machine configuration application,
bootstrap and kubeconfig retrieval use real node addresses rather than the VIP.

`talos_machine.this` manages machine configuration; `talos_cluster.this` tracks
bootstrap and orchestrates rolling Kubernetes upgrades. Machine configuration
changes are not automatically serialized by `for_each`. The iPXE schematic
wipes STATE and EPHEMERAL; do not use an iPXE reboot as a rollout method.

VIP API access is verified, but deliberate VIP failover testing remains outstanding.

## Inspiration

- https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/
- https://github.com/rafaribe/home-ops/
