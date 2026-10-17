# Real-document scanner validation — 17 October 2026

**Follow-up: the real passport failure is reproduced and repaired in a candidate; live-camera acceptance is pending.** A user reported no outline or automatic photo while framing only the details page in build 39. The build-39 results below are historical file-processing gates; they did not verify live camera capture. See the final section for the replacement candidate and its separate validation status.

**Historical file-processing validation for beta 1.2.18 (39).** Both complete macOS framing sweeps and the physical iPhone gate pass against the final production sources: 5,024 desktop frame evaluations, 832 physical-device framing cases, and 152 saved-JPEG checks across 19 document types. App Store Connect availability is verified separately after upload.

## Changes

- Live preview and saved photos use the same document detector and profile rules. Rectangle and document-segmentation results are checked against pixel evidence at every edge; fusion must preserve a supported perimeter.
- Boundary evidence uses explicit high-quality downsampling on both platforms. Core Image otherwise defaults to different sampling on macOS and iOS; thin-stroke aliasing caused one correctly framed JPEG to be rejected on the phone. The exact case reproduces with low-quality sampling on Mac and passes with the final setting on the phone. No crop or quality threshold changed.
- Sparse pages receive a second sharpness check inside the detected page. Severe defocus, clipped pages, and unsupported inner borders request a retake. Small identity cards use a suitable capture-area threshold.
- The live outline stays visible during the three-shot burst. Still processing is serial, obsolete queued jobs are canceled, and native preview temporaries are released each frame. The clearest accepted image is selected; this is not multi-frame pixel fusion.
- Automatic capture supports slower analysis with a bounded observation gap and at least four consecutive valid observations. Movement, missing frames, stale results, rotation, and camera interruptions revoke readiness.
- The portal retains corrected fields and exact pages across expired-review recovery and uncertain submission retries. A signed replay can acknowledge only the identical previously committed submission; it cannot authorize a new expired write.

## Corpus and scope

The private corpus contains 57 source files: 51 CRM files from 43 customers and six connected Drive PDFs. It yields 61 document-content page crops and nine original captures. The test manifest contains 133 inputs: 61 generated sources and 72 annotated raw-photo variants. Each complete sweep evaluates 61 × 40 + 72 = **2,512 frames** across **19 document types**.

Publications and supervisor acceptance letters are deferred at the user's explicit request. CV and previous-Chinese-university examples each have only one source; this remains sparse coverage.

CRM samples were originally divided between 16 tuning customers and 27 customer-disjoint held-out customers. Failures from the larger corpus were subsequently used to fix the detector. The final results therefore describe expanded regression coverage, not an unseen-customer accuracy estimate. Drive PDFs form a separate external-source group, but customer independence was not established. The second geometry seed uses the same source documents; raw variants repeat unchanged. Counts must not be interpreted as independent documents or customers.

Customer data collection was read-only. Source files, rendered scenes, manual annotations, diagnostic overlays, identifiers, and detailed metrics remain in private local directories outside Git and hosted CI. CRM submission validation used a dedicated fictional QA applicant.

## Fixed criteria

Each generated source receives eight normal scenes plus rotation, perspective, lighting, texture, shadows, glare, blur, background clutter, inner borders, clipping, tiny-document, and absent-document cases. Raw captures use manual boundary and safety annotations independently of the detector.

An accepted boundary must be complete, match its document profile, have maximum corner error at most **3%** of the true diagonal, and have polygon overlap (IoU) at least **0.85**. Every normal frame must pass live detection, still detection, and held-capture readiness. Any accepted incorrect boundary or accepted severe-blur frame fails release, including difficult positives. A difficult scene that safely requests a retake is reported separately and does not fail the normal-capture gate. Missing, alternating, and stale observations must not authorize capture.

These thresholds, source labels, projected truth, and coverage requirements were not relaxed to obtain a pass. Seed `20261017` changes scale, rotation, tilt, and placement while regenerating the corresponding truth.

## Complete-sweep results

Both seed 0 and seed 20261017 passed all 19 categories: **488/488 normal frames accurate in both paths and held-ready per sweep**, with **zero unsafe live, still, held, or severe-blur acceptances**. All 61 severe-blur challenges were rejected in each run. This is **5,024 frame evaluations**, not 5,024 distinct documents.

