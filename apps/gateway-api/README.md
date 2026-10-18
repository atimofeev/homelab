# Gateway API

Standalone Argo CD Application for cluster-scoped Gateway API resources.
Source: https://github.com/kubernetes-sigs/gateway-api.git
Pin: `v1.5.1`, path `config/crd/standard`.
The standard bundle includes CRDs and upgrade-safety admission policies.
No destination namespace is needed: upstream resources are cluster-scoped.

## Discovery and sync

The `argocd-apps` parent discovers `apps/*/main.yaml`; no bootstrap change is needed.
Wave `-16` precedes Traefik's `-15`, but does not guarantee child readiness.
Sync stays manual during ownership handoff: no automated sync or auto-pruning.
Server-side apply adopts/updates existing resources without forced replacement.
Traefik's own CRDs remain managed by Traefik.

## Staged ownership migration

1. Before adoption, pause old-chart Traefik auto-reconciliation through GitOps
   or another parent-safe method. A live-only edit may be reverted by its parent.
2. Protect existing Gateway API CRDs with resource annotation
   `argocd.argoproj.io/sync-options: Prune=false,Delete=false` before removing
   them from the old owner's desired state.
3. Manually sync `gateway-api` to adopt/update existing CRDs and install policies.
   Do not delete/recreate CRDs or use force/replace; stop on ownership conflicts.
4. Verify `gateway-api` resource ownership, sync status and health, then inspect
   Gateway and HTTPRoute conditions (including Accepted, Programmed where
   applicable, and ResolvedRefs). Confirm existing routing still works.
5. Only after successful handoff, merge/update separate Traefik upgrade PR #75
   and manually sync chart `40.3.0`, which no longer bundles Gateway API CRDs.
   Verify CRDs remain intact and healthy.
6. Restore Traefik automatic reconciliation only after that upgrade and checks.
7. Enable Gateway API application autosync in a follow-up after handoff;
   deliberately review pruning behavior before enabling any automatic pruning.

This PR prepares the application only; it does not perform the migration.
