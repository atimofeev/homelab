# Homer Dashboard Assets

The browser favicon and Walkxcode wallpapers are supplied explicitly through
`Dashboard.spec.assets.configMapRef`. Kustomize packages the four files in
`assets/` into `homer/main-homer-assets`; the ConfigMap name stays stable because
the Dashboard's custom asset reference is not a built-in Kustomize name reference.
The operator stages these files into the shared assets volume and aliases the
icons to the browser's expected paths. Light and dark background image paths
are set through the native Homer color configuration; the existing theme and
layout are unchanged.

## Why Explicit Assets

Homer's entrypoint with `INIT_ASSETS=1` installs bundled assets only if
`/www/assets/config.yml` is absent. The operator's config-sync sidecar creates
that config symlink after a fixed 10-second delay. If the sidecar runs before
Homer starts, bundled icons and wallpapers are skipped. The dashboard can then
load normally while those asset requests return HTTP 404. Explicit asset staging
works with either startup order and does not rely on external image URLs.

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
