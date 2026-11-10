# Karakeep

Bookmark storage, read-later, full-text search, and browser-based page capture at
<https://karakeep.prosto.dev>. ArgoCD discovers `main.yaml` automatically.

## Components

- Karakeep all-in-one image: web, background workers, SQLite, and assets.
- Upstream Karakeep Chrome image for screenshots and JavaScript rendering.
- Meilisearch, pinned to the version in upstream's release Compose file.
- Longhorn RWO volumes: 10 GiB for SQLite/assets, 5 GiB for search indexes.
  Both PVCs survive ArgoCD pruning/deletion. This is not a backup policy.
- ESO creates independent stable session and search secrets. The Dex Application
  owns client-secret generation in `dex`; Karakeep owns its destination
  ExternalSecret so ArgoCD creates the namespace before applying it.
- Traefik HTTPS HTTPRoute with Homer discovery. No oauth2-proxy middleware.

AI tagging, summaries, and embedding generation are disabled. No paid API keys
or external AI providers are configured. Full-text search and page capture work
without AI. CPU/memory requests and memory limits are starting budgets; measure
imports and crawling before tightening them.

## Authentication

Native Dex/Google login uses `/api/auth/callback/custom`. Registration is open
through OIDC; password registration and login remain disabled. Any Google user
accepted by the shared Dex provider can create an account. There is no email
allowlist and no private bootstrap step.

Each user has a separate private library unless bookmarks/lists are explicitly
shared. This is not infrastructure isolation: all accounts consume the same
storage, CPU, and crawler network access. Open registration allows untrusted
users to submit crawl jobs from your network. Internal-hostname protections are
not a complete SSRF sandbox; library privacy does not remove these risks.

Implicit email-based account linking is disabled. New users create their account
through Google directly, without a pre-existing password account to link.

Mobile apps and browser extensions can use API keys created in Karakeep's web
settings. Their requests go directly to Karakeep's native authentication, with
no proxy login page in front of the API.

## First Login

The first registered user becomes administrator. On a fresh installation, make
the first Google login while access is limited to you, before exposing the route
to others. Open registration alone does not reserve the admin role for your email.

1. Open <https://karakeep.prosto.dev> and sign in through Google.
2. Confirm your account has the admin role in Admin Settings. Later signups
   receive the regular user role and their own library.
3. Create an API key and test your mobile app/extension against the HTTPS URL.
4. If you no longer want new users, set `DISABLE_SIGNUPS=true` in
   `configmap.yaml`; existing OIDC accounts can still sign in.

Do not copy the live SQLite file while it is being written. Back up the data
volume consistently, including assets and SQLite WAL state, before upgrades.
Keep generated secrets with backups; do not delete/recreate the session secret
as a way to fix authentication.

## Isolation and Rollout Checks

NetworkPolicies allow Traefik to reach the web server, and only Karakeep server
pods to reach Chrome and Meilisearch. Service-account tokens are not mounted.
Egress is not restricted: crawling needs arbitrary public sites, and web workers
also need Dex and OCR downloads. This is ingress isolation, not a crawler egress
sandbox. The upstream Chrome image disables its browser sandbox; it runs as a
separate non-root pod with dropped capabilities and no persistent user data.
Karakeep's default internal-hostname protection is left enabled.

After deployment, verify:

```sh
kubectl -n karakeep get externalsecrets,pvc,pods,svc,httproute,networkpolicy
kubectl -n karakeep rollout status deployment/karakeep
kubectl -n karakeep rollout status deployment/karakeep-chrome
kubectl -n karakeep rollout status deployment/karakeep-meilisearch
```

Check the route's Accepted/ResolvedRefs status, TLS/DNS, Google login, API-key
access, and a saved public page's screenshot/search result. Test fresh connections
from unrelated pods to confirm backend ports are blocked; use an allowed caller
as a positive control. Schema validation does not prove packet enforcement.

SQLite and Meilisearch deployments use `Recreate`; upgrades have brief downtime.
Meilisearch version changes may require a dump/import or reindex, not just an
image bump. Review upstream's upgrade instructions before accepting dependency
updates. Longhorn replication does not replace off-cluster backups.

## Upstream References

- <https://docs.karakeep.app/installation/kubernetes>
- <https://docs.karakeep.app/configuration>
- <https://github.com/karakeep-app/karakeep/blob/v0.34.1/docker/docker-compose.yml>
- <https://github.com/karakeep-app/karakeep/blob/v0.34.1/apps/web/server/auth.ts>
