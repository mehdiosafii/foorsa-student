"""A stand-in for App Store Connect, for the tests of scripts/app_store_listing.py.

It holds an app's versions, their locales, review details, builds and review submissions in
memory, answers the requests the script makes in the JSON:API shapes Apple answers in, and keeps
the rules of Apple's that decide the order of a submission's writes:

  - one version at a time is on its way to the App Store: a new one is refused until the one
    before it is on sale;
  - a version changes only while it is being prepared or was sent back;
  - "What's New" is refused on an app's first version, and a later version is refused for
    review without it in every locale;
  - a version goes up for review with a build and review details, through a review submission,
    and a platform has one open submission at a time: one not submitted, waiting, in review, or
    sent back by App Review and not answered (UNRESOLVED_ISSUES) keeps another from being made;
  - only a submission waiting for review is cancelled here. One never submitted cannot be (a
    developer's report of 12 Nov 2026: 409, "not in cancellable state"): what it holds is taken
    out item by item. A cancelled one is CANCELING until the version is the developer's again;
  - what a new version takes from the one on sale (its locales, its review details) may come a
    moment after it is made, and it may not be readable at once.

Every request is kept in `requests`, and the writes among them in `writes`, as
(method, path, body): what would have gone over the wire.
"""
import copy
import json
import re
import urllib.parse

API = "https://api.appstoreconnect.apple.com"
APP = "6816127081"
BUNDLE = "ma.foorsa.foorsaStudent"

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
# A version whose way to the App Store is over, so that the next one can be made.
FINISHED = {"READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE"}
# Apple's new names (appVersionState) where they differ from the old ones (appStoreState).
NEW_NAME = {"READY_FOR_SALE": "READY_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE": "PROCESSING_FOR_DISTRIBUTION"}

# The review contact and the demo account: nothing of these may reach the script's output.
SECRETS = {
    "contactFirstName": "Reviewfirst",
    "contactLastName": "Reviewlast",
    "contactPhone": "+212 600-000000",
    "contactEmail": "review.contact@example.com",
    "demoAccountName": "DEMO7654321",
    "demoAccountPassword": "s3cret-Demo-pass",
}


class Refusal(Exception):
    """What the stand-in answers instead of a result; the tests turn it into the script's AscError."""

    def __init__(self, status: int, errors):
        super().__init__(f"{status}")
        self.status = status
        self.body = json.dumps({"errors": errors})


def error(status, code, detail, pointer=None, meta=None):
    one = {"id": "e", "status": str(status), "code": code, "title": "The request was refused.", "detail": detail}
    if pointer:
        one["source"] = {"pointer": pointer}
    if meta:
        one["meta"] = meta
    return one


