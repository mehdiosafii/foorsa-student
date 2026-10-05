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
G865J7CMBG and the `Foorsa Student App Store` distribution profile; install that
profile and its matching Apple Distribution certificate before archiving.

```sh
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --build-name 1.2.17 --build-number 32 \
  --export-options-plist=/path/to/ExportOptions.plist
```

Use an App Store Connect export options file with manual signing and the profile
above. The production archive and IPA completed successfully on 5 October 2026.
Analysis reports five existing informational lints; the placeholder test passes.
Physical-device permission testing is still required before final submission.
