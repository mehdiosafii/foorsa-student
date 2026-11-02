# The App Store listing and App Review

Foorsa Student is app 6816127081 in App Store Connect (bundle `ma.foorsa.foorsaStudent`,
iPhone only). Its listing (name, subtitle, description, keywords, screenshots, age rating,
category, price and availability) and its App Privacy answers were filled in on 20 Oct 2026,
when 1.2.18 (45) was submitted. Unlisted App Distribution has been requested, and the version
is released by hand (`releaseType: MANUAL`): an approved version reaches nobody until someone
presses Release in App Store Connect.

On 2 Nov 2026, 1.2.18 (45) had been waiting for review since 20 Oct. It predates the iPhone
microphone permission (build 46), so on today's portal a reviewer opening the live chat's voice
note or the video studio would have crashed the app or been refused. The demo account it named
had stopped signing in too. The waiting submission was cancelled, and 1.2.38 (69) went up for
review in its place with the notes in `store/app-store/review-notes.txt`.

## The workflow

**Actions › App Store listing › Run workflow** (`.github/workflows/app-store-listing.yml`, which
runs `scripts/app_store_listing.py` with the team key the TestFlight workflow uses):

- **state** prints what App Store Connect holds: the version and its state, its text, how many
  screenshots of each size, the build attached, the review details (whether each is filled, never
  their values), availability, and every review submission with its items.
- **review-check** signs in to the portal with the demo account App Store Connect gives App
  Review, and prints what a reviewer meets: a password to change, the contract popup, the step of
  the file. It prints the review notes with the account's name and password masked.
- **submit-latest** puts the newest valid build up for review in place of the version waiting:
  it cancels the waiting submission, names the version after the build, attaches the build,
  writes `store/app-store/review-notes.txt` into the review details (`{version}` and `{build}`
  are filled in) and submits. The listing text, screenshots, age rating, demo account and manual
  release stay as they are.

App Privacy is not in Apple's API. A person signed in to App Store Connect with an Apple ID
fills it in (App Store Connect › the app › App Privacy), and it has to say what the app collects
today, including what it has started collecting since 20 Oct: voice notes and the introduction
video (Audio Data, Photos or Videos), the ID photo selfie, how the app is used (Product
Interaction) and crash reports (Crash Data).

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
