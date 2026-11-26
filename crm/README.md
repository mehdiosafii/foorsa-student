# Foorsa CRM

The Foorsa team's app: the CRM at https://home.foorsa.ma in a native shell, on iPhone, iPad,
Apple-silicon Macs (the iPad app) and Android. Windows and Intel Macs install the same CRM as a web
app ("Foorsa CRM", from the browser, or the Microsoft Store package made from it).

| Platform | Identifier | Channel |
|---|---|---|
| iPhone, iPad, Apple-silicon Mac | `ma.foorsa.crm` | TestFlight, internal group "Foorsa team" (no App Review) |
| Android | `com.foorsa.app` | Google Play internal testing |

It is its own Flutter project inside this repository so it can use the same Apple and Google
credentials, the patched Android web view (`../third_party/flutter_inappwebview_android`) and the
iPhone touch fix (`lib/src/web_view_touch.dart`, a copy of the student app's: change both together).

## What the shell does

- Loads home.foorsa.ma with `FoorsaApp FoorsaCrmApp` in its User-Agent. Foorsa addresses stay in the
  app; anything else (WhatsApp, maps, Google Meet, a phone number) opens in its own app.
- `FoorsaBridge` (the CRM's `src/lib/nativeBridge.ts`):
  - `appInfo`: platform, version, build.
  - `getPushToken`: Apple's device token as `apns:<hex>` on iPhone and iPad, the Firebase token on
    Android. The CRM files it with `POST /api/push/register-device` and sends staff pushes to it.
  - `signInInBrowser {method}`: Google and passkeys, which a web view cannot do, in
    ASWebAuthenticationSession or a Custom Tab. The browser hands a one-time code back on
    `foorsacrm://signed-in`, and the web view redeems it with a secret only the app holds (RFC 7636
    S256; the CRM's `server/routes/native-sign-in.routes.ts`).
  - `saveFile`, `print`, `openExternal`: files the page makes (blob and `data:` downloads, Excel and PDF
    exports) are saved to the app's Downloads folder and opened; `window.print` prints the page.
- `FoorsaShellTheme`: the status bar follows the CRM's header colour.
- Camera, microphone and location for Foorsa pages only (calls, scans, attendance).
- A notification tap opens its route in the app.
- Offline and crashed-web-view screens recover by themselves.

## Releases

Bump `version:` in `crm/pubspec.yaml` on `main`:

- `crm-testflight.yml` builds the iPhone and iPad app on the `xcode-27` runner, signs it in the cloud
  with the App Store Connect API key, uploads it to TestFlight and gives the "Foorsa team" internal
  group access. Pull requests build and sign without uploading. Until the App Store Connect app
  record exists, an upload run stops after signing with a warning; once it exists, start the first
  upload with Run workflow in the Actions tab.
- `google-play.yml` (`crm-version`, `crm-publish`) builds the Android bundle with the release keystore
  and sends it to the internal testing track. Google's Workload Identity trusts only that workflow.
  Until the Play Console app exists, the run saves the bundle and ends with a warning.

TestFlight builds expire after 90 days: bump the version at least every two months.

### One-time store setup

1. App Store Connect: create the app "Foorsa CRM" for bundle `ma.foorsa.crm` (the workflow creates the
   bundle id and its Push and Associated Domains capabilities; Apple's API cannot create the app
   record). Invite the team as App Store Connect users and add them to "Foorsa team".
2. Play Console: create the app for `com.foorsa.app`, upload the first bundle by hand (the
   `foorsa-crm-google-play-<commit>` artifact of `google-play.yml`), and add the team's emails to internal testing.
3. Windows: in Partner Center (free company account), package https://home.foorsa.ma with PWABuilder.

## Develop

```bash
cd crm
flutter pub get
flutter analyze && flutter test
flutter run --dart-define=FOORSA_CRM_URL=https://home.foorsa.ma
```

`tool/make_icons.py` makes every icon from `store/app-icon-1024.png`.
