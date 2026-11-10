# Dex Secret Ownership Handoff

This is a manifest ownership change, not credential rotation. Do not deploy it
as an unattended prune-enabled sync on an existing cluster. This procedure is
for a separately approved rollout; writing these manifests does not perform it.

## Final Owners

| Resource | Namespace | New owner |
| --- | --- | --- |
| Password `dex-client-secret` | dex | dex |
| ExternalSecret `dex-client-{argocd,grafana,oauth2-proxy,paperless,karakeep}` | dex | dex |
| ExternalSecret `dex-credentials` | dex | dex |
| ServiceAccount `dex-client-secret-reader` | dex | dex |
| Role/RoleBinding `dex-client-secret-reader` | dex | dex |
| Role/RoleBinding `dex-client-token-request` | dex | dex |
| ClusterSecretStore `dex-client-secrets` | cluster | dex |
| ExternalSecret `argocd-dex` | argocd | argocd-oidc |
| ExternalSecret `grafana-dex` | monitoring | kube-prometheus-stack |
| ExternalSecret `oauth2-proxy-dex` | monitoring | oauth2-proxy |
| ExternalSecret `paperless-dex` | paperless-ngx | paperless-ngx |

These resources previously belonged to `external-secrets`. Karakeep's destination
ExternalSecret already belongs to Karakeep; its source may not exist yet on an
existing cluster. Inventory actual resources rather than assuming every new
manifest is deployed. The Dex NetworkPolicy remains Dex-owned; only its source
file moves into the local chart.

The Bitwarden ClusterSecretStore stays external-secrets-owned, with the same
namespace allowlist. Its Dex permission now comes from `additionalNamespaces`
instead of an entry in the centrally rendered ExternalSecret list.

## Preconditions

- Keep working Kubernetes credentials independent of Dex/ArgoCD browser login.
- Record the current Git revision and all affected Application specs. Inspect
  configured ArgoCD resource tracking; do not assume label or annotation mode.
- Back up existing source and destination Secrets securely outside the repo.
  Record each transferred resource's UID and generated Secret UID, plus a digest
  of each Secret's sorted `data` map. Do not print raw credentials to logs.
- Confirm existing source/destination ExternalSecrets and stores are Ready.
  Diagnose existing failures before migration.
- Stop concurrent changes to these apps until handoff completes. All Git sources
  below must use the reviewed migration revision, not an unrelated moving HEAD.

## Controlled Transfer

1. **Before publishing**, disable automatic reconciliation on `argocd-apps`
   (the parent), then `external-secrets`, `dex`, `kube-prometheus-stack`,
   `oauth2-proxy`, `paperless-ngx`, and `karakeep` if deployed. For each existing
   Application, set `spec.syncPolicy.automated.enabled: false`; preserve its
   other settings. Verify no sync operation is in flight. Stop if there is an
   active operation rather than racing it. The parent must stay paused or it can
   restore child auto-sync while this procedure is running.
2. Add live `argocd.argoproj.io/sync-options: Prune=false` protection to every
   existing resource in the table. Preserve any other sync options. Do this
   while the old owner is paused, and verify the annotations persisted. Do not
   delete ExternalSecrets, generated Secrets, ServiceAccounts, or stores.
3. Publish the reviewed migration. Apply updated receiving Application specs
   with `automated.enabled: false` retained, including the new `argocd-oidc`
   Application. In particular, Dex's second source must be detected as Helm,
   not retain the old explicit directory renderer. Do not sync the parent yet.
4. Hard-refresh and manually sync **Dex first**, verifying its Git source is
   at the migration revision and its upstream Helm version is unchanged.
   Confirm the moved generator, source ExternalSecrets, Google ExternalSecret,
   sharing RBAC/store, and unchanged NetworkPolicy are present. Check actual
   tracking metadata now identifies Dex as owner. All existing UIDs and Secret
   data digests must match the preflight snapshot.
5. Hard-refresh and sync `argocd-oidc`, `kube-prometheus-stack`, `oauth2-proxy`,
   and `paperless-ngx`, then Karakeep if deploying it. Verify each destination
   ExternalSecret has the new owner, the original UID, Ready status, and the
   same generated Secret UID/data. New Karakeep objects have no prior UID to
   compare. Rendering must preserve the literal ESO expressions, especially
   oauth2-proxy's expression passed through Helm `tpl`.
6. Recheck `Prune=false` protection on transferred live objects and restore it
   if a receiving sync removed it. Refresh the old `external-secrets` owner at
   the migration revision. Inspect its pending changes before syncing: stop if
   transferred resources are scheduled for deletion. Sync it only after all
   receiving owners have adopted their resources. Verify it no longer claims
   any transferred resources and the Bitwarden namespace allowlist is unchanged.
7. Remove only the temporary `Prune=false` options after old-owner inventory is
   clear. Do not drop unrelated annotations/options. Refresh all affected apps;
   check no shared-resource warnings, stale ownership, or unexpected prune
   remains. Recompare UIDs and Secret digests. Test fresh SSO for every consumer
   and verify authorization rules, callbacks, and app data are unchanged.
8. Restore child auto-sync settings, then resume/sync the parent last. Keep
   monitoring ESO readiness and workload reloads. A no-op Secret transfer should
   not cause credential changes; investigate unexpected rotation or restarts.

Do not change `creationPolicy`, `refreshPolicy`, target names, or source keys to
make a failed handoff pass. Source orphan retention does not protect destination
Secrets from garbage collection if their owner ExternalSecret is deleted.

## Rollback

Pause the parent and all affected owners again. Preserve Secrets and their UIDs.
Restore previous manifests and transfer tracking back in place under the same
prune protections; only then restore previous Application specs/revisions and
resume reconciliation. Do not blindly revert and let both sides auto-prune.
If any credential actually changed, stop and use the secure backup plus a
coordinated source/destination/workload recovery rather than regenerating more
secrets.

## Fresh Cluster

No ownership transfer is needed when none of these resources exist. ESO must be
installed before the Dex/local-chart and consumer ExternalSecrets reconcile.
ArgoCD's OIDC secret belongs to the post-bootstrap `argocd-oidc` Application:
putting it into the initial Helm bootstrap would require ESO CRDs before ArgoCD
can install ESO. App namespaces are created by each app; retries handle stores
and credentials becoming Ready. Sibling sync-wave numbers alone do not prove
readiness ordering.