| Document type | Frames per sweep | Normal baseline, both paths | Normal varied framing, both paths | Unsafe, either sweep | Gate |
|---|---:|---:|---:|---:|---|
| Admissions | 120 | 24/24 | 24/24 | 0 | PASS |
| Authorizations | 120 | 24/24 | 24/24 | 0 | PASS |
| Birth certificate | 120 | 24/24 | 24/24 | 0 | PASS |
| Contract | 240 | 48/48 | 48/48 | 0 | PASS |
| CSCA | 120 | 24/24 | 24/24 | 0 | PASS |
| CV | 40 | 8/8 | 8/8 | 0 | PASS |
| Highest degree | 120 | 24/24 | 24/24 | 0 | PASS |
| Passport | 120 | 16/16 | 16/16 | 0 | PASS |
| Last year degree | 128 | 24/24 | 24/24 | 0 | PASS |
| Last year transcript | 120 | 24/24 | 24/24 | 0 | PASS |
| Parent ID | 136 | 24/24 | 24/24 | 0 | PASS |
| Previous Chinese university | 40 | 8/8 | 8/8 | 0 | PASS |
| Receipts | 88 | 16/16 | 16/16 | 0 | PASS |
| Recommendation letter | 120 | 24/24 | 24/24 | 0 | PASS |
| Research proposal | 240 | 48/48 | 48/48 | 0 | PASS |
| Study plan | 240 | 48/48 | 48/48 | 0 | PASS |
| Transcript | 120 | 24/24 | 24/24 | 0 | PASS |
| Universities notices | 160 | 32/32 | 32/32 | 0 | PASS |
| Visa documents | 120 | 24/24 | 24/24 | 0 | PASS |

The baseline accurately captures **1,835/2,098 framing-positive scenes**; the varied-framing run captures **1,831/2,098**. The remaining 263 and 267 difficult scenes request retakes, including the severe-blur challenges that are deliberately framing-positive but quality-negative. Two difficult rotated raw captures became retakes as a result of the stronger edge check. Normal captures remained fully passing.

## App and integration verification

