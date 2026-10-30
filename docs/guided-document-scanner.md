# Custom iPhone document scanner

## Live text reading and the right-document gate (custom-live-v12)

The owner asked (30 Oct 2026) for the scan to capture by itself, with no tap,
once the document is stable and is the right document, and for the text to be
read while the page is in view, so nothing is missed when the scan finishes.

**How the page is read.** While the camera is open the page in view is read on
the phone a few times a second, never on a server.

- iPhone: Vision (`ScannerLiveTextReader.swift`), on its own `.utility` queue,
  so the preview and the outline detection never wait for it. Each read crops
  the detected page with a 10% margin from one preview frame (perspective
  corrected), holds the camera's buffer only while that crop is drawn, then
  runs `VNRecognizeTextRequest` (language correction off; the default revision,
  2 on iOS 15): `.fast` at most every 0.25 s while the page is framed,
  `.accurate` at most every 0.35 s once it is ready, and less often on a slow
  phone (1.5 times the last read). Cards and papers also run the script-blind
  `VNDetectTextRectanglesRequest`, so Arabic or Chinese print counts as text.
  Passports and cards are read with their long side across, upright and then
  upside down until the machine lines are found; papers as seen, then turned
  a quarter each way, then kept as seen.
- Android: ML Kit's Latin text model, **bundled in the app**
  (`com.google.mlkit:text-recognition:16.0.1`; `LiveTextReader.kt` on the
  `foorsa/live_text` channel), fed the camera's Y plane cropped round the
  page the luma analyzer found (`live_text_reader.dart`), one read at a time,
  at most every 0.3 s. It works offline and in China: no model download, no
  Google Play services. Never swap in `play-services-mlkit-text-recognition`,
  which downloads its model at runtime.

The rules are pure and identical on both platforms:
`ios/Runner/ScannerTextReading.swift` and
`lib/src/guided_scanner/scan_text_reading.dart` mirror each other rule for
rule and are tested with the same samples (`tools/scanner_text_reading_tests.swift`
in the macOS CI job, `test/scan_text_reading_test.dart`).

**The gate.** Automatic capture still needs everything it needed before (the
steady hold, sharpness, focus and exposure settling, the lighting grace; none
of it was loosened) and now also the reading:

| Paper (`documentKey`) | The reading passes when |
|---|---|
| Passport (`identity`) | the photo page's two machine-readable lines (ICAO 9303 TD3, 2 × 44) read with every check digit valid (document number, birth date, expiry, personal number, composite), real dates, the `P` line above, and two reads agreeing |
| Parents' ID cards (`parent_id`) | the back's three lines (TD1, 3 × 30) with valid check digits and two agreeing reads; or the front: the card number (a Moroccan CIN such as `AB123456`, or eight digits for a Tunisian card) read twice, plus "ROYAUME DU MAROC"-style words, three readable Latin lines or five lines of print. With `side` set only that side passes; the other asks to turn the card over |
| Every other paper | three rows of text inside the page, in two reads, and no text running past the page's detected edge or the frame |

Characters are voted across reads position by position (`ScannerMRZVotes`), so
one bad frame does not block a passport and one lucky frame does not pass it.
Each position is read in its own alphabet (an `O` in a date is a zero, a `0`
in a name an `O`); a filler gained or lost in a run is repaired when the check
digits then pass; in a field that holds letters and digits (document and
personal numbers) a look-alike is repaired only when its check digit accepts
exactly one repair, with characters other reads actually saw breaking a tie.
A passport's or an ID card's valid machine lines in a diploma's (or any
paper's) step read as a different paper; visa documents, other documents and
previous Chinese university papers are exempt, since they may carry such lines.

