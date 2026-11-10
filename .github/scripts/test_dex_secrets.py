"""Keep Dex credentials app-owned without changing their sharing contract."""

from pathlib import Path
import subprocess
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


def load(path):
    return yaml.safe_load((ROOT / path).read_text())


def render(path, name):
    return [
        doc
        for doc in yaml.safe_load_all(
            subprocess.check_output(
                ["helm", "template", name, str(ROOT / path)], text=True
            )
        )
        if doc
    ]


class DexSecretOwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dex = render("apps/dex", "dex")
        cls.external = render("apps/external-secrets", "external-secrets")
        cls.clients = load("apps/dex/values.yaml")["clients"]
        cls.dex_app = load("apps/dex/main.yaml")

    def resource(self, kind, name):
        matches = [
            obj for obj in self.dex
            if obj["kind"] == kind and obj["metadata"]["name"] == name
        ]
        self.assertEqual(len(matches), 1)
        return matches[0]

    def test_source_clients_match_dex_config(self):
        values = self.dex_app["spec"]["sources"][0]["helm"]["valuesObject"]
        clients = {client["name"] for client in self.clients}
        registrations = values["config"]["staticClients"]
        self.assertEqual(clients, {client["id"] for client in registrations})
        env = {entry["name"]: entry for entry in values["envVars"]}
        reloads = values["deploymentAnnotations"][
            "secret.reloader.stakater.com/reload"
        ].split(",")
        for client in registrations:
            source = "dex-client-" + client["id"]
            self.assertEqual(
                env[client["secretEnv"]]["valueFrom"]["secretKeyRef"],
                {"name": source, "key": "password"},
            )
            self.assertIn(source, reloads)
            spec = self.resource("ExternalSecret", source)["spec"]
            self.assertEqual(spec["refreshPolicy"], "CreatedOnce")
            self.assertEqual(spec["target"], {
                "creationPolicy": "Orphan", "immutable": True,
            })
            self.assertEqual(
                spec["dataFrom"][0]["sourceRef"]["generatorRef"]["name"],
                "dex-client-secret",
            )
        self.resource("Password", "dex-client-secret")

    def test_sharing_permissions_match_clients(self):
        rule = self.resource("Role", "dex-client-secret-reader")["rules"][0]
        self.assertEqual(rule["verbs"], ["get"])
        self.assertEqual(
            set(rule["resourceNames"]),
            {"dex-client-" + client["name"] for client in self.clients},
        )
        store = self.resource("ClusterSecretStore", "dex-client-secrets")["spec"]
        self.assertEqual(
            set(store["conditions"][0]["namespaces"]),
            {client["namespace"] for client in self.clients},
        )
        self.assertEqual(store["provider"]["kubernetes"]["remoteNamespace"], "dex")

    def test_consumers_own_destinations(self):
        destinations = [
            load("apps/argocd-oidc/dex-secret.yaml"),
            load("apps/kube-prometheus-stack/grafana-dex-secret.yaml"),
            load("apps/paperless-ngx/dex-secret.yaml"),
        ]
        destinations.extend(
            obj for obj in yaml.safe_load_all(
                (ROOT / "apps/karakeep/secrets.yaml").read_text()
            ) if obj["metadata"]["name"] == "karakeep-dex"
        )
        proxy = load("apps/oauth2-proxy/main.yaml")
        destinations.extend(
            obj for obj in proxy["spec"]["source"]["helm"]["valuesObject"]["extraObjects"]
            if obj["metadata"]["name"] == "oauth2-proxy-dex"
        )
        by_name = {obj["metadata"]["name"]: obj for obj in destinations}
        self.assertEqual(len(destinations), len(self.clients))
        for client in self.clients:
            dest = by_name[client["name"] + "-dex"]
            self.assertEqual(dest["metadata"]["namespace"], client["namespace"])
            self.assertEqual(dest["spec"]["secretStoreRef"], {
                "name": "dex-client-secrets", "kind": "ClusterSecretStore",
            })
            self.assertEqual(dest["spec"]["data"][0]["remoteRef"], {
                "key": "dex-client-" + client["name"], "property": "password",
            })
        for obj in self.dex + self.external:
            self.assertNotIn(obj["metadata"]["name"], by_name)
        self.assertNotIn("directory", self.dex_app["spec"]["sources"][1])
        argocd = by_name["argocd-dex"]["spec"]["target"]["template"]
        self.assertEqual(argocd["metadata"]["labels"]["app.kubernetes.io/part-of"], "argocd")

    def test_google_credentials_and_namespace_permission(self):
        google = self.resource("ExternalSecret", "dex-credentials")
        self.assertEqual(google["spec"]["target"]["template"]["data"], {
            "GOOGLE_CLIENT_ID": "{{ .GOOGLE_CLIENT_ID }}",
            "GOOGLE_CLIENT_SECRET": "{{ .GOOGLE_CLIENT_SECRET }}",
        })
        self.assertFalse(any(
            obj["metadata"]["name"].startswith("dex-") for obj in self.external
        ))
        store = next(obj for obj in self.external if obj["kind"] == "ClusterSecretStore")
        self.assertIn("dex", store["spec"]["conditions"][0]["namespaces"])

    def test_network_policy_remains_dex_owned(self):
        policy = self.resource("NetworkPolicy", "dex")
        self.assertEqual(policy["metadata"]["namespace"], "dex")
        self.assertEqual(policy["spec"]["podSelector"]["matchLabels"], {
            "app.kubernetes.io/name": "dex", "app.kubernetes.io/instance": "dex",
        })


if __name__ == "__main__":
    unittest.main()
