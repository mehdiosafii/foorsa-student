"""openapi_check.py against a small specification in Apple's form: a check that never finds
anything would make the tests that lean on it say nothing.

    python3 -m unittest discover -s scripts/tests -v
"""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import openapi_check  # noqa: E402

SPEC = {
    "info": {"version": "test"},
    "paths": {
        "/v1/things": {
            "get": {"parameters": [
                {"name": "filter[state]", "in": "query", "schema": {"type": "array", "items": {"type": "string", "enum": ["OPEN", "DONE"]}}},
                {"name": "limit", "in": "query", "schema": {"type": "integer", "maximum": 200}},
                {"name": "sort", "in": "query", "schema": {"type": "array", "items": {"type": "string", "enum": ["made", "-made"]}}},
                {"name": "filter[app]", "in": "query", "schema": {"type": "array", "items": {"type": "string"}}},
            ]},
            "post": {"requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/ThingCreateRequest"}}}}},
        },
        "/v1/things/{id}": {
            "parameters": [{"name": "id", "in": "path", "schema": {"type": "string"}}],
            "get": {"parameters": [{"name": "include", "in": "query", "schema": {"type": "array", "items": {"type": "string", "enum": ["owner"]}}}]},
        },
        "/v1/things/{id}/relationships/owner": {"patch": {"requestBody": {"content": {"application/json": {"schema": {
            "type": "object", "required": ["data"], "properties": {"data": {"$ref": "#/components/schemas/Link"}}}}}}}},
    },
    "components": {"schemas": {
        "Link": {"type": "object", "required": ["id", "type"],
                 "properties": {"type": {"type": "string", "enum": ["owners"]}, "id": {"type": "string"}}},
        "ThingCreateRequest": {"type": "object", "required": ["data"], "properties": {"data": {
            "type": "object", "required": ["type", "attributes"], "properties": {
                "type": {"type": "string", "enum": ["things"]},
                "attributes": {"type": "object", "required": ["name"], "properties": {
                    "name": {"type": "string"},
                    "kind": {"type": "string", "nullable": True, "enum": ["MANUAL", "AFTER_APPROVAL"]},
                    "wanted": {"type": "boolean"},
                    "count": {"type": "integer"},
                    "source": {"oneOf": [{"type": "object", "required": ["pointer"], "properties": {"pointer": {"type": "string"}}},
                                         {"type": "object", "required": ["parameter"], "properties": {"parameter": {"type": "string"}}}]},
                    "meta": {"type": "object", "additionalProperties": {}},
                }},
                "relationships": {"type": "object", "properties": {"owner": {"type": "object", "properties": {"data": {
                    "$ref": "#/components/schemas/Link"}}}, "tags": {"type": "object", "properties": {"data": {
                        "type": "array", "items": {"$ref": "#/components/schemas/Link"}}}}}},
            }}}},
    }},
}


def load():
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as f:
        json.dump(SPEC, f)
        f.flush()
        return openapi_check.load(f.name)


def body(**attributes):
    return {"data": {"type": "things", "attributes": attributes}}


