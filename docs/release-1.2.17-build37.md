# Foorsa Student1.2.17 (37)

Build37 retains the exact-origin/native-frame checks, bounded document transfers and expanded privacy manifest described in release-1.2.17-build36.md.

Download and retry feedback now expires during normal navigation and has an explicit close control. Accessible navigation (including VoiceOver) retains the Open/Retry action until dismissed, avoiding a four-second accessibility limit.

Initial WebView loading now has a45-second deadline. A slow attempt reveals the underlying page and offers a dismissible, neutral notice with explicit Retry. Retry recreates the platform view while retaining persistent website data. Initial WebKit termination offers recovery; completed sessions are never automatically reloaded by this deadline. Error retries wait for an actual error before scheduling again, so they do not repeatedly interrupt a slow in-flight load. Intro, startup and retry timers are cancelled on disposal.

Validation: Flutter analysis passed. Existing transfer/navigation tests passed (nine in the main selection, two origin-policy tests separately after correcting a test filename). Six focused startup lifecycle tests passed, covering deadline, late success, error cancellation, fresh retry, termination and disposal. Native Swift origin checks passed before these Dart-only changes. A simulator/release rebuild and updated signing evidence are required after the final source commit.

The earlier build37 simulator session verified populated Student home/documents, saving a sample PDF, dismissing save feedback and embedded CSCA practice through answer feedback and progression. The accessibility/startup refinements were made after that session; do not claim their native validation from those captures. The iPad simulator stalled while the16GB host was under severe memory pressure; device-control recovery was unreliable. The captured screens use the same normal UI, but the remaining iPad/role/permission walkthrough is still required.

App Store Connect has not received this candidate. PR10 stays draft/unmerged because merging to main automatically uploads TestFlight. Last verified Apple submission remains rejected1.2.17 (33). App Store Connect access is blocked by automatic approval review; no alternate browser/API/workflow has been used to bypass it.
