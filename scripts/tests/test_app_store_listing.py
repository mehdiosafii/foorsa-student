"""scripts/app_store_listing.py against a stand-in for App Store Connect.

Nothing here reaches Apple. The module's request() is replaced by the stand-in's, so its own
get(), pages() and patch() run as they do for real, and what the tests hold is what would have
gone over the wire: the exact writes, in order. token() and urlopen() are replaced by functions
that fail the test, and the portal by a canned answer.

    python3 -m unittest discover -s scripts/tests -v

With Apple's OpenAPI specification at hand, every request the script makes in every test is also
checked against it (that the path exists, its query, and a write's body):

    ASC_OPENAPI=/path/to/openapi.oas.json python3 -m unittest discover -s scripts/tests -v

The specification is the zip Apple publishes at
https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
"""
import contextlib
import io
import json
import os
import pathlib
import re
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

import app_store_listing as listing  # noqa: E402
import fake_app_store_connect as fake  # noqa: E402
import openapi_check  # noqa: E402

APP = fake.APP
NOTES_FILE = "Foorsa Student, for App Review.\n\nBuild {version} ({build}) is iPhone-only.\n"
WHATS_NEW = "In mainland China, notifications now arrive. The app opens a little faster. Fixes."


def notes_for(version, build):
    return NOTES_FILE.replace("{version}", version).replace("{build}", build).strip()


def new_version(name, release="AFTER_APPROVAL"):
    return ("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": name, "releaseType": release, "copyright": "2026 Foorsa"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})


