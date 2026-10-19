# Native capture: custom-live-v11

The portal opts into CRM enhancement with `profile.outputMode = 'imagegen'`.
Both that mode and the ordinary mode (payment receipts) now use the same
capture flow; only imagegen returns the original camera photos. Each
invocation captures **one physical page**.

## What the student sees

- **A live outline on the real page.** The detector runs Vision's document
  model on every preview frame (about ten a second) and draws a thin outline
  that follows the page. It no longer demands a plain, uniform background
  beside every edge, so a page held in the hand over a sofa or clothes is
  found. Build 44 (custom-live-v10) required that background: on 18 Oct 2026
  a hand-held baccalaureate got no outline for 25 seconds and never captured.
- **One short instruction for what to change:** show the whole page, move
  closer, move back a little, hold still, shadow on the page, glare on the
  page, more light needed. Corner marks replace the dashed portrait page, so
  landscape documents are not turned to fit a portrait guide.
- **Automatic capture in one hold.** After about 0.6 s of a steady, complete,
  sharp page the camera settles focus and exposure (at least 0.25 s, at most
  2 s) and takes a photo; the next photo is taken as soon as the previous one
  is delivered, while that one is still being checked. Two useful photos
  finish the page. There is no tilt sequence. Only when the first view showed
  shadow or glare does the scanner ask to tilt the phone slightly, for at
  most four seconds, so the second view shows what the first hid.
- **A manual shutter as a way out.** If no photo has been taken seven seconds
  after the scanner opens (or after a retry), a shutter button appears. A
  photo taken by hand uses the page outline when there is one, the document
  model on the photo otherwise, and the whole frame as a last resort.

## Detection

`ScannerRectangleDetector.detectLive` classifies each frame with
`ScannerLiveFramingPolicy` (`searching`, `ready`, `tooSmall`, `clipped`,
`wrongShape`, `blurry`). The document model tells the page from the clutter,
but over a busy background it often throws one or two corners to the frame's
edge or onto a hand, while the rectangle detector traces the page's real edges
without knowing paper from a cushion. So the outline is a rectangle proposal
that shares the model's corners (`ScannerOutlineRefinement`): three corners
within 2.5% of the page's diagonal, or two when the model's other two ran off
to the frame's edge. On synthetic hand-held scenes the model alone found 14 of
20 pages and readied two outlines about ten percent off; a printed border
inside the page, one page of an open booklet whose other corners stay in view,
and clutter rectangles keep the model's own outline. When the model
does not see a complete page, the strict pixel-evidence cascade still runs on
the same Vision pass, but an inner printed panel never stands in for a page
the model sees cut off. Passports keep the booklet-aware cascade first; a
model outline drives a passport capture only when it matches the confirmed
photo page or the cascade has had three seconds without finding one.

Light is read from a 160-pixel corrected rendering of the page
(`ScannerPageLightingProbe`): glare is a few blown-out cells while the typical
cell is not; shadow is a sizeable neutral region whose paper is much darker
than the brightest paper. Dim light is a very high camera ISO. These are hints
with a 1.5 s grace before capture goes ahead anyway.

## Still processing (both modes)

Severe blur is rejected before and after cropping. The crop is, in order: the
strict boundary on the photo; the document model on the photo, kept only when
it is a complete page of the expected shape within 8% of the live outline;
the live outline the student saw when the shutter fired; and, for a photo
taken by hand only, the whole frame. Automatic capture without a live outline
never fabricates a crop.

## Bounds and payload

At most six photos and 30 seconds per capture; every useful view's exact
`AVCapturePhoto.fileDataRepresentation()` bytes are kept (imagegen only),
8 MiB each and 32 MiB in total. Views that are not useful are not kept.
Cancellation invalidates delayed callbacks through the capture generation and
cancellation token.

```text
pages: [Data(previewJPEG)]
originals: [Data(originalCameraJPEG), ...]   // imagegen only
processing: 'imagegen'                       // imagegen only
scannerBuild: 'custom-live-v11'
burstProcessing: { mode, photosTaken, retainedUsefulViews, framesUsed, manual }
```

The Dart bridge contract is unchanged: one preview, 1–6 nonempty JPEG
originals for imagegen, none otherwise.

## Validation

`.github/workflows/scanner-native-checks.yml` runs on macOS for scanner
changes: the pure capture-logic tests (`scanner_live_framing_tests`,
`scanner_adaptive_capture_tests`, `scanner_imagegen_capture_tests`,
`scanner_lighting_capture_tests`), the Vision and image tests
(`scanner_view_quality_tests`, `scanner_imagegen_processing_tests`,
`scanner_lighting_processing_tests`, `scanner_live_detection_tests`) and an
iOS 15 type-check of the scanner sources. The pure-logic tests also compile on
Linux with a `CGImage` stand-in. Synthetic scenes are not camera frames:
physical-iPhone acceptance is separate and required before release.

The older adaptive-fusion machinery (`ScannerAdaptiveCaptureGuide`,
`resolveAdaptiveCapture`, lighting fusion) remains in the processor and its
tests but is no longer used by the capture screen.
