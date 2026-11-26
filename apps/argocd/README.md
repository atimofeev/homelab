# ArgoCD bootstrap and self-management

`infra/argocd.tf` seeds two Helm releases: `argo-cd` and `argocd-apps`. Both use:

```hcl
lifecycle {
  ignore_changes  = all
  prevent_destroy = true
}
```

After bootstrap, `apps/argocd/main.yaml` manages ArgoCD and its local policies.
`apps/argocd-apps/main.yaml` manages the root Application, which discovers
`apps/*/main.yaml`, including itself. The argocd-apps chart is only the initial
installer for that plain Application. Names stay unchanged, and neither
Application has a cascading-deletion finalizer.

## Fresh cluster

The normal infrastructure apply provisions Talos/Kubernetes, waits for cluster
health, obtains Kubernetes credentials from Talos, installs ArgoCD, and then
installs the root Application. No manual Helm/kubectl installation or separate
applications state is needed. Publish the application manifests to the configured
Git revision before provisioning; otherwise the root cannot discover them.

The Helm provider uses the infrastructure stack's API VIP and Talos-generated
client certificates, not a pre-existing local kubeconfig. Chart version and values
come from `apps/argocd/main.yaml`, so Renovate has one ArgoCD chart pin to update.

The seed preserves resource settings and policies, with two bootstrap overrides:
HTTPRoute creation is disabled until Gateway API exists, and OIDC is disabled
until Dex and its client Secret exist. Admin and anonymous access remain disabled.
ArgoCD subsequently restores the full Git configuration. These seed overrides
apply only to new installations; importing existing releases does not change their
values. Keep Kubernetes-admin access for recovery while ingress and SSO are coming up.

## Existing cluster: transfer state before applying

Removing root Terraform files does **not** move their state. Do not apply `infra/`
until the existing releases have been imported there. Otherwise it will attempt
to create releases that already exist. Do not destroy/uninstall either release
or delete the `argocd` namespace.

1. Freeze applies to both stacks and ArgoCD upgrades. Keep a separate checkout of
   the pre-migration root configuration, initialized against
   `tfstate-homelab/apps/terraform.tfstate`. Set `OLD_ROOT` to that checkout's
   absolute path. The current `infra/` stack must use the same bucket and key
   `infra/terraform.tfstate`. Do not change either backend or migrate one entire
   state over the other.

2. Before publishing/merging the GitOps changes, pause the existing root and wait
   for any active sync to finish. Child applications continue reconciling:

   ```sh
   export KUBECONFIG="$HOME/.kube/homelab.yaml"
   kubectl -n argocd patch application argocd-apps --type=merge \
     -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

3. Initialize `infra/` with its additional Helm provider, then back up **both**
   states privately outside Git. Store the backups durably; `/tmp` is temporary:

   ```sh
   tofu -chdir=infra init
   umask 077
   mkdir -p /tmp/pi-coding-agent/argocd-state-transfer
   backup_dir=$(mktemp -d /tmp/pi-coding-agent/argocd-state-transfer/backup.XXXXXX)
   tofu -chdir="$OLD_ROOT" state pull > "$backup_dir/apps.tfstate"
   tofu -chdir=infra state pull > "$backup_dir/infra.tfstate"
   tofu -chdir="$OLD_ROOT" state list
   tofu -chdir=infra state list
   ```

   Expect the old state to contain only `helm_release.argo_cd`,
   `helm_release.argocd_apps`, and `kubernetes_namespace_v1.argo_cd`. Neither Helm
   address should already be in the infra state. Stop on unexpected inventory.

4. Import both existing release records into infra without reinstalling them:

   ```sh
   tofu -chdir=infra import helm_release.argo_cd argocd/argo-cd
   tofu -chdir=infra import helm_release.argocd_apps argocd/argocd-apps
   tofu -chdir=infra plan
   ```

   Check that neither release is created, updated, replaced, or destroyed.
   Review unrelated infrastructure differences separately; do not apply them as
   part of this migration. During this brief overlap the two states describe the
   same releases, which is why applies to both stacks must remain frozen.

5. Only after both imports and the target plan are verified, forget the old
   entries. The namespace stays in Kubernetes; there is no separate namespace
   resource in the new stack (`create_namespace` handles fresh installations):

   ```sh
   tofu -chdir="$OLD_ROOT" state rm \
     helm_release.argo_cd helm_release.argocd_apps kubernetes_namespace_v1.argo_cd
   tofu -chdir="$OLD_ROOT" state list
   ```

   The old state must now be empty. Never apply the old root configuration again.

6. Publish/merge while the root is paused. Create a manual-sync version of the
   ArgoCD Application for the first adoption review (requires jq, not a script):

   ```sh
   kubectl create --dry-run=client -f apps/argocd/main.yaml -o json \
     | jq 'del(.spec.syncPolicy.automated)' | kubectl apply -f -
   ```

   Review its ArgoCD diff, then sync manually without pruning. Expect the same
   resource names, chart version and policies, not replacement workloads. Verify
   Synced/Healthy, the Redis initialization hook, CRD tracking, HTTPRoute, Dex
   login, and both network/admission policy pairs. Then resume the root:

   ```sh
   kubectl apply -f apps/argocd-apps/main.yaml
   kubectl -n argocd get applications argo-cd argocd-apps
   tofu -chdir=infra plan
   ```

   The root adopts itself and enables automated reconciliation for `argo-cd`.
   Both Applications should be Synced/Healthy, and Terraform should propose no
   release changes.

7. Archive/retire the empty `apps/terraform.tfstate` object and obsolete root
   backend cache after saving recovery material. Do not delete the shared bucket
   or infra state. Remove a required `tofu (.)` branch-protection check if present;
   the workflow now runs only `tofu (infra)`.

If a step fails, keep both applies frozen and inspect state inventory before
retrying. Do not blindly restore/push an old backup over newer infra state. State
transfer rollback must preserve a single active owner without uninstalling the
live releases; prefer fixing forward after verified imports.

## Lifecycle boundaries

- `ignore_changes = all` prevents Terraform updates, not creation of a missing
  release. Do not remove Helm release-history Secrets as routine cleanup.
- `prevent_destroy` rejects destruction while its resource block exists. Removing
  that block removes its protection. Never use `helm uninstall` after handoff.
- Helm history remains at the seed version; ArgoCD does not update release records.
  Use ArgoCD status and live workloads to determine the running version.
- New chart pins affect fresh installations and ArgoCD reconciliation, not a
  Terraform upgrade of the existing release.
- Talos does not own these Kubernetes resources, so its bootstrap-manifest
  inventory does not overwrite/prune them during Kubernetes upgrades.

## Validation

The isolated Talos-in-Docker experiment verified fresh creation of both releases,
ArgoCD self-management, a chart/image upgrade through Git, root self-healing, and
no-op Terraform plan/apply afterward. Removing only `ignore_changes` in a control
copy proposed two updates; that plan was not applied. This does not establish that
the complete baremetal infrastructure has been rebuilt or the live state moved.

Kubernetes CI renders the GitOps chart and local policies. Infrastructure validation
checks the bootstrap configuration. For chart upgrades, review release notes and
rendered differences, retaining direct Kubernetes recovery access.