def rename(vid, name):
    return ("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {"versionString": name}}})


def attach(vid, build):
    return ("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build}})


def whats_new(lid, text=WHATS_NEW):
    return ("PATCH", f"/v1/appStoreVersionLocalizations/{lid}",
            {"data": {"type": "appStoreVersionLocalizations", "id": lid, "attributes": {"whatsNew": text}}})


def notes(did, text):
    return ("PATCH", f"/v1/appStoreReviewDetails/{did}", {"data": {"type": "appStoreReviewDetails", "id": did, "attributes": {"notes": text}}})


def open_submission():
    return ("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})


def add_to(sid, vid):
    return ("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})


def submit(sid):
    return ("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})


def cancel(sid):
    return ("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"canceled": True}}})


def take_out(iid):
    return ("DELETE", f"/v1/reviewSubmissionItems/{iid}", None)


class ListingCase(unittest.TestCase):
    """A stand-in for App Store Connect in the module's place, and the repository's two texts in
    a folder of the test's own."""

    maxDiff = None
    spec = openapi_check.load(os.environ.get("ASC_OPENAPI"))
    checked = 0

    def setUp(self):
        self.asc = fake.FakeAppStoreConnect()
        self.outputs = []
        self.slept = []
        listing.PRIVATE.clear()
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        store = pathlib.Path(self.folder.name)
        (store / "whats-new").mkdir()
        (store / "review-notes.txt").write_text(NOTES_FILE, encoding="utf-8")
        (store / "whats-new" / "en-US.txt").write_text(WHATS_NEW + "\n", encoding="utf-8")
        self.store = store

        def request(method, path, query=None, body=None):
            try:
                return self.asc.request(method, path, query, body)
            except fake.Refusal as refusal:
                raise listing.AscError(refusal.status, refusal.body) from None

        def never(*args, **kwargs):
            raise AssertionError("a test reached for the network")

        for name, value in (("request", request), ("token", never), ("REVIEW_NOTES", str(store / "review-notes.txt")),
                            ("WHATS_NEW", str(store / "whats-new"))):
            patcher = mock.patch.object(listing, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        for target, value in (("urllib.request.urlopen", never), ("time.sleep", self.slept.append)):
            patcher = mock.patch(target, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.addCleanup(self.nothing_private_was_printed)
        self.addCleanup(self.requests_are_ones_apple_takes)

    # ---- the App Store as it stood on 12 Nov 2026, and as it will once 1.2.39 is approved ----

    def builds(self, newest=73):
        for number, marketing in ((69, "1.2.38"), (70, "1.2.39"), (71, "1.2.40"), (72, "1.2.41"), (73, "1.2.42")):
            if number <= newest:
                self.asc.add_build(number, marketing)

    def first_version(self, state, build="b70"):
        """1.2.39 (70), the only version there has been (v1, its locale loc1, its review details detail1)."""
        self.builds()
        return self.asc.add_version("1.2.39", state, build=build)

    def waiting(self):
        vid = self.first_version("WAITING_FOR_REVIEW")
        self.asc.add_submission("COMPLETE", item_state="REMOVED", submitted="2026-11-04T22:14:21.033Z")
        return vid, self.asc.add_submission("WAITING_FOR_REVIEW", version=vid)

    def on_sale(self, **version):
        self.builds()
        vid = self.asc.add_version("1.2.39", "READY_FOR_SALE", build="b70", **version)
        self.asc.add_submission("COMPLETE", version=vid, item_state="APPROVED")
        return vid

    # ---- running the script ----------------------------------------------------------------

    def run_script(self, function, *args, **kwargs):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = function(*args, **kwargs)
        self.outputs.append(out.getvalue())
        return code, out.getvalue()

    def submit_latest(self, *args, **kwargs):
        return self.run_script(listing.submit_latest, *args, **kwargs)

    def nothing_private_was_printed(self):
        for output in self.outputs:
            for field, value in fake.SECRETS.items():
                self.assertNotIn(value, output, f"the output shows the {field}")

    def requests_are_ones_apple_takes(self):
        if self.spec:
            for method, path, query, body in self.asc.requests:
                problems = openapi_check.problems(self.spec, method, path, query, body)
                self.assertEqual(problems, [], f"{method} {path} is not a request Apple's specification takes")
                ListingCase.checked += 1


class UpdateOnceTheVersionIsOnSale(ListingCase):
    def test_an_update_is_a_new_version_with_whats_new_and_is_submitted(self):
        v1 = self.on_sale()
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes, [
            new_version("1.2.42"),
            attach("v2", "b73"),
            whats_new("loc2"),
            notes("detail2", notes_for("1.2.42", "73")),
            open_submission(),
            add_to("sub2", "v2"),
            submit("sub2"),
        ])
        v2 = self.asc.versions["v2"]
        self.assertEqual((v2["versionString"], v2["state"], v2["build"], v2["releaseType"], v2["copyright"]),
                         ("1.2.42", "WAITING_FOR_REVIEW", "b73", "AFTER_APPROVAL", "2026 Foorsa"))
        self.assertEqual(self.asc.whats_new_of("v2"), {"en-US": WHATS_NEW})
        self.assertEqual(self.asc.submissions["sub2"]["state"], "WAITING_FOR_REVIEW")
        # The demo account and the contact are the ones the version on sale has.
        self.assertEqual({k: self.asc.details["v2"]["attributes"][k] for k in fake.SECRETS}, fake.SECRETS)
        # The version on sale is as it was.
        self.assertEqual(self.asc.versions[v1], {"versionString": "1.2.39", "state": "READY_FOR_SALE", "releaseType": "AFTER_APPROVAL",
                                                 "copyright": "2026 Foorsa", "createdDate": "2026-10-05T11:18:37-07:00", "build": "b70"})
        self.assertEqual(self.asc.whats_new_of(v1), {"en-US": None})
        self.assertEqual(self.asc.details[v1]["attributes"]["notes"], "The notes App Store Connect holds.")
        self.assertIn("Version 1.2.42 made, as an update to 1.2.39: release AFTER_APPROVAL", output)
        self.assertIn("Submitted 1.2.42 (73) for review: submission sub2 is WAITING_FOR_REVIEW", output)
        self.assertIn("Version is now WAITING_FOR_REVIEW", output)
        self.assertEqual(self.slept, [])

    def test_the_states_are_read_by_their_new_names_too(self):
        self.on_sale()
        self.asc.old_state_names = False      # READY_FOR_DISTRIBUTION, with no appStoreState beside it
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertIn("Version 1.2.39 is READY_FOR_DISTRIBUTION", output)
        self.assertEqual(self.asc.writes[0], new_version("1.2.42"))
        self.assertEqual(self.asc.versions["v2"]["state"], "WAITING_FOR_REVIEW")

    def test_a_release_by_hand_stays_a_release_by_hand(self):
        self.on_sale(release="MANUAL")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes[0], new_version("1.2.42", release="MANUAL"))
        self.assertEqual(self.asc.versions["v2"]["releaseType"], "MANUAL")

    def test_a_release_on_a_date_is_not_guessed(self):
        self.on_sale(release="SCHEDULED")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("was released on a date (SCHEDULED)", output)
        self.assertIn("Nothing was changed.", output)

    def test_whats_new_is_written_in_every_locale_of_the_listing(self):
        self.on_sale(locales=("en-US", "fr-FR", "ar-SA"))
        (self.store / "whats-new" / "fr-FR.txt").write_text("En Chine, les notifications arrivent.\n", encoding="utf-8")
        (self.store / "whats-new" / "ar-SA.txt").write_text("الإشعارات تصل الآن في الصين.\n", encoding="utf-8")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes[2:5], [
            whats_new("loc4"),
            whats_new("loc5", "En Chine, les notifications arrivent."),
            whats_new("loc6", "الإشعارات تصل الآن في الصين."),
        ])
        self.assertEqual(self.asc.whats_new_of("v2"), {"en-US": WHATS_NEW, "fr-FR": "En Chine, les notifications arrivent.",
                                                       "ar-SA": "الإشعارات تصل الآن في الصين."})

    def test_a_locale_without_its_text_stops_it_before_anything_is_written(self):
        self.on_sale(locales=("en-US", "fr-FR"))
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("::error::store/app-store/whats-new/fr-FR.txt is missing or empty", output)
        self.assertIn("(en-US, fr-FR)", output)

    def test_an_empty_text_counts_as_missing(self):
        self.on_sale()
        (self.store / "whats-new" / "en-US.txt").write_text("  \n", encoding="utf-8")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("whats-new/en-US.txt is missing or empty", output)

    def test_no_whats_new_folder_stops_it(self):
        self.on_sale()
        (self.store / "whats-new" / "en-US.txt").unlink()
        (self.store / "whats-new").rmdir()
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)

    def test_a_text_for_a_locale_the_listing_lacks_stops_it(self):
        self.on_sale()
        (self.store / "whats-new" / "fr-FR.txt").write_text("En Chine, les notifications arrivent.\n", encoding="utf-8")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("::error::store/app-store/whats-new/fr-FR.txt: the listing has no fr-FR (its locales: en-US)", output)

    def test_a_text_over_the_limit_stops_it(self):
        self.on_sale()
        (self.store / "whats-new" / "en-US.txt").write_text("a" * 4001, encoding="utf-8")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("whats-new/en-US.txt is 4001 characters; App Store Connect takes 4000", output)

    def test_the_text_the_version_on_sale_went_out_with_stops_it(self):
        self.on_sale(whats_new={"en-US": WHATS_NEW})
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("is the text the version on sale went out with", output)

    def test_review_notes_over_the_limit_stop_it_before_anything_is_written(self):
        self.on_sale()
        (self.store / "review-notes.txt").write_text("n" * 4001, encoding="utf-8")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("The review notes are 4001 characters; App Store Connect takes 4000", output)

    def test_the_review_details_are_copied_when_apple_has_not(self):
        v1 = self.on_sale()
        self.asc.copies_review_details = False
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes[3], ("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails",
            "attributes": dict(fake.SECRETS, demoAccountRequired=True, notes=notes_for("1.2.42", "73")),
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": "v2"}}}}}))
        self.assertEqual([write[:2] for write in self.asc.writes], [
            ("POST", "/v1/appStoreVersions"), ("PATCH", "/v1/appStoreVersions/v2/relationships/build"),
            ("PATCH", "/v1/appStoreVersionLocalizations/loc2"), ("POST", "/v1/appStoreReviewDetails"),
            ("POST", "/v1/reviewSubmissions"), ("POST", "/v1/reviewSubmissionItems"), ("PATCH", "/v1/reviewSubmissions/sub2")])
        self.assertEqual(self.asc.versions["v2"]["state"], "WAITING_FOR_REVIEW")
        self.assertIn("Review details made: the contact and the demo account as 1.2.39 has them", output)
        self.assertEqual(self.asc.details[v1]["attributes"]["notes"], "The notes App Store Connect holds.")

    def test_a_refusal_of_the_copied_details_shows_nothing_of_them(self):
        self.on_sale()
        self.asc.copies_review_details = False
        self.asc.refuse_once.append(("POST", "/v1/appStoreReviewDetails", fake.Refusal(409, [fake.error(
            409, "ENTITY_ERROR.ATTRIBUTE.INVALID", f"The phone number '{fake.SECRETS['contactPhone']}' is not valid.",
            "/data/attributes/contactPhone")])))
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 1, output)
        self.assertIn("::error::Making the review details of version 1.2.42: App Store Connect answered 409 "
                      "ENTITY_ERROR.ATTRIBUTE.INVALID [/data/attributes/contactPhone]", output)
        self.assertNotIn("is not valid", output)

    def test_the_build_on_sale_is_not_submitted_again(self):
        self.builds(newest=70)
        self.asc.add_version("1.2.39", "READY_FOR_SALE", build="b70")
        code, output = self.submit_latest("1.2.39+70")
        self.assertEqual((code, self.asc.writes), (0, []), output)
        self.assertIn("::notice::1.2.39 (70) is the build on sale already: nothing to submit.", output)

    def test_an_update_takes_a_version_above_the_one_on_sale(self):
        self.builds(newest=70)
        self.asc.add_build(74, "1.2.39")
        self.asc.add_version("1.2.39", "READY_FOR_SALE", build="b70")
        code, output = self.submit_latest("1.2.39+74")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("an update takes a version above the one on sale", output)

    def test_what_a_version_lacks_is_said_and_asking_again_goes_on_from_there(self):
        self.on_sale()
        lacking = {"/v1/appStoreVersions/v2": [fake.error(409, "ENTITY_ERROR.RELATIONSHIP.REQUIRED",
                                                           "An agreement has to be accepted first.", "/data/relationships/app")]}
        self.asc.refuse_once.append(("POST", "/v1/reviewSubmissionItems", fake.Refusal(409, [fake.error(
            409, "ENTITY_UNPROCESSABLE", "The provided entity is missing required information.", meta={"associatedErrors": lacking})])))
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 1, output)
        self.assertIn("::error::Adding version 1.2.42 to the review submission: App Store Connect answered 409 ENTITY_UNPROCESSABLE: "
                      "The provided entity is missing required information.; /v1/appStoreVersions/v2 ENTITY_ERROR.RELATIONSHIP.REQUIRED: "
                      "An agreement has to be accepted first. [/data/relationships/app]", output)
        self.assertIn("What was written before that stays written.", output)
        self.assertEqual((self.asc.versions["v2"]["state"], self.asc.submissions["sub2"]), ("PREPARE_FOR_SUBMISSION",
                         {"state": "READY_FOR_REVIEW", "submittedDate": None, "items": []}))

        # Asked again: the update is there, being prepared, and the submission opened for it holds
        # nothing. No second version, no second submission; each step is written again.
        del self.asc.writes[:]
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes, [
            attach("v2", "b73"),
            whats_new("loc2"),
            notes("detail2", notes_for("1.2.42", "73")),
            add_to("sub2", "v2"),
            submit("sub2"),
        ])
        self.assertIn("Review submission sub2 was made and holds nothing: it is taken up", output)
        self.assertEqual((self.asc.versions["v2"]["state"], self.asc.submissions["sub2"]["state"]),
                         ("WAITING_FOR_REVIEW", "WAITING_FOR_REVIEW"))

    def test_a_version_apple_refuses_to_make_changes_nothing(self):
        self.on_sale()
        self.asc.refuse_once.append(("POST", "/v1/appStoreVersions", fake.Refusal(409, [fake.error(
            409, "ENTITY_ERROR.RELATIONSHIP.INVALID", "You cannot create a new version of the App in the current state.",
            "/data/relationships/app")])))
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 1, output)
        self.assertEqual(self.asc.writes, [new_version("1.2.42")])
        self.assertEqual(list(self.asc.versions), ["v1"])
        self.assertIn("::error::Making version 1.2.42: App Store Connect answered 409 ENTITY_ERROR.RELATIONSHIP.INVALID: "
                      "You cannot create a new version of the App in the current state. [/data/relationships/app]", output)

    def test_a_version_just_made_is_waited_for(self):
        self.on_sale()
        self.asc.readable_takes = 2     # 404 twice, then there
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.slept, [6, 6])
        self.assertEqual(len(self.asc.writes), 7)

    def test_what_apple_copies_into_a_new_version_is_waited_for(self):
        self.on_sale()
        self.asc.copy_takes = 2         # the locales, then the review details, each found at the third read
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.slept, [6, 6, 6, 6])
        self.assertEqual(self.asc.writes, [
            new_version("1.2.42"),
            attach("v2", "b73"),
            whats_new("loc2"),
            notes("detail2", notes_for("1.2.42", "73")),      # Apple's own copy, not a second one made
            open_submission(),
            add_to("sub2", "v2"),
            submit("sub2"),
        ])

    def test_review_details_apple_copied_while_they_were_being_made_take_the_notes(self):
        self.on_sale()
        self.asc.details_take = 11      # nothing for the whole minute they are waited for, then Apple's copy
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual([write[:2] for write in self.asc.writes], [
            ("POST", "/v1/appStoreVersions"), ("PATCH", "/v1/appStoreVersions/v2/relationships/build"),
            ("PATCH", "/v1/appStoreVersionLocalizations/loc2"),
            ("POST", "/v1/appStoreReviewDetails"),              # refused: the version has them by now
            ("PATCH", "/v1/appStoreReviewDetails/detail2"),
            ("POST", "/v1/reviewSubmissions"), ("POST", "/v1/reviewSubmissionItems"), ("PATCH", "/v1/reviewSubmissions/sub2")])
        self.assertEqual(self.asc.details["v2"]["attributes"]["notes"], notes_for("1.2.42", "73"))
        self.assertNotIn("::error::", output)

    def test_a_refusal_of_the_notes_shows_nothing_apple_repeats_of_the_contact(self):
        self.on_sale()
        self.asc.refuse_once.append(("PATCH", "/v1/appStoreReviewDetails/detail2", fake.Refusal(409, [fake.error(
            409, "ENTITY_ERROR.ATTRIBUTE.INVALID", f"The contact {fake.SECRETS['contactEmail'].upper()} ({fake.SECRETS['contactPhone']}) "
            f"could not be reached; account {fake.SECRETS['demoAccountName']}.", "/data/attributes/notes")])))
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 1, output)
        self.assertIn("::error::Writing the review notes: App Store Connect answered 409 ENTITY_ERROR.ATTRIBUTE.INVALID: "
                      "The contact <private> (<private>) could not be reached; account <private>. [/data/attributes/notes]", output)

    def test_it_waits_for_the_version_to_show_in_the_submission_before_submitting(self):
        self.on_sale()
        self.asc.ready_takes = 3
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.slept, [6, 6, 6])
        self.assertEqual(self.asc.writes[-1], submit("sub2"))


