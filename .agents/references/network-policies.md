# Network Policy Boundaries

## Ownership and Intent

These are declarative boundaries, not evidence that a rollout or live traffic
check has completed. Inspect the deployed policies and test fresh connections
before claiming enforcement.

Traefik OAuth protects gateway requests, not direct pod or ClusterIP connections.
Select backend pods and allow only required callers. Native-auth applications
such as Grafana and ArgoCD retain their own authentication on direct access;
policies add defense in depth. Public utilities remain public through Traefik.

Keep policies with their owning application under `apps/<app>/`. Chart-backed
applications use additional directory sources when needed; exclude `main.yaml`.
Include Homer dashboard policy in its Kustomization. Do not create separate
Namespace manifests when ArgoCD can create the destination namespace.

ArgoCD bootstrap is OpenTofu-managed. The pinned chart hardcodes allow-all server
ingress; another restrictive policy cannot override it. `argocd.tf` disables
global chart policy creation, explicitly retains controller/repo-server/Redis/
notifications policies, and loads replacement server/ApplicationSet policies from
root `argocd-network-policies.yaml` through Helm `extraObjects`. This needs a
separately reviewed root OpenTofu plan/apply, not only application GitOps sync.

## Declared Traffic

| Workload | Allowed ingress | Egress |
| --- | --- | --- |
| BentoPDF / Vert | Traefik on 8080 / 80 | Deny initiated connections, including DNS |
| Longhorn UI | Traefik on 8000 | Unchanged; proxies manager API |
| Prometheus | Traefik/Grafana on 9090; Prometheus self-scrape on 9090/8080 | Unchanged; discovery and scraping |
| Alertmanager | Traefik/Prometheus/Grafana on 9093; Prometheus on 8080; peers on TCP/UDP 9094 | Unchanged; notification providers |
| Grafana | Traefik/Prometheus on 3000 | Unchanged; datasources, Dex, dashboard initialization |
| Dex | Traefik on 5556; Prometheus on 5558 | Unchanged; Google and Kubernetes storage |
| Atuin | Traefik on 8888; Prometheus on 9001 | CoreDNS TCP/UDP 53 and own database 5432 |
| Paperless / Atuin CNPG | Owning app on 5432; own cluster/jobs on 5432/8000; CNPG operator on 8000/5432; Prometheus on 9187 | Unchanged; instance management and recovery |
| ArgoCD server | Traefik and selected ArgoCD controllers on 8080; Prometheus on 8083 | Unchanged |
| ArgoCD ApplicationSet controller | Prometheus on 8080; no webhook route configured | Unchanged |
| kube-state-metrics | Prometheus on 8080/8081 | Unchanged; Kubernetes API |
| cert-manager / ESO / CNPG operator | Separate metrics from Prometheus; admission port from any source | Unchanged; reconciliation/provider APIs |
| Prometheus operator / metrics-server | Shared API/metrics HTTPS port 10250 from any source | Unchanged; Kubernetes API |
| external-dns | Prometheus on 7979; MikroTik webhook stays pod-local | Unchanged; MikroTik and Kubernetes APIs |
| reloader / Homer operator | Prometheus on 9090 / 8443 | Unchanged; Kubernetes API |
| Homer dashboard | Traefik on 8080 | Unchanged; config-sync sidecar uses Kubernetes API |
| Traefik | Public HTTP/HTTPS on 8000/8443; Prometheus on 9100 | Unchanged; backends and Kubernetes API |
| Blocky UI | Existing Traefik-only ingress | CoreDNS TCP/UDP 53 and Blocky API 4000 |

Preserve existing Blocky API, oauth2-proxy, Paperless server/MCP/Valkey, Bitwarden
SDK, ArgoCD Redis/repo-server, and chart-managed Longhorn storage policies.
Tandoor is excluded from this hardening scope.

