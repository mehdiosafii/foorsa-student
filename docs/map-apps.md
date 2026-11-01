# Map apps on the phone

The student portal shows a place (a university, the consulate in Rabat) on a real map, with
**Open in maps** under it (foorsa-reward: `src/portal/OpenInMaps.tsx`, `shared/mapApps.ts`). The
owner, 1 Nov 2026: "open on whatever maps he have in his phone".

- The portal opens a map app through `FoorsaShellOpenUrl`, as it opens any outside address: this
  build answers `true` once the phone opened it and rejects when nothing on the phone can, so the
  portal tries the app's own address first and its web page when it is missing. That works on
  every build since 1.2.17 (35).
- **`FoorsaShellMapApps`** (`lib/src/map_apps.dart`) answers `{ apps: [...] }`, the map apps the
  phone has among `google`, `amap`, `baidu` and `waze`, so the sheet lists only those (Apple Maps
  on an iPhone and Android's own chooser are always offered). The portal asks only builds whose
  `FoorsaShellCapabilities` answer `mapApps: 1`.
- An iPhone is asked with each app's scheme: `canOpenURL` answers only for schemes in
  `LSApplicationQueriesSchemes` (`Info.plist`: `comgooglemaps`, `iosamap`, `baidumap`, `waze`).
- Android is asked by package (`MainActivity.kt`, channel `foorsa/map_apps`, method `installed`):
  Android 11 and later see only the packages in the manifest's `<queries>`
  (`com.google.android.apps.maps`, `com.autonavi.minimap`, `com.baidu.BaiduMap`, `com.waze`). A
  scheme would not do there: Dart's `Uri` lowercases the host (`androidamap://viewMap` becomes
  `viewmap`), and Android matches an intent filter's host case by case.
- `test/map_apps_test.dart` holds both lists to the ones in `map_apps.dart`.
- The answer names apps, never anything about the student, and is never stored.
