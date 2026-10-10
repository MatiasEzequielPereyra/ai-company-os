"""Portable schema shape checks; byte correspondence is tested by PowerShell."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReviewCitationSpanContractTests(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads(
            (ROOT / "schemas/review-result.schema.json").read_text(encoding="utf-8")
        )
        self.assessment = self.schema["properties"]["assessments"]["items"]
        self.citation = self.assessment["properties"]["evidence"]["items"]

    def test_legacy_required_fields_and_version_are_unchanged(self):
        self.assertEqual(
            self.citation["required"],
            ["artifact_id", "start_line", "end_line", "excerpt"],
        )
        self.assertEqual(
            self.schema["properties"]["contract_version"]["enum"],
            ["review-grounding-v1"],
        )
        self.assertFalse(self.citation["additionalProperties"])

    def test_span_offsets_are_optional_primitive_integers(self):
        for name, minimum in (("byte_start", 0), ("byte_end", 1)):
            with self.subTest(field=name):
                node = self.citation["properties"][name]
                self.assertEqual(node["type"], "integer")
                self.assertEqual(node["minimum"], minimum)
                self.assertNotIn(name, self.citation["required"])
        self.assertIn("Must accompany byte_end", self.citation["properties"]["byte_start"]["description"])
        self.assertIn("Must accompany byte_start", self.citation["properties"]["byte_end"]["description"])

    def test_schema_uses_no_provider_incompatible_union_or_reference(self):
        forbidden = {"anyOf", "oneOf", "allOf", "$ref", "$defs", "definitions"}

        def inspect(value):
            if isinstance(value, dict):
                self.assertFalse(forbidden.intersection(value))
                for child in value.values():
                    inspect(child)
            elif isinstance(value, list):
                for child in value:
                    inspect(child)

        inspect(self.schema)

    def test_excerpt_and_coverage_caps_are_unchanged(self):
        self.assertEqual(self.citation["properties"]["excerpt"]["maxLength"], 2048)
        self.assertEqual(self.assessment["properties"]["evidence"]["maxItems"], 3)
        self.assertEqual(self.schema["properties"]["assessments"]["maxItems"], 64)
        self.assertEqual(self.schema["properties"]["assessments"]["minItems"], 1)

    def test_rationale_preserves_semantic_relevance_responsibility(self):
        description = self.assessment["properties"]["rationale"]["description"]
        self.assertIn("exact obligation", description)
        self.assertIn("irrelevant quote is insufficient", description)
        self.assertIn("UNSATISFIED", description)


if __name__ == "__main__":
    unittest.main()
