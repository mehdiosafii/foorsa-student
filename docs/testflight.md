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

## PDF crash regression (build 25)

Build 24's PDF viewer (flutter_pdfview 1.3.2) crashes on current iOS when creating the native view: `NSInternalInconsistencyException: View was already initialized`. Reproduced on iOS 27 with a valid one-page PDF through `_PdfPreviewPage`. Version 1.3.3 removes the duplicate native view initialization.

Build 25 pins that patch and rejects empty/non-PDF downloads before opening PDFKit. The header check is deliberately not a full structural validator; native error callbacks still handle malformed PDF structure. Unit tests cover PDF headers, an HTML login response, and empty downloads. Authenticated document testing on the tester's phone remains necessary.
- After the patch, the same PDF renders and remains open in the iOS 27 simulator; no duplicate-initialization exception occurs.

## Adaptive launcher icon (build 26)

Removed the baked-in circular ring from the launcher artwork. Added iOS dark and tinted appearances, Android adaptive foreground and monochrome layers, and a night-mode adaptive background. Default iOS artwork is opaque; dark artwork retains transparency for the system background. Asset generation instructions are in `assets/icons/README.md`.

## White icon background (build 27)

Default and dark iOS icons now use identical opaque white-background artwork. The tinted source also has a white base, though system tint settings can recolor it. Android day/night backgrounds are both white and the optional monochrome layer is removed. Generated iOS background pixels were checked as opaque white for all three appearances.
