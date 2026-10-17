# Real-document scanner validation — 17 October 2026

**Release status: NOT READY.** The expanded suite evaluated 2,512 frames across 19 document types. All 19 types fail at least one framing safety or normal-capture requirement. Publications and supervisor acceptance letters are deferred at the user's explicit request; their absence is no longer a release blocker. No new version bump or TestFlight upload is included in this change.

## What changed

- Native and Flutter document profiles now accept either rotation of passports, cards, and letters. Receipt slips have a separate length range. Native profiles use the canonical document key instead of trusting a conflicting layout hint.
- Live and still detection share the production detector used by the stress harness. Still capture now applies the document profile and rejects an incomplete or wrong-shaped largest observation instead of substituting an inner rectangle.
- The private-corpus harness scores both live outlines and saved-photo crops across normal and difficult cases. `--require-pass` exits unsuccessfully for failed or incomplete coverage. An injected regression proves that a still-only bad crop blocks the gate even when live detection is safe.
- Optional private diagnostics draw expected edges in green, live predictions in cyan, and still predictions in pink. Customer pixels, identifiers, source links, and credentials are not in this repository or hosted CI.

## Corpus and independence

The corpus contains 57 source files: 51 CRM files from 43 customers, plus six connected Drive PDFs containing study plans and research proposals. It yields 61 document-content page crops and nine original photo/scanner images. Eight transformations of each original image yield 72 raw inputs; these transformations are not independent documents. The complete run is 61 × 40 generated frames + 72 raw frames = 2,512.

CRM tuning and held-out groups contain 16 and 27 customers, respectively, with no customer overlap. Drive PDFs are a separate external-validation group; their identities were not cross-matched against CRM customers, so they are not claimed as an independent customer holdout. CV and previous-Chinese-university examples each have one source and no independent held-out example. Data collection was read-only; customer records were not changed.

Generated frames use known projected corners on real document content. Original photos have independent manual boundary/safety annotations: three complete positives and six clipped/invalid negatives. This is a framing test, not a learned document model or proof of OCR correctness.

## Test conditions and criteria

Each page crop receives 40 deterministic cases: eight normal scenes, rotation and perspective, low contrast, texture, shadows, glare, blur, competing rectangles and inner borders, plus clipped edges, a partial corner, a tiny document and an absent-document scene. Severe blur and glare are separate quality challenges; a correct frame does not certify readable text.

A correct boundary must be complete, accepted by its document profile, within 3% maximum corner error relative to the document diagonal, and have polygon overlap (IoU) of at least 0.85. Any eligible incorrect live or still boundary fails the gate, including difficult positives. A missed difficult positive counts as a retake; a normal-case miss fails. Each generated source must include all eight normal and six framing-negative cases. Held, dropped and alternating observations exercise the production live stability tracker. These are simulated observations, not physical camera motion.

## Results by type

“Incorrect” means an eligible crop failed the boundary criteria or accepted an invalid/clipped scene. Live and still counts can overlap. Normal columns count accurate frames out of eight per page crop; the frame count includes all generated and raw variants.