BentoPDF and Vert serve static nginx files without proxy upstreams. Browser-side
conversion and downloads do not require pod egress. Reply traffic to allowed
ingress is implicit; do not add egress just to permit responses. Their
service-account token mounts are disabled.

## API Servers Without Node-IP Lists

Admission and aggregated API requests originate from host-network control planes.
Standard NetworkPolicy cannot portably select them by API-server pod or namespace
labels. Allow only the required destination ports without source restrictions;
do not hardcode node IPs or subnets. Use pod ports, not Service ports: webhook
Service 443 can map to 10250 or 9443.

This preserves webhook/API reachability from application pods; it is not source
isolation or caller authentication. TLS alone does not guarantee authenticated
callers. Separate metrics ports remain Prometheus-only. Prometheus operator and
metrics-server share API and metrics on 10250, so L3/L4 policies cannot restrict
those metrics independently.

## Guardrails and Remaining Limits

- Combine namespace and pod selectors within the same peer entry. A pod selector
  without a namespace selector matches only the policy's namespace. Verify labels
  against rendered workloads, not assumed Helm release names.
- Check the union of chart-generated and handwritten rules: policies are additive.
  Chart upgrades may introduce broader allowances.
- Select CNPG databases and peer jobs by `cnpg.io/cluster`, not primary/replica
  roles or pod names. CNPG 1.30.1 initdb/join/recovery pod templates carry this
  cluster label. Preserve operator access on both 8000 and 5432.
- Leave CNPG egress open until API Service/endpoint translation, bootstrap,
  failover, recovery, and backup/restore dependencies are verified. Controller,
  identity-service, and Traefik egress also require separate dependency mapping;
  a guessed broad HTTPS rule is not destination isolation.
- Select system workloads, not whole namespaces. Preserve cert-manager HTTP-01
  solver pods and Longhorn engine/replica/CSI traffic.
- Host-network services, including node exporter, control-plane components, and
  MetalLB speakers, need node/LAN firewall review. Ordinary NetworkPolicy is not
  a portable host firewall; traffic from a pod's own node is special-cased.
- Blocky API/metrics share 4000, and Longhorn API/metrics share 9500. Prometheus
  allowances cover both API and metrics; L3/L4 policy cannot filter HTTP paths.
- ingress-nginx removal and node-firewall changes are separate tasks. Do not
  replace the CNI or disable enforcement globally to fix one application's rules.

## Verification and Rollout

1. Parse changed YAML and render pinned Helm charts with the application's exact
   release name, namespace, and values. Include directory/Kustomize sources.
2. Check policy selectors against workload labels and inspect the combined policy
   union, particularly ArgoCD's replacement allow-all policy. Run `tofu fmt -check
   argocd.tf` and `tofu validate` for bootstrap changes.
3. Server-dry-run candidate policies and modified Applications. Dry-runs validate
   resources, not actual packet filtering. Do not treat previous validations as
   proof that later edits or deployments work.
4. Keep authenticated Kubernetes/Talos access independent of browser SSO. After
   deployment, test fresh connections through both Services and pod IPs, including
   cross-node traffic. Confirm a known-allowed caller reaches every endpoint used
   for a negative test.
5. Confirm public BentoPDF/Vert pages and browser conversions still work; protected
   hostnames redirect to login; completed Dex login and authenticated UIs work.
6. Confirm unrelated pods cannot directly reach protected admin backends,
   databases, Blocky API/UI, or oauth2-proxy. Webhook/API ports are intentional
   exceptions. Public static workloads must not initiate outbound connections.
7. Check Prometheus targets and reloader metrics, Grafana datasource queries,
   Alertmanager delivery, CNPG replication, and new join/recovery jobs.
8. Exercise admission with harmless server-dry-run resources after enforcement;
   check aggregation with `kubectl top pods -A`. Check gateway/node probes;
   kubelet probes do not require opening health endpoints to all pods.

Revert faulty rules in their owning source and reconcile normally rather than
turning off policy enforcement for the whole cluster.