class TheUpdateBeingPrepared(ListingCase):
    """A second version already there: made by a run that stopped, or by hand in App Store Connect."""

    def prepared(self, name="1.2.42", state="PREPARE_FOR_SUBMISSION", build=None):
        self.builds()
        v1 = self.asc.add_version("1.2.39", "READY_FOR_SALE", build="b70")
        # Made later, and listed before the version on sale or after it: the newest is found by its date.
        v2 = self.asc.add_version(name, state, build=build, created="2026-11-20T09:00:00-08:00")
        return v1, v2

    def test_it_is_named_given_the_build_whats_new_and_notes_and_submitted(self):
        v1, v2 = self.prepared(name="1.2.41")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes, [
            rename("v2", "1.2.42"),
            attach("v2", "b73"),
            whats_new("loc2"),
            notes("detail2", notes_for("1.2.42", "73")),
            open_submission(),
            add_to("sub1", "v2"),
            submit("sub1"),
        ])
        self.assertEqual(self.asc.versions[v2]["state"], "WAITING_FOR_REVIEW")
        self.assertEqual(self.asc.versions[v1]["state"], "READY_FOR_SALE")

    def test_the_newest_version_is_found_whatever_order_the_api_lists_them_in(self):
        v1, v2 = self.prepared()
        for order in ([v1, v2], [v2, v1]):
            with self.subTest(order=order):
                self.asc.listed = order
                self.asc.versions[v2].update(state="PREPARE_FOR_SUBMISSION", build=None)
                self.asc.submissions.clear()
                del self.asc.writes[:]
                code, output = self.submit_latest("1.2.42+73")
                self.assertEqual(code, 0, output)
                self.assertIn("Version 1.2.42 is PREPARE_FOR_SUBMISSION", output)
                self.assertEqual(self.asc.writes[0], attach(v2, "b73"))

    def test_lists_are_read_to_their_last_page(self):
        v1, v2 = self.prepared()
        self.asc.listed = [v2, v1]
        for year in range(2015, 2025):          # ten versions long replaced, and a page holds three
            self.asc.add_version(f"0.{year}", "REPLACED_WITH_NEW_VERSION", created=f"{year}-01-01T00:00:00Z", details=False)
        self.asc.listed.remove(v2)
        self.asc.listed.append(v2)              # the newest comes last, on the fourth page
        self.asc.page_size = 3
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertIn("Version 1.2.42 is PREPARE_FOR_SUBMISSION", output)
        self.assertEqual(self.asc.versions[v2]["state"], "WAITING_FOR_REVIEW")

    def test_an_update_waiting_for_review_is_kept_too(self):
        v1, v2 = self.prepared(name="1.2.41", state="WAITING_FOR_REVIEW", build="b72")
        self.asc.add_submission("WAITING_FOR_REVIEW", version=v2)
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("A submission has been waiting for review since 2026-11-06T15:50:54.515Z", output)

    def test_an_update_waiting_is_replaced_with_the_word_and_takes_whats_new(self):
        v1, v2 = self.prepared(name="1.2.41", state="WAITING_FOR_REVIEW", build="b72")
        sub = self.asc.add_submission("WAITING_FOR_REVIEW", version=v2)
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes, [
            cancel(sub),
            rename("v2", "1.2.42"),
            attach("v2", "b73"),
            whats_new("loc2"),
            notes("detail2", notes_for("1.2.42", "73")),
            open_submission(),
            add_to("sub2", "v2"),
            submit("sub2"),
        ])

    def test_a_version_added_to_a_submission_and_not_submitted_is_taken_out_and_put_up_again(self):
        # Where a run that stopped between adding the version and submitting leaves things, or
        # "Add for Review" pressed in App Store Connect. Such a submission cannot be cancelled.
        v1, v2 = self.prepared(state="READY_FOR_REVIEW", build="b72")
        draft = self.asc.add_submission("READY_FOR_REVIEW", version=v2, submitted=None)
        self.asc.cancel_takes = 1
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes, [
            take_out("item1"),
            attach("v2", "b73"),
            whats_new("loc2"),
            notes("detail2", notes_for("1.2.42", "73")),
            add_to(draft, "v2"),
            submit(draft),
        ])
        self.assertEqual(self.slept, [6])
        self.assertIn(f"Version 1.2.42 taken out of review submission {draft}, which was made and not submitted", output)
        self.assertIn(f"Review submission {draft} was made and holds nothing: it is taken up", output)
        self.assertEqual((self.asc.versions[v2]["state"], self.asc.submissions[draft]["state"]), ("WAITING_FOR_REVIEW", "WAITING_FOR_REVIEW"))

    def test_an_item_taken_out_that_stays_listed_as_removed_holds_nothing(self):
        v1, v2 = self.prepared(state="READY_FOR_REVIEW", build="b72")
        draft = self.asc.add_submission("READY_FOR_REVIEW", version=v2, submitted=None)
        self.asc.removed_items_stay = True
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes[0], take_out("item1"))
        self.assertEqual(self.asc.writes[-2:], [add_to(draft, "v2"), submit(draft)])
        self.assertEqual([item["state"] for item in self.asc.submissions[draft]["items"]], ["REMOVED", "READY_FOR_REVIEW"])

        # And met again later, a submission whose only rows are removed ones is an empty one.
        self.asc.submissions[draft].update(state="READY_FOR_REVIEW", submittedDate=None)
        self.asc.submissions[draft]["items"] = [{"id": "item9", "state": "REMOVED", "version": v2}, {"id": "item8", "state": "REMOVED", "version": None}]
        self.asc.versions[v2].update(state="PREPARE_FOR_SUBMISSION")
        del self.asc.writes[:]
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes[-2:], [add_to(draft, "v2"), submit(draft)])
        self.assertNotIn(("DELETE", "/v1/reviewSubmissionItems/item9", None), self.asc.writes)

    def test_a_submission_not_submitted_that_holds_something_else_is_left_to_its_owner(self):
        for version, others, said in ((None, 1, "holds 1 thing other than version 1.2.42"),
                                      (True, 2, "holds 2 things other than version 1.2.42")):
            with self.subTest(said=said):
                self.asc = fake.FakeAppStoreConnect()
                v1, v2 = self.prepared(state="READY_FOR_REVIEW" if version else "PREPARE_FOR_SUBMISSION", build="b72")
                draft = self.asc.add_submission("READY_FOR_REVIEW", version=v2 if version else None, others=others, submitted=None)
                code, output = self.submit_latest("1.2.42+73")
                self.assertEqual((code, self.asc.writes), (1, []), output)
                self.assertIn(f"::error::Review submission {draft} was made and not submitted, and {said}", output)
                self.assertIn("Nothing was changed.", output)

    def test_something_else_waiting_for_review_is_not_cancelled_for_an_update_either(self):
        # An in-app event, say, waiting for review while the version is on sale.
        self.asc = fake.FakeAppStoreConnect()
        self.on_sale()
        self.asc.add_submission("WAITING_FOR_REVIEW", others=1)
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("A submission has been waiting for review since", output)

    def test_review_details_missing_on_the_update_are_copied_from_the_version_on_sale(self):
        v1, v2 = self.prepared()
        del self.asc.details[v2]
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.asc.writes[2][:2], ("POST", "/v1/appStoreReviewDetails"))
        self.assertEqual(self.asc.writes[2][2]["data"]["relationships"], {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v2}}})
        self.assertEqual({k: self.asc.details[v2]["attributes"][k] for k in fake.SECRETS}, fake.SECRETS)

    def test_review_check_tries_the_account_a_submission_would_copy(self):
        v1, v2 = self.prepared()
        del self.asc.details[v2]
        with mock.patch.object(listing, "portal", self.portal_that_takes_the_demo_account()):
            code, output = self.run_script(listing.review_check)
        self.assertEqual(code, 0, output)
        self.assertIn("Version 1.2.42 (PREPARE_FOR_SUBMISSION)", output)
        self.assertIn("It has no review details yet: those of 1.2.39 are read, which a submission copies.", output)
        self.assertIn("Portal sign-in with the demo account: HTTP 200", output)

    def portal_that_takes_the_demo_account(self):
        def portal(method, path, body=None, bearer=None):
            if path == "/api/portal/login":
                good = body == {"identifier": fake.SECRETS["demoAccountName"], "password": fake.SECRETS["demoAccountPassword"]}
                return (200, {"token": "t", "mustChangePassword": False, "kind": "student"}) if good else (401, {"error": "no"})
            return 200, {"rail": {"step": 0, "onHold": False}, "track": "bachelor", "signing": {"required": False}, "todo": {"count": 11}}
        return portal


