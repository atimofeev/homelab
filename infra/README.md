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

## Flannel NetworkPolicy Enforcement

Control-plane machine configurations enable `kubeNetworkPoliciesEnabled` in the
Talos `KubeFlannelCNIConfig` document. Talos manages the `kube-network-policies`
sidecar and its RBAC in the existing `kube-system/kube-flannel` DaemonSet; no
separate CNI or Helm release is needed. Keep this control-plane-only document out
of worker patches and keep the setting consistent across control-plane nodes.

On existing clusters, applying the machine configuration only updates Talos's
rendered bootstrap manifest. Talos 1.14's bootstrap controller creates Kubernetes
objects once and does not reconcile existing objects. After reviewing the
rendered bundle and preserving the existing Flannel image/settings, apply it
once using Talos's field manager:

```bash
talosctl --nodes "$CONTROL_PLANE_IP" get manifests 05-flannel -o json |
  jq '{apiVersion: "v1", kind: "List", items: .spec}' |
  kubectl apply --server-side --field-manager=talos -f -
kubectl -n kube-system rollout status daemonset/kube-flannel
```

Confirm the DaemonSet template actually contains `kube-network-policies` before
trusting rollout status; an unchanged, old DaemonSet also reports success.

Audit existing ingress and egress policies before enabling enforcement. Policies
that were previously inert immediately affect selected workloads as the DaemonSet
rolls across nodes. In particular, the Longhorn chart's manager policy needs the
additive Prometheus allowance in
`../apps/longhorn-operator/prometheus-network-policy.yaml` to preserve metrics on
TCP 9500. Apply that allowance before enabling the controller. Blocky metrics and
API share TCP 4000, allowed from Blocky UI and the selected Prometheus pods.

Review a saved plan and apply machine configuration updates serially; do not
combine this rollout with unrelated infrastructure changes. Verify the sidecar
on every node, fresh allowed and denied connections via both Services and pod
IPs, cross-node traffic, DNS over TCP/UDP, monitoring targets, and Paperless OIDC.
The bundled controller defaults to fail-open while it is unavailable; policy
objects or a Ready Flannel container alone do not prove enforcement.

For rollback, set `kubeNetworkPoliciesEnabled` to false consistently on all
control planes, reapply their newly rendered `05-flannel` bundle with the same
field manager, and verify removal of the sidecar and traffic recovery. This
restores connectivity by disabling policy isolation; it is not a security-safe
steady state. Do not disable or replace Flannel itself.

## Public Workload OIDC Metadata

`oidc.tf` publishes Kubernetes service-account discovery and public signing keys
at `https://oidc.${var.domain}`. A Cloudflare Worker serves embedded JSON; its
custom domain manages DNS and TLS. It has no origin, tunnel, cluster credentials,
or runtime connection to the homelab. Do not add a DNS record pointing this
hostname at the homelab, or protect these two paths with Cloudflare Access or a
browser challenge:

- `/.well-known/openid-configuration`
- `/openid/v1/jwks`

OpenTofu reads both documents from the private Kubernetes API using the existing
kubeconfig resource's CA and client certificate/key, then replaces discovery's
issuer and JWKS URL with the public URLs. Run plans/applies from a machine with
private API connectivity. Cloudflare credentials need Workers Scripts Edit and
Workers Routes Edit permissions in addition to the existing zone permissions.
Client credentials remain in state; the Worker receives only public metadata.

### Workers Billing

Workers Free includes 100,000 requests per day across the Cloudflare account
and 10 ms CPU per request. This Worker serves small embedded JSON documents;
it needs no KV, R2, Durable Objects, or paid subscription. These are Worker
handler requests, not the separate unlimited Workers Static Assets offering.
Exhausting the Free quota returns errors rather than paid request overage.

Workers Paid is a separate, opt-in account subscription starting at $5/month,
including 10 million requests and 30 million CPU-ms/month. Excess usage is
metered. This configuration does not create or upgrade a subscription. See
[Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
and [request limits](https://developers.cloudflare.com/workers/platform/limits/).

### Deployment

One normal plan/apply, using native providers only:

```sh
tofu plan -out=oidc.tfplan
tofu apply oidc.tfplan
```

The managed Talos configuration issues tokens with the public issuer and accepts
both that issuer and the existing Kubernetes API endpoint issuer/audience. It
preserves the signing key. `accepted.issuers` lists only the legacy issuer:
Talos adds the issuing URL automatically, and listing it again prevents the API
server from starting. Metadata reads depend on machine configuration and cluster
health; the Worker depends on those reads, followed by its custom domain.
There are no scripts, provisioners, migration resources, or phase flags.

During the first issuer transition, a control plane not yet updated can reject
new-issuer tokens from an updated control plane. This one-apply configuration
accepts that transient authentication risk; `depends_on` does not guarantee a
zero-disruption rolling issuer migration or wait for every API-server restart.
Verify all control planes advertise the public issuer after convergence and
both public URLs return matching public keys. TLS certificate activation at
Cloudflare can take time.

The compatibility issuer is `https://${var.talos_api_vip}:6443`, verified on all
three current control planes. For rollback, restore that value as the issuing
URL in the Talos patch while retaining both accepted issuers/audiences. Keep the
Worker while existing public-issuer tokens remain valid.

Normal upgrades and pod-token renewal preserve the signing key. Intentional key
rotation needs separate planning to publish new keys before using them and retain
old keys through token expiry/cache lifetimes.

AWS IAM providers/roles, S3 buckets, and CNPG backups remain separate. AWS pods
will need projected tokens with audience `sts.amazonaws.com`; that audience is
not added to Kubernetes API audiences.

### Offline Checks

```sh
tofu fmt -check -recursive
tofu validate
tofu test -filter=tests/oidc.tftest.hcl
node --test tests/oidc-worker.test.mjs
```

The OpenTofu tests use mocked providers in plan mode. Worker tests use only
fixture metadata; neither test suite contacts or changes live infrastructure.

## Inspiration

- https://github.com/hcloud-k8s/terraform-hcloud-kubernetes/
- https://github.com/rafaribe/home-ops/
