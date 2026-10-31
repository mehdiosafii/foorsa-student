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