class TheVersionWaitingForReview(ListingCase):
    """Where things stood on 12 Nov 2026: 1.2.39 (70) waiting since 6 Nov, 1.2.42 (73) in TestFlight."""

    def test_it_is_kept_unless_the_owner_said_to_replace_it(self):
        vid, sub = self.waiting()
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertEqual((self.asc.versions[vid]["state"], self.asc.submissions[sub]["state"]), ("WAITING_FOR_REVIEW", "WAITING_FOR_REVIEW"))
        self.assertIn("::error::A submission has been waiting for review since 2026-11-06T15:50:54.515Z. Putting 1.2.42 (73) in its "
                      "place cancels it, and the wait starts again: that is the owner's decision.", output)
        self.assertIn("replace-waiting", output)
        self.assertIn("Nothing was changed.", output)
        self.assertEqual(self.slept, [])

    def test_it_is_kept_even_if_the_list_of_submissions_does_not_show_it(self):
        vid, sub = self.waiting()
        del self.asc.submissions[sub]
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("::error::A submission has been waiting for review.", output)

    def test_with_the_word_it_is_cancelled_and_the_newest_build_goes_up_in_its_place(self):
        vid, sub = self.waiting()
        self.asc.cancel_takes = 2
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual(code, 0, output)
        # A first version: no What's New, which Apple refuses on one.
        self.assertEqual(self.asc.writes, [
            cancel(sub),
            rename("v1", "1.2.42"),
            attach("v1", "b73"),
            notes("detail1", notes_for("1.2.42", "73")),
            open_submission(),
            add_to("sub3", "v1"),
            submit("sub3"),
        ])
        self.assertEqual(self.slept, [6, 6])
        self.assertEqual((self.asc.versions[vid]["versionString"], self.asc.versions[vid]["state"], self.asc.versions[vid]["build"]),
                         ("1.2.42", "WAITING_FOR_REVIEW", "b73"))
        self.assertEqual(self.asc.whats_new_of(vid), {"en-US": None})
        self.assertIn(f"Cancelled review submission {sub} (WAITING_FOR_REVIEW)", output)
        self.assertIn("Version is now DEVELOPER_REJECTED", output)

    def test_app_review_taking_it_up_at_the_last_moment_stops_the_cancel(self):
        vid, sub = self.waiting()

        def taken_up():
            self.asc.submissions[sub]["state"] = "IN_REVIEW"
            self.asc.versions[vid]["state"] = "IN_REVIEW"

        self.asc.before.append(("GET", f"/v1/reviewSubmissions/{sub}", taken_up))
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn(f"::error::Review submission {sub} is no longer waiting for review but IN_REVIEW: it is left alone.", output)
        self.assertEqual(self.asc.submissions[sub]["state"], "IN_REVIEW")

    def test_the_cancelled_submission_is_let_go_of_before_the_new_one_is_made(self):
        vid, sub = self.waiting()
        self.asc.cancel_takes = 3
        seen = []
        self.asc.before.append(("POST", "/v1/reviewSubmissions", lambda: seen.append(self.asc.submissions[sub]["state"])))
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual((code, seen), (0, ["COMPLETE"]), output)
        self.assertEqual(self.slept, [6, 6, 6])

    def test_a_read_that_fails_after_the_submission_went_through_is_not_a_failure(self):
        vid, sub = self.waiting()
        self.asc.before.append(("PATCH", "/v1/reviewSubmissions/sub3", lambda: self.asc.refuse_once.append(
            ("GET", f"/v1/appStoreVersions/{vid}", fake.Refusal(500, [fake.error(500, "UNEXPECTED_ERROR", "Try again later.")])))))
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual(code, 0, output)
        self.assertIn("Submitted 1.2.42 (73) for review: submission sub3 is WAITING_FOR_REVIEW", output)
        self.assertIn("The version's state could not be read after that (500); state shows it.", output)
        self.assertNotIn("::error::", output)

    def test_a_first_version_needs_no_whats_new_file(self):
        vid, sub = self.waiting()
        (self.store / "whats-new" / "en-US.txt").unlink()
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual(code, 0, output)
        self.assertEqual(len(self.asc.writes), 7)

    def test_the_build_waiting_is_not_put_up_again_even_with_the_word(self):
        self.builds(newest=70)
        vid = self.asc.add_version("1.2.39", "WAITING_FOR_REVIEW", build="b70")
        self.asc.add_submission("WAITING_FOR_REVIEW", version=vid)
        for word in (False, True):
            code, output = self.submit_latest("1.2.39+70", replace_waiting=word)
            self.assertEqual((code, self.asc.writes), (0, []), output)
            self.assertIn("::notice::1.2.39 (70) is the build waiting for review already: nothing to submit.", output)

    def test_the_named_version_must_be_the_newest_valid_build(self):
        self.waiting()
        for named in ("1.2.41+72", "1.2.42+72", "1.2.43+73", "1.2.42"):
            code, output = self.submit_latest(named, replace_waiting=True)
            self.assertEqual((code, self.asc.writes), (1, []), output)
            self.assertIn(f"::error::The newest valid build is 1.2.42+73, not {named}: nothing was changed.", output)

    def test_a_build_still_processing_or_expired_is_not_the_newest_valid_one(self):
        self.waiting()
        self.asc.add_build(74, "1.2.43", state="PROCESSING")
        self.asc.add_build(75, "1.2.44", expired=True)
        code, output = self.submit_latest("1.2.43+74", replace_waiting=True)
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("The newest valid build is 1.2.42+73, not 1.2.43+74", output)

    def test_no_valid_build_changes_nothing(self):
        self.asc.add_version("1.2.39", "WAITING_FOR_REVIEW")
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("::error::No valid build to submit.", output)

    def test_a_cancelled_submission_that_never_lets_go_stops_it_there(self):
        vid, sub = self.waiting()
        self.asc.cancel_takes = 1000
        code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
        self.assertEqual(code, 1, output)
        self.assertEqual(self.asc.writes, [cancel(sub)])
        self.assertEqual(len(self.slept), 40)
        self.assertIn("::error::The version is still WAITING_FOR_REVIEW; nothing was changed on it.", output)


