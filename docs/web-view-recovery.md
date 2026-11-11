# When the portal's page dies or a load fails

The owner, 31 Oct 2026: "after uploading one file or two the app is a bit
sluggish make sure it's functioning smoothly across all your interactions and
upload without sudden crashes or freezing or going back to home screen".

Until 1.2.30 (61) three things in the shell sent a student back to Home or out
of the app:

- **Android**: a web view whose render process was killed for memory took the
  whole app down, because the shell did not handle `onRenderProcessGone`
  (`useOnRenderProcessGone` was off, so WebView's default killed the app).
- **iPhone**: when iOS ended the page's web content process (memory, most often
  after big uploads), the web view stayed blank (no
  `onWebContentProcessDidTerminate`).
- **Both**: any main-frame load the app or the page stopped on purpose (a file
  download taken by `onDownloadStartRequest`, a link handed to another app, a
  newer navigation) reached `onReceivedError` and read as being offline; the
  offline screen's retry then loaded `AppConfig.baseUrl`, which is Home.

Now (`lib/src/web_view_recovery.dart`, wired in `shell_page.dart`):

- The shell remembers the last portal page the student was on
  (`onUpdateVisitedHistory`, `onLoadStop`; never another site, never a one-time
  link's `token`), and every reload and retry goes there, not Home.
- iPhone: a terminated content process reloads that page. Android: a gone
  render process rebuilds the web view (`_webViewGeneration`) on that page.
  After three deaths in two minutes the offline screen and its retry take over
  instead of a reload loop.
- `isLoadFailure()` ignores iOS -999, WebKit 102 and 204, and Android's
  `net::ERR_ABORTED`; only a real failure shows the offline screen.
- Each death is reported to the crash board (Admin Portal › Student App in
  foorsa-reward) as `Web view stopped: …` with the page's first two path
  segments, the build and the iOS version (`lib/src/crash_reports.dart`,
  `POST /api/portal/client-error`, `source: 'shell'`), and uncaught Dart errors
  are reported the same way. Nothing about the student is sent; the server
  cleans the text again. Before 1.2.30 the shell reported nothing.

`test/web_view_recovery_test.dart` and `test/crash_reports_test.dart` pin it.
What the page itself holds in memory during uploads is the portal's side
(foorsa-reward, `src/portal/`).

## A web view that could not be created (1.2.34, 65)

The owner, 1 Nov 2026: "in android the app still freezes". The crash board held
22 Android reports that day, on every build from 1.2.30 to 1.2.33, all one
line: `PlatformException(error, android.webkit.WebSettingsWrapper cannot be cast
to com.android.webview.chromium.ContentSettingsAdapter …)`. On those phones the
installed Android System WebView refuses every `androidx.webkit` settings call,
and the web view plugin makes such calls while the web view is created, so it
was never created: the app stayed on its loader, and nothing on screen said why.
There were only 4 Android sessions that week.

- The app now builds the plugin from a copy whose settings calls are guarded
  (`third_party/flutter_inappwebview_android`, `third_party/README.md`).
- A web view that still has not said it was created after
  `webViewStartLimit` (15 s) hands over to the offline screen, whose retry makes
  a new one, and reports `Web view stopped: not created in time`
  (`_watchWebViewStart` in `shell_page.dart`).
- Reports from Android now carry the system (`Android 16`) and, where a report
  names no place of its own, the WebView's version (`WebView 142.0…`), from the
  `foorsa/system` channel (`MainActivity.kt`, `CrashReports.describeAndroid`).
- `offscreenPreRaster` is off: it kept every tile of the page in view rastered
  on top of what the page holds, in a web view the phone closes when it grows
  too large.
- A file for the portal (a photo picked, a scan) is turned into its data URL
  off the UI isolate (`bridge_files.dart`): ten photos from the library at a
  time held the app's frames while each was encoded.

## A slow load is not offline (1.2.40)

On the offline screen the retry ticks every 6 s, and each tick loaded the page
again, cancelling the load before it. On a connection where the portal's first
load takes longer than that (from mainland China it was 2 to 10 s, 6 Nov 2026),
no load ever finished and the student sat on "No internet connection" with a
network that worked. `_retry()` now leaves a load under way alone for
`retryLoadPatience` (45 s, `shouldRetryLoad`), counted from `onLoadStart` and
cleared by `onLoadStop` or a main-frame error.

## The stress test of 11 Nov 2026

The owner, 11 Nov 2026: "stress test the app, so we can detect all the
crashes, and all possible failures". What it found in the shell's own part,
each pinned by a test that fails on the code as it was:

- **The start watch counted time the app could not draw.** The fifteen
  seconds of `webViewStartLimit` ran whatever the app was doing. An app started
  without being shown, or left in its first seconds, draws no frame, so no web
  view is even asked for; the watch still ended, reported `Web view stopped:
  not created in time` and put "No internet connection" up for a student who
  had one. The crash board's thirteen such reports of 1 to 8 Nov (every build
  from 1.2.34 to 1.2.40, in pairs seconds apart, none with an error beside it)
  have that shape: a device farm starting each new build unseen. Now
  `WebViewStartWatch` (`web_view_recovery.dart`) counts only while the app is
  on screen (`appCanDraw`), starts again when it comes back, and does not
  believe a watch that ended late by the phone's clock (the app was
  suspended).
- **The retry made a new web view every six seconds while there was none.**
  One that needed longer than that was thrown away before it finished, each
  time. `_retry()` now leaves a web view being made its fifteen seconds
  (`WebViewStartWatch.mayRebuild`), as `shouldRetryLoad` does for a page, and
  makes none while the app is away.
- **A download or a preview had no time limit.** `shell_page.dart` fetched
  the file with a bare `HttpClient`: on a connection that stalls mid-file the
  loader stayed over the app for good, and an iPhone has no back button.
  `fetchToFile` (`file_fetch.dart`) gives the server 15 s to connect and 30 s
  without a byte, closes the connection whatever happens and removes a
  half-written file. The portal already falls back to the phone's browser
  when the app does not answer `{ ok: true }`.
- **The loader was taken away with `Navigator.pop()`.** On Android a student
  who pressed back while it showed had closed it already; when the file
  arrived the pop took the app's own page and left a blank app. `ShellSpinner`
  removes its own route and no other. The "Set up your device" reminder had
  the same fault (`device_access.dart`): Allow's answer and the resume after
  the system prompt both found every access granted and both popped. It now
  closes once, its Continue is never off, and a system prompt that never
  answers (Android, when one is interrupted) no longer leaves its buttons
  dead.

`test/web_view_recovery_test.dart`, `test/file_fetch_test.dart`,
`test/shell_spinner_test.dart` and `test/device_access_test.dart` pin them.
What only a phone can confirm: that a real slow phone's first web view now
finishes, and the loader and the reminder under the phone's own back button
and prompts.
