# Real-document scanner validation — 17 October 2026

**Release status: pending physical-device validation.** Scanner fixes pass both complete macOS framing gates. The iOS Simulator returned invalid document-segmentation results, so it cannot establish native image-processing readiness. A separate on-device diagnostic app is prepared; device-provisioning access currently blocks execution. No new TestFlight build has been uploaded.

## Changes

- Live preview and saved photos use the same document detector and profile rules. Rectangle and document-segmentation results are checked against pixel evidence at every edge; fusion must preserve a supported perimeter.
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
- Physical-device validation: a separate diagnostic app compiled successfully with the exact production detector, geometry, clarity, and image-processor sources. The prepared suite has **832 frames**, including all 19 types and 72 annotated raw-photo variants, plus **152 saved-JPEG crop checks**. Signing/provisioning access is required before execution; no on-device pass or timing result is claimed.
- Portal: **376 tests passed**, frontend/server typechecks, production build, and bundle budgets passed. Production QA verified corrected fields, exactly one document after identical retry, completed OCR review state, and Drive mirroring. PR #1123 is merged and deployed.
- Independent review findings on cancellation, analysis cadence, and camera interruption were fixed before the final native build.

## Limits and beta delivery

Generated boundaries are known projected page-image borders on real document content. They do not prove that every original physical-paper edge was visible in the source image. Original photos are tested separately. Framing accuracy does not establish text legibility, OCR correctness, or authenticity; users review and correct extracted fields before submission.

Desktop and iOS Simulator timings are diagnostics, not physical-iPhone performance measurements. Physical autofocus, moving outlines, glare recovery, hand motion, thermal behavior, and complete capture-to-submit usability still need on-phone acceptance through TestFlight. The scanner selects the best of three shots and does not fuse pixels across photographs.

Planned beta: **1.2.18 (39)**. Release upload remains gated on physical-device execution and the unchanged crop/quality criteria. The current available TestFlight build remains **1.2.18 (38)** as verified on 17 October 2026.

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
