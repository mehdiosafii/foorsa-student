# Custom iPhone document scanner

The iOS scanner uses AVFoundation for the live camera and Vision for real document quadrilaterals. A thin animated outline follows the detected page. Stable framing captures three still photos; perspective correction runs on each and the sharpest complete result is retained. This is best-frame selection, not pixel fusion or reconstruction of missing text. Captures preserve natural colour and have a maximum edge of 2600 pixels.

The camera has no shutter, thumbnail tray or native review step. When the page is steady, it automatically runs the three-photo burst and returns the first successfully retained best frame to the portal review. A rejected burst stays on the live camera and can retry after another steady hold. Students can cancel, use the torch and resume after an interruption. The portal review owns retakes and optional additional pages, with each new camera invocation returning one page.

Passport framing accepts both the landscape data page and a full open spread. The detected corners determine the live outline; the initial guide does not force an open passport into a landscape crop. Private real-document checks use the saved scan on controlled light/dark backgrounds at straight and tilted angles. Those images are not included in the repository or application.

The bridge returns `processed: true`, `engine: avfoundation_vision`, `scannerBuild: custom-live-v4` and non-sensitive capabilities. It checks the trusted portal origin and per-navigation nonce before and after capture. Preview frames remain on-device. Missing iOS plugin registration is an explicit error; only unsupported hardware uses the existing framed Flutter fallback.

The companion portal review displays one selected page and a single editable set of extracted fields. It supports rotation, reordering, retakes and adding pages without another Continue/Save wizard. OCR uses a private draft; no official document or applicant fields change until Confirm and submit. Submission binds the reviewed bytes and fields, detects concurrent profile changes and retries without duplicate documents. The existing student document privacy policy applies before extraction and submission.

Validation includes native geometry, stability, best-frame selection and single-page completion tests, plus an iOS 15 source build. Detector and image-processing thresholds remain unchanged. Physical camera performance, glare handling, automatic transition timing and the full portal review still require acceptance on an iPhone through TestFlight.

## Device acceptance

On a contrasting desk, scan a passport, an ID card, portrait A4 and a landscape transcript. Confirm the outline stays on the printed page while moving or tilting the phone, a steady document captures without a button, the clearest complete burst image appears in portal review, and a rejected burst retries without leaving the camera. Exercise torch, permission denial, cancel and background/resume. In portal review, add another page, retake or rotate, correct a field and submit once. Compare the final PDF and confirmed CRM fields; repeat a submission after an interrupted connection and ensure it appears only once.
