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
  submit-latest [1.2.42+73] [replace-waiting]
      Puts the newest valid build up for review. What that takes depends on where the newest
      App Store version stands:
        on sale        an update: a new version is made, named after the build
                       (CFBundleShortVersionString), with the release the version on sale has
                       (released by itself once approved, or by hand) and its copyright;
                       "What's New" is written in each of its locales from
                       store/app-store/whats-new/<locale>.txt (Apple refuses an update
                       without it); then as below.
        being prepared, or taken back
                       the version is named after the build, the build attached,
                       store/app-store/review-notes.txt written into the review details (the
                       contact and the demo account are kept as they are), and it is submitted.
                       When an earlier version is on sale it is an update, and "What's New" is
                       written as above.
        waiting for review
                       nothing, unless the word replace-waiting follows: the wait for review
                       starts again, and that is the owner's decision each time. With the
                       word, the submission waiting is cancelled and the version goes up again
                       with the build, as above.
        in review, sent back by App Review and not answered, or approved and not yet on sale
                       nothing: what is in review is never touched, how to answer App Review
                       is decided in App Store Connect, and no update can be made until the
                       version before it is on sale.
      Text, screenshots, age rating and categories stay as they are. What is read from the
      repository is checked against the listing before anything is written. Given a version
      (1.2.42+73), it changes nothing unless the newest valid build is that one:
      .github/app-store-request.txt always names one.
"""
import contextlib
import datetime
import json
import os
import re
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


def pages(path: str, query=None):
    """Every resource of a list, following its pages."""
    found, page = [], get(path, query)
    while page:
        found += page.get("data") or []
        following = (page.get("links") or {}).get("next")
        page = get(following) if following else None
    return found


# What a version's review details hold of the review contact and the demo account. Nothing of
# them is printed: each value is remembered as it is read, and taken out of whatever is said
# of Apple's answers, which could repeat one back.
PRIVATE_FIELDS = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail", "demoAccountName", "demoAccountPassword")
PRIVATE = set()


def scrub(text: str) -> str:
    for value in sorted(PRIVATE, key=len, reverse=True):
        text = re.sub(re.escape(value), lambda _: "<private>", text, flags=re.IGNORECASE)
    return text


def explain(err: AscError, details: bool = True) -> str:
    """Apple's answer in a line: each error's code, what it says and the field it points at,
    with the errors under it (what a version still lacks to be submitted comes that way).
    Without details, the codes and the fields only: for a request that carried a contact or
    the demo account, so nothing of theirs can come back into the log."""
    def a(kind, value):
        return value if isinstance(value, kind) else kind()

    try:
        errors = a(list, a(dict, json.loads(err.body)).get("errors"))
    except ValueError:
        errors = []
    said = []

    def add(error, under=""):
        source = a(dict, error.get("source"))
        text = under + str(error.get("code") or "?")
        if details and error.get("detail"):
            text += f": {error['detail']}"
        if source.get("pointer") or source.get("parameter"):
            text += f" [{source.get('pointer') or source.get('parameter')}]"
        said.append(text)

    for error in errors:
        if isinstance(error, dict):
            add(error)
            for path, more in a(dict, a(dict, error.get("meta")).get("associatedErrors")).items():
                for one in a(list, more):
                    if isinstance(one, dict):
                        add(one, under=f"{path} ")
    if not said and details:
        said = [err.body[:300].strip()]
    return scrub(" ".join(part for part in (str(err.status), "; ".join(said)) if part))


class Refused(Exception):
    """A submission stopped part-way: what it was doing, and App Store Connect's answer."""


@contextlib.contextmanager
def doing(what: str, details: bool = True):
    try:
        yield
    except AscError as err:
        raise Refused(f"{what}: App Store Connect answered {explain(err, details)}") from None


STORE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "store", "app-store")
REVIEW_NOTES = os.path.join(STORE, "review-notes.txt")
WHATS_NEW = os.path.join(STORE, "whats-new")
# App Store Connect takes 4000 characters of review notes, and of "What's New" in a locale.
LONGEST = 4000


def review_notes(marketing: str, number: str) -> str:
    """The notes for App Review as a submission writes them, for that version and build."""
    with open(REVIEW_NOTES, encoding="utf-8") as f:
        return f.read().replace("{version}", marketing).replace("{build}", number).strip()


