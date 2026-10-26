# Homer Dashboard Assets

The browser favicon and Walkxcode wallpapers are supplied explicitly through
`Dashboard.spec.assets.configMapRef`. Kustomize packages the four files in
`assets/` into `homer/main-homer-assets`; the ConfigMap name stays stable because
the Dashboard's custom asset reference is not a built-in Kustomize name reference.
The operator stages these files into the shared assets volume and aliases the
icons to the browser's expected paths. Light and dark background image paths
are set through the native Homer color configuration; the existing theme and
layout are unchanged. Use origin-absolute `/assets/...` background paths: relative
URLs in CSS custom properties resolve against the consuming stylesheet under
`/resources/`, not the page URL.

## Why Explicit Assets

Homer's entrypoint with `INIT_ASSETS=1` installs bundled assets only if
`/www/assets/config.yml` is absent. The operator's config-sync sidecar creates
that config symlink after a fixed 10-second delay. If the sidecar runs before
Homer starts, bundled icons and wallpapers are skipped. The dashboard can then
load normally while those asset requests return HTTP 404. Explicit asset staging
works with either startup order and does not rely on external image URLs.

## Config-Sync CPU Quota

Operator 1.2.4 hardcodes a 50m CPU limit for `config-sync` and recopies assets
on a five-second loop. Short copy bursts exhaust that quota despite low average
CPU use, firing `CPUThrottlingHigh`. The operator exposes no sidecar resource
setting; `Dashboard.spec.resources` changes only the main Homer container.

`apps/homer-operator/config-sync-cpu-policy.yaml` uses Kubernetes native
`MutatingAdmissionPolicy` to remove only the sidecar CPU limit from newly created
Pods for Dashboard `main` in namespace `homer`. CPU requests, memory limits,
other containers, and the operator-owned Deployment remain unchanged. The policy
is fail-open and idempotent; it needs no webhook deployment. It requires the
`admissionregistration.k8s.io/v1` policy API served by this cluster.

After the operator Application syncs the policy and binding, an approved rolling
restart of `deployment/main-homer` is needed for existing Pods to pick it up.
Verify the new Pod retains the `config-sync` memory limit but has no CPU limit,
asset URLs still return HTTP 200, and the throttling alert clears after its
five-minute query window. Removing the policy affects future Pods only; restoring
the original quota also requires recreating existing Pods. Remove this workaround
when upstream provides suitable sidecar resource configuration or fixes the loop.

## Asset Provenance

Unmodified files copied from Homer 26.08.3, using the same image digest observed
on the running dashboard:

`b4bz/homer@sha256:febc8967c9f7648ec37633ef3ae1ec90dbe8b7c46fecab80299f08f05be7ecb6`

- `favicon.ico`, `apple-touch-icon.png`: `/www/default-assets/icons/`
- `wallpaper.webp`, `wallpaper-light.webp`: `/www/default-assets/themes/walkxcode/`

Upstream: https://github.com/bastienwirtz/homer. The upstream Apache-2.0 license
is retained in `assets/LICENSE`.

## Verification

Run `kubectl kustomize apps/homer-dashboard` to check that the output contains
only the Dashboard, existing HTTPRoute, and asset ConfigMap; it must not include
the ArgoCD Application in `main.yaml`.

After publishing and ArgoCD/operator reconciliation, check these paths on
`https://homer.prosto.dev` return HTTP 200 with image content types:

- `/assets/icons/favicon.ico`
- `/assets/icons/apple-touch-icon.png`
- `/assets/wallpaper.webp`
- `/assets/wallpaper-light.webp`

The config-sync sidecar refreshes custom assets every five seconds. If the
browser keeps a failed favicon or old CSS/config cached, hard-refresh the page
or clear site data before checking both light and dark modes.
