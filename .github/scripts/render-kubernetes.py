"""Prepare resources and pinned CRD schemas for the kubeconform container."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.request import urlopen

import yaml


ROOT = Path(__file__).resolve().parents[2]


class KubernetesLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        keys = set()
        for key_node, _ in node.value:
            if key_node.tag == "tag:yaml.org,2002:merge":
                continue
            key = self.construct_object(key_node, deep=deep)
            if key in keys:
                raise ValueError(
                    f"Duplicate YAML key {key!r} at line {key_node.start_mark.line + 1}"
                )
            keys.add(key)
        return super().construct_mapping(node, deep=deep)


# CRD enum values can contain a bare "=", which PyYAML tags specially.
KubernetesLoader.add_constructor(
    "tag:yaml.org,2002:value", KubernetesLoader.construct_scalar
)


def load_resources(text):
    for document in yaml.load_all(text, Loader=KubernetesLoader):
        if document is None:
            continue
        # argocd-network-policies.yaml is a Helm extraObjects list.
        for resource in document if isinstance(document, list) else [document]:
            if (
                not isinstance(resource, dict)
                or not {"apiVersion", "kind"} <= resource.keys()
            ):
                raise ValueError(
                    "Expected Kubernetes resource with apiVersion and kind"
                )
            yield resource


def json_schema(value):
    """Translate Kubernetes OpenAPI extensions needed by JSON Schema validators."""
    if not isinstance(value, dict):
        return value
    result = value.copy()
    for key in ("properties", "patternProperties", "definitions", "$defs"):
        if key in result:
            result[key] = {
                name: json_schema(schema) for name, schema in result[key].items()
            }
    for key in ("items", "additionalProperties", "not"):
        if key in result:
            result[key] = json_schema(result[key])
    for key in ("allOf", "anyOf", "oneOf"):
        if key in result:
            result[key] = [json_schema(schema) for schema in result[key]]
    nullable = result.pop("nullable", False)
    if result.get("x-kubernetes-int-or-string"):
        result.pop("type", None)
        result["anyOf"] = [{"type": "integer"}, {"type": "string"}]
    properties = result.get("properties", {})
    if properties and not result.get("x-kubernetes-preserve-unknown-fields"):
        result.setdefault("additionalProperties", False)
    # Kubernetes applies defaults before checking required fields; kubeconform does not.
    if "required" in result:
        required = [
            name
            for name in result["required"]
            if "default" not in properties.get(name, {})
        ]
        if required:
            result["required"] = required
        else:
            result.pop("required")
    if nullable:
        if "type" in result:
            result["type"] = [result["type"], "null"]
        else:
            result = {"anyOf": [result, {"type": "null"}]}
    return result


def crd_definition_schema(kubernetes_version):
    # CRD-object schemas are absent from kubeconform's default schema registry.
    url = (
        f"https://raw.githubusercontent.com/kubernetes/kubernetes/v{kubernetes_version}/"
        "api/openapi-spec/v3/apis__apiextensions.k8s.io__v1_openapi.json"
    )
    with urlopen(url, timeout=30) as response:
        openapi = json.load(response)
    return {
        "$ref": "#/components/schemas/io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.CustomResourceDefinition",
        "components": {
            "schemas": {
                name: json_schema(schema)
                for name, schema in openapi["components"]["schemas"].items()
            }
        },
    }


def render_chart(application, source, kubernetes_version, api_versions):
    spec = application["spec"]
    helm = source.get("helm", {})
    unsupported = helm.keys() - {"releaseName", "values", "valuesObject"}
    if unsupported:
        raise ValueError(f"Unsupported Helm options: {sorted(unsupported)}")
    command = [
        "helm",
        "template",
        helm.get("releaseName", application["metadata"]["name"]),
    ]
    if "chart" in source:
        repo = source["repoURL"].rstrip("/")
        chart = source["chart"]
        if repo.startswith("oci://"):
            command += [repo if repo.endswith("/" + chart) else f"{repo}/{chart}"]
        else:
            command += [chart, "--repo", repo]
        command += ["--version", str(source["targetRevision"])]
    else:
        command += [str(ROOT / source["path"])]
    command += [
        "--namespace",
        spec["destination"]["namespace"],
        "--kube-version",
        kubernetes_version,
        "--include-crds",
    ]
    for api_version in api_versions:
        command += ["--api-versions", api_version]
    # Helm applies valuesObject after values, matching ArgoCD precedence.
    with tempfile.TemporaryDirectory() as directory:
        for name in ("values", "valuesObject"):
            if name in helm:
                path = Path(directory) / f"{name}.yaml"
                value = helm[name]
                path.write_text(
                    yaml.safe_dump(value) if name == "valuesObject" else value
                )
                command += ["--values", str(path)]
        print(
            f"Rendering {application['metadata']['name']}: {source.get('chart', source.get('path'))}",
            flush=True,
        )
        return list(
            load_resources(subprocess.check_output(command, text=True, cwd=ROOT))
        )


def main(output_directory):
    version = re.search(
        r'^kubernetes_version\s*=\s*"v?([^"\n]+)"',
        (ROOT / "infra/terraform.tfvars").read_text(),
        re.MULTILINE,
    )
    if version is None:
        raise ValueError("Cannot find kubernetes_version in infra/terraform.tfvars")
    kubernetes_version = version[1]
    resources = {}
    for path in sorted(
        path for path in (ROOT / "apps").rglob("*") if path.suffix in {".yaml", ".yml"}
    ):
        if "templates" in path.parts or path.name in {
            "Chart.yaml",
            "values.yaml",
            "kustomization.yaml",
        }:
            continue
        resources[str(path.relative_to(ROOT))] = list(load_resources(path.read_text()))
    resources["argocd-network-policies.yaml"] = list(
        load_resources((ROOT / "argocd-network-policies.yaml").read_text())
    )
    api_versions = sorted(
        {
            name
            for documents in resources.values()
            for resource in documents
            for name in (
                resource["apiVersion"],
                f"{resource['apiVersion']}/{resource['kind']}",
            )
        }
    )
    for path, documents in list(resources.items()):
        for application in documents:
            if application["kind"] != "Application":
                continue
            spec = application["spec"]
            sources = spec.get("sources", [spec.get("source", {})])
            for index, source in enumerate(sources):
                local_chart = ROOT / source.get("path", "") / "Chart.yaml"
                if "chart" in source or local_chart.is_file():
                    resources[f"{path}-helm-{index}"] = render_chart(
                        application,
                        source,
                        kubernetes_version,
                        api_versions,
                    )
                elif source.get("repoURL") != "https://github.com/atimofeev/homelab":
                    print(f"Not rendered (remote Git source): {source}", flush=True)

    schemas = output_directory / "schemas"
    manifests = output_directory / "manifests"
    schemas.mkdir(parents=True)
    manifests.mkdir()
    (schemas / "apiextensions.k8s.io-customresourcedefinition-v1.json").write_text(
        json.dumps(crd_definition_schema(kubernetes_version))
    )
    served_versions = {}
    for documents in resources.values():
        for resource in documents:
            if resource["kind"] != "CustomResourceDefinition":
                continue
            spec = resource["spec"]
            group, kind = spec["group"], spec["names"]["kind"]
            served_versions[group, kind] = {
                item["name"] for item in spec["versions"] if item["served"]
            }
            for item in spec["versions"]:
                if item["served"]:
                    schema = json_schema(item["schema"]["openAPIV3Schema"])
                    (
                        schemas / f"{group}-{kind.lower()}-{item['name']}.json"
                    ).write_text(json.dumps(schema))
    for index, (origin, documents) in enumerate(resources.items()):
        for resource in documents:
            group, _, version = resource["apiVersion"].rpartition("/")
            served = served_versions.get((group, resource["kind"]))
            if served is not None and version not in served:
                raise ValueError(
                    f"{origin}: {resource['apiVersion']}/{resource['kind']} is not served by rendered CRDs"
                )
        path = manifests / f"{index}-{origin.replace('/', '-')}.yaml"
        path.write_text(yaml.safe_dump_all(documents))
    (output_directory / "kubernetes-version").write_text(kubernetes_version)
    if github_output := os.environ.get("GITHUB_OUTPUT"):
        with Path(github_output).open("a") as output:
            output.write(f"kubernetes_version={kubernetes_version}\n")
    print(
        f"Prepared {sum(map(len, resources.values()))} resources for Kubernetes {kubernetes_version}",
        flush=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_directory", type=Path)
    main(parser.parse_args().output_directory)