def whats_new() -> dict:
    """The "What's New" texts by App Store locale: store/app-store/whats-new/<locale>.txt."""
    texts = {}
    if os.path.isdir(WHATS_NEW):
        for name in sorted(os.listdir(WHATS_NEW)):
            if name.endswith(".txt"):
                with open(os.path.join(WHATS_NEW, name), encoding="utf-8") as f:
                    texts[name[:-len(".txt")]] = f.read().strip()
    return texts


def whats_new_problems(texts: dict, locales, went_out: dict) -> list:
    """What stops an update: a locale of the listing without its text, a text too long or left
    as the version on sale went out with it, a text for a locale the listing does not have."""
    problems = []
    listed = ", ".join(locales) or "none"
    for locale in locales:
        text = texts.get(locale) or ""
        where = f"store/app-store/whats-new/{locale}.txt"
        if not text:
            problems.append(f"{where} is missing or empty: an update needs \"What's New\" in each locale of the listing ({listed})")
        elif len(text) > LONGEST:
            problems.append(f"{where} is {len(text)} characters; App Store Connect takes {LONGEST}")
        elif text == (went_out.get(locale) or "").strip():
            problems.append(f"{where} is the text the version on sale went out with: it has to say what a student gets since that version")
    for locale in sorted(set(texts) - set(locales)):
        problems.append(f"store/app-store/whats-new/{locale}.txt: the listing has no {locale} (its locales: {listed}); "
                        "a language is added to the listing in App Store Connect, with its description and screenshots")
    return problems


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


# Where a version stands, by Apple's old name (appStoreState) or its new one (appVersionState).
RELEASED = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
# A version a submission leaves alone, and why, as the log says it.
LEFT_ALONE = {
    "IN_REVIEW": "it is in review, and a version in review is never touched",
    "PENDING_DEVELOPER_RELEASE": "it is approved and waits to be released by hand (App Store Connect, Release This Version): "
                                 "an update can be made once it is on sale",
    "PENDING_APPLE_RELEASE": "it is approved and waits for Apple to release it: an update can be made once it is on sale",
    "PROCESSING_FOR_APP_STORE": "it is approved and on its way to the App Store: an update can be made once it is on sale",
    "PROCESSING_FOR_DISTRIBUTION": "it is approved and on its way to the App Store: an update can be made once it is on sale",
    "ACCEPTED": "it is accepted and not yet on sale: an update can be made once it is",
}


def state_of(version) -> str:
    a = version["attributes"]
    return a.get("appStoreState") or a.get("appVersionState") or ""


def made(version) -> float:
    """When a version was made, to sort by: the API lists an app's versions in no promised order."""
    text = (version["attributes"].get("createdDate") or "").replace("Z", "+00:00")
    try:
        return datetime.datetime.fromisoformat(text).timestamp()
    except ValueError:
        return 0.0


def app_versions(app_id: str):
    """The app's iPhone versions, the newest first."""
    found = pages(f"/v1/apps/{app_id}/appStoreVersions", {"filter[platform]": "IOS", "limit": 200})
    return sorted(found, key=made, reverse=True)


