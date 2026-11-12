"""The shell step of .github/workflows/app-store-listing.yml, run as GitHub runs it, with a stub
in the script's place that only notes how it was called.

The step names no shell, so GitHub runs it with `bash -e` (a run's log says
"shell: /usr/bin/bash -e {0}"); it is also run here the way a step that names bash is,
`bash --noprofile --norc -eo pipefail`, so that naming one later changes nothing.

    python3 -m unittest discover -s scripts/tests -v
"""
import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "app-store-listing.yml"
SHELLS = (["bash", "-e"], ["bash", "--noprofile", "--norc", "-eo", "pipefail"])

STUB = '''\
import os, sys
with open(os.environ["STUB_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(sys.argv[1:]) + "\\n")
sys.exit(1 if sys.argv[1] in os.environ.get("STUB_FAILS", "").split(",") else 0)
'''


def step():
    """The step's name, the names of what it is given, and its script, read from the workflow as
    text (the runner has no YAML reader that can be counted on)."""
    lines = WORKFLOW.read_text(encoding="utf-8").splitlines()
    start = next(n for n, line in enumerate(lines) if line.strip() == "run: |")
    indent = len(lines[start]) - len(lines[start].lstrip())
    script = []
    for line in lines[start + 1:]:
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        script.append(line)
    given = []
    for line in reversed(lines[:start]):
        if line.strip() == "env:":
            break
        given.append(line.strip().split(":", 1))
    return textwrap.dedent("\n".join(script)) + "\n", {name: value.strip() for name, value in given}


