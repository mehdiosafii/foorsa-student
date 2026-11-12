# The App Store listing and App Review

Foorsa Student is app 6816127081 in App Store Connect (bundle `ma.foorsa.foorsaStudent`,
iPhone only). Its listing (name, subtitle, description, keywords, screenshots, age rating,
category, price and availability) and its App Privacy answers were filled in on 20 Oct 2026,
when 1.2.18 (45) was submitted. The listing has one locale, `en-US`. The version was set to be
released by hand then (`releaseType: MANUAL`); on 12 Nov 2026 `state` read `AFTER_APPROVAL`, so
an approved version now goes out by itself. Read `state` before saying which it is.

On 2 Nov 2026, 1.2.18 (45) had been waiting for review since 20 Oct. It predates the iPhone
microphone permission (build 46), so on today's portal a reviewer opening the live chat's voice
note or the video studio would have crashed the app or been refused. The demo account it named
had stopped signing in too. The waiting submission was cancelled, and 1.2.38 (69) went up for
review in its place with the notes in `store/app-store/review-notes.txt`.

What followed was done in App Store Connect itself, not by this workflow (no run of it has
submitted since 2 Nov), and is known here only from what App Store Connect held on 12 Nov. Its
review notes, which **review-check** prints, say that Apple Developer Support approved Unlisted
App Distribution on 4 Nov, that the privacy labels and the privacy and deletion links were
updated that day, and that the build was resubmitted "following the November 2 review
instructions for Guideline 3.2". Its submissions show the one of 2 Nov submitted again on 4 Nov
(22:14 UTC) and since emptied, and a new one on 6 Nov, which is 1.2.39 (70).

On 12 Nov 2026 (12:42 UTC), 1.2.39 (70) had been waiting for review since 6 Nov (submitted at
15:50 UTC), and no version had been approved yet; 1.2.40 (71), 1.2.41 (72) and 1.2.42 (73) went
to TestFlight only, and 1.2.42 (73) was the newest valid build.

Asked that day whether a newer build should take its place, the owner kept it: "keep same for
apple review when accepted we will push an update". So the newest build goes up as an update
once 1.2.39 is approved and on sale, each time on the owner's word: **submit-latest** makes the
update then (below), and until then it refuses, because a submission is waiting.

## The workflow

**Actions › App Store listing › Run workflow** (`.github/workflows/app-store-listing.yml`, which
runs `scripts/app_store_listing.py` with the team key the TestFlight workflow uses):

- **state** prints what App Store Connect holds: the versions, newest first, and their states;
  the newest one's text, how many screenshots of each size, the build attached, the review
  details (whether each is filled, never their values) and whether its review notes are the
  ones the repository writes; what would stop an update's "What's New"; the builds, and the
  newest valid one as a submission names it (`1.2.42+73`); availability; the latest review
  submissions with what each holds, and how many are still open.
- **review-check** signs in to the portal with the demo account App Store Connect gives App
  Review, and prints what a reviewer meets: a password to change, the contract popup, the step of
  the file. It prints the review notes with the account's name and password masked.
