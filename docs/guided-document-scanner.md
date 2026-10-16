# iPhone system document camera (build 37)

On supported iPhones the document scan bridge uses Apple VisionKit. The system camera supplies live edge highlighting, automatic/manual shutter, crop/rotate review, and colour/grayscale/black-and-white choices. The student can scan up to 20 pages in one session; no pages are silently discarded. If a batch exceeds the size limit, the system review stays open for removal/retry. Unsupported devices retain the existing framed Flutter camera.

The native result includes `processed: true` and `engine: visionkit`. The portal must retain all pages and skip automatic recropping/re-enhancement of these results. Uploaded files still follow the existing portal/CRM document workflow. Only supported devices can exercise real camera behavior; simulator tests cannot verify live detection.

Before scanning, `FoorsaShellScannerSession` republishes the navigation nonce into the trusted main frame. It never returns the nonce to the calling frame. This removes reliance on page-load timing. A failed scanner session returns a visible error rather than opening a plain camera. Origin and nonce are checked again after capture; app-managed system scan bytes stay in memory rather than app-created temporary files.

Verification: Flutter bridge tests cover all pages, processed metadata, cancellation, unsupported fallback, and invalid results. A signed iOS archive verifies VisionKit linkage and plugin registration. Real iPhone QA must cover tracking on a contrasting surface, auto/manual capture, crop and colour review, multi-page save, permission denial, cancel, and upload to the test applicant.

---

# Foorsa Student — document-aware guided auto-capture

## The student experience

The portal's actual applicant-document folder determines the camera profile.
New shells receive `FoorsaShellScanDocument({v:1, documentKey, title,
instruction, layout, zones, pages})`; older shells use the unchanged
`FoorsaShellPickFile('camera', false)` bridge.

The native screen opens a rear-camera preview with a lightweight frame
that corresponds to the expected document shape, while allowing the actual
detected boundaries to move away from the suggestion. A low-resolution
luminance stream checks border support, framing, exposure, contrast,
sharpness and stability. The shutter automatically fires only after four
stable acceptable frames spanning at least 650 milliseconds.

The student can ALWAYS use the manual shutter, choose Other camera, or
use the existing portal file picker. We do not run OCR on the live camera
and do not send preview frames off-device. The existing portal scanner
still provides perspective correction, color-preserving enhancement,
manual corner editing, multi-page PDF output and asynchronous OCR review.

## Source of requirements

- Portal taxonomy: `foorsa-reward/shared/applicantDocumentRules.ts`
- Official bilingual instructions:
  `foorsa-reward/src/portal/documentInstructions.ts`
- Wire profiles: `foorsa-reward/src/portal/scanDocumentProfiles.ts`
- Native safe/offline profile fallback: `lib/src/guided_scanner/scan_document_profile.dart`

The native fallback maps every canonical Foorsa document category.
`identity` uses the passport data-page guide with regions for the
portrait and both MRZ lines; uploading an identity photo is separate
and should use Choose file. `parent_id` uses an ID-card guide, with a
reverse-side hint only when explicitly requested, not a blanket rule.
`medical_check` reminds the student to add both official form pages.
`transcript` allows portrait or landscape and asks for all grades and the
school stamp. Diplomas, criminal records, bank certificates and most
university notices use an adaptive rectangle rather than a fixed A4
template. Letters and research papers use a portrait-first guide with
multi-page instructions.

These are **visible-region guides**, not automated authenticity checks.
No preview analysis can establish that a medical stamp is legitimate or
that MRZ text has been correctly read. The post-upload OCR and the
counselor do that work.

## Low-memory device behavior

- Grayscale preview only: 120 × 160 = 19,200 pixels per analysed frame.
- Throttle analysis to one pass per approximately 230 milliseconds.
- Preserve still-image resolution, then defer heavy PDF enhancement/OCR.
- YUV420 on supported Android cameras; BGRA8888 on iOS.
- Unsupported image streams keep the manual shutter active.
- The original system camera remains available if the new camera fails.
- Keep the WebView app version unchanged in this PR; TestFlight must not
  automatically upload a build until the scanner is device-tested.

## Staging acceptance requirements

1. Real phones: low-memory Android without flagship camera hardware,
   Samsung/Android budget phone, iPhone with multiple preview aspect
   ratios. Test camera permission (grant/deny), foreground/background,
   flashlight and cancellation.
2. Geometry: portrait A4, landscape transcript/diploma, ID card, passport
   photo and bottom MRZ. Move, tilt and partially crop each; green
   auto-capture must require complete visible borders.
3. Exposure: shadows, yellow room lighting, direct glare, blank paper,
   printed table with strong grid lines, patterned desk and moving camera.
   No accidental shutter on an empty/incorrect frame.
4. Usability: first-pass success, false-positive captures, median and P95
   time from camera open to confirmed PDF, frame processing on older
   devices, battery/thermal conditions.
5. Completion: medical form Page 2 is requested in the portal scanner;
   the existing reviewer handles other multi-page documents according
   to the applicant's requirements.
6. Integration: both companion PRs in staging; changing portal assets on
   an older shell continues to launch the old camera rather than break
   uploads; all student files remain scoped to the authenticated user.

This remains a draft. Avoid auto-deployment and preserve the existing
human-review override until these checks are completed.

## Capture recovery regression coverage

The scanner releases its camera on non-resumed lifecycle states, recovers when
pause/resume overlaps a failed capture, and waits for initialization cleanup
before switching to the regular camera. Still captures and cleanup have bounded
waits; a late or abandoned capture is deleted from temporary storage. Turning
Auto off stops the preview analysis stream to reduce work on older phones.

Camera permissions and document image delivery use the exact configured HTTPS
portal origin, including its port. `test/trusted_portal_test.dart` covers
production/staging origins, sibling domains, alternate ports and lookalikes.
Validation uses the PR scanner workflow for analysis, unit tests and Android,
plus a branch-only iOS workflow run with TestFlight upload disabled. Device QA must still exercise pause/resume during
capture, slow initialization, fallback, unsupported formats and torch recovery.
