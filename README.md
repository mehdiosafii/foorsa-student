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

Validated with Flutter 3.47.5 and Xcode 27.0. iOS deployment target is 15.0.
The project keeps CocoaPods integration because the current splash plugin cannot
resolve its Swift Package Manager headers. Release device signing uses team
G865J7CMBG and the `Foorsa Student App Store` distribution profile.

### TestFlight from GitHub Actions

`.github/workflows/testflight.yml` builds the app on a GitHub macOS runner and
uploads it to TestFlight:

- **Release by bumping the version.** Merging a change to `version:` in
  `pubspec.yaml` into `main` (for example `1.2.17+34` to `1.2.17+35`) builds that
  version and uploads it. Other edits to `pubspec.yaml` do not release anything.
  The build number must be higher than every build already in App Store Connect.
- **Or by hand.** Actions → TestFlight → Run workflow builds `main`'s current
  version. Untick "Upload" for a build that stops before TestFlight.
- A pull request that edits the workflow runs the same build without uploading.

Flutter analysis and tests run first, on Linux. App Store Connect then takes 10 to
30 minutes to process the upload. Internal testers get the build automatically when
their TestFlight group has automatic distribution turned on. The repository is
public, so GitHub's macOS runners cost nothing, and secrets never appear in the logs.

**One-time setup** (repository Settings → Secrets and variables → Actions):

| Name | Kind | What to put in it |
|---|---|---|
| `IOS_DISTRIBUTION_P12` | Secret | The Apple Distribution certificate with its private key, exported from Keychain Access as a `.p12`, base64-encoded: `base64 -i dist.p12 \| pbcopy` |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Secret | The password chosen when exporting the `.p12` |
| `IOS_PROVISIONING_PROFILE` | Secret | The `Foorsa Student App Store` profile from developer.apple.com → Profiles, base64-encoded: `base64 -i Foorsa_Student_App_Store.mobileprovision \| pbcopy` |
| `APPSTORE_API_PRIVATE_KEY` | Secret | The whole `AuthKey_XXXXXXXXXX.p8` file, from App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys (role App Manager; the file downloads only once) |
| `APPSTORE_API_KEY_ID` | Variable | That key's Key ID |
| `APPSTORE_ISSUER_ID` | Variable | The Issuer ID shown above the keys list |

The workflow checks that the profile is the `Foorsa Student App Store` one for
`ma.foorsa.foorsaStudent` before building, and stops with a message naming
anything that is missing. When the certificate or the profile is renewed, replace
its secret.

### Building on a Mac

The same build by hand, with that profile and its certificate installed:

```sh
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --build-name 1.2.17 --build-number 34 \
  --export-options-plist=/path/to/ExportOptions.plist
```

Use an App Store Connect export options file with manual signing and the profile
above (the workflow writes the same file). The production archive and IPA
completed successfully on 5 October 2026. Analysis reports five existing
informational lints. Physical-device permission testing is still required before
final submission.