def localizations(version_id: str):
    return pages(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", {"limit": 200})


def review_detail(version_id: str):
    """A version's review details (contact, demo account, notes), or None when it has none yet."""
    try:
        detail = (get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail") or {}).get("data")
    except AscError as err:
        if err.status == 404:
            return None
        raise
    for field in PRIVATE_FIELDS:
        value = ((detail or {}).get("attributes") or {}).get(field)
        if isinstance(value, str) and len(value.strip()) >= 3:
            PRIVATE.add(value.strip())
    return detail


def attached_build(version_id: str):
    """The id of the build a version carries, or None."""
    try:
        return ((get(f"/v1/appStoreVersions/{version_id}/build") or {}).get("data") or {}).get("id")
    except AscError as err:
        if err.status == 404:
            return None
        raise


def open_submissions(app_id: str):
    """The review submissions still open: made and not submitted, waiting for review, in review,
    or sent back by App Review and not yet answered."""
    return pages("/v1/reviewSubmissions", {"filter[app]": app_id, "filter[platform]": "IOS", "limit": 200,
                                           "filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"})


def submission_items(submission_id: str):
    """What a review submission holds, each item with the version it is for, if it is for one.
    An item taken out of it may stay listed as REMOVED: it holds that no more."""
    items = pages(f"/v1/reviewSubmissions/{submission_id}/items", {"include": "appStoreVersion", "limit": 200})
    return [item for item in items if (item.get("attributes") or {}).get("state") != "REMOVED"]


def item_version(item):
    """The id of the App Store version a submission's item is for, or None."""
    return (((item.get("relationships") or {}).get("appStoreVersion") or {}).get("data") or {}).get("id")


def the_app(fields=None):
    """The app with exactly this bundle id, whatever else the filter finds; None when there is none."""
    query = {"filter[bundleId]": BUNDLE_ID}
    if fields:
        query["fields[apps]"] = fields
    found = (get("/v1/apps", query) or {}).get("data") or []
    return next((app for app in found if app.get("attributes", {}).get("bundleId") == BUNDLE_ID), None)


def state() -> int:
    app = the_app("name,bundleId,primaryLocale,contentRightsDeclaration")
    if not app:
        print(f"No app with bundle id {BUNDLE_ID} in this team.")
        return 1
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

    section("App Store versions (iOS, newest first)")
    try:
        versions = app_versions(app_id)
    except AscError as err:
        print(f"  versions: App Store Connect answered {err.status} ({err.body[:200].strip()})")
        versions = []
    editable = None
    for v in versions[:10]:
        va = v["attributes"]
        print(f"  {v['id']}: {va.get('versionString')} {va.get('appStoreState') or va.get('appVersionState')}, release {va.get('releaseType')}, copyright {filled(va.get('copyright'))}")
        if editable is None and (va.get("appStoreState") or va.get("appVersionState")) in (
                "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "READY_FOR_REVIEW"):
            editable = v
    if len(versions) > 10:
        print(f"  and {len(versions) - 10} older")
    if not versions:
        print("  none: a version has to be created before anything can be submitted")
    # The version being prepared, else the newest one, whatever its state (one in review is read too).
    shown = editable or (versions[0] if versions else None)
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
            if bd:
                ours = review_notes(shown["attributes"].get("versionString") or "", bd["attributes"].get("version") or "")
                same = ours == (ra.get("notes") or "").replace("\r\n", "\n").strip()
                print("  review notes: " + ("what store/app-store/review-notes.txt writes" if same else
                      f"not what store/app-store/review-notes.txt writes ({len(ours)} characters): a submission writes the file over them"))
        else:
            print("  review details: none yet" + (" (a submission copies the contact and the demo account from the version before)" if len(versions) > 1 else ""))

    section("What's New for an update (store/app-store/whats-new)")
    try:
        on_sale = None
        if versions:
            on_sale = versions[0] if state_of(versions[0]) in RELEASED else (versions[1] if len(versions) > 1 else None)
        locales = [loc["attributes"].get("locale") for loc in localizations(versions[0]["id"])] if versions else []
        went_out = {loc["attributes"].get("locale"): loc["attributes"].get("whatsNew") for loc in localizations(on_sale["id"])} if on_sale else {}
        texts = whats_new()
        for locale in locales:
            if texts.get(locale):
                print(f"  {locale}: {len(texts[locale])} characters in the repository")
        for problem in whats_new_problems(texts, locales, went_out):
            print(f"  {problem}")
        if not on_sale:
            print("  no version is on sale yet: a first version has no What's New, and these wait for the update")
    except AscError as err:
        print(f"  App Store Connect answered {err.status} ({err.body[:200].strip()})")

    section("Builds (newest first)")
    builds = try_get("builds", "/v1/builds", {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5,
                                               "fields[builds]": "version,processingState,expired,uploadedDate,minOsVersion,preReleaseVersion",
                                               "include": "preReleaseVersion", "fields[preReleaseVersions]": "version"})
    marketing = {p["id"]: p["attributes"].get("version") for p in (builds or {}).get("included", []) if p.get("type") == "preReleaseVersions"}
    for b in (builds or {}).get("data", []):
        ba = b["attributes"]
        pre = (b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
        print(f"  {marketing.get(pre, '?')} ({ba.get('version')}): {ba.get('processingState')}, expired {ba.get('expired')}, uploaded {ba.get('uploadedDate')}")
    for b in (builds or {}).get("data", []):
        if b["attributes"].get("processingState") == "VALID" and not b["attributes"].get("expired"):
            pre = (b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
            print(f"  the newest valid build, as a submission names it: {marketing.get(pre, '?')}+{b['attributes'].get('version')}")
            break

    section("Availability and price")
    avail = try_get("availability", f"/v1/apps/{app_id}/appAvailabilityV2")
    if avail and avail.get("data"):
        print(f"  availability set: {avail['data']['attributes']}")
    else:
        print("  availability: not set")
    price = try_get("price schedule", f"/v1/apps/{app_id}/appPriceSchedule")
    print(f"  price schedule: {'set' if price and price.get('data') else 'not set'}")

    section("Review submissions")
    try:
        # The API names no order for them: one not submitted yet first, then the latest submitted.
        subs = sorted(pages("/v1/reviewSubmissions", {"filter[app]": app_id, "limit": 200}),
                      key=lambda sub: sub["attributes"].get("submittedDate") or "9", reverse=True)
    except AscError as err:
        print(f"  review submissions: App Store Connect answered {err.status} ({err.body[:200].strip()})")
        subs = []
    for s in subs[:8]:
        print(f"  {s['id']}: {s['attributes'].get('state')} submitted {s['attributes'].get('submittedDate')}, platform {s['attributes'].get('platform')}")
        items = try_get("submission items", f"/v1/reviewSubmissions/{s['id']}/items", {"include": "appStoreVersion"})
        for item in (items or {}).get("data", []):
            rel = item.get("relationships", {})
            what = [f"{k} {v['data'].get('id')}" for k, v in rel.items() if isinstance(v, dict) and isinstance(v.get("data"), dict)]
            print(f"    item {item['id']}: {item['attributes'].get('state')} ({', '.join(what) or 'no linked object shown'})")
    if len(subs) > 8:
        print(f"  and {len(subs) - 8} older")
    if not subs:
        print("  none")
    try:
        still_open = open_submissions(app_id)
        print(f"  still open (not submitted, waiting, in review, or sent back): {len(still_open)}"
              + (f" ({', '.join(str(s['attributes'].get('state')) for s in still_open)})" if still_open else ""))
    except AscError as err:
        print(f"  open submissions: App Store Connect answered {err.status} ({err.body[:200].strip()})")

    section("App Privacy")
    print("  not in Apple's API: filled in App Store Connect › App Privacy by a person signed in with an Apple ID")
    return 0


PORTAL = "https://student.foorsa.ma"


def app_and_versions():
    """The app's id and its iPhone versions, the newest first."""
    app = the_app()
    if not app:
        sys.exit(f"No app with bundle id {BUNDLE_ID} in this team.")
    return app["id"], app_versions(app["id"])


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
    _, versions = app_and_versions()
    if not versions:
        print("App Store Connect has no version of the app.")
        return 1
    version = versions[0]
    print(f"Version {version['attributes'].get('versionString')} ({state_of(version)})")
    # An update just made may have no review details yet: a submission copies the contact and
    # the demo account from the version before it, so that is the account to try.
    detail = review_detail(version["id"])
    if not detail and len(versions) > 1:
        detail = review_detail(versions[1]["id"])
        if detail:
            print(f"It has no review details yet: those of {versions[1]['attributes'].get('versionString')} are read, which a submission copies.")
    if not detail:
        print("No review details, so no demo account to try.")
        return 1
    review = detail["attributes"]
    name = (review.get("demoAccountName") or "").strip()
    password = review.get("demoAccountPassword") or ""
    notes = review.get("notes") or ""
    # The notes are written by hand as well: whatever of the account or the contact is in them is masked.
    masks = [(password, "<demo password>"), (name, "<demo name>")]
    masks += [(value.strip(), mask) for value, mask in ((review.get("contactEmail"), "<contact email>"), (review.get("contactPhone"), "<contact phone>"),
                                                      (review.get("contactFirstName"), "<contact first name>"),
                                                      (review.get("contactLastName"), "<contact last name>"))
              if isinstance(value, str) and len(value.strip()) >= 3]
    for secret, mask in sorted((pair for pair in masks if pair[0]), key=lambda pair: len(pair[0]), reverse=True):
        notes = re.sub(re.escape(secret), lambda _, mask=mask: mask, notes, flags=re.IGNORECASE)
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


def patch(path: str, type_: str, id_: str, attributes=None, relationships=None):
    data = {"type": type_, "id": id_}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    return request("PATCH", path, body={"data": data})


def version_states(version_id: str) -> tuple:
    a = get(f"/v1/appStoreVersions/{version_id}")["data"]["attributes"]
    return a.get("appStoreState") or "", a.get("appVersionState") or ""


def version_state(version_id: str) -> str:
    old, new = version_states(version_id)
    return old or new


# What a version's review details keep from the version before, when Apple has not copied them.
KEPT_FOR_REVIEW = PRIVATE_FIELDS + ("demoAccountRequired",)


def submit_latest(expected: str = "", replace_waiting: bool = False) -> int:
    try:
        return put_up_for_review(expected, replace_waiting)
    except Refused as err:
        print(f"::error::{scrub(str(err))}")
    except AscError as err:
        print(f"::error::App Store Connect answered {explain(err)}")
    print("What was written before that stays written. state shows it, and asking again goes on from there.")
    return 1


def put_up_for_review(expected: str, replace_waiting: bool) -> int:
    import time
    app_id, versions = app_and_versions()
    if not versions:
        print("::error::App Store Connect has no version of the app: the first one is made there, by hand. Nothing was changed.")
        return 1
    version = versions[0]
    vid, name, state_now = version["id"], version["attributes"].get("versionString"), state_of(version)
    print(f"Version {name} is {state_now}")

    builds = get("/v1/builds", {"filter[app]": app_id, "filter[processingState]": "VALID", "filter[expired]": "false",
                               "sort": "-uploadedDate", "limit": 1, "fields[builds]": "version,uploadedDate"})
    if not builds.get("data"):
        print("::error::No valid build to submit.")
        return 1
    build = builds["data"][0]
    marketing = get(f"/v1/builds/{build['id']}/preReleaseVersion")["data"]["attributes"]["version"]
    number = build["attributes"]["version"]
    print(f"Newest valid build: {marketing} ({number})")
    if expected and expected != f"{marketing}+{number}":
        print(f"::error::The newest valid build is {marketing}+{number}, not {expected}: nothing was changed.")
        return 1

    # Where the newest version stands decides what a submission is. Nothing is written until
    # every refusal below has had its say.
    on_sale = state_now in RELEASED
    if not on_sale and state_now not in EDITABLE | {"WAITING_FOR_REVIEW", "READY_FOR_REVIEW"}:
        print(f"::error::Version {name} is {state_now}: {LEFT_ALONE.get(state_now, 'not a state a submission is made from')}. Nothing was changed.")
        return 1
    carried = attached_build(vid)
    if carried == build["id"] and (on_sale or state_now == "WAITING_FOR_REVIEW"):
        print(f"::notice::{marketing} ({number}) is the build {'on sale' if on_sale else 'waiting for review'} already: nothing to submit.")
        return 0
    if on_sale and name == marketing:
        print(f"::error::Version {name} is on sale with another build, and the newest valid build is {marketing} ({number}): "
              "an update takes a version above the one on sale. Nothing was changed.")
        return 1
    still_open = open_submissions(app_id)
    for sub in still_open:
        if sub["attributes"].get("state") == "IN_REVIEW":
            print(f"::error::Review submission {sub['id']} is in review, and what is in review is never touched. Nothing was changed.")
            return 1
        if sub["attributes"].get("state") == "UNRESOLVED_ISSUES":
            print(f"::error::App Review sent review submission {sub['id']} back and it is not answered yet (UNRESOLVED_ISSUES). "
                  "How to answer is decided in App Store Connect (App Review), where its messages are: reply there, or change the "
                  "version there and resubmit it. Nothing was changed.")
            return 1
    waiting = [sub for sub in still_open if sub["attributes"].get("state") == "WAITING_FOR_REVIEW"]
    if (waiting or state_now == "WAITING_FOR_REVIEW") and not replace_waiting:
        since = f" since {waiting[0]['attributes'].get('submittedDate')}" if waiting else ""
        print(f"::error::A submission has been waiting for review{since}. Putting {marketing} ({number}) in its place cancels it, "
              "and the wait starts again: that is the owner's decision. With their word, ask again with replace-waiting after "
              "the version. Nothing was changed.")
        return 1

    # What the repository gives the submission, read and checked before anything is written.
    problems = []
    # A submission made and never submitted cannot be cancelled. An empty one is taken up in
    # step 6, and this version is taken out of one that holds it; anything else in one is a
    # person's work in App Store Connect, and is left to them.
    in_draft = []
    for sub in still_open:
        if sub["attributes"].get("state") == "READY_FOR_REVIEW":
            items = submission_items(sub["id"])
            others = [item for item in items if item_version(item) != vid]
            if others:
                problems.append(f"Review submission {sub['id']} was made and not submitted, and holds {len(others)} "
                                f"thing{'s' if len(others) > 1 else ''} other than version {name}: submit it or empty it in "
                                "App Store Connect (App Review), then ask again")
            in_draft += [(sub["id"], item["id"]) for item in items]
    notes = review_notes(marketing, number)
    if len(notes) > LONGEST:
        problems.append(f"The review notes are {len(notes)} characters; App Store Connect takes {LONGEST}")
    # An update is any version after the first. Apple refuses one without "What's New", and
    # refuses "What's New" on a first version.
    update = on_sale or len(versions) > 1
    texts = {}
    if update:
        before = version if on_sale else versions[1]
        went_out = {loc["attributes"].get("locale"): loc["attributes"].get("whatsNew") for loc in localizations(before["id"])}
        locales = list(went_out) if on_sale else [loc["attributes"].get("locale") for loc in localizations(vid)]
        texts = whats_new()
        problems += whats_new_problems(texts, locales, went_out)
    release = version["attributes"].get("releaseType")
    if on_sale and release == "SCHEDULED":
        problems.append(f"Version {name} was released on a date (SCHEDULED), which an update cannot keep: make version {marketing} "
                        "in App Store Connect with the release it should have, then ask again")
    if problems:
        for problem in problems:
            print(f"::error::{problem}")
        print("Nothing was changed.")
        return 1

    # 1. With the owner's word, the submission waiting goes back to the developer, so the version
    #    can change; and the version comes out of a submission it was put in and not submitted with.
    for sub in waiting:
        # Read again at the last moment: App Review may have taken it up since the list was read.
        now = get(f"/v1/reviewSubmissions/{sub['id']}")["data"]["attributes"].get("state")
        if now != "WAITING_FOR_REVIEW":
            print(f"::error::Review submission {sub['id']} is no longer waiting for review but {now}: it is left alone.")
            return 1
        with doing(f"Cancelling review submission {sub['id']}"):
            patch(f"/v1/reviewSubmissions/{sub['id']}", "reviewSubmissions", sub["id"], {"canceled": True})
        print(f"Cancelled review submission {sub['id']} (WAITING_FOR_REVIEW)")
    for submission_id, item_id in in_draft:
        with doing(f"Taking version {name} out of review submission {submission_id}"):
            request("DELETE", f"/v1/reviewSubmissionItems/{item_id}")
        print(f"Version {name} taken out of review submission {submission_id}, which was made and not submitted")

    # 2. An update is a new version, with the release and the copyright of the one on sale.
    #    Apple copies the listing's text and screenshots into it.
    previous = versions[1] if len(versions) > 1 else None
    if on_sale:
        attributes = {"platform": "IOS", "versionString": marketing}
        if release:
            attributes["releaseType"] = release
        if version["attributes"].get("copyright"):
            attributes["copyright"] = version["attributes"]["copyright"]
        with doing(f"Making version {marketing}"):
            new = request("POST", "/v1/appStoreVersions", body={"data": {
                "type": "appStoreVersions", "attributes": attributes,
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        got = new["attributes"].get("releaseType")
        print(f"Version {marketing} made, as an update to {name}: release {got}")
        if got != release:
            print(f"::warning::Version {marketing} was asked for with the release {name} has, {release}, and App Store Connect says {got}.")
        previous, version, vid = version, new, new["id"]
    for _ in range(40):
        try:
            state_now = version_state(vid)
        except AscError as err:
            if not (on_sale and err.status == 404):
                raise
            state_now = "not readable yet"      # a version just made is not always there at once
        if state_now in EDITABLE:
            break
        time.sleep(6)
    else:
        print(f"::error::The version is still {state_now}; nothing was changed on it.")
        return 1
    print(f"Version is now {state_now}")

    def once_copied(read):
        """What `read` gives; for a version just made, asked again for a minute while it gives
        nothing, since what Apple copies from the version on sale is not always there at once."""
        found = read()
        for _ in range(10 if on_sale else 0):
            if found:
                break
            time.sleep(6)
            found = read()
        return found

    # 3. The version takes the build's number and the build.
    if version["attributes"].get("versionString") != marketing:
        with doing(f"Renaming version {name} to {marketing}"):
            patch(f"/v1/appStoreVersions/{vid}", "appStoreVersions", vid, {"versionString": marketing})
        print(f"Version renamed {name} -> {marketing}")
    with doing(f"Attaching build {marketing} ({number})"):
        request("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", body={"data": {"type": "builds", "id": build["id"]}})
    print(f"Build {marketing} ({number}) attached")

    # 4. What's New, in each locale the version has.
    if update:
        mine = once_copied(lambda: localizations(vid))
        if not mine:
            raise Refused(f"Version {marketing} has no locale, so nowhere to write What's New: the listing has to be filled in App Store Connect")
        for loc in mine:
            locale = loc["attributes"].get("locale")
            if not texts.get(locale):
                raise Refused(f"Version {marketing} has the locale {locale}, and store/app-store/whats-new/{locale}.txt is missing or empty")
            with doing(f"Writing What's New for {locale}"):
                patch(f"/v1/appStoreVersionLocalizations/{loc['id']}", "appStoreVersionLocalizations", loc["id"], {"whatsNew": texts[locale]})
            print(f"What's New written for {locale} ({len(texts[locale])} characters)")

    # 5. Review notes for this build. The contact and the demo account stay as they are. Apple's
    #    site copies them into a new version; where the API has not, they are copied from the
    #    version before.
    detail = once_copied(lambda: review_detail(vid))
    if not detail:
        source = review_detail(previous["id"]) if previous else None
        if not source:
            raise Refused(f"Version {marketing} has no review details and no version before it to copy the contact and the demo account from: "
                          "fill App Review Information in App Store Connect, then ask again")
        attributes = {key: source["attributes"][key] for key in KEPT_FOR_REVIEW if source["attributes"].get(key) is not None}
        attributes["notes"] = notes
        try:
            request("POST", "/v1/appStoreReviewDetails", body={"data": {
                "type": "appStoreReviewDetails", "attributes": attributes,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        except AscError as err:
            # Refused because Apple's own copy came in meanwhile: then the notes go into that.
            detail = review_detail(vid) if err.status == 409 else None
            if not detail:
                raise Refused(f"Making the review details of version {marketing}: App Store Connect answered {explain(err, details=False)}") from None
        else:
            print(f"Review details made: the contact and the demo account as {previous['attributes'].get('versionString')} has them, "
                  f"and the review notes ({len(notes)} characters)")
    if detail:
        with doing("Writing the review notes"):
            patch(f"/v1/appStoreReviewDetails/{detail['id']}", "appStoreReviewDetails", detail["id"], {"notes": notes})
        print(f"Review notes written ({len(notes)} characters)")

    # 6. A submission with this version, submitted once App Store Connect shows the version in it.
    #    Apple keeps one open submission for a platform: one made earlier and holding nothing
    #    (a run that stopped before this step leaves one) is taken up.
    sub = next((one for one in open_submissions(app_id) if one["attributes"].get("state") == "READY_FOR_REVIEW"), None)
    if sub:
        print(f"Review submission {sub['id']} was made and holds nothing: it is taken up")
    else:
        with doing("Opening a review submission"):
            sub = request("POST", "/v1/reviewSubmissions", body={"data": {
                "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    with doing(f"Adding version {marketing} to the review submission"):
        request("POST", "/v1/reviewSubmissionItems", body={"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    for _ in range(10):
        if "READY_FOR_REVIEW" in version_states(vid):
            break
        time.sleep(6)
    with doing(f"Submitting {marketing} ({number}) for review"):
        done = patch(f"/v1/reviewSubmissions/{sub['id']}", "reviewSubmissions", sub["id"], {"submitted": True})["data"]
    print(f"Submitted {marketing} ({number}) for review: submission {done['id']} is {done['attributes'].get('state')}")
    try:
        print(f"Version is now {version_state(vid)}")
    except AscError as err:
        print(f"The version's state could not be read after that ({err.status}); state shows it.")
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "state"
    commands = {"state": state, "review-check": review_check, "submit-latest": submit_latest}
    if command not in commands:
        sys.exit(f"Unknown command {command!r}: {', '.join(commands)}")
    if command == "submit-latest":
        words = sys.argv[2:]
        named = [word for word in words if word != "replace-waiting"]
        if len(named) > 1 or len(words) - len(named) > 1:
            sys.exit("submit-latest takes a version (1.2.42+73) and the word replace-waiting, each once at most")
        sys.exit(submit_latest(named[0] if named else "", replace_waiting=len(named) < len(words)))
    sys.exit(commands[command]())