class VersionsLeftAlone(ListingCase):
    def test_a_version_in_review_is_never_touched(self):
        vid = self.first_version("IN_REVIEW")
        self.asc.add_submission("IN_REVIEW", version=vid)
        for word in (False, True):
            code, output = self.submit_latest("1.2.42+73", replace_waiting=word)
            self.assertEqual((code, self.asc.writes), (1, []), output)
            self.assertIn("::error::Version 1.2.39 is IN_REVIEW: it is in review, and a version in review is never touched. "
                          "Nothing was changed.", output)
        self.assertEqual(self.slept, [])
        self.assertEqual(self.asc.versions[vid]["state"], "IN_REVIEW")

    def test_a_submission_in_review_is_never_touched_whatever_the_version_says(self):
        # The version's own state can lag behind its submission's, and a submission can hold
        # something other than the version.
        for version_state in ("WAITING_FOR_REVIEW", "PREPARE_FOR_SUBMISSION", "READY_FOR_SALE"):
            with self.subTest(version_state=version_state):
                self.asc = fake.FakeAppStoreConnect()
                vid = self.first_version(version_state)
                sub = self.asc.add_submission("IN_REVIEW", version=vid)
                code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
                self.assertEqual((code, self.asc.writes), (1, []), output)
                self.assertIn(f"::error::Review submission {sub} is in review, and what is in review is never touched. Nothing was changed.", output)

    def test_an_approved_version_not_yet_on_sale_is_waited_for(self):
        for state, reason in (("PENDING_DEVELOPER_RELEASE", "waits to be released by hand"),
                              ("PENDING_APPLE_RELEASE", "waits for Apple to release it"),
                              ("PROCESSING_FOR_APP_STORE", "on its way to the App Store"),
                              ("ACCEPTED", "accepted and not yet on sale"),
                              ("WAITING_FOR_EXPORT_COMPLIANCE", "not a state a submission is made from"),
                              ("REMOVED_FROM_SALE", "not a state a submission is made from")):
            with self.subTest(state=state):
                self.asc = fake.FakeAppStoreConnect()
                self.first_version(state)
                code, output = self.submit_latest("1.2.42+73", replace_waiting=True)
                self.assertEqual((code, self.asc.writes), (1, []), output)
                self.assertIn(f"::error::Version 1.2.39 is {state}: ", output)
                self.assertIn(reason, output)
                self.assertIn("Nothing was changed.", output)
        self.assertEqual(self.slept, [])

    def test_no_version_at_all_changes_nothing(self):
        self.builds()
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)
        self.assertIn("has no version of the app", output)