- Flutter: **40 tests passed**, analyzer clean.
- Native source: iOS 15 target typecheck passed.
- Release-gate regressions: an injected unsafe still crop and a severe-blur frame with correct corners both block release.
- Slower-cadence regression: 300 ms and 550 ms observations can finish a continuous hold; too few observations, missing frames, excessive gaps, and stale analysis cannot.
- iOS 27 Simulator: **15/16 native tests passed**. The synthetic pixel-detector test failed because document segmentation returned a false bottom strip. A diagnostic across all 19 document types showed the same rejection while rectangle detection remained correct. Switching between CIImage and CGImage input, and forcing CPU processing, did not resolve it. Apple warns that [Vision results in Simulator can be inaccurate](https://developer.apple.com/documentation/vision/vnimagerequesthandler/init%28cmsamplebuffer%3Aorientation%3Aoptions%3A%29-335k4).
- Physical-device validation: a separate release-optimized diagnostic app with the exact production detector, geometry, clarity, and image-processor sources passed the gate over **832 framing cases** on an **iPhone 17 Pro Max running iOS 27.2**. These include all 19 types, 72 annotated raw-photo variants, and **152/152 normal saved-JPEG checks**, with zero unsafe live, still, held, or severe-blur acceptances. All 19 severe-blur inputs were rejected. A separate validator checks complete manifest coverage, recomputes the fixed geometry gates, checks saved-image decoding/size/coverage, and verifies source fingerprints.
- Physical detector timing on loaded corpus images: live median **11.40 ms**, p95 **14.73 ms**; still median **11.27 ms**, p95 **13.99 ms**. These measure image analysis on this high-end phone, not end-to-end camera latency or low-end-device performance. The physical synthetic-page result also matches Mac, confirming the Simulator segmentation failure does not occur on this device.
- Portal: **376 tests passed**, frontend/server typechecks, production build, and bundle budgets passed. Production QA verified corrected fields, exactly one document after identical retry, completed OCR review state, and Drive mirroring. PR #1123 is merged and deployed.
- Independent review findings on cancellation, analysis cadence, and camera interruption were fixed before the final native build.

## Limits and beta delivery

Generated boundaries are known projected page-image borders on real document content. They do not prove that every original physical-paper edge was visible in the source image. Original photos are tested separately. Framing accuracy does not establish text legibility, OCR correctness, or authenticity; users review and correct extracted fields before submission.

Desktop and iOS Simulator timings are diagnostics, not physical-iPhone performance measurements. Physical autofocus, moving outlines, glare recovery, hand motion, thermal behavior, and complete capture-to-submit usability still need on-phone acceptance through TestFlight. The scanner selects the best of three shots and does not fuse pixels across photographs.

Validated beta candidate: **1.2.18 (39)**. Final detector SHA-256: `fd0515e9d798b0ce61d31d69afcb83bb364f66ef2721c42c21a579d57f3ed1c8`. Both desktop sweeps and the physical-device gate use this source. The signed release archive must match the committed candidate and exclude all private fixtures before TestFlight upload.

## Reproduction

With the approved private corpus outside the checkout:

```sh
tools/scanner_stress/test_gate.sh
tools/scanner_stress/run.sh --manifest "$PRIVATE_SCANNER_CORPUS/release-manifest.json" \
  --output "$PRIVATE_SCANNER_RESULTS/baseline" --variants 40 --require-pass
tools/scanner_stress/run.sh --manifest "$PRIVATE_SCANNER_CORPUS/release-manifest.json" \
  --output "$PRIVATE_SCANNER_RESULTS/varied" --variants 40 --seed 20261017 --require-pass
```

The private iOS harness is deliberately excluded from the application repository and release package. Public synthetic native tests remain in `RunnerTests`.

## Live passport follow-up

The full-height aspect-fill preview and its screen-sized passport guide disagreed with the detector's camera-area rules. On a 440 × 956 viewport with a 1440 × 1920 upright camera feed, a passport filling the old guide occupied only 13.37% of the camera image, below the 16% automatic-capture requirement. At 90% of the guide width it occupied 10.83%, below the detector's 12% minimum, so even a perfectly recognized page could yield no outline.

The corrected preview preserves the camera aspect ratio inside the space available between controls. Its guide leaves a framing margin while meeting the unchanged area rules. Tests cover 48 combinations of phone size, orientation, camera aspect ratio, and document profile; a passport at 90% of the guide covers at least 26% of the camera image. The 18 platform-independent native tests pass on macOS, including explicit asymmetric quarter-turn corner mapping. These checks do not replace device layout or live capture acceptance.

The old generated-scene gate also allowed original-photo detection misses. Its passing passport category included rejected unmodified and rotated original passport photos; its normal cases came from two composited document sources. The optional `requiredRawPositives` manifest field now makes each named original-photo case mandatory in live detection, still detection, and held-capture readiness. Missing, filtered-out, or inaccurate required cases block release even when the generated normal cases pass. Synthetic gate regressions verify these failures without customer data.

### Actual camera reproduction and replacement candidate

Check 4 retained two complete 20-second recordings from the user's iPhone: 128 and 116 analyzed frames, respectively, with zero accepted outlines. Eight saved images were selected for the required original-photo regression set. Images and measurements remain local, outside Git. This opt-in diagnostic does not submit documents to the CRM.

On those images, Vision often proposed an accurate complete details-page boundary, but the uniform-exterior checks rejected the surrounding fingers, clothing, and curved binding. The corrected camera guide alone therefore could not resolve the reported failure.

The replacement detector preserves the original boundary path and adds a passport-specific recovery. It requires a continuous binding and three continuous physical outer edges, with either close independent rectangle agreement or especially strong perimeter evidence when there is no complete competing rectangle. It preserves the segmentation corners. Printed inner panels and closed printed borders are separately rejected. An ambiguous closed-border passport can use a bounded, local fast text check of its machine-readable rows; it is not field extraction or authenticity verification, and no recognized text is retained. At most four text requests and four orientation pipelines may run per detection. The eight real phone images do not need that text fallback.

The required regression set contains **119 cases: 20 complete passport positives and 99 clipped, blurred, or printed-panel negatives**. All 20 positives pass live and still detection, the unchanged 3% maximum corner-error and 0.85 polygon-overlap thresholds, and held-capture readiness. All 99 negatives are rejected. Eight positives are the newly captured phone images; the other twelve are two details-page sources and one original spread in four orientations. These are regression cases, not twenty independent customers or documents.

Four additional phone photos initially received inaccurate manual corner annotations from resized images. A separate reviewer, without access to predictions or the previous annotations, marked full-resolution corner crops with coordinate grids. The original annotations and failing results remain preserved privately beside the replacement annotations and an audit trail. The annotation file SHA-256 is `b07eac4e9ab861282552df80e12754e8b0ee3fbef14a11181464a1010d541f78`. No acceptance threshold was relaxed. One genuine detection miss in this additional set was repaired before the final run.

The 18 platform-independent native tests, required-raw release-gate regressions, and production-source iOS 15 typecheck pass. Independent review findings about competing complete rectangles and recovery after a rejected primary candidate were corrected. The first repair candidate's detector SHA-256 is `38c91919e370b9397ff630bdae24a1be69dcd1228cce2c6bea091d5e3d1a8f18`; the later camera test below supersedes its release clearance.

That first repair candidate also passes the frozen **2,512-frame sweep across all 19 types**: 488/488 normal frames are accurate in both paths and held-ready; 1,842/2,098 framing-positive scenes are captured accurately; all 61 severe-blur challenges are rejected; no unsafe live, still, held, or quality acceptances occur. The remaining difficult positives request a retake. Desktop live analysis median/p95 is 18.4/38.4 ms; these timings are not phone performance measurements.

### Further live-camera regression and orientation comparison

The exact first repair passed all eight saved-image cases and production JPEG processing on the physical iPhone. The user then confirmed an outline and a saved page in Check 5. Its complete 20-second recording nevertheless accepted only **24/137** live observations and never reached automatic-hold readiness. The manual three-shot burst produced one accepted scan. The signed build 40 was withheld and was not uploaded.

Independent, blind full-resolution annotations of that new recording identified eight complete positive images and three blurred or clipped negatives. Their frozen annotation SHA-256 is `f5eb8a0f6a7cd84ce0e09645e4937a39ddab566b7726bb310f65b9b168d06677`. Shadows beneath the booklet could look like a second binding; an early segmentation hypothesis could also cut a corner inward even when a later orientation showed the physical corner or that it lay beyond the camera frame.

The updated passport path compares all four bounded orientation pipelines. It associates proposals through three agreeing corners, combines confidence with physical edge and binding support, and selects an observed complete outer boundary. A supported associated proposal that is incomplete vetoes the inner crop. It never synthesizes a replacement corner. Both sparse-page sharpness checks and the enclosing-sheet/printed-frame safeguards remain required. A lower-confidence orientation can be considered only with a high-confidence agreeing sibling and physical perimeter support; JPEG decoding versus lossless PNG re-encoding demonstrated that confidence alone was unstable near the old cutoff. Recognized text remains transient and limited to four requests per detection.

The expanded required regression set now contains **203 cases: 52 complete positives and 151 negatives**. This includes the prior 119 cases, eleven images from the new camera run, exact rotations with transformed annotations, deterministic crops inside each page edge, and severe-blur variants. All 52 positives pass live/still accuracy and held readiness, and all 151 negatives are rejected in both paths. These counts include transformations of the same documents and are not independent-customer accuracy estimates. Corner-error and polygon-overlap thresholds are unchanged.

Current detector SHA-256: `c664f38bd2ee11a09066e20de476603c2bea54d895e75c2db44f74a86fb96b05`. The 18 native core tests and iOS 15 source typecheck pass. Independent review found no demonstrated blocker in the new comparison logic and required verification against the unchanged 650 ms live-observation expiry. Every passport analysis now evaluates four orientations; low-end physical-device speed remains unverified.

The exact current candidate also passes the full **2,512-frame sweep across all 19 types**: all 488 normal frames are accurate in live/still detection and held-ready; 1,842/2,098 framing-positive scenes are accurate; all 61 severe-blur challenges are rejected; zero unsafe live, still, held, or quality acceptances occur. Desktop live analysis median/p95 is 18.5/53.5 ms, with passport p95 135.2 ms. These are desktop measurements, not camera latency.

**Remaining release gates:** physical saved-image replay and live outline plus automatic-capture acceptance. Check 6 is built and installed with a 19-case saved-image preflight before the camera opens. A clean signed build 40 from commit `83c0af9444b20e0468bf0dbd02ec2fbf74c07567` matches the current production sources; its signature, App Store profile, and absence of private fixtures are verified. It remains ineligible for release while the physical gates are pending and has not been uploaded. Loaded-image replay cannot establish live-camera smoothness or low-end-phone performance.
