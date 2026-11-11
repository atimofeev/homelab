"""Validate app-owned AI credentials without accessing Bitwarden or paid APIs."""

from pathlib import Path
import unittest
from uuid import UUID

import yaml


ROOT = Path(__file__).resolve().parents[2]


def load(path):
    return yaml.safe_load((ROOT / path).read_text())


class KarakeepAISecretTests(unittest.TestCase):
    def test_bitwarden_source_is_app_owned_and_authorized(self):
        objects = list(yaml.safe_load_all(
            (ROOT / "apps/karakeep/secrets.yaml").read_text()
        ))
        matches = [obj for obj in objects if obj["metadata"]["name"] == "karakeep-ai"]
        self.assertEqual(len(matches), 1)
        secret = matches[0]
        self.assertEqual(secret["kind"], "ExternalSecret")
        self.assertEqual(secret["metadata"]["namespace"], "karakeep")
        self.assertEqual(secret["spec"]["secretStoreRef"], {
            "name": "bitwarden-secrets-manager", "kind": "ClusterSecretStore",
        })
        self.assertEqual(secret["spec"]["refreshInterval"], "1h0m0s")
        UUID(secret["spec"]["dataFrom"][0]["extract"]["key"])
        settings = load("apps/external-secrets/values.yaml")["externalSecrets"]
        self.assertIn("karakeep", settings["additionalNamespaces"])
        self.assertFalse(any(item["name"] == "karakeep-ai" for item in settings["secrets"]))

    def test_deployment_requires_secret_and_reloads_on_change(self):
        deployment = load("apps/karakeep/deployment.yaml")
        containers = deployment["spec"]["template"]["spec"]["containers"]
        app = next(item for item in containers if item["name"] == "karakeep")
        refs = [entry["secretRef"] for entry in app["envFrom"] if "secretRef" in entry]
        self.assertIn({"name": "karakeep-ai"}, refs)
        reloads = deployment["metadata"]["annotations"][
            "secret.reloader.stakater.com/reload"
        ].split(",")
        self.assertIn("karakeep-ai", reloads)

    def test_inference_settings_have_no_manifest_overrides(self):
        deployment = load("apps/karakeep/deployment.yaml")
        config = load("apps/karakeep/configmap.yaml")["data"]
        explicit_env = {
            item["name"]
            for container in deployment["spec"]["template"]["spec"]["containers"]
            for item in container.get("env", [])
        }
        self.assertFalse(any(
            name.startswith(("OPENAI_", "INFERENCE_", "EMBEDDING_"))
            for name in set(config) | explicit_env
        ))


if __name__ == "__main__":
    unittest.main()