class AVersionSentBack(ListingCase):
    def test_one_app_review_sent_back_is_left_to_the_owner(self):
        # As on 2 Nov 2026: the version rejected, its submission open until it is answered.
        for state in ("REJECTED", "METADATA_REJECTED"):
            for word in (False, True):
                with self.subTest(state=state, word=word):
                    self.asc = fake.FakeAppStoreConnect()
                    vid = self.first_version(state)
                    sub = self.asc.add_submission("UNRESOLVED_ISSUES", version=vid, item_state="REJECTED")
                    code, output = self.submit_latest("1.2.42+73", replace_waiting=word)
                    self.assertEqual((code, self.asc.writes), (1, []), output)
                    self.assertIn(f"::error::App Review sent review submission {sub} back and it is not answered yet (UNRESOLVED_ISSUES).", output)
                    self.assertIn("Nothing was changed.", output)
                    self.assertEqual((self.asc.versions[vid]["versionString"], self.asc.versions[vid]["build"]), ("1.2.39", "b70"))

    def test_an_update_app_review_sent_back_is_left_to_the_owner_too(self):
        self.builds()
        self.asc.add_version("1.2.39", "READY_FOR_SALE", build="b70")
        v2 = self.asc.add_version("1.2.41", "REJECTED", build="b72", created="2026-11-20T09:00:00-08:00")
        self.asc.add_submission("UNRESOLVED_ISSUES", version=v2, item_state="REJECTED")
        code, output = self.submit_latest("1.2.42+73")
        self.assertEqual((code, self.asc.writes), (1, []), output)

    def test_one_taken_back_or_never_submitted_goes_up_again_without_whats_new(self):
        # Cancelled by the developer, an invalid binary, or a rejection whose submission was since
        # withdrawn in App Store Connect: nothing is open, and a first version takes no What's New.
        for state in sorted(fake.EDITABLE):
            with self.subTest(state=state):
                self.asc = fake.FakeAppStoreConnect()
                vid = self.first_version(state)
                self.asc.add_submission("COMPLETE", version=vid, item_state="REMOVED")
                code, output = self.submit_latest("1.2.42+73")
                self.assertEqual(code, 0, output)
                self.assertEqual(self.asc.writes, [
                    rename("v1", "1.2.42"),
                    attach("v1", "b73"),
                    notes("detail1", notes_for("1.2.42", "73")),
                    open_submission(),
                    add_to("sub2", "v1"),
                    submit("sub2"),
                ])
                self.assertEqual(self.asc.versions[vid]["state"], "WAITING_FOR_REVIEW")


