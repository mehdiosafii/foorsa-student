# Native capture for asynchronous CRM enhancement

The portal opts into this mode with `profile.outputMode = 'imagegen'`. Omitting
that exact value preserves the existing local fusion behavior. Each invocation
captures **one physical page** in multiple source photos, not several pages.

The student sees the live outline and one short instruction. Capture is automatic
and requires all corners, a steady page, settled autofocus/exposure, and the
existing severe-blur threshold. Two useful cropped views complete
capture; a relatively softer view is rejected, and a sharper later view can
replace an earlier soft view. The mode never calls the local fusion resolver.
Each subsequent shot requires a fresh stable hold, but no particular tilt or
perspective change. This avoids discarding a clear first shot while waiting for
an unnecessary angle change. Eight attempts, six retained originals, an 18-second
wait and 60-second total deadline bound the session. Failure requires deliberate
reframing before retry. Cancellation resets the raw pool and invalidates delayed
callbacks using the existing capture generation and cancellation token.

Every retained original is the exact `AVCapturePhoto.fileDataRepresentation()`
JPEG, with no decode/re-encode. Sources are limited to 8 MiB each and 32 MiB total.
A shot with valid shutter-time live geometry is preserved even if subsequent
strict still-boundary detection fails. The OCR preview is a crop from one real
source photograph. Strict still detection is preferred; when it fails, the
stable live quadrilateral is projected from the centered live sensor crop into
the oriented still. A source bounding crop handles a perspective-render failure.
Both source and cropped content retain blur checks, and empty cropped content is
rejected. No guide overlay or generated pixels are included in the preview.

Native success payload:

```text
pages: [Data(previewJPEG)]
originals: [Data(originalCameraJPEG), ...]
processing: 'imagegen'
scannerBuild: 'custom-live-v10'
```

Dart validates exactly one preview, 1–6 nonempty JPEG originals, per-file and
aggregate limits, and the requested mode. It returns the existing `files` preview
envelope plus `originals: [{name, dataUrl}, ...]` and `processing: 'imagegen'`.
The preview is for OCR and student review. The portal owns upload, field
confirmation, and asynchronous enhancement for the CRM; native capture does not
send photographs to an AI service or generate the final PDF.

Validation includes the targeted Flutter scanner/profile tests, native
`scanner_imagegen_capture_tests.swift`, `scanner_imagegen_processing_tests.swift`,
the existing adaptive-capture and view-quality tests, and iOS scanner typechecking.
The processing test proves a source whose strict boundary is rejected can produce
a cropped preview only with the explicit mode and valid live geometry, while
empty/blurred content remains rejected. Physical iPhone acceptance is separate.