- **submit-latest** puts the newest valid build up for review. What that takes depends on where
  the newest App Store version stands:

  | The newest version is | submit-latest |
  | --- | --- |
  | on sale (`READY_FOR_SALE`) | makes the update: a new version named after the build, with the release the version on sale has (by itself once approved, or by hand) and its copyright; writes "What's New" in each locale; then the row below. The new version takes the listing's text and screenshots from the one on sale. |
  | being prepared, or taken back (`PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `INVALID_BINARY`, or rejected with its submission since withdrawn) | names the version after the build, attaches the build, writes `store/app-store/review-notes.txt` into the review details (`{version}` and `{build}` are filled in; the contact and the demo account stay as they are) and submits. When an earlier version is on sale it is an update, and "What's New" is written too. |
  | waiting for review | changes nothing, unless **replace-waiting** is asked for (the box of the button, or the word after the version in the request file). Then the waiting submission is read once more, cancelled if it is still waiting, and the row above follows. The wait for review starts again: ask the owner each time. |
  | in review | changes nothing, ever. |
  | sent back by App Review and not answered (`REJECTED`, `METADATA_REJECTED`; its submission is `UNRESOLVED_ISSUES`) | changes nothing: how to answer is decided in App Store Connect (App Review), where Apple's messages are. Reply there, or change the version there and resubmit it, as was done on 4 Nov 2026. |
  | approved and not yet on sale (`PENDING_DEVELOPER_RELEASE`, `PROCESSING_FOR_APP_STORE`, …) | changes nothing: Apple makes no new version until the one before it is on sale. Release it, or wait, then ask again. |

  It also changes nothing when the build is the one already on sale or already waiting. What it
  reads from the repository is checked against the listing before the first write, and a
  refusal says what to do. The listing's text, screenshots, age rating and categories stay as
  they are. **state** is printed after it, whether it went through or stopped part-way; a run
  that stopped part-way (Apple's answer is in the log) is finished by asking again.

  A review submission that was made and never submitted cannot be cancelled (a run that
  stopped at its last step leaves one, and so does "Add for Review" in App Store Connect). An
  empty one is taken up; the version is taken out of one that holds only it, then put up again;
  one that holds anything else stops the run before it writes, since that is someone's work in
  App Store Connect.

**Without the button.** A session that cannot start a workflow by hand asks through
`.github/app-store-request.txt`, as `.github/google-play-promote.txt` does for Google Play: a
push to `main` that changes the file runs what its first line names, `state`, `review-check`,
`submit-latest 1.2.42+73` or `submit-latest 1.2.42+73 replace-waiting` (12 Nov 2026, when GitHub
refused such a session the button). A submission asked for this way names its version and
changes nothing unless the newest valid build is exactly that one, so a line left in the file
can never send up a later build; and it runs **review-check** first and stops there if the demo
account no longer signs in. Wait for the TestFlight run of that version to be green before
asking: only then is the build valid. The workflow runs only when the file changes, and nothing
under its first line is read: a note there (who asks, when) is how the same thing is asked
twice, such as `state` on two days running.

## An update's "What's New"

Apple refuses an update without "What's New" in every locale of the listing, and refuses the
text on an app's first version, which is why none was written before. It is kept in
`store/app-store/whats-new/<locale>.txt`, one file per App Store locale, as
`android/play-release-notes/` holds Google Play's notes: `en-US.txt` today. It says what a
student gets on iPhone since the version on sale, so it is written again for each update, and it
names no other platform (App Review refuses App Store text that does). **submit-latest** stops
before writing anything when a locale of the listing has no file or an empty one, when a file is
over 4000 characters or still the text the version on sale went out with, or when a file is for a
locale the listing does not have (a language is added in App Store Connect, with its description
and screenshots). **state** shows the same.

## The review notes

`store/app-store/review-notes.txt` is what a submission writes, over whatever App Store Connect
holds. The notes can also be edited there by hand, as they were on 4 Nov 2026 (the paragraph on
Unlisted App Distribution): **state** says whether the two are the same text, and
**review-check** prints App Store Connect's. Bring the file up to date before a submission, or
the hand's edit is lost. The file took in the approval of Unlisted App Distribution on 12 Nov.
Two lines of 4 Nov that spoke of that day's resubmission were left out: an update is not that
resubmission, and with both the notes pass App Store Connect's 4000 characters (3905 for
1.2.42 (73) as the file stands).

App Privacy is not in Apple's API. A person signed in to App Store Connect with an Apple ID
fills it in (App Store Connect › the app › App Privacy), and it has to say what the app collects
today. The review notes say it was brought up to date on 4 Nov 2026. Since then, from 1.2.40,
an iPhone sends Foorsa Apple's own push token where it used to send only Firebase's and the one
for calls (docs/student-push.md); 1.2.41 and 1.2.42 collect nothing new.

## The demo account

App Review signs in as **SAM DEMO**, a fictional applicant in the CRM (applicant 5399, stage
`Test`, Non-Foorsa, so it counts in no board or pay). The user name is its passport number and the
password is the one in App Store Connect › App Review Information › Sign-In Information. The two
must stay the same: on 2 Nov 2026 the account's password no longer matched App Store Connect's,
and every reviewer would have been turned away at sign-in. It was set back from App Store
Connect's (only its bcrypt hash crossed over) and the change is audited on the applicant.

Run **review-check** before any submission. If it says the demo account no longer signs in, give
the account App Store Connect's password again (or change both together), and keep the account
off the contract popup: today it opens straight on Home.

The demo signs in with a password, which the portal still offers under the email field ("Sign in
with a password"); students sign in with a link or a code sent to their card's email.

A new version takes the review details of the one before it. App Store Connect's site copies
the contact, the demo account and the notes into it; whether its API does has not been seen
yet, so where it has not after a minute, **submit-latest** copies the contact and the demo
account itself, and **review-check** tries the account of the version before. Nothing of them
is printed: **review-check** masks them in the notes, and they are taken out of any answer of
Apple's that the log shows.

## The tests

`scripts/tests` holds the script against a stand-in for App Store Connect
(`fake_app_store_connect.py`, which keeps the rules of Apple's that decide the order of a
submission's writes) and the workflow's shell step with a stub in the script's place, run by
`bash -e` as GitHub runs it. Nothing in them reaches Apple. **App Store listing checks** runs
them on a pull request that touches the script, the workflow, the tests or `store/app-store`.

```sh
python3 -m unittest discover -s scripts/tests -v
```

With Apple's OpenAPI specification at hand (the zip at
https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip),
every request the script makes in them is also checked against it:

```sh
ASC_OPENAPI=/path/to/openapi.oas.json python3 -m unittest discover -s scripts/tests -v
```

The stand-in is a reading of Apple's documentation, not Apple. Until the first update has gone
up, these have only ever been tried against it: making a version, writing "What's New", copying
review details into a version that has none, taking up an empty submission, and taking a version
out of one. Whether a new version has its locales and review details at once, or a moment
later, is not known either: the run waits up to a minute for each. Read the log of the first
real run with that in mind.