**A clear page does not wait on the reading for long** (the owner, 30 Oct
2026: "it should be automatic once the shot is clear"; until then a page
the reading could not confirm waited for the shutter). Once the page is
steady and clear, the reading has `clearPageGrace`: 1.2 s for a paper, 2 s
for a passport or a card, whose lines fill the student's details when the
server's reader cannot answer. If it has not passed by then, the camera
takes the page anyway. Only a reading that sees the wrong paper, or the
wrong side of a card, holds the capture (`holdsCapture`: "This looks like a
different paper", "Turn the card over"); the shutter is there for that. Both
platforms ask `capturesWhenClear` (`ScannerTextGateStatus` on the iPhone,
`ScanTextGateStatus` on Android), and a page taken this way returns its
reading with `matched: false`.

**Guidance instead of a premature capture.** Framing comes first, then what
the reading still needs: "Show the photo page with the two lines at the
bottom", "Move closer — the bottom lines are too small", "Glare on the bottom
lines" (tilt the page), "Show both bottom lines", "This looks like a different
paper", "Turn the card over", "Move closer so the text is readable", "Show the
whole page" (some text runs past the edge), "Hold still · Reading…". The
outline does not turn green until the reading passes; when it passes the
capture starts at once, and otherwise once the clear page's grace is over
(above).

**Fallbacks.** The manual shutter stays: on iPhone it appears seven seconds
after the scanner opens or retries, as before (accessibility, and papers the
reader cannot judge, such as a card with neither machine lines nor Latin
text); on Android it is always on screen. A phone whose text engine fails four
reads in a row goes back to steadiness alone. A photo taken by hand returns
whatever had been read by then.

**What the bridge returns.** Beside the page, a bounded `liveReading`, checked
again in Dart by `sanitizeLiveReading` on both platforms (a malformed one is
dropped, never the page):

```text
liveReading: {
  version: 1,
  kind: 'passport' | 'id_card' | 'paper',   // the rules the step asked for
  matched: bool,                            // the gate passed for this capture
  engine: 'apple_vision' | 'mlkit_latin',
  frames: int,                              // reads aggregated
  mrzFormat?: 'TD3' | 'TD1',
  mrz?: [line, …],                          // complete lines as voted, valid or not
  mrzValid: bool,                           // every check digit passed
  side?: 'front' | 'back',                  // cards: the side that was read
  fields?: { surname, givenNames, documentNumber, nationality, issuingState,
             birthDate: 'YYYY-MM-DD', sex, expiryDate: 'YYYY-MM-DD', personalNumber? },
  lines: [string, …],                       // ≤ 24 read lines inside the page, ≤ 120 chars, top first
}
```

`fields` come only from valid machine lines (a card front gives
`documentNumber` alone). A birth year after the current year is read as last
century. The iPhone also adds `live_text_reading` and `right_document_gate` to
`capabilities` and reports `scannerBuild: custom-live-v12`; Android adds
`liveReading` beside `files`.

**What the portal must do.** Its `usable()` in `guidedScanBridge.ts` rebuilds
the shell's answer from known fields, so it drops `liveReading` today; to use
the reading it must pass the field through (validated). To make the card gate
side-aware, send `side: 'front'` with a card's first capture and
`side: 'back'` with the capture of its back, and nothing for "both sides are
on this photo". A portal that sends no `side` keeps today's behaviour: either
side of the card is accepted.

**Privacy.** Nothing read is logged; diagnostic builds record counts only. The
reading leaves the phone only as the bounded `liveReading` returned with the
student's own capture of that paper. ML Kit's bundled SDK itself sends Google
anonymous usage metadata (device model, API latency, image size; never the
image or the text) through Google's data transport when online, and has no
documented switch to turn that off.

**Size** (measured 30 Oct 2026). ML Kit's text library is native code, one
copy per ABI: 11.1 MB for 64-bit ARM, 6.8 MB for 32-bit ARM, 11.6 MB for
x86_64, plus 1.5 MB of models and 0.6 MB of code shared by all. Google Play
gives each phone one ABI from the app bundle, so a 64-bit ARM phone installs
about 13 MB more and downloads about 6 MB more (the library travels
compressed, about 4.4 MB). The bundle uploaded to Play grows by about 31 MB,
and so does any APK that carries every ABI: `flutter build apk --release
--target-platform android-arm64` went from 74.5 MB to 105.7 MB, because that
flag keeps only Flutter's own libraries to arm64 and ML Kit's still come for
all three.

**What only a phone can confirm.** Whether Vision `.accurate` and ML Kit read
a real passport's and CNIE's machine lines at preview resolution, how long a
read takes on the oldest phones (iOS 15 on an iPhone 8, a low-end Android)
and whether the preview stays smooth while it runs, glare on laminated cards,
and the time from a steady page to the capture.

## Adaptive capture under validation (custom-live-v8)

The AVFoundation camera has no shutter, thumbnail tray, accuracy percentage, fixed directions, or native review wizard. One instruction below the camera explains what is needed now: frame the page, hold still, tilt slightly, or reframe. Lighting guidance is used when the processing result calls for another lighting view. A thin outline follows the detected document. The scanner captures automatically and retains useful views until a verified combination is available.

Focus and exposure must remain settled for 0.25 seconds while fresh detections confirm the page remains in position. The settling wait is bounded to two seconds. On devices with a shorter-focusing autofocus ultra-wide lens, a dual-wide camera can switch to close focus while retaining the ordinary wide field of view. Other devices use their wide camera. A lens switch revokes the current settling hold. Still photos use quality priority.

The adaptive session allows up to eight photo attempts, holds at most six corrected images, and lasts at most 60 seconds including processing. Each additional view has an 18-second wait; each processing phase has a separate 20-second deadline. These are limits, not a required photo count. Relative sharpness rejects a weaker incoming shot and drops an earlier soft shot once clearer evidence arrives. The scanner preserves useful photos during supplemental-view retries. Each new view must differ from the latest accepted viewpoint; there is no prescribed left/right route. Translation, uniform zoom, in-plane rotation, and detector jitter do not count as an angle change.

The processor needs at least three usable observations for its median comparison, then searches compatible subsets of three to six images in the retained pool (at most 42 combinations). A fourth or later registered view can supply detail that is hidden in the initial observations. Registration, fine-detail, lighting and byte limits remain authoritative. It ends capture as soon as a selected combination passes; otherwise it asks for another useful view. Exhausting the time or attempt budget requests a lighting/reframing adjustment, never an unverified success. An unchanged failed page does not silently restart.

Passport detection isolates the details page when the facing page dominates segmentation. A displaced binding can be recovered only from an observed continuous seam with supported outside edges; ambiguous seams are rejected. Bounded side crops retain the original-image clipping checks, and their outside-edge checks follow the crop orientation. No missing corner or margin is invented.

Photo decoding, boundary detection, perspective correction, rendering, encoding and fingerprint failures remain separate from fusion and lighting results. A missing boundary asks the student to keep the whole page visible; a timeout asks for reframing. Lower detail alone does not diagnose blur or bad lighting.

The guide remains outside the camera pixels. It supports Dynamic Type and VoiceOver, with no photo-count completion checkmarks or accuracy percentages. Cancel remains available throughout. Generation checks and cancellation tokens discard late work. Orientation changes reset capture because earlier geometry belongs to the previous orientation; interruptions retain the resume behavior.

## Source-only output

Each accepted still is perspective-corrected to document space with a maximum edge of 2600 pixels. The processor selects compatible corrected images, checks local fine-detail agreement, and combines observed pixels from the selected sources. Unused photos do not contribute to the output. Lighting replacement must be supported by registered source images. It does not generate missing text, faces or security patterns and does not whiten a single image to conceal persistent shadows.

The image processor retains a best-frame fallback for diagnostics and regression comparisons. The guided camera does not report that fallback as successful multi-view capture: it asks the student to reframe if the views cannot be combined safely. Persistent lighting hidden in every source cannot be reconstructed. Passing a heuristic alone is not evidence of a perfect or fully readable document; physical output inspection remains a release gate.

## Portal and diagnostics

The bridge returns one page, `engine: avfoundation_vision`, `scannerBuild` (now `custom-live-v12`), non-sensitive capabilities and, since v12, the bounded `liveReading` described above. `burstProcessing` records the fusion mode, frames considered/used, actual photo count, guided attempts, accepted guided angles, retained useful views, alignment models and lighting measurements. These are diagnostics, not student-facing accuracy percentages. Trusted-origin and navigation-nonce checks remain in place.

The portal provides one review screen for the scanned page and editable extracted fields. It owns retakes, rotation and additional pages. Passport and personal photo remain separate document slots. Submission binds the reviewed bytes and fields, detects concurrent profile changes, and retries without duplicate documents. The document-specific PDF placement and samples remain owned by the portal.

Raw camera observers, local frame persistence and native guide-preview checks exist only under `SCANNER_DIAGNOSTICS`; ordinary production builds exclude them. Private real-customer fixtures are not included in the repository or application.

## Verification and release gate

Run the pure adaptive capture, accepted-angle/stability and incremental quality tests, processing tests for observed moving lighting and static-print preservation, fine-text registration regressions, bridge tests, and an iOS 15 source check. Replay the saved real-document corpus and manually annotated underlying camera frames, including clipping and printed-inner-frame negatives. Inspect native guide layouts at small, landscape and large-text sizes.

On the physical iPhone, capture a passport, ID card, CV, diploma and landscape paper with genuinely different views. Confirm capture ends on verified detail, can continue beyond three photos, discards weak shots, and shows no shutter or fixed-direction steps, followed by one field review. Inspect corners, small text, MRZ, portraits, stamps and colored marks at full size. Check lighting movement, cancellation, timeout, interruption, orientation changes and retry bounds. Verify the final PDF against its document sample and confirm one CRM submission.

This describes local work under validation. It does not declare a new TestFlight build released or the physical multi-angle acceptance complete.