class FakeAppStoreConnect:
    def __init__(self):
        self.requests = []          # (method, path, query, body), every one
        self.writes = []            # (method, path, body), the writes among them
        self.versions = {}          # id -> versionString, state, releaseType, copyright, createdDate, build
        self.listed = []            # version ids in the order the API lists them
        self.locales = {}           # localization id -> version, locale, description, whatsNew
        self.details = {}           # version id -> {"id", "attributes"}
        self.builds = {}            # id -> number, marketing, state, expired, uploaded
        self.submissions = {}       # id -> state, submittedDate, items: [{"id", "state", "version"}]
        self.copies_review_details = True   # into a new version, as App Store Connect's site does
        self.old_state_names = True         # appStoreState is still answered beside appVersionState
        self.page_size = None               # lists answer in pages of this many, when set
        self.cancel_takes = 0       # reads of a version before a cancelled submission lets go of it
        self.ready_takes = 0        # reads of a version before it shows as added to a submission
        self.readable_takes = 0     # reads of a version just made that are answered 404
        self.copy_takes = 0         # reads of a new version's locales, and of its review details, that find nothing yet
        self.details_take = None    # the same for the review details alone, when it differs
        self.removed_items_stay = False     # an item taken out of a submission stays listed, as REMOVED
        self.refuse_once = []       # (method, path pattern, Refusal): answered to the next such request
        self.before = []            # (method, path pattern, what to do first): something that happens meanwhile
        self.later = {}             # version id -> [reads left, state it then takes]
        self.finishing = {}         # version id -> the cancelled submission that is COMPLETE once the version has changed
        self.unreadable = {}        # version id -> reads still answered 404
        self.uncopied = {}          # (version id, "locales" or "details") -> reads that still find nothing
        self.counters = {}

    # ---- what the tests put in it ---------------------------------------------------------

    def new_id(self, kind: str) -> str:
        self.counters[kind] = self.counters.get(kind, 0) + 1
        return f"{kind}{self.counters[kind]}"

    def add_version(self, name, state, build=None, release="AFTER_APPROVAL", created="2026-10-05T11:18:37-07:00",
                    locales=("en-US",), whats_new=None, details=True, notes="The notes App Store Connect holds."):
        vid = self.new_id("v")
        self.versions[vid] = {"versionString": name, "state": state, "releaseType": release,
                              "copyright": "2026 Foorsa", "createdDate": created, "build": build}
        self.listed.append(vid)
        for locale in locales:
            self.locales[self.new_id("loc")] = {"version": vid, "locale": locale, "description": f"About the app ({locale})",
                                                "whatsNew": (whats_new or {}).get(locale)}
        if details:
            self.details[vid] = {"id": self.new_id("detail"),
                                 "attributes": dict(SECRETS, demoAccountRequired=True, notes=notes)}
        return vid

    def add_build(self, number, marketing, state="VALID", expired=False, uploaded=None):
        bid = f"b{number}"
        self.builds[bid] = {"number": str(number), "marketing": marketing, "state": state, "expired": expired,
                            "uploaded": uploaded or f"2026-11-{int(number) - 60:02d}T04:16:53-08:00"}
        return bid

    def add_submission(self, state, version=None, submitted="2026-11-06T15:50:54.515Z", item_state="READY_FOR_REVIEW", others=0):
        """A review submission holding that version, and `others` things that are not a version
        (an in-app event, a product page)."""
        sid = self.new_id("sub")
        items = [{"id": self.new_id("item"), "state": item_state, "version": version}] if version else []
        items += [{"id": self.new_id("item"), "state": item_state, "version": None} for _ in range(others)]
        self.submissions[sid] = {"state": state, "submittedDate": submitted, "items": items}
        return sid

    def version_named(self, name):
        return next(vid for vid, v in self.versions.items() if v["versionString"] == name)

    def whats_new_of(self, vid):
        return {loc["locale"]: loc["whatsNew"] for loc in self.locales.values() if loc["version"] == vid}

    # ---- resources as the API answers them ------------------------------------------------

    def version_resource(self, vid):
        v = self.versions[vid]
        attributes = {"platform": "IOS", "versionString": v["versionString"],
                      "appVersionState": NEW_NAME.get(v["state"], v["state"]),
                      "copyright": v["copyright"], "releaseType": v["releaseType"], "createdDate": v["createdDate"]}
        if self.old_state_names:
            attributes["appStoreState"] = v["state"]
        return {"type": "appStoreVersions", "id": vid, "attributes": attributes}

    def locale_resource(self, lid):
        loc = self.locales[lid]
        return {"type": "appStoreVersionLocalizations", "id": lid, "attributes": {
            "locale": loc["locale"], "description": loc["description"], "keywords": "study, china",
            "supportUrl": "https://foorsa.ma/en/contact", "marketingUrl": "https://foorsa.ma/en",
            "promotionalText": "Your file, step by step.", "whatsNew": loc["whatsNew"]}}

    def build_resource(self, bid, with_version=True):
        b = self.builds[bid]
        resource = {"type": "builds", "id": bid, "attributes": {
            "version": b["number"], "processingState": b["state"], "expired": b["expired"], "uploadedDate": b["uploaded"]}}
        if with_version:
            resource["relationships"] = {"preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": f"pre-{b['marketing']}"}}}
        return resource

    def submission_resource(self, sid):
        s = self.submissions[sid]
        return {"type": "reviewSubmissions", "id": sid,
                "attributes": {"platform": "IOS", "state": s["state"], "submittedDate": s["submittedDate"]}}

    def listing(self, path, query, resources):
        """A list as the API answers it: whole, or page by page with a link to the next."""
        if not self.page_size:
            return {"data": resources}
        start = int(query.get("cursor", 0))
        page = {"data": resources[start:start + self.page_size]}
        if start + self.page_size < len(resources):
            following = dict(query, cursor=start + self.page_size)
            page["links"] = {"next": f"{API}{path}?{urllib.parse.urlencode(following)}"}
        return page

    # ---- requests -------------------------------------------------------------------------

    def request(self, method, path, query=None, body=None):
        query = dict(query or {})
        if path.startswith(API):            # the link to a list's next page, as the API gives it
            path = path[len(API):]
        if "?" in path:
            path, _, text = path.partition("?")
            query.update(dict(urllib.parse.parse_qsl(text)))
        body = copy.deepcopy(body)
        self.requests.append((method, path, query, body))
        if method != "GET":
            self.writes.append((method, path, body))
        for index, (meanwhile_method, pattern, happen) in enumerate(self.before):
            if method == meanwhile_method and re.fullmatch(pattern, path):
                del self.before[index]
                happen()
                break
        for index, (refused_method, pattern, refusal) in enumerate(self.refuse_once):
            if method == refused_method and re.fullmatch(pattern, path):
                del self.refuse_once[index]
                raise refusal
        for route_method, pattern, handler in self.routes():
            match = re.fullmatch(pattern, path)
            if method == route_method and match:
                return handler(*match.groups(), query=query, body=body)
        raise Refusal(404, [error(404, "NOT_FOUND", f"The path {path} has no stand-in.")])

    def routes(self):
        one = r"([^/]+)"
        return [
            ("GET", r"/v1/apps", self.get_apps),
            ("GET", rf"/v1/apps/{one}/appStoreVersions", self.get_versions),
            ("GET", rf"/v1/apps/{one}/appInfos", lambda app, query, body: {"data": []}),
            ("GET", rf"/v1/appStoreVersions/{one}", self.get_version),
            ("GET", rf"/v1/appStoreVersions/{one}/appStoreVersionLocalizations", self.get_locales),
            ("GET", rf"/v1/appStoreVersionLocalizations/{one}/appScreenshotSets", lambda lid, query, body: {"data": []}),
            ("GET", rf"/v1/appStoreVersions/{one}/appStoreReviewDetail", self.get_details),
            ("GET", rf"/v1/appStoreVersions/{one}/build", self.get_version_build),
            ("GET", r"/v1/builds", self.get_builds),
            ("GET", rf"/v1/builds/{one}/preReleaseVersion", self.get_build_version),
            ("GET", r"/v1/reviewSubmissions", self.get_submissions),
            ("GET", rf"/v1/reviewSubmissions/{one}", lambda sid, query, body: {"data": self.submission_resource(sid)}),
            ("GET", rf"/v1/reviewSubmissions/{one}/items", self.get_items),
            ("POST", r"/v1/appStoreVersions", self.post_version),
            ("PATCH", rf"/v1/appStoreVersions/{one}", self.patch_version),
            ("PATCH", rf"/v1/appStoreVersions/{one}/relationships/build", self.patch_version_build),
            ("PATCH", rf"/v1/appStoreVersionLocalizations/{one}", self.patch_locale),
            ("POST", r"/v1/appStoreReviewDetails", self.post_details),
            ("PATCH", rf"/v1/appStoreReviewDetails/{one}", self.patch_details),
            ("POST", r"/v1/reviewSubmissions", self.post_submission),
            ("PATCH", rf"/v1/reviewSubmissions/{one}", self.patch_submission),
            ("POST", r"/v1/reviewSubmissionItems", self.post_item),
            ("DELETE", rf"/v1/reviewSubmissionItems/{one}", self.delete_item),
        ]

    # ---- reads ----------------------------------------------------------------------------

    def get_apps(self, query, body):
        # Apple's filter also finds bundle ids that only begin with the one asked for.
        return {"data": [
            {"type": "apps", "id": "999", "attributes": {"bundleId": BUNDLE + ".beta", "name": "Another app", "primaryLocale": "en-US"}},
            {"type": "apps", "id": APP, "attributes": {"bundleId": BUNDLE, "name": "Foorsa Student", "primaryLocale": "en-US"}},
        ]}

    def get_versions(self, app, query, body):
        assert app == APP and query.get("filter[platform]") == "IOS", (app, query)
        return self.listing(f"/v1/apps/{app}/appStoreVersions", query, [self.version_resource(vid) for vid in self.listed])

    def not_yet(self, counts, key):
        """Whether a read comes too early: `counts` says how many reads of `key` still do."""
        if counts.get(key, 0) > 0:
            counts[key] -= 1
            return True
        return False

    def get_version(self, vid, query, body):
        if self.not_yet(self.unreadable, vid):
            raise Refusal(404, [error(404, "NOT_FOUND", "There is no resource of type 'appStoreVersions' with that id")])
        waiting = self.later.get(vid)
        if waiting:
            if waiting[0] <= 0:
                self.versions[vid]["state"] = waiting[1]
                del self.later[vid]
                if vid in self.finishing:
                    self.submissions[self.finishing.pop(vid)]["state"] = "COMPLETE"
            else:
                waiting[0] -= 1
        return {"data": self.version_resource(vid)}

    def get_locales(self, vid, query, body):
        mine = [self.locale_resource(lid) for lid, loc in self.locales.items() if loc["version"] == vid]
        if self.not_yet(self.uncopied, (vid, "locales")):
            mine = []
        return self.listing(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", query, mine)

    def get_details(self, vid, query, body):
        if vid not in self.details or self.not_yet(self.uncopied, (vid, "details")):
            raise Refusal(404, [error(404, "NOT_FOUND", "The specified resource does not exist")])
        return {"data": {"type": "appStoreReviewDetails", "id": self.details[vid]["id"],
                         "attributes": dict(self.details[vid]["attributes"])}}

    def get_version_build(self, vid, query, body):
        bid = self.versions[vid]["build"]
        return {"data": self.build_resource(bid, with_version=False) if bid else None}

    def get_builds(self, query, body):
        assert query.get("filter[app]") == APP, query
        found = list(self.builds)
        if "filter[processingState]" in query:
            found = [b for b in found if self.builds[b]["state"] in query["filter[processingState]"].split(",")]
        if "filter[expired]" in query:
            found = [b for b in found if str(self.builds[b]["expired"]).lower() == query["filter[expired]"]]
        if query.get("sort") == "-uploadedDate":
            found.sort(key=lambda b: self.builds[b]["uploaded"], reverse=True)
        found = found[:int(query.get("limit", 50))]
        # Apple answers the relationships a fields list names, and no others.
        with_version = "fields[builds]" not in query or "preReleaseVersion" in query["fields[builds]"].split(",")
        answer = {"data": [self.build_resource(b, with_version) for b in found]}
        if query.get("include") == "preReleaseVersion":
            answer["included"] = [{"type": "preReleaseVersions", "id": f"pre-{m}", "attributes": {"version": m}}
                                  for m in sorted({self.builds[b]["marketing"] for b in found})]
        return answer

    def get_build_version(self, bid, query, body):
        marketing = self.builds[bid]["marketing"]
        return {"data": {"type": "preReleaseVersions", "id": f"pre-{marketing}", "attributes": {"version": marketing, "platform": "IOS"}}}

    def get_submissions(self, query, body):
        assert query.get("filter[app]") == APP, query
        found = list(self.submissions)[::-1]     # the newest first, as Apple has answered so far
        if "filter[state]" in query:
            found = [s for s in found if self.submissions[s]["state"] in query["filter[state]"].split(",")]
        return self.listing("/v1/reviewSubmissions", query, [self.submission_resource(s) for s in found])

    def get_items(self, sid, query, body):
        # What an item is for is named only when asked for with include, as Apple answers.
        named = "appStoreVersion" in query.get("include", "").split(",")
        items = []
        for item in self.submissions[sid]["items"]:
            link = {"links": {"related": f"{API}/v1/reviewSubmissionItems/{item['id']}/appStoreVersion"}}
            if named:
                link["data"] = {"type": "appStoreVersions", "id": item["version"]} if item["version"] else None
            items.append({"type": "reviewSubmissionItems", "id": item["id"], "attributes": {"state": item["state"]},
                          "relationships": {"appStoreVersion": link}})
        return self.listing(f"/v1/reviewSubmissions/{sid}/items", query, items)

    # ---- writes ---------------------------------------------------------------------------

    def must_be_editable(self, vid, pointer):
        if self.versions[vid]["state"] not in EDITABLE:
            raise Refusal(409, [error(409, "ENTITY_ERROR.ATTRIBUTE.INVALID.INVALID_STATE",
                                      f"The version cannot be changed while it is {self.versions[vid]['state']}.", pointer)])

    def post_version(self, query, body):
        data = body["data"]
        assert data["type"] == "appStoreVersions" and data["relationships"]["app"]["data"] == {"type": "apps", "id": APP}, data
        attributes = data["attributes"]
        assert attributes["platform"] == "IOS", attributes
        if any(v["state"] not in FINISHED for v in self.versions.values()):
            raise Refusal(409, [error(409, "ENTITY_ERROR.RELATIONSHIP.INVALID",
                                      "You cannot create a new version of the App in the current state.", "/data/relationships/app")])
        if any(v["versionString"] == attributes["versionString"] for v in self.versions.values()):
            raise Refusal(409, [error(409, "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE",
                                      "The version number has been previously used.", "/data/attributes/versionString")])
        on_sale = next(vid for vid in self.versions if self.versions[vid]["state"] == "READY_FOR_SALE")
        vid = self.new_id("v")
        self.versions[vid] = {"versionString": attributes["versionString"], "state": "PREPARE_FOR_SUBMISSION",
                              "releaseType": attributes.get("releaseType") or "AFTER_APPROVAL",
                              "copyright": attributes.get("copyright"), "createdDate": "2026-11-20T09:00:00-08:00", "build": None}
        # The API lists versions in no promised order: the new one is not put first.
        self.listed.append(vid)
        for loc in [loc for loc in self.locales.values() if loc["version"] == on_sale]:
            self.locales[self.new_id("loc")] = dict(loc, version=vid, whatsNew=None)
        if self.copies_review_details and on_sale in self.details:
            self.details[vid] = {"id": self.new_id("detail"), "attributes": dict(self.details[on_sale]["attributes"])}
        self.unreadable[vid] = self.readable_takes
        self.uncopied[(vid, "locales")] = self.copy_takes
        self.uncopied[(vid, "details")] = self.copy_takes if self.details_take is None else self.details_take
        return {"data": self.version_resource(vid)}

    def patch_version(self, vid, query, body):
        data = body["data"]
        assert data["type"] == "appStoreVersions" and data["id"] == vid and set(data["attributes"]) == {"versionString"}, data
        self.must_be_editable(vid, "/data/attributes/versionString")
        self.versions[vid]["versionString"] = data["attributes"]["versionString"]
        return {"data": self.version_resource(vid)}

    def patch_version_build(self, vid, query, body):
        assert set(body) == {"data"} and body["data"]["type"] == "builds", body
        self.must_be_editable(vid, "/data/relationships/build")
        build = self.builds[body["data"]["id"]]
        assert build["state"] == "VALID" and not build["expired"], build
        self.versions[vid]["build"] = body["data"]["id"]
        return None     # 204, no content

    def patch_locale(self, lid, query, body):
        data = body["data"]
        assert data["type"] == "appStoreVersionLocalizations" and data["id"] == lid, data
        vid = self.locales[lid]["version"]
        self.must_be_editable(vid, "/data/attributes")
        if "whatsNew" in data["attributes"] and len(self.versions) == 1:
            raise Refusal(409, [error(409, "ENTITY_ERROR.ATTRIBUTE.INVALID.INVALID_STATE",
                                      "The attribute 'whatsNew' can not be edited at this time", "/data/attributes/whatsNew")])
        self.locales[lid].update(data["attributes"])
        return {"data": self.locale_resource(lid)}

    def post_details(self, query, body):
        data = body["data"]
        assert data["type"] == "appStoreReviewDetails", data
        vid = data["relationships"]["appStoreVersion"]["data"]["id"]
        assert data["relationships"]["appStoreVersion"]["data"]["type"] == "appStoreVersions"
        if vid in self.details:
            raise Refusal(409, [error(409, "ENTITY_ERROR.RELATIONSHIP.INVALID", "The version already has review details.")])
        self.details[vid] = {"id": self.new_id("detail"), "attributes": dict(data["attributes"])}
        return {"data": {"type": "appStoreReviewDetails", "id": self.details[vid]["id"], "attributes": dict(data["attributes"])}}

    def patch_details(self, did, query, body):
        data = body["data"]
        assert data["type"] == "appStoreReviewDetails" and data["id"] == did, data
        vid = next(v for v, d in self.details.items() if d["id"] == did)
        self.must_be_editable(vid, "/data/attributes")
        self.details[vid]["attributes"].update(data["attributes"])
        return {"data": {"type": "appStoreReviewDetails", "id": did, "attributes": dict(self.details[vid]["attributes"])}}

    def post_submission(self, query, body):
        data = body["data"]
        assert data == {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}, data
        if any(s["state"] in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES") for s in self.submissions.values()):
            raise Refusal(409, [error(409, "ENTITY_ERROR.RELATIONSHIP.INVALID",
                                      "There is another reviewSubmission still open for this platform.")])
        sid = self.new_id("sub")
        self.submissions[sid] = {"state": "READY_FOR_REVIEW", "submittedDate": None, "items": []}
        return {"data": self.submission_resource(sid)}

    def post_item(self, query, body):
        data = body["data"]
        assert data["type"] == "reviewSubmissionItems" and set(data["relationships"]) == {"reviewSubmission", "appStoreVersion"}, data
        sid = data["relationships"]["reviewSubmission"]["data"]["id"]
        vid = data["relationships"]["appStoreVersion"]["data"]["id"]
        if self.submissions[sid]["state"] != "READY_FOR_REVIEW":
            raise Refusal(409, [error(409, "STATE_ERROR", "The review submission is no longer open.")])
        lacking = {}
        version = self.versions[vid]
        if version["state"] not in EDITABLE:
            lacking.setdefault(f"/v1/appStoreVersions/{vid}", []).append(error(409, "STATE_ERROR", f"The version is {version['state']}."))
        if not version["build"]:
            lacking.setdefault(f"/v1/appStoreVersions/{vid}", []).append(
                error(409, "ENTITY_ERROR.RELATIONSHIP.REQUIRED", "You must choose a build.", "/data/relationships/build"))
        if vid not in self.details:
            lacking.setdefault(f"/v1/appStoreVersions/{vid}", []).append(
                error(409, "ENTITY_ERROR.RELATIONSHIP.REQUIRED", "App Review Information is required.", "/data/relationships/appStoreReviewDetail"))
        if len(self.versions) > 1:
            for lid, loc in self.locales.items():
                if loc["version"] == vid and not loc["whatsNew"]:
                    lacking.setdefault(f"/v1/appStoreVersionLocalizations/{lid}", []).append(
                        error(409, "ENTITY_ERROR.ATTRIBUTE.REQUIRED",
                              "You must provide a value for the attribute 'whatsNew' with this request", "/data/attributes/whatsNew"))
        if lacking:
            raise Refusal(409, [error(409, "ENTITY_UNPROCESSABLE", "The provided entity is missing required information.",
                                      meta={"associatedErrors": lacking})])
        item = {"id": self.new_id("item"), "state": "READY_FOR_REVIEW", "version": vid}
        self.submissions[sid]["items"].append(item)
        self.later[vid] = [self.ready_takes, "READY_FOR_REVIEW"]
        if not self.ready_takes:
            self.get_version(vid, {}, None)
        return {"data": {"type": "reviewSubmissionItems", "id": item["id"], "attributes": {"state": "READY_FOR_REVIEW"}}}

    def delete_item(self, iid, query, body):
        assert body is None, body
        sid = next(s for s, submission in self.submissions.items() if any(item["id"] == iid for item in submission["items"]))
        submission = self.submissions[sid]
        if submission["state"] != "READY_FOR_REVIEW":
            raise Refusal(409, [error(409, "STATE_ERROR.ENTITY_STATE_INVALID", "An item of a submission that was submitted cannot be removed.")])
        item = next(item for item in submission["items"] if item["id"] == iid)
        if item["state"] == "REMOVED":
            raise Refusal(409, [error(409, "STATE_ERROR.ENTITY_STATE_INVALID", "The item was removed already.")])
        if self.removed_items_stay:
            item["state"] = "REMOVED"
        else:
            submission["items"].remove(item)   # either way the submission stays, open and holding nothing
        if item["version"]:
            self.later[item["version"]] = [self.cancel_takes, "PREPARE_FOR_SUBMISSION"]
            if not self.cancel_takes:
                self.get_version(item["version"], {}, None)
        return None     # 204, no content

    def patch_submission(self, sid, query, body):
        data = body["data"]
        assert data["type"] == "reviewSubmissions" and data["id"] == sid, data
        submission = self.submissions[sid]
        held = [item for item in submission["items"] if item["state"] != "REMOVED"]
        versions = [item["version"] for item in held if item["version"]]
        if data["attributes"] == {"submitted": True}:
            if submission["state"] != "READY_FOR_REVIEW" or not held:
                raise Refusal(409, [error(409, "STATE_ERROR", "The review submission holds nothing to submit.")])
            if any(self.versions[vid]["state"] != "READY_FOR_REVIEW" for vid in versions):
                raise Refusal(409, [error(409, "STATE_ERROR", "An item of the submission is not ready for review yet.")])
            submission.update(state="WAITING_FOR_REVIEW", submittedDate="2026-11-20T17:05:00.000Z")
            for vid in versions:
                self.versions[vid]["state"] = "WAITING_FOR_REVIEW"
        elif data["attributes"] == {"canceled": True}:
            if submission["state"] != "WAITING_FOR_REVIEW":
                raise Refusal(409, [error(409, "STATE_ERROR.ENTITY_STATE_INVALID", "Resource is not in cancellable state")])
            submission["state"] = "CANCELING" if versions else "COMPLETE"
            for item in submission["items"]:
                item["state"] = "REMOVED"
            for vid in versions:
                self.later[vid] = [self.cancel_takes, "DEVELOPER_REJECTED"]
                self.finishing[vid] = sid
                if not self.cancel_takes:
                    self.get_version(vid, {}, None)
        else:
            raise AssertionError(f"unexpected change to a review submission: {data['attributes']}")
        return {"data": self.submission_resource(sid)}