class WhatTheOtherActionsRead(ListingCase):
    def test_state_reads_and_writes_nothing(self):
        vid, sub = self.waiting()
        self.asc.details[vid]["attributes"]["notes"] = notes_for("1.2.39", "70")
        code, output = self.run_script(listing.state)
        self.assertEqual((code, self.asc.writes), (0, []), output)
        self.assertIn(f"  {vid}: 1.2.39 WAITING_FOR_REVIEW, release AFTER_APPROVAL, copyright filled (11 characters)", output)
        self.assertIn("  build attached: 70", output)
        self.assertIn("  review notes: what store/app-store/review-notes.txt writes", output)
        self.assertIn("  1.2.42 (73): VALID, expired False", output)
        self.assertIn("  the newest valid build, as a submission names it: 1.2.42+73", output)
        self.assertIn("  en-US: 82 characters in the repository", output)
        self.assertIn("  no version is on sale yet: a first version has no What's New, and these wait for the update", output)
        self.assertIn(f"  {sub}: WAITING_FOR_REVIEW submitted 2026-11-06T15:50:54.515Z, platform IOS", output)
        self.assertIn(f"    item item1: READY_FOR_REVIEW (appStoreVersion {vid})", output)
        self.assertIn("  still open (not submitted, waiting, in review, or sent back): 1 (WAITING_FOR_REVIEW)", output)

    def test_state_says_when_the_notes_are_not_the_repository_s(self):
        self.waiting()
        code, output = self.run_script(listing.state)
        self.assertEqual(code, 0, output)
        self.assertIn(f"  review notes: not what store/app-store/review-notes.txt writes ({len(notes_for('1.2.39', '70'))} characters): "
                      "a submission writes the file over them", output)

    def test_state_shows_the_update_and_what_would_stop_one(self):
        self.on_sale(whats_new={"en-US": WHATS_NEW}, locales=("en-US", "fr-FR"))
        code, output = self.run_script(listing.state)
        self.assertEqual((code, self.asc.writes), (0, []), output)
        self.assertIn("  store/app-store/whats-new/en-US.txt is the text the version on sale went out with", output)
        self.assertIn("  store/app-store/whats-new/fr-FR.txt is missing or empty", output)
        self.assertIn("  still open (not submitted, waiting, in review, or sent back): 0", output)

    def test_state_shows_the_latest_submissions_of_a_long_history(self):
        vid = self.first_version("READY_FOR_REVIEW")
        for day in (3, 9, 1, 7, 5, 10, 2, 8, 4, 6):         # in no order, as the API may list them
            self.asc.add_submission("COMPLETE", item_state="REMOVED", submitted=f"2026-10-{day:02d}T10:00:00.000Z")
        draft = self.asc.add_submission("READY_FOR_REVIEW", version=vid, submitted=None)
        self.asc.submissions = dict(sorted(self.asc.submissions.items(), key=lambda pair: pair[0]))
        self.asc.page_size = 4
        code, output = self.run_script(listing.state)
        self.assertEqual((code, self.asc.writes), (0, []), output)
        shown = [line.split(":")[0].strip() for line in output.splitlines() if " submitted " in line and line.startswith("  sub")]
        dates = [line.split(" submitted ")[1].split(",")[0] for line in output.splitlines() if " submitted " in line and line.startswith("  sub")]
        self.assertEqual(shown[0], draft)
        self.assertEqual(dates, ["None"] + [f"2026-10-{day:02d}T10:00:00.000Z" for day in (10, 9, 8, 7, 6, 5, 4)])
        self.assertIn("  and 3 older", output)
        self.assertIn("  still open (not submitted, waiting, in review, or sent back): 1 (READY_FOR_REVIEW)", output)

    def test_state_shows_the_newest_version_first(self):
        self.builds()
        v1 = self.asc.add_version("1.2.39", "READY_FOR_SALE", build="b70")
        v2 = self.asc.add_version("1.2.42", "WAITING_FOR_REVIEW", build="b73", created="2026-11-20T09:00:00-08:00", details=False)
        code, output = self.run_script(listing.state)
        self.assertEqual(code, 0, output)
        self.assertLess(output.index(f"  {v2}: 1.2.42 WAITING_FOR_REVIEW"), output.index(f"  {v1}: 1.2.39 READY_FOR_SALE"))
        self.assertIn("== Version 1.2.42 (WAITING_FOR_REVIEW)", output)
        self.assertIn("review details: none yet (a submission copies the contact and the demo account from the version before)", output)

    def test_review_check_reads_the_newest_version_and_masks_the_account(self):
        vid, sub = self.waiting()
        self.asc.details[vid]["attributes"]["notes"] = (
            f"Sign in as {fake.SECRETS['demoAccountName']} with {fake.SECRETS['demoAccountPassword']}.\n\nThen open Home.\n\n"
            f"Questions: {fake.SECRETS['contactFirstName'].upper()} {fake.SECRETS['contactLastName']}, "
            f"{fake.SECRETS['contactPhone']}, {fake.SECRETS['contactEmail'].title()}.")
        asked = []

        def portal(method, path, body=None, bearer=None):
            asked.append((method, path, body, bearer))
            if path == "/api/portal/login":
                return 200, {"token": "session-token", "mustChangePassword": False, "kind": "student"}
            return 200, {"rail": {"step": 0, "onHold": False}, "track": "bachelor", "signing": {"required": False}, "todo": {"count": 11}}

        with mock.patch.object(listing, "portal", portal):
            code, output = self.run_script(listing.review_check)
        self.assertEqual((code, self.asc.writes), (0, []), output)
        self.assertEqual(asked[0], ("POST", "/api/portal/login", {"identifier": fake.SECRETS["demoAccountName"],
                                                                  "password": fake.SECRETS["demoAccountPassword"]}, None))
        self.assertIn("Version 1.2.39 (WAITING_FOR_REVIEW)", output)
        self.assertIn("  | Sign in as <demo name> with <demo password>.", output)
        self.assertIn("  | Questions: <contact first name> <contact last name>, <contact phone>, <contact email>.", output)
        self.assertIn("Portal sign-in with the demo account: HTTP 200", output)

    def test_review_check_fails_when_the_demo_account_no_longer_signs_in(self):
        self.waiting()
        with mock.patch.object(listing, "portal", lambda *a, **k: (401, {"error": "Invalid credentials", "code": "bad"})):
            code, output = self.run_script(listing.review_check)
        self.assertEqual((code, self.asc.writes), (1, []), output)