class TheStep(unittest.TestCase):
    maxDiff = None

    def run_step(self, request=None, event="push", action="", replace_waiting="", fails=""):
        """How the stub was called, line by line, the step's exit code and what it printed, under
        each shell; the two have to agree."""
        script, _ = step()
        results = []
        for shell in SHELLS:
            with tempfile.TemporaryDirectory() as folder:
                work = pathlib.Path(folder)
                (work / "scripts").mkdir()
                (work / ".github").mkdir()
                (work / "scripts" / "app_store_listing.py").write_text(STUB, encoding="utf-8")
                (work / "step.sh").write_text(script, encoding="utf-8")
                if request is not None:
                    (work / ".github" / "app-store-request.txt").write_bytes(request.encode())
                log = work / "calls.log"
                env = {"PATH": os.environ["PATH"], "EVENT": event, "ACTION": action, "REPLACE_WAITING": replace_waiting,
                       "STUB_LOG": str(log), "STUB_FAILS": fails}
                done = subprocess.run([*shell, "step.sh"], cwd=work, env=env, capture_output=True, text=True, timeout=60)
                calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
                results.append((calls, done.returncode, done.stdout + done.stderr))
        self.assertEqual(results[0][:2], results[1][:2], "the two shells disagree")
        return results[0]

    # ---- asked for by a push that changes .github/app-store-request.txt -------------------

    def test_state_and_review_check(self):
        for request in ("state\n", "state", "  state  \n", "state\n\n"):
            self.assertEqual(self.run_step(request)[:2], (["state"], 0), repr(request))
        for request in ("review-check\n", "review-check"):
            self.assertEqual(self.run_step(request)[:2], (["review-check"], 0), repr(request))

    def test_a_submission_checks_the_demo_account_first_and_prints_state_after(self):
        for request in ("submit-latest 1.2.42+73\n", "submit-latest 1.2.42+73", "submit-latest\t1.2.42+73\n", "submit-latest 10.0+1\n"):
            version = request.split()[1]
            self.assertEqual(self.run_step(request)[:2], (["review-check", f"submit-latest {version}", "state"], 0), repr(request))

    def test_the_word_that_lets_a_waiting_submission_be_replaced(self):
        self.assertEqual(self.run_step("submit-latest 1.2.42+73 replace-waiting\n")[:2],
                         (["review-check", "submit-latest 1.2.42+73 replace-waiting", "state"], 0))

    def test_only_the_first_line_is_read(self):
        self.assertEqual(self.run_step("state\nasked again on 13 Nov 2026, to see whether 1.2.39 is approved\n")[:2], (["state"], 0))
        # The word under the version is a note like any other: nothing waiting is replaced.
        self.assertEqual(self.run_step("submit-latest 1.2.42+73\nreplace-waiting\n")[:2],
                         (["review-check", "submit-latest 1.2.42+73", "state"], 0))
        self.assertEqual(self.run_step("state\nsubmit-latest 1.2.42+73 replace-waiting\n")[:2], (["state"], 0))

    def test_anything_else_in_the_file_runs_nothing(self):
        for request in (
            "", "\n", "\nstate\n", "State\n", "delete\n", "state extra\n", "state 1.2.42+73\n", "review-check now\n",
            "state\r\n", "submit-latest 1.2.42+73\r\n",
            "submit-latest\n", "submit-latest latest\n", "submit-latest 1.2.42\n", "submit-latest +73\n", "submit-latest 1.2.42+\n",
            "submit-latest v1.2.42+73\n", "submit-latest 1.2.42+73a\n", "submit-latest 1..2+73\n", "submit-latest 1.2.42 + 73\n",
            "submit-latest replace-waiting\n", "submit-latest replace-waiting 1.2.42+73\n",
            "submit-latest 1.2.42+73 force\n", "submit-latest 1.2.42+73 replace\n", "submit-latest 1.2.42+73 Replace-Waiting\n",
            "submit-latest 1.2.42+73 replace-waiting now\n", "submit-latest 1.2.42+73 replace-waiting replace-waiting\n",
            "submit-latest 1.2.42+73 1.2.41+72\n",
            "submit-latest 1.2.42+73; echo pwned\n", "submit-latest $(id)+1\n", "submit-latest `id`+1\n", "submit-latest 1.2.42+73 && id\n",
            "submit-latest *\n", "submit-latest 1.2.42+73 *\n", "state; id\n", "state && id\n", "--help\n", "submit-latest --help\n",
        ):
            calls, code, output = self.run_step(request)
            self.assertEqual((calls, code), ([], 1), repr(request))
            self.assertIn("::error::.github/app-store-request.txt", output, repr(request))

    def test_no_request_file_runs_nothing_and_fails_nothing(self):
        calls, code, output = self.run_step(None)
        self.assertEqual((calls, code), ([], 0))
        self.assertIn("::notice::.github/app-store-request.txt is gone; nothing was asked.", output)

    def test_a_demo_account_that_no_longer_signs_in_stops_a_submission(self):
        self.assertEqual(self.run_step("submit-latest 1.2.42+73\n", fails="review-check")[:2], (["review-check"], 1))
        self.assertEqual(self.run_step("submit-latest 1.2.42+73 replace-waiting\n", fails="review-check")[:2], (["review-check"], 1))

    def test_state_is_printed_after_a_submission_that_stopped_and_the_step_still_fails(self):
        self.assertEqual(self.run_step("submit-latest 1.2.42+73\n", fails="submit-latest")[:2],
                         (["review-check", "submit-latest 1.2.42+73", "state"], 1))
        self.assertEqual(self.run_step("submit-latest 1.2.42+73\n", fails="state")[:2],
                         (["review-check", "submit-latest 1.2.42+73", "state"], 1))
        self.assertEqual(self.run_step("submit-latest 1.2.42+73\n", fails="submit-latest,state")[:2],
                         (["review-check", "submit-latest 1.2.42+73", "state"], 1))

    def test_a_failing_read_fails_the_step(self):
        self.assertEqual(self.run_step("state\n", fails="state")[:2], (["state"], 1))
        self.assertEqual(self.run_step("review-check\n", fails="review-check")[:2], (["review-check"], 1))

    def test_the_box_of_the_button_does_not_reach_a_push(self):
        self.assertEqual(self.run_step("submit-latest 1.2.42+73\n", replace_waiting="true")[:2],
                         (["review-check", "submit-latest 1.2.42+73", "state"], 0))

    # ---- started by hand (Run workflow) ------------------------------------------------------

    def test_by_hand_each_action_runs_as_chosen(self):
        hand = dict(event="workflow_dispatch", replace_waiting="false")
        self.assertEqual(self.run_step(None, action="state", **hand)[:2], (["state"], 0))
        self.assertEqual(self.run_step(None, action="review-check", **hand)[:2], (["review-check"], 0))
        self.assertEqual(self.run_step(None, action="submit-latest", **hand)[:2], (["submit-latest", "state"], 0))

    def test_by_hand_the_box_is_what_lets_a_waiting_submission_be_replaced(self):
        hand = dict(event="workflow_dispatch", action="submit-latest")
        self.assertEqual(self.run_step(None, replace_waiting="true", **hand)[:2], (["submit-latest replace-waiting", "state"], 0))
        for box in ("false", "", "True", "1", "yes"):
            self.assertEqual(self.run_step(None, replace_waiting=box, **hand)[:2], (["submit-latest", "state"], 0), box)

    def test_by_hand_the_box_means_nothing_to_the_other_actions(self):
        for action in ("state", "review-check"):
            self.assertEqual(self.run_step(None, event="workflow_dispatch", action=action, replace_waiting="true")[:2], ([action], 0))

    def test_by_hand_the_request_file_is_not_read(self):
        self.assertEqual(self.run_step("submit-latest 1.2.42+73 replace-waiting\n", event="workflow_dispatch", action="state",
                                       replace_waiting="false")[:2], (["state"], 0))

    def test_by_hand_a_submission_that_stopped_still_prints_state(self):
        self.assertEqual(self.run_step(None, event="workflow_dispatch", action="submit-latest", replace_waiting="false",
                                       fails="submit-latest")[:2], (["submit-latest", "state"], 1))


