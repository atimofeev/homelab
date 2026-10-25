# Dex

Dex brokers Google login for ArgoCD, Grafana, Paperless, and the Prometheus,
Alertmanager, and Longhorn UIs through oauth2-proxy.

## Credentials

Only `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` come from the existing
`dex-credentials` Bitwarden item. Its ExternalSecret filters out every other
field. Google issues these credentials; ESO cannot invent replacements.

ESO generates a distinct password for each client in the `dex` namespace:

- `dex-client-argocd/password`
- `dex-client-grafana/password`
- `dex-client-paperless/password`
- `dex-client-oauth2-proxy/password`

One Password generator definition is reused, but each ExternalSecret invokes it
independently, producing a different value. Each generated source uses
`refreshPolicy: CreatedOnce`, `creationPolicy: Orphan`, and `immutable: true`.
Normal syncs do not rotate credentials, and deleting an ExternalSecret does not
delete its source Secret. Back up these Secrets; deleting a source Secret loses
its value and causes a new credential to be generated.

The Kubernetes-provider `dex-client-secrets` ClusterSecretStore copies the source
passwords into the existing app Secrets: `argocd/argocd-dex`,
`monitoring/grafana-dex`, `paperless-ngx/paperless-dex`, and
`monitoring/oauth2-proxy-dex`. It uses a dedicated ServiceAccount whose Role
permits only `get` on those four source Secrets. Only the three app namespaces
may use this store; they share access to its four sources. A second
namespace-scoped Role lets the ESO controller request short-lived tokens for
this reader ServiceAccount only. Kubernetes' default `system:basic-user`
permission allows the provider's self-subject access reviews.

App-specific output formats stay unchanged. ArgoCD retains its required Secret
label, Grafana receives its client-secret environment variable, Paperless
receives provider JSON, and oauth2-proxy receives client-id/client-secret keys.
Dex reads source Secrets directly. Reloader annotations reload Dex, Grafana,
Paperless, and oauth2-proxy when their referenced Secrets change; ArgoCD watches
its labeled SSO Secret. Prometheus, Alertmanager, and Longhorn access is restricted
by oauth2-proxy's exact email allowlist, not by the shared Dex connector; see
`apps/oauth2-proxy/README.md`.

## Migration

The first sync rotates previously Bitwarden-backed client credentials once.
Login can fail briefly while automated syncs, Secret copies, and workload reloads
converge. Wait for all four source ExternalSecrets, the ClusterSecretStore, and
all four destination ExternalSecrets to be Ready, then check the Dex, Grafana,
Paperless, and oauth2-proxy rollouts before testing SSO. Existing application
data and account bindings are unchanged.

Do not delete generated source Secrets during routine maintenance. Intentional
rotation must coordinate source regeneration, refreshing the destination
ExternalSecrets, and workload reloads; destination copies otherwise refresh on
the normal one-hour interval.

After rollout and successful SSO checks, the unused `ARGOCD_CLIENT_SECRET`,
`GRAFANA_CLIENT_SECRET`, and `PAPERLESS_CLIENT_SECRET` fields may be removed from
Bitwarden. They are no longer read. Keep the two Google fields and leave the
Google OAuth callback as `https://dex.prosto.dev/callback`.

On a new cluster, ArgoCD creates destination namespaces with
`CreateNamespace=true`; no standalone Namespace manifests are needed. Store and
Secret reconciliation may retry until those namespaces and sources exist.
