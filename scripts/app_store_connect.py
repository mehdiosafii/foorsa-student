#!/usr/bin/env python3
"""The App Store Connect API calls the TestFlight workflow makes.

Reads the team key from the environment: ASC_KEY (the text of the .p8 file),
ASC_KEY_ID and ASC_ISSUER_ID. It prints ids, types and names only, never the
key or a token.

  check-build-number BUNDLE_ID NUMBER
      Exit 1 when App Store Connect already has that build number for the app,
      so a release stops in seconds instead of after the whole build.
  certificates TYPE...
      Print the ids of the team's certificates of those types, one per line.
  revoke-new BEFORE_FILE TYPE...
      Revoke the certificates of those types that this run made: not listed in
      BEFORE_FILE and made by Xcode through the API ("Created via API"). Used
      for the development certificate Xcode makes on a fresh runner to sign the
      archive. Never pass a distribution type: Apple marks a build that is
      uploaded but not yet submitted for review "Invalid Binary" when the
      certificate that signed it is revoked.
  report-new BEFORE_FILE TYPE...
      Warn about certificates of those types that were not in BEFORE_FILE.
  ensure-bundle-id BUNDLE_ID NAME [CAPABILITY...]
      Register an iOS bundle id if the team has none by that identifier, and
      turn on the capabilities named (PUSH_NOTIFICATIONS, ASSOCIATED_DOMAINS).
      The Foorsa CRM app's release does this before Apple signs its build.
  app-exists BUNDLE_ID
      Exit 1, with what to do, when App Store Connect has no app record for
      the bundle id: Apple lets only its website create one.
  ensure-internal-group BUNDLE_ID GROUP_NAME
      Make an internal TestFlight group that gets every build, if the app has
      none by that name.
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.parse

API = "https://api.appstoreconnect.apple.com"
MADE_BY_XCODE = "Created via API"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_signature_to_raw(der: bytes) -> bytes:
    """openssl signs as DER SEQUENCE { INTEGER r, INTEGER s }; a JWT wants r || s."""
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("unexpected signature encoding")
    i, raw = 2, b""
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("unexpected signature encoding")
        length = der[i + 1]
        raw += der[i + 2:i + 2 + length].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + length
    return raw


def token() -> str:
    """An App Store Connect token: an ES256 JWT signed with the .p8 key, valid ten minutes."""
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = b64url(json.dumps(header).encode()) + "." + b64url(json.dumps(claims).encode())
    with tempfile.NamedTemporaryFile("w", suffix=".p8", dir=os.environ.get("RUNNER_TEMP")) as key:
        key.write(os.environ["ASC_KEY"].strip() + "\n")
        key.flush()
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key.name],
                             input=signing_input.encode(), capture_output=True, check=True).stdout
    return signing_input + "." + b64url(der_signature_to_raw(der))


def call(method: str, path: str, query=None, body=None):
    url = path if path.startswith("https://") else API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    command = ["curl", "-sS", "--fail-with-body", "-X", method, "-H", "Authorization: Bearer " + token()]
    if body is not None:
        command += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
    out = subprocess.run(command + [url], capture_output=True, text=True,
                         input=json.dumps(body) if body is not None else None)
    if out.returncode:
        print(f"::error::App Store Connect answered {method} {path} with: {out.stdout.strip() or out.stderr.strip()}")
        sys.exit(1)
    return json.loads(out.stdout) if out.stdout.strip() else None


def certificates(types):
    """Every certificate of those types, following the pages."""
    found, page = [], call("GET", "/v1/certificates", {"filter[certificateType]": ",".join(types), "limit": "200"})
    while page:
        found += page.get("data", [])
        following = (page.get("links") or {}).get("next")
        page = call("GET", following) if following else None
    return found


def describe(cert) -> str:
    a = cert.get("attributes", {})
    return f"{a.get('certificateType')} '{a.get('name') or a.get('displayName')}' (id {cert['id']}, expires {a.get('expirationDate')})"


def made_by_xcode(cert) -> bool:
    a = cert.get("attributes", {})
    return MADE_BY_XCODE in f"{a.get('name') or ''} {a.get('displayName') or ''}"


def new_since(before_file, types):
    with open(before_file) as f:
        before = {line.strip() for line in f if line.strip()}
    return [cert for cert in certificates(types) if cert["id"] not in before]


def bundle_id(identifier):
    """The team's bundle id record for exactly this identifier, or None."""
    found = call("GET", "/v1/bundleIds", {"filter[identifier]": identifier, "limit": "200"})["data"]
    return next((b for b in found if b["attributes"]["identifier"] == identifier), None)


