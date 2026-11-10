# Dex

Dex brokers Google login for ArgoCD, Grafana, Paperless, Karakeep, and the
Prometheus, Alertmanager, Longhorn, and Blocky UIs through oauth2-proxy.

## Ownership

The Dex Application has two Helm sources: the pinned upstream Dex chart and the
local chart in this directory. The local chart owns the network policy, Google
credentials ExternalSecret, generated client credentials, and secret-sharing
RBAC/ClusterSecretStore. `values.yaml` lists clients and permitted namespaces;
`main.yaml` registers those clients and their exact callbacks with Dex.

Each consumer owns its destination ExternalSecret and output format:

| Consumer | Destination | Owner/source |
| --- | --- | --- |
| ArgoCD | `argocd/argocd-dex` | `apps/argocd-oidc/dex-secret.yaml` |
| Grafana | `monitoring/grafana-dex` | `apps/kube-prometheus-stack/grafana-dex-secret.yaml` |
| oauth2-proxy | `monitoring/oauth2-proxy-dex` | `extraObjects` in `apps/oauth2-proxy/main.yaml` |
| Paperless | `paperless-ngx/paperless-dex` | `apps/paperless-ngx/dex-secret.yaml` |
| Karakeep | `karakeep/karakeep-dex` | `apps/karakeep/secrets.yaml` |

ArgoCD's destination secret is reconciled by a small post-bootstrap
`argocd-oidc` Application. Do not add its ExternalSecret to the initial ArgoCD
Helm release: ESO CRDs are not installed at that stage. ArgoCD itself remains
OpenTofu-managed; this Application owns only its OIDC ExternalSecret.

The external-secrets Application owns the shared Bitwarden store, not Dex's
credential definitions. Its `additionalNamespaces: [dex]` authorizes Dex's
app-owned ExternalSecret to read that store. New Dex clients do not require
changes to the external-secrets Application.

## Credentials

Only `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` come from the existing
`dex-credentials` Bitwarden item. The Dex-owned ExternalSecret filters out every
other field. Google issues these credentials; ESO cannot invent replacements.

ESO generates a distinct password for each `values.yaml` client in namespace
`dex`, in Secret `dex-client-<client>/password`. One Password generator definition
is reused, but every ExternalSecret invokes it independently. Each source uses
`refreshPolicy: CreatedOnce`, `creationPolicy: Orphan`, and `immutable: true`.
Normal syncs do not rotate credentials. Removing an ExternalSecret does not
delete its source Secret; deleting that Secret loses the credential and causes
regeneration. Back up these Secrets.

The Kubernetes-provider `dex-client-secrets` ClusterSecretStore exposes these
source passwords. Its reader ServiceAccount can only `get` the enumerated source
Secrets. Only listed consumer namespaces may use the store. They share access
to all listed client sources; this is not per-client credential isolation.
A second namespace-scoped Role permits ESO to request short-lived tokens for
that reader ServiceAccount. Kubernetes' default `system:basic-user` permission
allows the provider's self-subject access reviews.

Destination ExternalSecrets preserve app-specific formats and refresh hourly.
ArgoCD retains its required Secret label, Grafana receives its environment
variable, Paperless receives provider JSON, oauth2-proxy receives its two keys,
and Karakeep receives `OAUTH_CLIENT_SECRET`. Dex reads source Secrets directly.
Reloader restarts dependent workloads when referenced Secrets change; ArgoCD
watches its labeled SSO Secret. Retained source values do not need rotation
merely because their manifests change owners.

## Adding a Client

1. Register the client and exact callbacks in `main.yaml`, including its source
   Secret environment reference and Reloader entry.
2. Add its name and destination namespace to `values.yaml`. This creates its
   source ExternalSecret and updates sharing permissions.
3. Define the destination ExternalSecret in the consuming app, pointing to
   `dex-client-secrets` and `dex-client-<client>/password`.
4. Consume the generated Secret and verify authentication plus app-specific
   authorization. Google authentication alone does not restrict who can log in.

Apps use `CreateNamespace=true` for their own destination namespaces. ESO retries
if a store or source is not yet ready; no consumer ExternalSecrets are applied
by Dex into another app's not-yet-created namespace. Namespace creation and
sibling Application convergence must not rely on sync waves alone.

## Existing-Cluster Handoff

**This ownership migration is not safe to publish blindly with auto-pruning
active.** Existing destination ExternalSecrets own their generated Secrets;
pruning/recreating them can delete credentials and interrupt SSO. Source Secrets
are orphan-retained, but that does not protect destination copies or sharing
RBAC.

Follow [the guarded ownership handoff](../../.agents/references/dex-secret-ownership.md)
before publishing this migration. It freezes reconciliation, protects existing
resources, syncs receiving owners first, and verifies unchanged resource UIDs
and credential data before retiring the old owner's inventory. No credential
rotation is intended. A fresh cluster has no ownership transfer to perform.

Keep authenticated Kubernetes access independent of browser SSO during rollout.
Afterwards, check source/destination ExternalSecrets and both stores are Ready,
then test ArgoCD, Grafana, Paperless, Karakeep, and protected admin UIs. Preserve
existing per-application authorization rules and callbacks.
