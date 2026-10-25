# Admin UI ForwardAuth

Prometheus, Alertmanager, and Longhorn browser access uses Traefik ForwardAuth
-> oauth2-proxy -> Dex -> Google. Only the exact addresses in
`authenticatedEmailsFile.restricted_access` in `main.yaml` are allowed. Currently
this is the same single account allowed by Grafana. Other Google accounts may
log in to Dex but cannot access these three UIs or their external HTTP APIs.

Keep `config.emailDomains: []`. Domain rules and the email file are ORed:
`*` would bypass the email restriction and `gmail.com` would allow every Gmail
account. Do not enable trusted-IP, JWT, or skipped-route authentication bypasses.
The pinned image rejects explicitly unverified emails; keep the shared Dex
Google connector as the trusted source of verified email claims.

## Routing

Each application's chart generates its protected HTTPRoute on Traefik's HTTPS
listener. The old nginx Ingresses are disabled:

| Host | Namespace | ForwardAuth Middleware |
| --- | --- | --- |
| `prometheus.prosto.dev` | `monitoring` | `prometheus-auth` |
| `alertmanager.prosto.dev` | `monitoring` | `alertmanager-auth` |
| `longhorn.prosto.dev` | `longhorn-system` | `longhorn-auth` |

The oauth2-proxy chart generates one more HTTPRoute in `monitoring`, matching
`/oauth2/` on all three hosts. This more-specific path goes directly to the
proxy without ForwardAuth, so login and callbacks cannot loop. It never routes
to application backends. All remaining application paths require ForwardAuth.
The callback route and proxy Service share a namespace, so no cross-namespace
Service grants are needed. Each app's Middleware lives beside its app route.

Proxy and application Services stay ClusterIP. Grafana's Prometheus datasource,
Prometheus-to-Alertmanager delivery, metrics scraping, and Longhorn's internal
traffic retain their existing direct cluster access. This is an edge
authentication boundary, not authentication on internal application Services.
The oauth2-proxy NetworkPolicy allows ingress only from Traefik pods; it requires
a CNI that enforces Kubernetes NetworkPolicy.

No extra public hostname or domain-wide cookie is needed. The callback path
`/oauth2/callback` is expanded to an absolute URL using the host supplied by
Traefik. Dex registers only the three exact HTTPS callback URLs. Traefik does
not trust client-supplied forwarded headers on these auth middlewares.

The cookie name `__Host-prometheus_auth` is retained for compatibility with
existing Prometheus sessions. Despite its historical name, each host has its
own Secure, HttpOnly, SameSite=Lax, host-only cookie. Visiting another UI starts
its own proxy session; an existing Dex/Google login can avoid another credential
prompt. Traefik copies renewed auth cookies to the browser. The redirect
allowlist contains only the three exact app hosts; it is separate from the
email allowlist.

## Secrets

All three apps reuse the existing oauth2-proxy deployment, Dex client, exact-email
list, and generated secrets. No new credentials or secret rotation are needed.
ESO generates the Dex client secret using the existing `dexClients` machinery,
copies it to `monitoring/oauth2-proxy-dex`, and exposes the matching source to
Dex. Registered callbacks are:

- `https://prometheus.prosto.dev/oauth2/callback`
- `https://alertmanager.prosto.dev/oauth2/callback`
- `https://longhorn.prosto.dev/oauth2/callback`

Google's existing Dex callback does not change.

A separate ESO Password generator creates a base64url-encoded 32-byte cookie key
in `monitoring/oauth2-proxy-cookie`. Both source secrets are created once and
immutable, with orphan retention; routine syncs do not rotate them. Back them up
with the other Dex client secrets. Reloader restarts the proxy when its
referenced secrets change. Do not delete these secrets during normal syncs.

## Rollout Checks

After publishing and ArgoCD sync:

1. Wait for Dex and oauth2-proxy rollouts to finish. A brief login interruption
   is possible while the independently synced apps converge. The existing ESO
   secrets must remain Ready; do not recreate them.
2. Confirm all three old nginx Ingresses are gone. App routes and the shared
   callback route must report `Accepted=True` and `ResolvedRefs=True` on
   `traefik-gateway`. Keep reference group/kind and backend weight defaults
   explicit; otherwise API defaulting can leave ArgoCD perpetually OutOfSync.
3. Check that each hostname resolves to the Traefik Gateway address, not the old
   nginx address. ExternalDNS uses a 30-minute TTL; client caches may retain the
   old address after the router record updates. Compare a direct router DNS
   query with the client resolver before changing routing. On a Linux client
   using systemd-resolved, `resolvectl flush-caches` clears that local cache.
4. Open each UI in a private browser: it must redirect to Dex/Google, using a
   callback on the same host. Sign in with the listed account and confirm the UI
   and its API work. Check Longhorn's live updates as well as its initial page.
5. Sign in with a different Google account on each host: access must be denied,
   including direct API requests. A valid Dex login alone must not grant access.
6. Confirm Grafana still queries Prometheus, Prometheus still delivers alerts to
   Alertmanager internally, and Longhorn's volumes/replicas remain healthy.

To change access, edit the exact-email list and sync. The chart rolls the proxy
on list changes, and the proxy also watches its mounted file. Once each replica
loads the new list, subsequent HTTP requests recheck existing sessions; removed
accounts need not wait for their session cookie to expire.
