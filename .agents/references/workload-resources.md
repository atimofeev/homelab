# Workload resource configuration

All Kubernetes workload containers should request CPU and memory, limit memory,
and omit CPU limits. Resource values are per container, not per workload replica
set. Small application requests allow bursts; storage and control-plane memory
limits need substantially more headroom than an idle sample.

## Configuration owners

- App manifests and Helm values own regular, init, sidecar, and hook resources.
  Do not add duplicate Deployments or modify generated objects directly.
- `argocd.tf` owns ArgoCD resources and installs
  `kube-system-resource-policies.yaml` through Helm `extraObjects`.
- `infra/talos.tf` owns real static control-plane resource settings through
  `KubeAPIServerConfig`, `KubeControllerManagerConfig`, and `KubeSchedulerConfig`.
  Mutating mirror Pods does not configure their actual containers.
- Talos Flannel/proxy resource settings configure bootstrap manifests but do not
  update existing DaemonSets. The kube-system policy handles new Flannel,
  network-policy, proxy, and install-config containers without taking ownership
  of Talos-managed DaemonSets. CoreDNS already has the required resource shape.
- CNPG `Cluster.spec.resources` covers PostgreSQL, bootstrap init containers, and
  native initialization/recovery jobs. Recheck external plugin containers if added.
- Homer `Dashboard.spec.resources` replaces main-container defaults. Keep the
  existing config-sync CPU-removal policy: its sidecar resources are hardcoded by
  the operator. Helm `limits.cpu: null` removes the Homer operator chart default.
- Longhorn manager/global-manager and all seven CSI component resource profiles
  use native settings. `systemManagedCSIComponentsResourceLimits` is a JSON
  string; omitted CSI keys clear that component's resources.
- `apps/longhorn-operator/resource-policy.yaml` covers unsupported generated
  containers, including engine images, v1 instance managers, UI, driver deployer,
  trim jobs, and chart lifecycle hooks. It preserves the operator-calculated
  instance-manager CPU request. V2/SPDK instance managers are intentionally not
  matched; configure their distinct CPU/hugepage/memory requirements before use.

## Admission and rollout boundaries

The two resource policies match Pod CREATE only, by namespace, workload labels,
and container name. They preserve other resource keys and remove CPU limits only
for their targeted containers. They fail open (`failurePolicy: Ignore`) so an
admission expression failure cannot block storage/network recovery; offline CEL
and server dry-run validation are therefore important.

Installing a policy does not resize existing Pods or restart their controllers.
Longhorn instance-manager replacement requires a separate storage-safe rollout.
Do not delete all instance managers or network Pods together to force coverage.
Talos static-pod settings require a separately reviewed infrastructure apply.

Before deployment, render the exact pinned charts and inspect every regular/init
container and job. Check operator-generated pods separately; a successful Helm
render alone cannot prove their coverage. Validate policies with server dry-run
and real CEL mutation tests, including missing resources, extra resource keys,
computed CPU requests, excluded workloads, and idempotence.

Prometheus currently uses ephemeral TSDB storage: a resource-triggered Pod
replacement loses history. Do not mistake a short post-restart sample for a
retention-window peak. Check sustained usage, imports, backups, and recovery
before tightening memory caps further.