class TheWorkflow(unittest.TestCase):
    def test_the_step_reads_what_it_is_given_from_its_environment_only(self):
        script, given = step()
        # An expression in the script would be pasted into it before bash reads it.
        self.assertNotIn("${{", script)
        self.assertEqual(given["ACTION"], "${{ inputs.action }}")
        self.assertEqual(given["REPLACE_WAITING"], "${{ inputs.replace_waiting }}")
        self.assertEqual(given["EVENT"], "${{ github.event_name }}")
        self.assertEqual(sorted(given), ["ACTION", "ASC_ISSUER_ID", "ASC_KEY", "ASC_KEY_ID", "EVENT", "REPLACE_WAITING"])

    def test_it_runs_for_the_request_file_on_main_and_by_hand_and_for_nothing_else(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        triggers = text[text.index("\non:\n"):text.index("\npermissions:\n")]
        self.assertIn("  push:\n    branches: [main]\n    paths: [.github/app-store-request.txt]\n", triggers)
        self.assertIn("  workflow_dispatch:\n", triggers)
        self.assertNotIn("pull_request", triggers)
        self.assertNotIn("schedule", triggers)
        self.assertIn("\nconcurrency:\n  group: app-store-listing\n  cancel-in-progress: false\n", text)

    def test_the_text_reading_of_the_workflow_is_what_a_yaml_reader_sees(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("no YAML reader here")
        workflow = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        steps = workflow["jobs"]["listing"]["steps"]
        mine = next(s for s in steps if s.get("name") == "App Store listing")
        script, given = step()
        self.assertEqual(mine["run"], script)
        self.assertEqual(mine["env"], given)
        self.assertNotIn("shell", mine)
        self.assertNotIn("defaults", workflow)
        inputs = workflow[True]["workflow_dispatch"]["inputs"]      # YAML reads the key "on" as true
        self.assertEqual(inputs["action"]["options"], ["state", "review-check", "submit-latest"])
        self.assertEqual((inputs["replace_waiting"]["type"], inputs["replace_waiting"]["default"]), ("boolean", False))


if __name__ == "__main__":
    unittest.main()
