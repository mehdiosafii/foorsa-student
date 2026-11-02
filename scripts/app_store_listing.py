#!/usr/bin/env python3
"""The App Store listing of Foorsa Student, read and kept through the App Store Connect API.

Reads the team key as the TestFlight workflow does: ASC_KEY (the text of the .p8 file),
ASC_KEY_ID and ASC_ISSUER_ID. It prints ids, states, counts and whether a field is filled,
never the key, a token, a contact's details or a demo account's password.

  state
      What App Store Connect holds for the app, and what a first submission still lacks:
      the App Store version being prepared, its text, screenshots, build, age rating,
      categories, review details, availability and any review submission. App Privacy
      (the data the app collects) is not in Apple's API; it is reported as unknown.
  review-check
      Whether App Review's demo account still opens the app as it is today: it signs in
      to the portal with the demo account App Store Connect holds and reports only what a
      reviewer would meet (a password to change, the contract to sign, the step of the
      file), and prints the review notes with the account's name and password masked.
  demo-hash
      The bcrypt hash of the demo account's password App Store Connect holds, encrypted
      to DEMO_HASH_PUBKEY (RSA-OAEP), so the portal's demo account can be given that
      password again without the password or its hash appearing in the log.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app_store_connect import API, token  # noqa: E402  (the one token maker)

BUNDLE_ID = "ma.foorsa.foorsaStudent"


class AscError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"{status}: {body[:400]}")
        self.status = status
        self.body = body


def request(method: str, path: str, query=None, body=None):
    url = path if path.startswith("https://") else API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token(),
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            text = res.read().decode()
            return json.loads(text) if text.strip() else None
    except urllib.error.HTTPError as err:
        raise AscError(err.code, err.read().decode(errors="replace")) from None


def get(path: str, query=None):
    return request("GET", path, query)


def filled(value) -> str:
    if value is None or value == "":
        return "empty"
    if isinstance(value, str):
        return f"filled ({len(value)} characters)"
    return "filled"


def section(title: str):
    print(f"\n== {title}")


def try_get(label: str, path: str, query=None):
    try:
        return get(path, query)
    except AscError as err:
        print(f"  {label}: App Store Connect answered {err.status} ({err.body[:200].strip()})")
        return None


def state() -> int:
    apps = get("/v1/apps", {"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name,bundleId,primaryLocale,contentRightsDeclaration"})
    if not apps or not apps.get("data"):
        print(f"No app with bundle id {BUNDLE_ID} in this team.")
        return 1
    app = apps["data"][0]
    app_id = app["id"]
    attrs = app["attributes"]
    section("App")
    print(f"  id {app_id}, name {attrs.get('name')!r}, primary locale {attrs.get('primaryLocale')}")
    print(f"  content rights declaration: {attrs.get('contentRightsDeclaration') or 'not set'}")

    section("App information (name, subtitle, privacy policy, categories, age rating)")
    infos = try_get("app infos", f"/v1/apps/{app_id}/appInfos", {"include": "primaryCategory,secondaryCategory"})
    for info in (infos or {}).get("data", []):
        a = info["attributes"]
        rel = info.get("relationships", {})
        primary = (rel.get("primaryCategory", {}).get("data") or {}).get("id")
        secondary = (rel.get("secondaryCategory", {}).get("data") or {}).get("id")
        print(f"  info {info['id']}: state {a.get('state') or a.get('appStoreState')}, primary category {primary or 'not set'}, secondary {secondary or 'none'}")
        locs = try_get("info localizations", f"/v1/appInfos/{info['id']}/appInfoLocalizations")
        for loc in (locs or {}).get("data", []):
            la = loc["attributes"]
            print(f"    {la.get('locale')}: name {la.get('name')!r}, subtitle {filled(la.get('subtitle'))}, "
                  f"privacy policy URL {la.get('privacyPolicyUrl') or 'empty'}, privacy choices URL {filled(la.get('privacyChoicesUrl'))}")
        rating = try_get("age rating", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
        if rating and rating.get("data"):
            ra = rating["data"]["attributes"]
            unset = sorted(k for k, v in ra.items() if v is None)
            print(f"    age rating declaration {rating['data']['id']}: {len(ra) - len(unset)} of {len(ra)} answers set"
                  + (f"; unset: {', '.join(unset)}" if unset else ""))

    section("App Store versions (iOS)")
    versions = try_get("versions", f"/v1/apps/{app_id}/appStoreVersions",
                       {"filter[platform]": "IOS", "limit": 10, "fields[appStoreVersions]": "versionString,appStoreState,appVersionState,releaseType,copyright,createdDate"})
    editable = None
    for v in (versions or {}).get("data", []):
        va = v["attributes"]
        print(f"  {v['id']}: {va.get('versionString')} {va.get('appStoreState') or va.get('appVersionState')}, release {va.get('releaseType')}, copyright {filled(va.get('copyright'))}")
        if editable is None and (va.get("appStoreState") or va.get("appVersionState")) in (
                "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "READY_FOR_REVIEW"):
            editable = v
    if not (versions or {}).get("data"):
        print("  none: a version has to be created before anything can be submitted")
    # The version being prepared, else the newest one, whatever its state (one in review is read too).
    shown = editable or ((versions or {}).get("data") or [None])[0]
    if shown:
        vid = shown["id"]
        section(f"Version {shown['attributes'].get('versionString')} ({shown['attributes'].get('appStoreState') or shown['attributes'].get('appVersionState')})")
        locs = try_get("version localizations", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
        for loc in (locs or {}).get("data", []):
            la = loc["attributes"]
            print(f"  {la.get('locale')}: description {filled(la.get('description'))}, keywords {filled(la.get('keywords'))}, "
                  f"support URL {la.get('supportUrl') or 'empty'}, marketing URL {la.get('marketingUrl') or 'empty'}, "
                  f"promotional text {filled(la.get('promotionalText'))}, what's new {filled(la.get('whatsNew'))}")
            sets = try_get("screenshot sets", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
            for s in (sets or {}).get("data", []):
                shots = try_get("screenshots", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")
                print(f"    screenshots {s['attributes'].get('screenshotDisplayType')}: {len((shots or {}).get('data', []))}")
            if not (sets or {}).get("data"):
                print("    screenshots: none")
        build = try_get("build", f"/v1/appStoreVersions/{vid}/build")
        bd = (build or {}).get("data")
        print(f"  build attached: {bd['attributes'].get('version') if bd else 'none'}")
        review = try_get("review detail", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        rd = (review or {}).get("data")
        if rd:
            ra = rd["attributes"]
            print("  review details: contact first name {}, last name {}, phone {}, email {}, demo account required {}, demo name {}, demo password {}, notes {}".format(
                filled(ra.get("contactFirstName")), filled(ra.get("contactLastName")), filled(ra.get("contactPhone")),
                filled(ra.get("contactEmail")), ra.get("demoAccountRequired"), filled(ra.get("demoAccountName")),
                "set" if ra.get("demoAccountPassword") else "empty", filled(ra.get("notes"))))
        else:
            print("  review details: none yet")

    section("Builds (newest first)")
    builds = try_get("builds", "/v1/builds", {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5,
                                               "fields[builds]": "version,processingState,expired,uploadedDate,minOsVersion",
                                               "include": "preReleaseVersion", "fields[preReleaseVersions]": "version"})
    marketing = {p["id"]: p["attributes"].get("version") for p in (builds or {}).get("included", []) if p.get("type") == "preReleaseVersions"}
    for b in (builds or {}).get("data", []):
        ba = b["attributes"]
        pre = (b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
        print(f"  {marketing.get(pre, '?')} ({ba.get('version')}): {ba.get('processingState')}, expired {ba.get('expired')}, uploaded {ba.get('uploadedDate')}")

    section("Availability and price")
    avail = try_get("availability", f"/v1/apps/{app_id}/appAvailabilityV2")
    if avail and avail.get("data"):
        print(f"  availability set: {avail['data']['attributes']}")
    else:
        print("  availability: not set")
    price = try_get("price schedule", f"/v1/apps/{app_id}/appPriceSchedule")
    print(f"  price schedule: {'set' if price and price.get('data') else 'not set'}")

    section("Review submissions")
    subs = try_get("review submissions", "/v1/reviewSubmissions", {"filter[app]": app_id, "limit": 5})
    for s in (subs or {}).get("data", []):
        print(f"  {s['id']}: {s['attributes'].get('state')} submitted {s['attributes'].get('submittedDate')}, platform {s['attributes'].get('platform')}")
        items = try_get("submission items", f"/v1/reviewSubmissions/{s['id']}/items")
        for item in (items or {}).get("data", []):
            rel = item.get("relationships", {})
            what = [k for k, v in rel.items() if (v.get("data") if isinstance(v, dict) else None)]
            print(f"    item {item['id']}: {item['attributes'].get('state')} ({', '.join(what) or 'no linked object shown'})")
    if not (subs or {}).get("data"):
        print("  none")

    section("App Privacy")
    print("  not in Apple's API: filled in App Store Connect › App Privacy by a person signed in with an Apple ID")
    return 0


PORTAL = "https://student.foorsa.ma"


def app_and_version():
    apps = get("/v1/apps", {"filter[bundleId]": BUNDLE_ID})
    app_id = apps["data"][0]["id"]
    versions = get(f"/v1/apps/{app_id}/appStoreVersions", {"filter[platform]": "IOS", "limit": 1})
    return app_id, versions["data"][0]


def portal(method: str, path: str, body=None, bearer=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json", "User-Agent": "Foorsa App Store listing check"}
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    req = urllib.request.Request(PORTAL + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return res.status, json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as err:
        text = err.read().decode(errors="replace")
        try:
            return err.code, json.loads(text)
        except ValueError:
            return err.code, {"raw": text[:200]}


def review_check() -> int:
    import hashlib
    import textwrap
    _, version = app_and_version()
    print(f"Version {version['attributes'].get('versionString')} ({version['attributes'].get('appStoreState')})")
    review = get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]["attributes"]
    name = (review.get("demoAccountName") or "").strip()
    password = review.get("demoAccountPassword") or ""
    notes = review.get("notes") or ""
    for secret, mask in ((password, "<demo password>"), (name, "<demo name>")):
        if secret:
            notes = notes.replace(secret, mask)
    print(f"Demo account: name sha256 {hashlib.sha256(name.lower().encode()).hexdigest()[:16]}, password {'set' if password else 'empty'}")
    print("Review notes, as App Review reads them (account masked):")
    for paragraph in notes.splitlines():
        print(textwrap.fill(paragraph, 110, initial_indent="  | ", subsequent_indent="  | ") if paragraph.strip() else "  |")
    if not (name and password):
        print("No demo account to try.")
        return 1
    status, body = portal("POST", "/api/portal/login", {"identifier": name, "password": password})
    print(f"Portal sign-in with the demo account: HTTP {status}"
          + (f", error {body.get('error')!r}, code {body.get('code')}" if status != 200 else ""))
    if status != 200 or not body.get("token"):
        return 1
    print(f"  must change password at first sign-in: {body.get('mustChangePassword')}, kind {body.get('kind')}")
    status, me = portal("GET", "/api/portal/me", bearer=body["token"])
    print(f"/api/portal/me: HTTP {status}")
    if status == 200:
        signing = me.get("signing") or {}
        rail = me.get("rail") or {}
        print(f"  file: rail step {rail.get('step')} on hold {rail.get('onHold') if 'onHold' in rail else me.get('onHold')}, "
              f"track {me.get('track')}, in China {me.get('inChina')}, papers open {me.get('papersOpen')}")
        print(f"  signing popup required: {signing.get('required')}, contract {(signing.get('contract') or {}).get('status') if isinstance(signing.get('contract'), dict) else signing.get('contract')}, "
              f"authorization {(signing.get('authorization') or {}).get('status') if isinstance(signing.get('authorization'), dict) else signing.get('authorization')}")
        todo = me.get("todo") or {}
        print(f"  to do: {todo.get('count')} ({todo.get('detailsCount')} details), consent version on file {me.get('consentVersion')}")
    return 0


def demo_hash() -> int:
    import base64
    import subprocess
    import tempfile
    import bcrypt  # installed by the workflow for this command only
    _, version = app_and_version()
    review = get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]["attributes"]
    password = review.get("demoAccountPassword") or ""
    if not password:
        print("No demo password in App Store Connect.")
        return 1
    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=10, prefix=b"2b"))
    with tempfile.NamedTemporaryFile("w", suffix=".pem", dir=os.environ.get("RUNNER_TEMP")) as key:
        key.write(os.environ["DEMO_HASH_PUBKEY"].strip() + "\n")
        key.flush()
        sealed = subprocess.run(["openssl", "pkeyutl", "-encrypt", "-pubin", "-inkey", key.name,
                                 "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256"],
                                input=hashed, capture_output=True, check=True).stdout
    print("Sealed demo password hash (RSA-OAEP, SHA-256):")
    print(base64.b64encode(sealed).decode())
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "state"
    commands = {"state": state, "review-check": review_check, "demo-hash": demo_hash}
    if command not in commands:
        sys.exit(f"Unknown command {command!r}: {', '.join(commands)}")
    sys.exit(commands[command]())
