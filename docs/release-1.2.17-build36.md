# Native hardening — 1.2.17 (36)

Base: 6248b3ce3ec3c657b60d3670eabba550cea529ff. Candidate source is prepared
for review; no App Store Connect upload or distribution archive was created.

## Changes

- Top-level internal navigation now uses exact HTTPS student.foorsa.ma,
  foorsa.ma, and www.foorsa.ma origins. Shared-hosting suffixes and arbitrary
  Foorsa subdomains are no longer trusted. Native camera/location callbacks
  accept only the exact HTTPS student portal origin.
- CSCA (csca.foorsa.ma), HSK (hsk.foorsa.ma, hsk.guide) and current YouTube
  embeds remain in frames. Unknown frames are cancelled without launching an
  external app. These embedded origins receive no Foorsa native bridge access.
  Sources checked: adjacent portal LearnScreen.tsx, portal-learn.routes.ts,
  UniversityGallery.tsx, KitchenLibrary.tsx and PortalRoot.tsx.
- Vendored flutter_inappwebview_ios 1.1.2 checks WebKit's native frameInfo:
  Foorsa-prefixed handlers require a main frame, HTTPS, student.foorsa.ma and
  default/443 port. See third_party/flutter_inappwebview_ios/FOORSA_PATCH.md.
- Preview/save transfers share connection (15 s), response (20 s), body-idle
  (20 s) and total (60 s) deadlines. Expiration force-closes the client;
  temporary partial files are cleaned up; only completed files replace targets.
  Both modal paths dismiss their specific dialog in finally and offer a clear
  error with retry. Preview busy state always resets.
- Added confirmed linked, non-tracking, app-functionality privacy categories:
  physical address, emails/text messages, customer support, product interaction,
  other diagnostic data. Local-only prayer location is not declared collected.
  Official enum and purpose definitions checked at:
  https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype
  https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes

## Verification, 2026-10-15

- `flutter analyze`: no issues. Unchanged upstream vendored code is excluded
  from the application's lint rules; its Swift code is compiled in the build.
- `flutter test`: 12 tests passed (including the pre-existing placeholder).
  Meaningful tests cover exact origin policy, retained learning/video frames,
  successful PDF transfer, failed HTTP plus retry, stalled TLS handshake,
  stalled response headers/body and continuous trickle bounded by total timeout.
  Partial staging files are checked for cleanup and existing files preserved.
- Compiled/executed the Swift native policy test: main-frame/default-port and
  explicit-443 accepted; same-origin iframe, foreign frames/hosts, HTTP and
  nondefault ports rejected.
- `flutter build ios --simulator --debug`: succeeded. Built app metadata:
  ma.foorsa.foorsaStudent, 1.2.17, 36. Built privacy manifest has all 12 categories.
  Compiled Dart asset is newer than the final app-source modifications.
- Dart package resolution and CocoaPods plugin symlink point to the local
  vendored directory. Generated Pods project includes FoorsaBridgePolicy.swift
  in Sources. Shared pub cache was not modified.
- Privacy plist validation and `git diff --check` pass. Flutter-generated
  LLDB scheme additions were removed from this isolated worktree only; the
  original review worktree and its pre-existing scheme edits were not touched.

## Remaining verification

This is a successful simulator compile and automated policy/network test result,
not a claim of physical-device readiness. Real WKScriptMessage rejection from
an attacker frame, normal camera/file picker flows, embedded lesson/video
playback, PDF/image preview and save, permission denial/revoke, iPhone/iPad
rotation, offline recovery and background/resume still require interactive
verification on the exact release candidate. No signed build-36 archive was
exported here. Android's upstream JavaScript bridge is unchanged by the
specifically iOS-native guard.
