# Node-local control-plane metrics

## Ownership and security boundary

`apps/kube-prometheus-stack/node-metrics-agent.yaml` runs a Prometheus agent on
all Linux nodes using host networking. Kubernetes discovery is restricted to
`kube-system` and the agent's node. Controller-manager and scheduler targets are
rewritten to `127.0.0.1:10257/10259`; kube-proxy to `127.0.0.1:10249`. Nothing
changes Talos component bind addresses. Workers discover only kube-proxy.

Scheduler/controller-manager generate self-signed, in-memory serving certificates
at process startup in the inspected Talos v1.14.4 / Kubernetes v1.37.1 deployment.
These are not signed by the Kubernetes CA. The user explicitly approved skipping
certificate verification **only** for those two HTTPS loopback targets. Redirects
are disabled; the address allowlist relabel prevents this exception from reaching
non-loopback targets. Bearer authentication remains enabled. Never extend this
exception to API discovery or remote write.

The dedicated agent ServiceAccount has only `/metrics` GET and namespaced pod
get/list/watch. The discovery field selector reduces data requested, but RBAC
still permits reading all pod specifications in kube-system; it is not a
node-scoped authorization boundary. The API token is projected with a one-hour
lifetime and mounted only in the Prometheus container. No Talos credentials,
admin kubeconfigs, host paths, or Secret API permissions are used. Host networking
still grants network reachability to other node-local services, not just metrics.

Agent and config-reloader web listeners bind to loopback (19090/19091). Kubelet
probes intentionally address host loopback. Monitoring namespace already allows
privileged Pod Security; host networking produces restricted-policy warnings but
containers remain non-root, unprivileged, capability-free, and read-only except
for explicit config/WAL volumes.

## Forwarding and certificates

`node-metrics-receiver.yaml` exposes only a ClusterIP mTLS listener on 8443.
NGINX accepts only the client subject `CN=node-metrics-agent` and POST requests to
`/api/v1/write`. It forwards to the existing central Prometheus receiver. There
is no Ingress/HTTPRoute, host port, or new node-facing listener.

Certificates use the existing `cluster-signed-issuer`; cert-manager renews both
client and server certificates. Prometheus config-reloader watches the client
Secret directory. Stakater Reloader rolls the receiver Deployment when its
certificate/CA Secret or configuration changes. Neither Secret is mounted with
subPath; only the NGINX ConfigMap uses subPath, with rollout on change.

The receiver policy permits 8443 from any source because host-network clients
cannot be selected portably by namespace/pod labels. mTLS provides authentication.
The central Prometheus ingress policy allows only the receiver pods as an
additional caller on 9090; it is not opened to every node/pod. Enabling remote
write also makes `/api/v1/write` available to existing callers allowed to reach
Prometheus directly. User accepts metrics-integrity risks; this is not a claim of
write-path isolation from those existing clients.

The existing CA issuer's lifecycle remains a dependency. Leaf renewal does not
solve CA expiry/rotation: issuer replacement requires overlapping trust and
coordinated leaf renewal. Existing cert-manager alerts cover renewal/expiry;
collector heartbeat detects delivery loss. Agents use bounded ephemeral WAL;
restarts or long outages can lose metrics, an accepted trade-off.

## Alerts and labels

Keep chart component `enabled` and default rules on. Disable only the three
original ServiceMonitors. Agent labels preserve jobs `kube-scheduler`,
`kube-controller-manager`, and `kube-proxy`, with node-specific instances.

Central Prometheus evaluates all rules. `NodeMetricsAgentMissing` compares
remote-written self-scrape heartbeats against kube-state-metrics node inventory;
it detects a missing agent, receiver failure, or delivery loss even when all
component series vanish. Component-target-missing rules compare expected nodes
against discovered targets only while the agent heartbeat is healthy. Existing
chart unreachable rules handle present targets with `up == 0`.

Inventory assumes Linux/Talos nodes and kube-proxy on every node. Revisit it if
adding non-Linux nodes or replacing kube-proxy. Inventory itself depends on
kube-state-metrics; retain its upstream availability alerts.

## Offline validation

Use a task directory outside the repository. Parse all manifests, extract
`ConfigMap.data["prometheus.yaml"]`, and run the pinned config-reloader with
`NODE_NAME` and `POD_NAME` to expand `$(...)` variables. Check its output using the
pinned Prometheus image's `promtool check config --agent --syntax-only`.

Extract `node-metrics-rules.yaml`'s `spec` to a standalone file of the same name in
the task directory. Copy `node-metrics.test.yaml` beside it and run:

```sh
promtool check rules node-metrics-rules.yaml
promtool test rules node-metrics.test.yaml
```

Tests cover healthy control-plane/worker nodes, one/all agents missing, stale
heartbeats, missing individual targets, failed scrapes versus missing targets,
and configuration reload failure. Render the pinned kube-prometheus-stack chart
with the exact application values. Confirm the three old ServiceMonitors are
absent while component rules remain and remote-write receiver is enabled.

Server dry-run resources with the ArgoCD field manager to avoid false ownership
conflicts. Do not apply or publish as part of code-only validation.

## Rollout checks

1. Confirm certificates Ready and receiver Deployment Ready; wait for one ready
   agent per Linux node. Never relax listener bindings or grant broad RBAC to fix
   a rollout issue.
2. Query central `up{job=~"node-metrics-agent|kube-scheduler|kube-controller-manager|kube-proxy"}`.
   Expect one self/kube-proxy series per node and one scheduler/controller-manager
   series per control-plane node, all equal to one. Check node/instance labels.
   Remote-written targets appear in queries, not central Prometheus target discovery.
3. Confirm component alerts resolve and new missing-agent/target alerts remain
   inactive. Inspect local agent logs for RBAC, TLS, discovery and remote-write errors.
4. Verify no/untrusted/wrong-subject client certificates cannot write; valid client
   cannot query `/api/v1/query` through receiver. Confirm unrelated pods still cannot
   connect directly to central Prometheus.
5. During an approved maintenance test, interrupt one collector and confirm missing
   heartbeat alert fires while other nodes remain visible. Test leaf renewal and
   receiver reload separately; offline tests do not prove live CNI or renewal behavior.
