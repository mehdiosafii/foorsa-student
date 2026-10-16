# Custom iPhone document scanner — 1.2.18 (38)

The iOS scanner uses AVFoundation for the live camera and Vision for real document quadrilaterals. A thin animated outline follows the detected page. Stable framing captures three still photos; perspective correction runs on each and the sharpest complete result is retained. This is best-frame selection, not pixel fusion or reconstruction of missing text. Captures preserve natural colour and have a maximum edge of 2600 pixels.

The camera stays open for additional pages. Automatic duplicate protection waits for the document to leave the frame; the manual shutter intentionally overrides the duplicate guard. Students may remove thumbnails, use the torch, or return all pages with Review details. Limits are 20 pages and 24 MB. Backgrounding, interruption, cancellation, stale Vision results and slow captures have explicit recovery paths.

Passport framing accepts both the landscape data page and a full open spread. The detected corners determine the live outline; the initial guide does not force an open passport into a landscape crop. Private real-document checks use the saved scan on controlled light/dark backgrounds at straight and tilted angles. Those images are not included in the repository or application.

The bridge returns `processed: true`, `engine: avfoundation_vision`, `scannerBuild: custom-live-v2` and non-sensitive capabilities. It checks the trusted portal origin and per-navigation nonce before and after capture. Preview frames remain on-device. Missing iOS plugin registration is an explicit error; only unsupported hardware uses the existing framed Flutter fallback.

The companion portal review displays one selected page and a single editable set of extracted fields. It supports rotation, reordering, retakes and adding pages without another Continue/Save wizard. OCR uses a private draft; no official document or applicant fields change until Confirm and submit. Submission binds the reviewed bytes and fields, detects concurrent profile changes and retries without duplicate documents. The existing student document privacy policy applies before extraction and submission.

Validation for this release includes Flutter analysis and tests, native geometry/stability/selection tests executed in the iPhone simulator, controlled Vision boundary detection with a private real-document image, an iOS signed archive, browser review interaction and live isolated-account OCR/CRM submission checks. Physical camera performance, glare handling and real-world edge tracking still require testing on an iPhone through TestFlight. Build/upload is explicitly authorized by the user for that purpose.

## Device acceptance

On a contrasting desk, scan a passport, an ID card, portrait A4 and a landscape transcript. Confirm the outline stays on the printed page while moving/tilting the phone, stable capture chooses a readable image, the same page does not repeat automatically, and the next page can be added with automatic or manual capture. Exercise torch, permission denial, cancel, background/resume, three-page review, retake/rotate, field correction and one-tap submission. Compare the final PDF and confirmed CRM fields; repeat a submission after an interrupted connection and ensure it appears only once.
