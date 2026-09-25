# TestFlight release

- App: Foorsa Student (App Store Connect ID `6816127081`)
- Bundle ID: `ma.foorsa.foorsaStudent`
- Team: foorsa llc (`G865J7CMBG`)
- Toolchain: Flutter 3.47.5 / Dart 3.13.4, Xcode 27, CocoaPods 1.17
- Minimum iOS: 15.0
- Distribution profile: `Foorsa Student App Store`

Install the team's Apple Distribution identity and provisioning profile before building. Do not commit private keys, certificates, or profiles.

```sh
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

The version and build number come from `pubspec.yaml`. Increment the build number for each subsequent upload. Upload the resulting IPA with Xcode Organizer, Transporter, or `xcrun altool` using authorized App Store Connect credentials.

The project uses CocoaPods because its current native plugins are not all compatible with Swift Package Manager. Camera support is enabled in the Podfile. The app's encryption consists of standard platform/network encryption; `ITSAppUsesNonExemptEncryption` is false.

Before each release, smoke-test launch and portal sign-in on iOS, then verify camera document capture on a physical device, file upload, document preview/download, and external links. The repository's existing automated test is only a placeholder and does not validate these flows.

## Initial release validation (1.2.15, build 24)

- `flutter analyze`: no issues.
- Existing `flutter test`: passes (placeholder coverage only).
- Signed iOS archive and App Store export: succeeded.
- iPhone 18 Pro simulator on iOS 27: app remains running and displays the Foorsa Student portal sign-in page.
- Authenticated student flows and physical-device camera capture still require a student test account/device.