def ensure_bundle_id(identifier, name, capabilities):
    record = bundle_id(identifier)
    if record is None:
        record = call("POST", "/v1/bundleIds", body={"data": {"type": "bundleIds", "attributes": {
            "identifier": identifier, "name": name, "platform": "IOS"}}})["data"]
        print(f"Registered bundle id {identifier} ({name}), id {record['id']}.")
    else:
        print(f"Bundle id {identifier} is registered (id {record['id']}).")
    have = {c["attributes"]["capabilityType"] for c in
            call("GET", f"/v1/bundleIds/{record['id']}/bundleIdCapabilities")["data"]}
    for capability in capabilities:
        if capability in have:
            print(f"  {capability}: on")
            continue
        call("POST", "/v1/bundleIdCapabilities", body={"data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": capability},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": record["id"]}}}}})
        print(f"  {capability}: turned on")
    return 0


def app_for(identifier):
    apps = call("GET", "/v1/apps", {"filter[bundleId]": identifier})["data"]
    return next((a for a in apps if a["attributes"]["bundleId"] == identifier), None)


def ensure_internal_group(identifier, name):
    app = app_for(identifier)
    if app is None:
        print(f"::error::App Store Connect has no app for {identifier}.")
        return 1
    groups = call("GET", f"/v1/apps/{app['id']}/betaGroups", {"limit": "200"})["data"]
    if any(g["attributes"]["name"] == name for g in groups):
        print(f"TestFlight group '{name}' exists.")
        return 0
    call("POST", "/v1/betaGroups", body={"data": {
        "type": "betaGroups",
        "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})
    print(f"Made the internal TestFlight group '{name}', which gets every build.")
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    command, args = argv[1], argv[2:]
    if command == "check-build-number":
        bundle, number = args
        apps = [a for a in call("GET", "/v1/apps", {"filter[bundleId]": bundle})["data"]
                if a["attributes"]["bundleId"] == bundle]
        if not apps:
            print(f"::error::The App Store Connect key cannot see an app with bundle id {bundle}.")
            return 1
        if call("GET", "/v1/builds", {"filter[app]": apps[0]["id"], "filter[version]": number, "limit": "1"})["data"]:
            print(f"::error::App Store Connect already has build {number}. Raise the number after + in pubspec.yaml's version.")
            return 1
        print(f"Build number {number} is free in App Store Connect.")
        return 0
    if command == "certificates":
        for cert in certificates(args):
            print(cert["id"])
        return 0
    if command == "revoke-new":
        before_file, types = args[0], args[1:]
        if any("DISTRIBUTION" in t for t in types):
            print("::error::A distribution certificate is never revoked by the workflow.")
            return 2
        for cert in new_since(before_file, types):
            if made_by_xcode(cert):
                call("DELETE", f"/v1/certificates/{cert['id']}")
                print(f"Revoked {describe(cert)}, made by Xcode for this run's archive.")
            else:
                print(f"::warning::Left {describe(cert)} alone: it appeared during the run but Xcode did not make it.")
        return 0
    if command == "report-new":
        before_file, types = args[0], args[1:]
        for cert in new_since(before_file, types):
            print(f"::warning::A new certificate appeared during the run: {describe(cert)}. Apple's cloud signing should not need one; check Certificates in the developer account.")
        return 0
    if command == "ensure-bundle-id":
        identifier, name, capabilities = args[0], args[1], args[2:]
        return ensure_bundle_id(identifier, name, capabilities)
    if command == "app-exists":
        (identifier,) = args
        if app_for(identifier) is None:
            print(f"::error::App Store Connect has no app for {identifier}. Create it once on "
                  "appstoreconnect.apple.com (Apps, +, New App, bundle id " + identifier + "); "
                  "Apple's API cannot. Then run the release again.")
            return 1
        print(f"App Store Connect has an app for {identifier}.")
        return 0
    if command == "ensure-internal-group":
        identifier, name = args
        return ensure_internal_group(identifier, name)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
