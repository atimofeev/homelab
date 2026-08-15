# arr-stack

Media automation stack: qBittorrent, Prowlarr, Radarr, Sonarr, Configarr, Bazarr, Jellyfin, Jellyseerr.

> **Status: PLANNED.** Service directories exist but are empty. Neither `apps/arr-stack/main.yaml` (stack Application) nor child Applications (`apps/arr-stack/<service>/main-arr.yaml`) exist — nothing runs yet. Execute phases in order; track completion in [Phase tracker](#phase-tracker).

This document is both architecture reference and executable plan. Fixed defaults are in [Fixed decisions and defaults](#fixed-decisions-and-defaults). Operator inputs to collect first are in [Phase 0](#phase-0-preflight-and-decisions).

## Existing prerequisites (already deployed)

The homelab already provides everything the stack depends on:

| Component | What exists | Where |
| --- | --- | --- |
| GitOps | ArgoCD; root app `argocd-apps` auto-discovers `apps/*/main.yaml` (`recurse`, `include: "*/main.yaml"`); repo `https://github.com/atimofeev/homelab`, `targetRevision: HEAD` | `argocd.tf` |
| Secrets | External Secrets Operator 2.0.1 + `bitwarden-sdk-server`; Bitwarden items referenced centrally from values | `apps/external-secrets-operator/main.yaml`, `apps/external-secrets/values.yaml` |
| Storage | Longhorn 1.12.0; default StorageClass `longhorn` (3 replicas) | `apps/longhorn-operator/main.yaml` |
| Ingress | Traefik 40.0.0-ea.1, Gateway API, gateway `traefik-gateway` in `traefik` ns | `apps/traefik/main.yaml` |
| TLS | ClusterIssuer `prosto-dev` (Let's Encrypt, DNS01 Cloudflare); wildcard `*.prosto.dev` cert; secret `prosto-dev-wildcard-tls` in `ingress` and `traefik` namespaces | `apps/certs-and-issuers/prosto-dev.yaml` |
| Networking | kube-flannel CNI, MetalLB L2. No Cilium needed for this stack | `infra/`, `apps/metallb-*` |
| Dashboard | Homer, app tiles via annotations | `apps/homer-*` |

Cluster access: kubeconfig `~/.kube/homelab.yaml`, context `admin@homelab`. The default kubeconfig has no homelab context, so every command in this document uses `kubectl --kubeconfig ~/.kube/homelab.yaml`.

## Fixed decisions and defaults

### Deployment model

- Nested app-of-apps:
  - root `argocd-apps` sees only `apps/arr-stack/main.yaml` (its include is `*/main.yaml`);
  - the stack Application sees only `*/main-arr.yaml` (its include) — the root app can never pick up child manifests;
  - each child Application is independent: own `main-arr.yaml`, own source path, own sync lifecycle.
- All child Applications target **one shared namespace `arr-stack`**. One namespace is required because every media consumer mounts the same PVC.
- Child Application pattern: `source.path: apps/arr-stack/<service>`, `directory.exclude: main-arr.yaml`, `destination.namespace: arr-stack`, `syncOptions: [CreateNamespace=true]`, sync-wave `0`.

Stack Application (`apps/arr-stack/main.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: arr-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/atimofeev/homelab
    targetRevision: HEAD
    path: apps/arr-stack
    directory:
      recurse: true
      include: "*/main-arr.yaml"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Child Application (same shape for every service, e.g. `apps/arr-stack/radarr/main-arr.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: radarr
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/atimofeev/homelab
    targetRevision: HEAD
    path: apps/arr-stack/radarr
    directory:
      exclude: main-arr.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: arr-stack
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Directory layout:

```text
apps/arr-stack/
├── main.yaml                 # stack Application, discovered by root argocd-apps
├── storage/                  # media PVC + alerts (child)
│   ├── main-arr.yaml
│   ├── prometheus-rule.yaml
│   └── pvc.yaml
├── qbittorrent/
│   ├── main-arr.yaml
│   └── *.yaml
├── prowlarr/                 # child dirs for every service
├── radarr/
├── sonarr/
├── configarr/
├── bazarr/
├── jellyfin/
└── jellyseerr/
```

### Storage

- **Media volume:** existing `single-replica` StorageClass + one **250Gi ReadWriteMany** PVC `media` in `arr-stack`. RWX lets pods schedule on any node — Longhorn 1.12 serves RWX via share-manager (NFSv4).
- **Capacity reality:** each node's Longhorn disk is ~463Gi maximum / ~418Gi available, 3 nodes. The 250Gi media volume fits; do **not** plan for multi-TB. Grow later via `allowVolumeExpansion: true`.
- **Config PVCs** (Radarr/Sonarr/Prowlarr/Bazarr/Jellyfin configs, SQLite DBs): small RWO on default `longhorn` StorageClass (3 replicas) — pattern in `apps/tandoor-recipes/pvc.yaml`.
- **PVC protection:** every PVC manifest carries `argocd.argoproj.io/sync-options: Delete=false,Prune=false` — data must survive syncs and Application deletion. Do not use ApplicationSet-only preservation fields on these plain Applications.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media
  namespace: arr-stack
  annotations:
    argocd.argoproj.io/sync-options: Delete=false,Prune=false
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: single-replica
  resources:
    requests:
      storage: 250Gi
```

### Hardlink path contract

All consumers mount the same PVC at `/data`. One filesystem = hardlinks work: downloads import instantly without double disk usage.

| Dir | Owner | Purpose |
| --- | --- | --- |
| `/data/torrents/incomplete` | qBittorrent | active downloads |
| `/data/torrents/complete` | qBittorrent | finished downloads |
| `/data/media/movies` | Radarr | movie library root |
| `/data/media/tv` | Sonarr | TV library root |
| `/data/media` | Jellyfin | media library (same tree) |

All media-writing app processes use UID/GID **1000** so files remain mutually writable. LinuxServer images use `PUID=1000`/`PGID=1000`; pods use `fsGroup: 1000`.

Hardlink proof after the first import:

```bash
kubectl --kubeconfig ~/.kube/homelab.yaml exec -n arr-stack deploy/qbittorrent -- stat -c '%i %h %n' /data/torrents/complete/<file>
kubectl --kubeconfig ~/.kube/homelab.yaml exec -n arr-stack deploy/radarr -- stat -c '%i %h %n' /data/media/movies/<file>
```

Same inode, link count ≥ 2 → hardlink path works.

### Media retention

Nothing deletes library media by age automatically. Retention follows hardlink lifecycle:

1. qBittorrent downloads one file under `/data/torrents/complete`.
2. Radarr/Sonarr hardlink it into `/data/media`; both paths share one inode and consume one set of data blocks.
3. qBittorrent keeps its link while seeding.
4. At seed ratio **1.0** or seed time **7 days** (whichever limit is reached first), qBittorrent stops the torrent. Private tracker rules override these defaults.
5. Radarr/Sonarr Completed Download Handling removes the stopped torrent and download link after successful import. Library link remains; link count drops from 2 to 1.
6. Library media stays until explicitly deleted through Radarr/Sonarr. Unmonitor deleted titles/series when they must not be downloaded again.

Quality upgrades replace the library link, but the old file still consumes space while its torrent remains seeded. Jellyfin mounts `/data/media` read-only; deletion belongs to Radarr/Sonarr. Longhorn snapshots may delay physical block reclamation after filesystem deletion.

Capacity policy:

- warning at 80% PVC usage;
- critical at 90%;
- manual Radarr/Sonarr cleanup first;
- add Maintainerr only when rule-based watched/age cleanup becomes necessary.

### Other defaults

- **VPN:** none for MVP. qBittorrent uses normal cluster egress. Optional Proton VPN + WireGuard + Gluetun setup is documented in Phase 9.
- **Exposure:** qBittorrent, Prowlarr, Radarr, Sonarr, Bazarr internal-only (ClusterIP). Jellyseerr gets a public HTTPRoute in Phase 8. Exceptions are decided in Phase 0.
- **Jellyfin:** software (CPU) transcoding first; transcode dir on `emptyDir` (plain disk-backed — a 1080p software transcode is memory-heavy, do not use `medium: Memory`). GPU later, optional (Phase 9).
- **Configarr:** TRaSH-guide quality profiles + custom formats, Russian/English dual-audio scoring.

## Dependency graph

```text
storage (single-replica SC + 250Gi RWX PVC media @ /data)
├── qbittorrent                     → /data/torrents
├── prowlarr                        (indexer manager)
├── radarr    → /data/media/movies  (needs prowlarr indexers, qbittorrent client)
├── sonarr    → /data/media/tv      (needs prowlarr indexers, qbittorrent client)
├── configarr                       (needs radarr + sonarr APIs)
├── bazarr                          (needs radarr + sonarr)
├── jellyfin  → /data/media         (needs media volume only)
└── jellyseerr                      (needs radarr + sonarr + jellyfin)
```

**MVP** = Phases 0–8 complete: request → acquire → import → watch works end to end. The Phase 8 Jellyseerr end-to-end request test is the MVP acceptance gate. Phase 9 items are optional.

## Planned components

| Component | Dir | Purpose | Phase |
| --- | --- | --- | --- |
| Storage | `apps/arr-stack/storage/` | `single-replica` StorageClass + 250Gi RWX `media` PVC | 1 |
| qBittorrent | `apps/arr-stack/qbittorrent/` | Torrent downloader using normal cluster egress | 2 |
| Prowlarr | `apps/arr-stack/prowlarr/` | Indexer manager (feeds Radarr/Sonarr) | 3 |
| Radarr | `apps/arr-stack/radarr/` | Movie acquisition | 4 |
| Sonarr | `apps/arr-stack/sonarr/` | TV acquisition | 4 |
| Configarr | `apps/arr-stack/configarr/` | TRaSH-guide quality profiles & custom formats (RU/EN dual-audio scoring) | 5 |
| Bazarr | `apps/arr-stack/bazarr/` | Subtitle management | 6 |
| Jellyfin | `apps/arr-stack/jellyfin/` | Media server (software transcode first) | 7 |
| Jellyseerr | `apps/arr-stack/jellyseerr/` | Request/curation frontend | 8 |

Optional (separate, not MVP):

| Component | Purpose | Phase |
| --- | --- | --- |
| VPN for qBittorrent | Optional Proton VPN + WireGuard + Gluetun privacy layer | 9 |
| FlareSolverr | Cloudflare bypass, only if a chosen indexer needs it | 9 |
| GPU transcoding | Intel i915 / NVIDIA plugin; no GPU infra exists today | 9 |
| Subgen / Whisper | AI subtitle generation | 9 |
| Maintainerr | Rule-based watched/age media cleanup, only when manual retention becomes insufficient | 9 |
| Longhorn backup target | Volume backups; `backupTargetURL: ""` placeholder today | 9 |

## Phase 0: Preflight and decisions

Operator inputs — collect before Phase 1. This replaces the former open-decisions list.

- [ ] **qBittorrent WebUI password policy.** The password is set at first boot (not pre-injected via env); decide the value now, store in Bitwarden right after setting it.
- [ ] **Exposure exceptions.** Default is internal-only for everything except Jellyseerr. Note any per-app exceptions.
- [ ] **Prowlarr indexer list.** Which indexers to add (public first; private ones need API keys later).
- [ ] **Cluster preflight.** 3 nodes up; Longhorn healthy; per-node free space ≥ ~418Gi:

  ```bash
  kubectl --kubeconfig ~/.kube/homelab.yaml get nodes
  kubectl --kubeconfig ~/.kube/homelab.yaml -n longhorn-system get nodes.longhorn.io
  ```

- [ ] **External Secrets flow confirmed.** Bitwarden item → one list entry in `apps/external-secrets/values.yaml` → chart template emits `ExternalSecret` using `ClusterSecretStore` `bitwarden-secrets-manager`. See [Secrets inventory](#secrets-inventory).

Rollback boundary: none — no resources created.

## Phase 1: Nested Argo skeleton + storage child

Files to create:

- `apps/arr-stack/main.yaml` — stack Application (`include: "*/main-arr.yaml"`)
- `apps/arr-stack/storage/main-arr.yaml` — child Application → ns `arr-stack`
- `apps/arr-stack/storage/pvc.yaml` — `media`, 250Gi, RWX
- `apps/kube-prometheus-stack/main.yaml` — media PVC warning/critical alerts

Checklist:

- [ ] Stack Application exactly as in [Deployment model](#deployment-model); child Application per the same pattern.
- [ ] Shared `single-replica` StorageClass from `apps/longhorn-storage/` is Synced/Healthy.
- [ ] PVC: `accessModes: [ReadWriteMany]`, `storageClassName: single-replica`, `requests.storage: 250Gi`, annotation `argocd.argoproj.io/sync-options: Delete=false,Prune=false`.
- [ ] Add Prometheus alerts using `kubelet_volume_stats_used_bytes / clamp_min(kubelet_volume_stats_capacity_bytes, 1)` filtered by `namespace="arr-stack", persistentvolumeclaim="media"`: warning `> 0.80` for 15m, critical `> 0.90` for 5m.
- [ ] Commit and push; ArgoCD auto-syncs (root app → stack app → child app).

Acceptance:

- [ ] `kubectl --kubeconfig ~/.kube/homelab.yaml get application arr-stack -n argocd` → Synced/Healthy
- [ ] `kubectl --kubeconfig ~/.kube/homelab.yaml get application arr-storage -n argocd` → Synced/Healthy
- [ ] `kubectl --kubeconfig ~/.kube/homelab.yaml get pvc media -n arr-stack` → Bound
- [ ] Prometheus query returns one media PVC series; warning and critical rules show Healthy/Inactive before thresholds.
- [ ] RWX smoke test: two throwaway pods pinned to different nodes, write from one and read from the other under `/data` — proves Longhorn share-manager/NFS works on these Talos nodes before the stack builds on it.

Rollback: fix forward while storage is empty. To remove this phase, remove PVC only after confirming no data is needed, wait for PV deletion, then remove child Application.

## Phase 2: qBittorrent

Files to create: `apps/arr-stack/qbittorrent/main-arr.yaml`, `deployment.yaml`, `service.yaml`, `pvc.yaml`.

Checklist:

- [ ] Single qBittorrent container using normal cluster egress.
- [ ] Save/temp paths `/data/torrents/complete` and `/data/torrents/incomplete`; PVC `media` mounted at `/data`.
- [ ] qBittorrent uses `PUID=1000`, `PGID=1000`; pod uses `fsGroup: 1000`.
- [ ] Service ClusterIP, no HTTPRoute yet.
- [ ] First boot: set WebUI password → Bitwarden.
- [ ] Share limits: ratio `1.0`, seeding time `10080` minutes (7 days), action **Stop**. Never use automatic “remove torrent and files”; Radarr/Sonarr remove only after successful import.

Acceptance:

- [ ] Pod Running 1/1; WebUI reachable via `kubectl --kubeconfig ~/.kube/homelab.yaml port-forward -n arr-stack deploy/qbittorrent 8080:8080`.
- [ ] Outbound connectivity works. Leave WAN inbound port forwarding disabled initially; add a fixed torrent port through RouterOS only if peer connectivity is measurably poor.
- [ ] Test torrent downloads land in `/data/torrents/complete`.

Rollback: revert workload changes while retaining `main-arr.yaml`; push and let child Application reconcile.

## Phase 3: Prowlarr

Files to create: `apps/arr-stack/prowlarr/main-arr.yaml`, `deployment.yaml`, `service.yaml`, `pvc.yaml` (small RWO, default StorageClass).

Checklist:

- [ ] Deploy; add the Phase 0 indexer list after first boot.
- [ ] Internal-only Service.

Acceptance:

- [ ] UI reachable; every added indexer passes its test.

Rollback: revert workload changes while retaining `main-arr.yaml`; push and let child Application reconcile.

## Phase 4: Radarr + Sonarr, integration, hardlink proof

Files to create: `apps/arr-stack/radarr/main-arr.yaml` + `deployment.yaml`, `service.yaml`, `pvc.yaml`; same set for `apps/arr-stack/sonarr/`.

Checklist:

- [ ] Root folders: Radarr `/data/media/movies`, Sonarr `/data/media/tv`; PVC `media` mounted at `/data`.
- [ ] Download client: qBittorrent (WebUI API; harvest password/token after boot → Bitwarden).
- [ ] Prowlarr Applications: add Radarr and Sonarr using their internal Service URLs and generated API keys; Prowlarr then syncs indexers into both apps.
- [ ] Enable Completed Download Handling and Remove in both apps. Removal waits for successful import, completed seed goal, and stopped torrent.
- [ ] Media-writing processes use UID/GID 1000; pod uses `fsGroup: 1000`.

Acceptance:

- [ ] Test grabs: one movie + one episode downloaded and imported into the library.
- [ ] Hardlink proof passes (commands in [Hardlink path contract](#hardlink-path-contract)) — identical inode, link count ≥ 2.
- [ ] After seed goal, torrent/download link disappears while library file remains with link count 1.
- [ ] Radarr/Sonarr API keys harvested → Bitwarden (needed by Configarr, Bazarr, Jellyseerr).

Rollback: revert workload changes while retaining both child Applications; library files on `/data` remain untouched.

## Phase 5: Configarr

Files to create: `apps/arr-stack/configarr/main-arr.yaml`, `cronjob.yaml`, `configmap.yaml`, `pvc.yaml` (small cache).

Checklist:

- [ ] TRaSH-guide quality profiles + custom formats, RU/EN dual-audio scoring rules.
- [ ] Exclude 2160p/4K qualities and set bounded 1080p preferred/max sizes to control retention pressure.
- [ ] Radarr/Sonarr API keys from Bitwarden (harvested in Phase 4).
- [ ] Run as a Kubernetes CronJob; pin the Configarr image tag and inject API keys through environment variables referenced by `config.yml`.

Acceptance:

- [ ] Profiles and custom formats visible in Radarr and Sonarr UIs.

Rollback: revert CronJob/config changes while retaining `main-arr.yaml`; previously synced profiles remain until changed in Radarr/Sonarr.

## Phase 6: Bazarr

Files to create: `apps/arr-stack/bazarr/main-arr.yaml`, `deployment.yaml`, `service.yaml`, `pvc.yaml`.

Checklist:

- [ ] Connect Radarr + Sonarr (API keys already in Bitwarden).
- [ ] Language profile: Russian + English.

Acceptance:

- [ ] Subtitles fetched for a library title.

Rollback: revert workload changes while retaining `main-arr.yaml`; push and reconcile.

## Phase 7: Jellyfin (software transcoding first)

Files to create: `apps/arr-stack/jellyfin/main-arr.yaml`, `deployment.yaml`, `service.yaml`, `pvc.yaml`.

Checklist:

- [ ] Library rooted at `/data/media` (the same tree Radarr/Sonarr write).
- [ ] Mount `/data/media` read-only; manage deletion through Radarr/Sonarr.
- [ ] Transcode dir: `emptyDir` (plain disk-backed; memory medium only with large RAM headroom).
- [ ] Hardware acceleration disabled (no GPU yet); UID/GID 1000.

Acceptance:

- [ ] Playback works; a 1080p title completes a CPU transcode without buffering.

Rollback: revert workload changes while retaining `main-arr.yaml`; push and reconcile.

## Phase 8: Jellyseerr (end-to-end request test = MVP gate)

Files to create: `apps/arr-stack/jellyseerr/main-arr.yaml`, `deployment.yaml`, `service.yaml`, `http-route.yaml`, `pvc.yaml`.

Checklist:

- [ ] Connect Radarr, Sonarr, Jellyfin (all API keys now in Bitwarden).
- [ ] Exposure: public `jellyseerr.prosto.dev` HTTPRoute + Homer tile (pattern in `apps/vert/http-route.yaml`).
- [ ] Request flow: request a movie from the Jellyseerr UI.

Acceptance (**MVP complete when both pass**):

- [ ] Movie request → Radarr → qBittorrent → hardlink import → Jellyfin.
- [ ] Episode request → Sonarr → qBittorrent → hardlink import → Jellyfin.

Rollback: revert workload changes while retaining `main-arr.yaml`; existing library data remains untouched.

## Phase 9: Optional enhancements

- [ ] **VPN for qBittorrent** — add only when privacy or ISP behavior warrants the extra complexity:
  1. Buy Proton VPN Plus and choose a nearby P2P-capable server.
  2. Add Gluetun as qBittorrent sidecar using WireGuard; both containers share the pod network namespace.
  3. Store Proton/WireGuard credentials in Bitwarden and expose them through `apps/external-secrets/values.yaml`.
  4. Grant Gluetun required tunnel access (`NET_ADMIN`, `/dev/net/tun`) and set `FIREWALL_INPUT_PORTS=8080`; use privileged mode only if Talos/containerd requires it.
  5. Disable qBittorrent UPnP/NAT-PMP. Sync Proton's forwarded port into qBittorrent because it can change after reconnect.
  6. Verify public IP is the VPN endpoint, forwarded port is reachable, and stopping Gluetun blocks qBittorrent egress.
  7. Keep WebUI internal; do not expose port 8080 through WAN.
- [ ] **FlareSolverr** — only if a Phase 3 indexer requires Cloudflare bypass.
- [ ] **GPU transcoding** — Intel i915 / NVIDIA plugin, node selection, transcode volume strategy; no GPU infra exists today.
- [ ] **Subgen / Whisper** — AI subtitle generation.
- [ ] **Maintainerr** — add only when manual cleanup is insufficient. Define explicit dry-run rules first (watched age, unrequested age, minimum free-space floor), review candidates, then enable deletion through Radarr/Sonarr integrations.
- [ ] **Longhorn backup target** — `apps/longhorn-backup-target/backup-target.yaml` currently has `backupTargetURL: ""` placeholder. Configure Cloudflare R2 or local storage (avoid AWS-only dependencies). Enables volume backups for `media` + config PVCs.

## Secrets inventory

| Secret | Consumed by | Becomes available | Flow |
| --- | --- | --- | --- |
| qBittorrent WebUI credentials | qBittorrent config, Radarr/Sonarr download client | Phase 2 (set at first boot) | Bitwarden → values.yaml |
| Radarr API key | Prowlarr, Configarr, Bazarr, Jellyseerr | Phase 4 (harvest) | Bitwarden → values.yaml |
| Sonarr API key | Prowlarr, Configarr, Bazarr, Jellyseerr | Phase 4 (harvest) | Bitwarden → values.yaml |
| Jellyfin integration credential | Jellyseerr | Phase 8 setup | Bitwarden → values.yaml if manifest consumption is needed; otherwise retain as recovery record |
| Private indexer credentials | Prowlarr | per indexer (Phase 3+) | Store in Bitwarden; configure in Prowlarr UI unless manifest integration exists |

**Centralized flow (no per-service ExternalSecret manifests):**

1. Create the Bitwarden item (in the org project used by the `bitwarden-secrets-manager` ClusterSecretStore).
2. Add one entry under `externalSecrets.secrets` in `apps/external-secrets/values.yaml`: `name`, `namespace` (arr-stack services → `arr-stack`), `bitwardenKey`.
3. The chart template emits the `ExternalSecret`; the generated Secret lands in the target namespace and workloads reference it by name.
4. Secrets that exist only after first boot are harvested from the app and stored in Bitwarden. Add them to values.yaml only when a workload consumes a generated Kubernetes Secret.

## Phase tracker

| Phase | Component | Status |
| --- | --- | --- |
| 0 | Preflight and decisions | ☐ |
| 1 | Skeleton + storage | ☐ |
| 2 | qBittorrent | ☐ |
| 3 | Prowlarr | ☐ |
| 4 | Radarr + Sonarr + hardlink proof | ☐ |
| 5 | Configarr | ☐ |
| 6 | Bazarr | ☐ |
| 7 | Jellyfin | ☐ |
| 8 | Jellyseerr (MVP gate) | ☐ |
| 9 | Optional: VPN, FlareSolverr, GPU, Subgen, backups | ☐ |

Update this table when a phase's acceptance checks pass.

## Networking and exposure

Public exposure follows the Traefik Gateway API pattern in `apps/vert/http-route.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: jellyseerr
  namespace: arr-stack
  annotations:
    item.homer.rajsingh.info/name: "Jellyseerr"        # Homer dashboard tile
    item.homer.rajsingh.info/subtitle: "Request media"
    item.homer.rajsingh.info/logo: "<url>"
    service.homer.rajsingh.info/name: "Media"
    service.homer.rajsingh.info/icon: "fas fa-film"
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - "jellyseerr.prosto.dev"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: jellyseerr
          port: 80
```

- Hostnames use the `*.prosto.dev` wildcard cert (already provisioned into the `traefik` namespace).
- Each app also needs a `Service` (see `apps/vert/service.yaml`).
- Default: only Jellyseerr is public; the rest stay ClusterIP-internal (exceptions decided in Phase 0).

## Teardown and rollback

- **Phase rollback:** restore previously working workload manifests while retaining `main-arr.yaml`, then push. Removing a child Application is teardown, not routine rollback. Data on `/data` and protected config PVCs remains untouched.
- **Application deletion:** existing Applications carry no `resources-finalizer.argocd.argoproj.io`. Deleting a child Application without pruning first **orphans its workloads** (no cascading delete). Order matters:
  1. remove the workload manifests (child app syncs → prunes workloads),
  2. then remove the child `main-arr.yaml`,
  3. then remove the stack `main.yaml` last.
- **PVC protection:** `media` and all config PVCs carry `argocd.argoproj.io/sync-options: Delete=false,Prune=false` — they survive syncs and Application deletion. Delete manually only after backing up the data.
- Longhorn replication: config volumes 3 replicas, media volume 1 replica. Back up before destructive operations; see Phase 9 for the backup target.

## Deployment flow

```bash
# 1. Write the phase's files, commit, push
git add apps/arr-stack apps/external-secrets/values.yaml && git commit -m "feat(arr-stack): phase N ..." && git push
# 2. ArgoCD reconciles: root app → stack app → child apps. No manual apply.
```

- `targetRevision: HEAD` means the cluster follows whatever is pushed. Persistent changes must be committed; live edits are reverted by self-heal.
- Empty service dirs are ignored until they contain a `main-arr.yaml`.

## Validation commands

```bash
kubectl --kubeconfig ~/.kube/homelab.yaml get applications -n argocd
kubectl --kubeconfig ~/.kube/homelab.yaml get application arr-stack -n argocd
kubectl --kubeconfig ~/.kube/homelab.yaml get application <service> -n argocd
kubectl --kubeconfig ~/.kube/homelab.yaml get pods -n arr-stack -w
kubectl --kubeconfig ~/.kube/homelab.yaml get pvc -n arr-stack
kubectl --kubeconfig ~/.kube/homelab.yaml get httproute -n arr-stack
kubectl --kubeconfig ~/.kube/homelab.yaml logs -n arr-stack deploy/radarr
kubectl --kubeconfig ~/.kube/homelab.yaml describe pod <pod> -n arr-stack
```

If an app is OutOfSync or self-heal reverts a change, the manifests in git differ from the cluster — commit the intended state and push.
