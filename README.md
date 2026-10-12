# foorsa_student

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## iOS release build

Validated locally with Flutter 3.47.5 and Xcode 27.0. The GitHub build uses
Flutter 3.47.5 and the newest stable Xcode on the `macos-26` runner (Xcode 26.6
in the September 2026 image), which meets Apple's Xcode 26 / iOS 26 SDK minimum
for uploads. iOS deployment target is 15.0. The project keeps CocoaPods
integration because the current splash plugin cannot resolve its Swift Package
Manager headers. Release device signing uses team G865J7CMBG and the
`Foorsa Student App Store` distribution profile.

### TestFlight from GitHub Actions

`.github/workflows/testflight.yml` builds the app on a GitHub macOS runner and
uploads it to TestFlight:

- **Release by bumping the version.** Merging a change to `version:` in
  `pubspec.yaml` into `main` (for example `1.2.17+34` to `1.2.17+35`) builds that
  version and uploads it. Other edits to `pubspec.yaml` do not release anything.
  Each build number uploads once; to ship again, raise it.
- **Or by hand.** Actions → TestFlight → Run workflow builds the branch you pick.
  Only a run on `main` uploads; untick "Upload the build to TestFlight" for a
  build that stops before TestFlight. Use it to retry a release whose automatic
  run failed ("Re-run jobs" would rebuild the old commit).
- A pull request that touches the workflow, `pubspec.yaml`, `pubspec.lock` or
  `ios/` runs the same build without uploading: signed when the secrets are set,
  unsigned otherwise.

Flutter analysis and tests run first, on Linux. Before building, an upload run
stops in seconds when App Store Connect already has the build number. After the
upload, the run waits until Apple has processed the build (usually under half an
hour), so a green run means the build is in TestFlight; a rejected build fails
the run, and the reason is in App Store Connect → TestFlight and in Apple's email.
Internal testers get the build automatically when their TestFlight group has
automatic distribution turned on.

The repository is public, so GitHub's macOS runners cost nothing. Its run logs
are public too: GitHub masks the four secrets below, the Key ID and Issuer ID
(variables) are printed but are useless without the `.p8`, and runs for pull
requests from forks get no secrets at all.

**First release after setting this up.** Merging the workflow does not touch
`pubspec.yaml`, so it uploads nothing by itself. Add the secrets and variables
below, then open Actions → TestFlight → Run workflow on `main` with the upload
box ticked: that uploads the version `main` is on (`1.2.17+34`). If App Store
Connect already has that build number, the run says so; bump the number and
merge instead.

**One-time setup** (repository Settings → Secrets and variables → Actions):

| Name | Kind | What to put in it |
|---|---|---|
| `IOS_DISTRIBUTION_P12` | Secret | The Apple Distribution certificate **with its private key**. On the Mac that holds it: Keychain Access → login → My Certificates → "Apple Distribution: … (G865J7CMBG)" (a key shows beneath it) → File → Export Items… → Personal Information Exchange (.p12), saved as `dist.p12`; then `base64 -i dist.p12 \| pbcopy`. If it is not under My Certificates, its key is not on that Mac: make a new Apple Distribution certificate and update the profile to use it |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Secret | The password chosen when exporting the `.p12`. It must not be empty: GitHub does not store an empty secret, and the workflow then treats signing as not set up |
| `IOS_PROVISIONING_PROFILE` | Secret | The `Foorsa Student App Store` profile from developer.apple.com → Certificates, Identifiers & Profiles → Profiles, base64-encoded: `base64 -i Foorsa_Student_App_Store.mobileprovision \| pbcopy` |
| `APPSTORE_API_PRIVATE_KEY` | Secret | The contents of `AuthKey_XXXXXXXXXX.p8` (`pbcopy < AuthKey_XXXXXXXXXX.p8`), from App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → + (created by the Account Holder or an Admin, with the App Manager role; the file downloads only once, and if the page shows Request Access the Account Holder clicks it first) |
| `APPSTORE_API_KEY_ID` | Variable | That key's Key ID (on the Variables tab) |
| `APPSTORE_ISSUER_ID` | Variable | The Issuer ID shown above the keys list (on the Variables tab) |

An upload run with any of these missing stops at once and names the missing
ones. Before building, the workflow also checks that the profile is the
`Foorsa Student App Store` one for `ma.foorsa.foorsaStudent`, that it has not
expired, and that it was made for the certificate in the `.p12`.

The certificate and the profile each last a year (every run's log prints the
profile's expiry). A renewed profile replaces only `IOS_PROVISIONING_PROFILE`;
keep its name. A new certificate means editing the `Foorsa Student App Store`
profile on developer.apple.com to use it and downloading the profile again, so
replace `IOS_DISTRIBUTION_P12`, `IOS_DISTRIBUTION_P12_PASSWORD` and
`IOS_PROVISIONING_PROFILE` together.

### Building on a Mac

The same build by hand, with that profile and its certificate installed:

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build ipa --release --build-name 1.2.17 --build-number 34 \
  --export-options-plist=/path/to/ExportOptions.plist
```

Use an App Store Connect export options file with manual signing and the profile
above (the workflow writes the same file). The production archive and IPA
completed successfully on 5 October 2026. Analysis reports five existing
informational lints. Physical-device permission testing is still required before
final submission.