class TheCheck(unittest.TestCase):
    spec = load()

    def problems(self, method, path, query=None, sent=None):
        return openapi_check.problems(self.spec, method, path, query, sent)

    def test_no_specification_named_means_no_check(self):
        self.assertIsNone(openapi_check.load(None))
        self.assertIsNone(openapi_check.load(""))

    def test_requests_the_specification_takes(self):
        self.assertEqual(self.problems("GET", "/v1/things"), [])
        self.assertEqual(self.problems("GET", "/v1/things", {"filter[state]": "OPEN,DONE", "limit": 200, "sort": "-made", "filter[app]": "1"}), [])
        self.assertEqual(self.problems("GET", "/v1/things", {"limit": "1", "cursor": "abc"}), [])
        self.assertEqual(self.problems("GET", "/v1/things/42", {"include": "owner"}), [])
        self.assertEqual(self.problems("POST", "/v1/things", sent=body(name="a", kind=None, wanted=True, count=3)), [])
        self.assertEqual(self.problems("POST", "/v1/things", sent=body(name="a", source={"parameter": "x"}, meta={"any": [1]})), [])
        self.assertEqual(self.problems("PATCH", "/v1/things/42/relationships/owner", sent={"data": {"type": "owners", "id": "7"}}), [])
        with_owner = body(name="a")
        with_owner["data"]["relationships"] = {"owner": {"data": {"type": "owners", "id": "7"}}, "tags": {"data": [{"type": "owners", "id": "8"}]}}
        self.assertEqual(self.problems("POST", "/v1/things", sent=with_owner), [])

    def test_a_path_or_a_method_it_does_not_have(self):
        self.assertEqual(self.problems("GET", "/v1/thing"), ["/v1/thing: no such path"])
        self.assertEqual(self.problems("GET", "/v1/things/42/owner"), ["/v1/things/42/owner: no such path"])
        self.assertEqual(self.problems("GET", "/v1/things/42/"), ["/v1/things/42/: no such path"])
        self.assertEqual(self.problems("DELETE", "/v1/things/42"), ["DELETE /v1/things/{id}: the path has no such method"])
        self.assertEqual(self.problems("PATCH", "/v1/things"), ["PATCH /v1/things: the path has no such method"])

    def test_a_query_it_does_not_take(self):
        self.assertEqual(self.problems("GET", "/v1/things", {"filter[status]": "OPEN"}), ["?filter[status]: not a parameter of GET /v1/things"])
        self.assertEqual(self.problems("GET", "/v1/things/42", {"limit": 5}), ["?limit: not a parameter of GET /v1/things/{id}"])
        self.assertEqual(len(self.problems("GET", "/v1/things", {"filter[state]": "OPEN,WAITING"})), 1)
        self.assertEqual(len(self.problems("GET", "/v1/things", {"sort": "made,name"})), 1)
        self.assertEqual(len(self.problems("GET", "/v1/things", {"limit": 201})), 1)
        self.assertEqual(len(self.problems("GET", "/v1/things", {"limit": "many"})), 1)
        self.assertEqual(len(self.problems("GET", "/v1/things/42", {"include": "owner,tags"})), 1)

    def test_a_body_it_does_not_take(self):
        for sent, said in (
            (None, "body: null where the specification takes none"),
            ({}, "body: data is required"),
            ({"data": {"type": "things"}}, "body/data: attributes is required"),
            ({"data": {"type": "thing", "attributes": {"name": "a"}}}, "body/data/type: 'thing' is not one of things"),
            (body(), "body/data/attributes: name is required"),
            (body(name="a", nam="b"), "body/data/attributes/nam: not a field the specification names"),
            (body(name="a", kind="SCHEDULED"), "body/data/attributes/kind: 'SCHEDULED' is not one of MANUAL, AFTER_APPROVAL"),
            (body(name=7), "body/data/attributes/name: not text"),
            (body(name=None), "body/data/attributes/name: null where the specification takes none"),
            (body(name="a", wanted="true"), "body/data/attributes/wanted: not true or false"),
            (body(name="a", count=True), "body/data/attributes/count: not a number"),
            (body(name="a", count="3"), "body/data/attributes/count: not a number"),
            ({"data": {"type": "things", "attributes": {"name": "a"}, "id": "1"}}, "body/data/id: not a field the specification names"),
            ({"data": [body(name="a")["data"]]}, "body/data: not an object"),
        ):
            self.assertEqual(self.problems("POST", "/v1/things", sent=sent), [said], sent)
        self.assertEqual(len(self.problems("POST", "/v1/things", sent=body(name="a", source={"neither": "x"}))), 1)
        self.assertEqual(self.problems("PATCH", "/v1/things/42/relationships/owner", sent={"data": {"type": "owners"}}), ["body/data: id is required"])
        tags = body(name="a")
        tags["data"]["relationships"] = {"tags": {"data": {"type": "owners", "id": "8"}}}
        self.assertEqual(self.problems("POST", "/v1/things", sent=tags), ["body/data/relationships/tags/data: not a list"])
        tags["data"]["relationships"] = {"tags": {"data": [{"type": "owners"}]}}
        self.assertEqual(self.problems("POST", "/v1/things", sent=tags), ["body/data/relationships/tags/data/0: id is required"])
        self.assertEqual(self.problems("GET", "/v1/things", sent={"data": {}}), ["GET /v1/things takes no body"])


if __name__ == "__main__":
    unittest.main()
