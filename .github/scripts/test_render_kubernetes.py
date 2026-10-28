import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "validation",
    Path(__file__).with_name("render-kubernetes.py"),
)
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class ValidationTests(unittest.TestCase):
    def test_resource_list_and_bare_equals(self):
        resources = list(
            validation.load_resources(
                "- apiVersion: v1\n  kind: ConfigMap\n  data:\n    operator: =\n"
            )
        )
        self.assertEqual(resources[0]["data"]["operator"], "=")

    def test_duplicate_keys_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate YAML key"):
            list(
                validation.load_resources("apiVersion: v1\nkind: Pod\nkind: Service\n")
            )

    def test_non_resource_is_rejected(self):
        with self.assertRaises(ValueError):
            list(validation.load_resources("replicas: 2"))

    def test_defaults_do_not_hide_other_required_fields(self):
        schema = {
            "type": "object",
            "required": ["length", "noUpper"],
            "properties": {
                "length": {"type": "integer"},
                "noUpper": {"type": "boolean", "default": False},
            },
        }
        converted = validation.json_schema(schema)
        self.assertEqual(converted["required"], ["length"])
        self.assertEqual(converted["properties"]["noUpper"]["type"], "boolean")
        self.assertFalse(converted["additionalProperties"])
        self.assertEqual(schema["required"], ["length", "noUpper"])

    def test_property_names_are_not_schema_keywords(self):
        schema = {
            "type": "object",
            "properties": {
                "required": {"type": "array", "items": {"type": "string"}},
                "nullable": {"type": "boolean"},
            },
        }
        self.assertEqual(
            validation.json_schema(schema)["properties"], schema["properties"]
        )

    def test_nested_nullable_and_int_or_string(self):
        schema = {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "value": {"type": "string", "nullable": True},
                    "port": {"x-kubernetes-int-or-string": True},
                },
            },
        }
        properties = validation.json_schema(schema)["items"]["properties"]
        self.assertEqual(properties["value"]["type"], ["string", "null"])
        self.assertEqual(
            properties["port"]["anyOf"], [{"type": "integer"}, {"type": "string"}]
        )

    def test_preserve_unknown_fields(self):
        schema = {
            "type": "object",
            "x-kubernetes-preserve-unknown-fields": True,
            "properties": {"name": {"type": "string"}},
        }
        self.assertNotIn("additionalProperties", validation.json_schema(schema))


if __name__ == "__main__":
    unittest.main()
