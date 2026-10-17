# Real-document scanner validation — 17 October 2026

**Follow-up: live passport capture is under repair.** A user reported no outline or automatic photo while framing only the details page in build 39. The results below are historical file-processing gates; they did not verify live camera capture. A replacement build must also pass the required original-photo cases and the live-phone capture check described below.

**Validation passed for beta candidate 1.2.18 (39).** Both complete macOS framing sweeps and the physical iPhone gate pass against the final production sources: 5,024 desktop frame evaluations, 832 physical-device framing cases, and 152 saved-JPEG checks across 19 document types. App Store Connect availability is verified separately after upload.

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

A separate details-page-only view of real passport content reproduces rejection at the binding and exterior-texture checks. A private diagnostic records numeric camera dimensions, guide bounds, candidate geometry, rejection reasons, and timing without uploading document pixels. Live-phone acceptance and the subsequent replacement TestFlight delivery remain pending; do not use the earlier loaded-image results as evidence that this report is resolved.

The working detector candidate recognizes a continuous passport binding only when three independently supported outer edges also pass exterior checks. A faint-edge recovery now checks the final exterior after bounded local refinement; a synthetic textured-exterior regression rejects while its clean control passes. Passport-only quarter-turn retries run the complete detector at most four times, preserving completeness, type, clarity, and boundary checks. The frozen 2,512-frame sweep passes with 1,842 accurate framing-positive outcomes, zero regressions against the production baseline, and zero unsafe outcomes. A separate required-raw gate passes all 12 complete passport cases (two details-page sources and one original spread, each in four rotations) and rejects all 68 clipping/blur negatives. These are regression cases, not 12 independent documents.

**Live camera acceptance still fails.** The revised candidate's on-phone diagnostic recorded 88 live observations with zero accepted outlines and four failed manual bursts; 86 observations passed the central sharpness check. The available log is partial and has no finish event. Several geometrically plausible rectangle proposals were blocked by a segmentation result touching the image boundary. Their correctness cannot be inferred from coordinates alone. An explicitly labeled local image-replay diagnostic is prepared to capture the actual failing camera view before changing that gate. The replacement TestFlight release remains pending the live-camera fix and acceptance.