| Document type | Frames | Normal live | Normal still | Incorrect live | Incorrect still | Result |
|---|---:|---:|---:|---:|---:|---|
| Admissions | 120 | 24/24 | 24/24 | 4 | 6 | FAIL |
| Authorizations | 120 | 24/24 | 24/24 | 3 | 3 | FAIL |
| Birth certificate | 120 | 24/24 | 24/24 | 3 | 4 | FAIL |
| Contract | 240 | 48/48 | 48/48 | 8 | 12 | FAIL |
| CSCA | 120 | 24/24 | 24/24 | 5 | 9 | FAIL |
| CV | 40 | 8/8 | 8/8 | 2 | 2 | FAIL |
| Highest degree | 120 | 24/24 | 24/24 | 4 | 4 | FAIL |
| Passport | 120 | 12/16 | 12/16 | 13 | 14 | FAIL |
| Last-year degree | 128 | 24/24 | 24/24 | 6 | 6 | FAIL |
| Last-year transcript | 120 | 24/24 | 24/24 | 3 | 2 | FAIL |
| Parent ID | 136 | 20/24 | 22/24 | 4 | 4 | FAIL |
| Previous Chinese university | 40 | 8/8 | 8/8 | 2 | 3 | FAIL |
| Receipts | 88 | 14/16 | 14/16 | 10 | 10 | FAIL |
| Recommendation letter | 120 | 23/24 | 23/24 | 10 | 11 | FAIL |
| Research proposal | 240 | 48/48 | 48/48 | 8 | 8 | FAIL |
| Study plan | 240 | 48/48 | 48/48 | 6 | 8 | FAIL |
| Transcript | 120 | 24/24 | 24/24 | 4 | 4 | FAIL |
| University notices | 160 | 32/32 | 32/32 | 4 | 5 | FAIL |
| Visa documents | 120 | 23/24 | 24/24 | 4 | 5 | FAIL |

Across normal frames, live detection is accurate on **476/488 (97.5%)** and still detection on **479/488 (98.2%)**. Across all 2,512 frames there are **103 incorrect eligible live selections and 120 incorrect eligible still selections**, spanning 121 distinct frames. The customer-disjoint held-out group alone contains 56 incorrect live and 64 incorrect still selections. A high normal-case percentage therefore does not establish release readiness.

Severe blur, clipped top edges, and printed inner rectangles remain the main failure patterns. Some normal misses are distance/area guard rejections, not incorrect edge localization. The test deliberately treats those as failed normal usability cases.

Tuning-only alternatives using document segmentation, detector agreement, and edge contrast/sharpness did not meet both safety and usability targets. The strictest edge experiment eliminated tuning-set incorrect selections but reduced accurate normal frames from 179/184 to 153/184 and added substantial computation. It was not integrated. No parameters were tuned against the final held-out results.

## Verification and release limits

- Full Flutter suite: **40 tests passed**; analyzer reported no issues.
- iPhone 13 Pro Max simulator, iOS 27: **9 native tests passed**, including rotated shape rules and rejection of clipped/wrong-shaped outer rectangles without inner fallback.
- Still-only release-gate regression: passed, with expected exit status 1 from the injected unsafe crop.
- Final corpus: completed; `--require-pass` returned **1**, as expected for the failing quality gate. Raw-photo line overlays were also generated and visually checked privately.
- Independent code reviews found the final detector ordering and still-path gating fixes consistent with their regression tests.

The full-corpus timing run overlapped simulator work and briefly paused; its desktop timings and process memory are diagnostic only and are not iPhone performance claims. Simulation does not verify physical autofocus, live smoothness, glare recovery, multi-shot OCR quality, or the complete CRM submission flow. Those remain necessary after the framing failures are fixed. The current camera selects the strongest burst image; these results do not establish multi-frame image fusion.

Before another TestFlight delivery, resolve the remaining inner-boundary/blur/clipping failures, rerun the full private corpus including customer-disjoint cases, strengthen sparse category coverage, and verify capture → corrected extracted fields → CRM on a physical iPhone. Existing CI builds and tests the app without customer files; its green status does not replace the private-corpus release gate. The generated still-only regression was run locally. A separate harness workflow proposal is retained locally because the current GitHub connection cannot write workflow files.

## Reproduction

On a Mac with Xcode, set `PRIVATE_SCANNER_CORPUS` to the approved private corpus directory, then run:

```sh
tools/scanner_stress/test_gate.sh
tools/scanner_stress/run.sh --manifest "$PRIVATE_SCANNER_CORPUS/release-manifest.json" \
  --output "$PRIVATE_SCANNER_CORPUS/new-results" --variants 40 --require-pass
```

The private manifest for future runs requires the 19 in-scope categories. The completed run originally listed the two unavailable categories as missing; the user's subsequent deferral is recorded separately and does not change any frame result or the failing release decision.
