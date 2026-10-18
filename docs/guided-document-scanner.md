# Custom iPhone document scanner

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

The bridge returns one page, `engine: avfoundation_vision`, `scannerBuild: custom-live-v8`, and non-sensitive capabilities. `burstProcessing` records the fusion mode, frames considered/used, actual photo count, guided attempts, accepted guided angles, retained useful views, alignment models and lighting measurements. These are diagnostics, not student-facing accuracy percentages. Trusted-origin and navigation-nonce checks remain in place.

The portal provides one review screen for the scanned page and editable extracted fields. It owns retakes, rotation and additional pages. Passport and personal photo remain separate document slots. Submission binds the reviewed bytes and fields, detects concurrent profile changes, and retries without duplicate documents. The document-specific PDF placement and samples remain owned by the portal.

Raw camera observers, local frame persistence and native guide-preview checks exist only under `SCANNER_DIAGNOSTICS`; ordinary production builds exclude them. Private real-customer fixtures are not included in the repository or application.

## Verification and release gate

Run the pure adaptive capture, accepted-angle/stability and incremental quality tests, processing tests for observed moving lighting and static-print preservation, fine-text registration regressions, bridge tests, and an iOS 15 source check. Replay the saved real-document corpus and manually annotated underlying camera frames, including clipping and printed-inner-frame negatives. Inspect native guide layouts at small, landscape and large-text sizes.

On the physical iPhone, capture a passport, ID card, CV, diploma and landscape paper with genuinely different views. Confirm capture ends on verified detail, can continue beyond three photos, discards weak shots, and shows no shutter or fixed-direction steps, followed by one field review. Inspect corners, small text, MRZ, portraits, stamps and colored marks at full size. Check lighting movement, cancellation, timeout, interruption, orientation changes and retry bounds. Verify the final PDF against its document sample and confirm one CRM submission.

This describes local work under validation. It does not declare a new TestFlight build released or the physical multi-angle acceptance complete.
