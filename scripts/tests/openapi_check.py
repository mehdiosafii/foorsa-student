"""Whether a request is one Apple's App Store Connect API takes, by Apple's own OpenAPI
specification: that the path exists for the method, that each query parameter is one it names
with a value it allows, and that a write's body has the fields it requires and no other.

The specification is not in the repository (7 MB, and Apple's). The tests use it when
ASC_OPENAPI names the openapi.oas.json from the zip Apple publishes at
https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
and skip this check without it.
"""
import json
import re


def load(path):
    if not path:
        return None
    with open(path, encoding="utf-8") as f:
        spec = json.load(f)
    spec["_templates"] = [(re.compile(re.sub(r"\{[^/}]+\}", "[^/]+", template)), template) for template in spec["paths"]]
    return spec


def resolve(spec, schema):
    while "$ref" in schema:
        node = spec
        for part in schema["$ref"].lstrip("#/").split("/"):
            node = node[part]
        schema = node
    return schema


def check(spec, schema, value, where, found):
    schema = resolve(spec, schema)
    if value is None:
        if not schema.get("nullable"):
            found.append(f"{where}: null where the specification takes none")
        return
    for several in ("oneOf", "anyOf"):
        if several in schema:
            tries = []
            for option in schema[several]:
                problems = []
                check(spec, option, value, where, problems)
                tries.append(problems)
            if all(tries):
                found.append(f"{where}: fits none of the specification's forms ({tries[0][0]})")
            return
    kind = schema.get("type")
    if kind == "object":
        if not isinstance(value, dict):
            found.append(f"{where}: not an object")
            return
        fields = schema.get("properties", {})
        for name in schema.get("required", []):
            if name not in value:
                found.append(f"{where}: {name} is required")
        for name, inner in value.items():
            if name in fields:
                check(spec, fields[name], inner, f"{where}/{name}", found)
            elif schema.get("additionalProperties", False) is not False:
                # Any field is taken, each in the form given for them (an empty form: any value).
                if isinstance(schema["additionalProperties"], dict):
                    check(spec, schema["additionalProperties"], inner, f"{where}/{name}", found)
            else:
                found.append(f"{where}/{name}: not a field the specification names")
    elif kind == "array":
        if not isinstance(value, list):
            found.append(f"{where}: not a list")
            return
        for index, inner in enumerate(value):
            check(spec, schema.get("items", {}), inner, f"{where}/{index}", found)
    elif kind == "string" and not isinstance(value, str):
        found.append(f"{where}: not text")
    elif kind == "boolean" and not isinstance(value, bool):
        found.append(f"{where}: not true or false")
    elif kind in ("integer", "number") and (isinstance(value, bool) or not isinstance(value, (int, float))):
        found.append(f"{where}: not a number")
    if "enum" in schema and value not in schema["enum"]:
        found.append(f"{where}: {value!r} is not one of {', '.join(map(str, schema['enum']))}")


def problems(spec, method, path, query=None, body=None):
    """What is wrong with the request by the specification; nothing when it is one Apple takes."""
    template = path if path in spec["paths"] else next((t for pattern, t in spec["_templates"] if pattern.fullmatch(path)), None)
    if template is None:
        return [f"{path}: no such path"]
    item = spec["paths"][template]
    operation = item.get(method.lower())
    if operation is None:
        return [f"{method} {template}: the path has no such method"]
    found = []
    named = {p["name"]: p for p in item.get("parameters", []) + operation.get("parameters", []) if p.get("in") == "query"}
    for name, value in (query or {}).items():
        if name == "cursor":            # a list's next page, as the API's own link carries it
            continue
        if name not in named:
            found.append(f"?{name}: not a parameter of {method} {template}")
            continue
        schema = resolve(spec, named[name].get("schema", {}))
        if schema.get("type") == "array":
            allowed = resolve(spec, schema.get("items", {})).get("enum")
            for one in str(value).split(","):
                if allowed and one not in allowed:
                    found.append(f"?{name}: {one!r} is not one of the values the specification allows")
        elif schema.get("type") == "integer":
            if not str(value).isdigit() or ("maximum" in schema and int(value) > schema["maximum"]):
                found.append(f"?{name}: {value!r} is not a number up to {schema.get('maximum')}")
        elif "enum" in schema and str(value) not in map(str, schema["enum"]):
            found.append(f"?{name}: {value!r} is not one of the values the specification allows")
    wanted = operation.get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema")
    if wanted is not None:
        check(spec, wanted, body, "body", found)
    elif body is not None:
        found.append(f"{method} {template} takes no body")
    return found