class ApplesAnswers(unittest.TestCase):
    def test_an_answer_that_is_not_json_is_shown_short(self):
        self.assertEqual(listing.explain(listing.AscError(502, "<html>Bad gateway</html>")), "502 <html>Bad gateway</html>")
        self.assertEqual(listing.explain(listing.AscError(502, "<html>Bad gateway</html>"), details=False), "502")
        self.assertEqual(listing.explain(listing.AscError(500, "[1, 2]")), "500 [1, 2]")
        self.assertEqual(listing.explain(listing.AscError(409, '{"errors": [null, "x"]}')), '409 {"errors": [null, "x"]}')
        self.assertEqual(listing.explain(listing.AscError(409, '{"errors": "no"}')), '409 {"errors": "no"}')
        self.assertEqual(listing.explain(listing.AscError(503, "")), "503")

    def test_an_answer_in_a_form_not_met_before_is_still_read(self):
        odd = json.dumps({"errors": [{"code": "X", "detail": "Said.", "source": "nowhere", "meta": "none"},
                                     {"code": "Y", "meta": {"associatedErrors": ["not", "a", "map"]}},
                                     {"code": "Z", "meta": {"associatedErrors": {"/v1/things/1": "not a list", "/v1/things/2": [None, {"code": "W"}],
                                                                                 "/v1/things/3": None, "/v1/things/4": 7}}}]})
        self.assertEqual(listing.explain(listing.AscError(409, odd)), "409 X: Said.; Y; Z; /v1/things/2 W")

    def test_each_error_is_named_with_the_field_it_points_at(self):
        body = json.dumps({"errors": [
            {"code": "ENTITY_ERROR.ATTRIBUTE.INVALID", "detail": "The version is not valid.", "source": {"pointer": "/data/attributes/versionString"}},
            {"code": "PARAMETER_ERROR.INVALID", "detail": "Bad filter.", "source": {"parameter": "filter[state]"}}]})
        self.assertEqual(listing.explain(listing.AscError(409, body)),
                         "409 ENTITY_ERROR.ATTRIBUTE.INVALID: The version is not valid. [/data/attributes/versionString]; "
                         "PARAMETER_ERROR.INVALID: Bad filter. [filter[state]]")
        self.assertEqual(listing.explain(listing.AscError(409, body), details=False),
                         "409 ENTITY_ERROR.ATTRIBUTE.INVALID [/data/attributes/versionString]; PARAMETER_ERROR.INVALID [filter[state]]")


class TheCommandLine(unittest.TestCase):
    """What the workflow's step passes on: a version, the word, both or neither."""

    def run_main(self, *words):
        script = HERE.parent / "app_store_listing.py"
        source = script.read_text(encoding="utf-8")
        calls = []
        scope = {"__name__": "__main__", "__file__": str(script)}
        with mock.patch.object(sys, "argv", [str(script), *words]):
            # The file is run as the workflow runs it, with the three actions swapped for recorders.
            code = compile(source.replace('commands = {"state": state, "review-check": review_check, "submit-latest": submit_latest}',
                                          'commands = RECORDERS; submit_latest = RECORDERS["submit-latest"]'), str(script), "exec")
            scope["RECORDERS"] = {
                "state": lambda: calls.append(("state",)) or 0,
                "review-check": lambda: calls.append(("review-check",)) or 0,
                "submit-latest": lambda expected="", replace_waiting=False: calls.append(("submit-latest", expected, replace_waiting)) or 0,
            }
            with self.assertRaises(SystemExit) as stopped:
                exec(code, scope)
        return stopped.exception.code, calls

    def test_the_words_after_the_action(self):
        self.assertEqual(self.run_main(), (0, [("state",)]))
        self.assertEqual(self.run_main("state"), (0, [("state",)]))
        self.assertEqual(self.run_main("review-check"), (0, [("review-check",)]))
        self.assertEqual(self.run_main("submit-latest"), (0, [("submit-latest", "", False)]))
        self.assertEqual(self.run_main("submit-latest", "1.2.42+73"), (0, [("submit-latest", "1.2.42+73", False)]))
        self.assertEqual(self.run_main("submit-latest", "1.2.42+73", "replace-waiting"), (0, [("submit-latest", "1.2.42+73", True)]))
        self.assertEqual(self.run_main("submit-latest", "replace-waiting"), (0, [("submit-latest", "", True)]))

    def test_words_it_does_not_know_stop_it_before_anything_runs(self):
        for words in (("submit-latest", "1.2.42+73", "1.2.41+72"), ("submit-latest", "replace-waiting", "replace-waiting"),
                      ("submit-latest", "1.2.42+73", "replace-waiting", "now"), ("delete",)):
            code, calls = self.run_main(*words)
            self.assertIsInstance(code, str, words)
            self.assertEqual(calls, [], words)


class TheRepositorysTexts(unittest.TestCase):
    """The files a submission would send today."""

    store = HERE.parent.parent / "store" / "app-store"

    def version_and_build(self):
        line = next(line for line in (HERE.parent.parent / "pubspec.yaml").read_text(encoding="utf-8").splitlines() if line.startswith("version:"))
        return line.split(":", 1)[1].strip().split("+")

    def test_the_review_notes_fit(self):
        version, build = self.version_and_build()
        text = listing.review_notes(version, build)
        self.assertLessEqual(len(text), listing.LONGEST)
        self.assertIn(f"Build {version} ({build}) is iPhone-only", text)
        self.assertNotIn("{", text)

    def test_whats_new_is_there_for_the_listing_s_locale_and_fits(self):
        texts = listing.whats_new()
        self.assertIn("en-US", texts)       # the listing's only locale, as state read it on 12 Nov 2026
        self.assertEqual(listing.whats_new_problems(texts, ["en-US"], {}), [])

    def test_whats_new_names_no_other_platform(self):
        # App Review refuses App Store text that names another mobile platform (guideline 2.3.10).
        for locale, text in listing.whats_new().items():
            self.assertIsNone(re.search(r"android|google|play store", text, re.IGNORECASE), locale)


def tearDownModule():
    if ListingCase.spec:
        print(f"\n{ListingCase.checked} requests checked against Apple's OpenAPI specification "
              f"{ListingCase.spec['info'].get('version')}", file=sys.stderr)


if __name__ == "__main__":
    unittest.main()
