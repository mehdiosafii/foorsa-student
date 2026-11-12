"""request(), which the other tests replace, run for real against a server on this machine:
the method, the path with its query, the JSON body and the bearer token as they leave, an answer
with no content, and a refusal turned into AscError. Nothing reaches Apple, and no key is used:
token() is replaced by a fixed word.

    python3 -m unittest discover -s scripts/tests -v
"""
import http.server
import json
import os
import pathlib
import sys
import threading
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import app_store_listing as listing  # noqa: E402


class Handler(http.server.BaseHTTPRequestHandler):
    def answer(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.server.seen.append((self.command, self.path, dict(self.headers.items()), self.rfile.read(length) if length else b""))
        status, payload = self.server.answers.pop(0)
        data = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PATCH = do_DELETE = answer

    def log_message(self, *args):
        pass


class OverTheWire(unittest.TestCase):
    def setUp(self):
        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        self.server.seen, self.server.answers = [], []
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        patchers = [mock.patch.object(listing, "API", f"http://127.0.0.1:{self.server.server_port}"),
                    mock.patch.object(listing, "token", lambda: "a-token"),
                    # A proxy set for this machine has no business between the test and itself.
                    mock.patch.dict(os.environ, {"no_proxy": "127.0.0.1", "NO_PROXY": "127.0.0.1"})]
        for patcher in patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def exchange(self, status, payload, call, *args, **kwargs):
        self.server.answers.append((status, payload))
        result = call(*args, **kwargs)
        return result, self.server.seen[-1]

    def test_a_read_carries_its_query_and_the_token(self):
        result, (method, path, headers, body) = self.exchange(
            200, {"data": [{"id": "sub1"}]}, listing.get, "/v1/reviewSubmissions",
            {"filter[app]": "6816127081", "filter[state]": "WAITING_FOR_REVIEW,READY_FOR_REVIEW", "limit": 200})
        self.assertEqual(result, {"data": [{"id": "sub1"}]})
        self.assertEqual((method, body), ("GET", b""))
        self.assertEqual(path, "/v1/reviewSubmissions?filter%5Bapp%5D=6816127081&filter%5Bstate%5D=WAITING_FOR_REVIEW%2CREADY_FOR_REVIEW&limit=200")
        self.assertEqual(headers["Authorization"], "Bearer a-token")

    def test_a_new_version_leaves_as_json(self):
        sent = {"data": {"type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": "1.2.42"},
                         "relationships": {"app": {"data": {"type": "apps", "id": "6816127081"}}}}}
        result, (method, path, headers, body) = self.exchange(
            201, {"data": {"id": "v2"}}, listing.request, "POST", "/v1/appStoreVersions", body=sent)
        self.assertEqual((result, method, path), ({"data": {"id": "v2"}}, "POST", "/v1/appStoreVersions"))
        self.assertEqual(json.loads(body), sent)
        self.assertEqual(headers["Content-Type"], "application/json")

    def test_whats_new_keeps_its_letters(self):
        text = "A slow connection no longer shows “No internet connection”. الإشعارات تصل الآن."
        result, (method, path, headers, body) = self.exchange(
            200, {"data": {"id": "loc2"}}, listing.patch, "/v1/appStoreVersionLocalizations/loc2",
            "appStoreVersionLocalizations", "loc2", {"whatsNew": text})
        self.assertEqual((method, path), ("PATCH", "/v1/appStoreVersionLocalizations/loc2"))
        self.assertEqual(json.loads(body.decode("utf-8")),
                         {"data": {"type": "appStoreVersionLocalizations", "id": "loc2", "attributes": {"whatsNew": text}}})

    def test_an_answer_with_no_content_is_nothing(self):
        result, (method, path, headers, body) = self.exchange(204, None, listing.request, "DELETE", "/v1/reviewSubmissionItems/item1")
        self.assertEqual((result, method, path, body), (None, "DELETE", "/v1/reviewSubmissionItems/item1", b""))
        result, (method, path, headers, body) = self.exchange(
            204, None, listing.request, "PATCH", "/v1/appStoreVersions/v2/relationships/build", body={"data": {"type": "builds", "id": "b73"}})
        self.assertEqual((result, method, json.loads(body)), (None, "PATCH", {"data": {"type": "builds", "id": "b73"}}))

    def test_a_refusal_is_raised_with_apple_s_answer(self):
        refusal = {"errors": [{"status": "409", "code": "ENTITY_ERROR.RELATIONSHIP.INVALID",
                               "detail": "You cannot create a new version of the App in the current state.",
                               "source": {"pointer": "/data/relationships/app"}}]}
        self.server.answers.append((409, refusal))
        with self.assertRaises(listing.AscError) as raised:
            listing.request("POST", "/v1/appStoreVersions", body={"data": {}})
        self.assertEqual((raised.exception.status, json.loads(raised.exception.body)), (409, refusal))
        self.assertEqual(listing.explain(raised.exception), "409 ENTITY_ERROR.RELATIONSHIP.INVALID: You cannot create a new version "
                         "of the App in the current state. [/data/relationships/app]")

    def test_review_details_that_are_not_there_are_none(self):
        self.server.answers.append((404, {"errors": [{"status": "404", "code": "NOT_FOUND", "detail": "There is no resource of that id."}]}))
        self.assertIsNone(listing.review_detail("v2"))
        self.server.answers.append((200, {"data": None}))
        self.assertIsNone(listing.review_detail("v2"))
        self.server.answers.append((500, {"errors": [{"status": "500", "code": "UNEXPECTED_ERROR", "detail": "Try again."}]}))
        with self.assertRaises(listing.AscError):
            listing.review_detail("v2")


if __name__ == "__main__":
    unittest.main()
