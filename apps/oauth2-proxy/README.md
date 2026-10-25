# Prometheus ForwardAuth

Prometheus browser access uses Traefik ForwardAuth -> oauth2-proxy -> Dex ->
Google. Only the exact addresses in `authenticatedEmailsFile.restricted_access`
in `main.yaml` are allowed. Currently this is the same single account allowed
by Grafana. Other Google accounts may log in to Dex but cannot access Prometheus.

Keep `config.emailDomains: []`. Domain rules and the email file are ORed:
`*` would bypass the email restriction and `gmail.com` would allow every Gmail
account. Do not enable trusted-IP, JWT, or skipped-route authentication bypasses.
The pinned image rejects explicitly unverified emails; keep the shared Dex
Google connector as the trusted source of verified email claims.

## Routing

The kube-prometheus-stack chart generates one HTTPRoute for
`https://prometheus.prosto.dev` on Traefik's HTTPS listener:

- `/oauth2/` goes directly to oauth2-proxy for login and callbacks, without
  ForwardAuth. It never routes to Prometheus.
- Every other path, including Prometheus API endpoints, requires the
  `monitoring/prometheus-auth` Middleware before reaching Prometheus.

The old Prometheus nginx Ingress is disabled. Both Services stay ClusterIP.
Grafana and in-cluster scrapers retain their existing internal access; this is
an edge authentication boundary, not authentication on the internal Prometheus
Service. The oauth2-proxy NetworkPolicy allows ingress only from Traefik pods.
It requires a CNI that enforces Kubernetes NetworkPolicy.

No extra public hostname is needed. The `__Host-prometheus_auth` cookie is
Secure, HttpOnly, SameSite=Lax, and host-only: no domain-wide cookie is issued.
Traefik copies renewed auth cookies to the browser. The redirect allowlist is
only `prometheus.prosto.dev`; this is separate from the email allowlist.

## Secrets

ESO generates the Dex client secret using the existing `dexClients` machinery,
copies it to `monitoring/oauth2-proxy-dex`, and exposes the matching source to
Dex. The only registered callback is
`https://prometheus.prosto.dev/oauth2/callback`. Google's existing Dex callback
does not change.

A separate ESO Password generator creates a base64url-encoded 32-byte cookie key
in `monitoring/oauth2-proxy-cookie`. Both source secrets are created once and
immutable, with orphan retention; routine syncs do not rotate them. Back up
them with the other Dex client secrets. Reloader restarts the proxy when its
referenced secrets change. Do not delete these secrets during normal syncs.

## Rollout Checks

After publishing and ArgoCD sync:

1. Wait for the new Dex client source/copy and cookie ExternalSecrets to be Ready,
   and for Dex and oauth2-proxy rollouts to finish. A brief login interruption
   is possible while the independently synced apps converge.
2. Confirm the old Prometheus Ingress is gone, and the HTTPRoute reports
   `Accepted=True` and `ResolvedRefs=True` on `traefik-gateway`. Keep reference
   group/kind and backend weight defaults explicit in the chart values;
   otherwise API defaulting can leave ArgoCD perpetually OutOfSync.
3. Check that DNS resolves to the Traefik Gateway address, not the old nginx
   address. ExternalDNS uses a 30-minute DNS TTL; client caches may retain the
   old address after the router record updates. Compare a direct router DNS
   query with the client resolver before changing routing. On a Linux client
   using systemd-resolved, `resolvectl flush-caches` clears that local cache.
4. Open Prometheus in a private browser: it must redirect to Dex/Google.
5. Sign in with the listed account: both UI and `/api/v1/query` must work.
6. Sign in with a different Google account: access must be denied, including
   direct API requests. A valid Dex login alone must not grant access.
7. Confirm Grafana still queries its internal Prometheus datasource.

To change access, edit the exact-email list and sync. The chart rolls the proxy
on list changes, and the proxy also watches its mounted file. Once each replica
loads the new list, subsequent HTTP requests recheck existing sessions; removed
accounts need not wait for their session cookie to expire.
