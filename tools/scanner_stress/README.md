# Scanner stress simulation

This macOS command compiles the production `ScannerGeometry.swift`, `ScannerRectangleDetector.swift`, and `ScannerContentClarity.swift` with `main.swift`. Every rendered frame goes through `ScannerRectangleDetector.detect` for live and still detection. The hold, dropout, and alternating movement sequences feed selected live observations to the production `ScannerStabilityTracker` and apply the scanner profile before tracking.

Keep the manifest, source images, output reports, and optional diagnostic PNGs in a private directory outside `scanner-mobile`. The tool rejects source, manifest, and output paths inside the repository, including symbolic links. Use anonymous IDs; those IDs appear in detailed results.

```json
{
  "samples": [
    {"id":"passport_01","category":"passport","documentKey":"identity","layout":"passport","path":"/absolute/private/path/passport_01.jpg","split":"tuning"},
    {"id":"card_01","category":"identity_card","documentKey":"parent_id","layout":"card","path":"/absolute/private/path/card_01.jpg","split":"holdout"}
  ]
}
```

Use a crop of the **document itself** as each source image. If a source is a phone screenshot, flatbed sheet, or photo containing a small document, crop the physical document first. Otherwise the generator will treat the screenshot or paper sheet as the ground-truth document boundary. Full-page PDFs exported as page images can remain full pages. Accepted layouts are `passport`, `card`, `portrait`, and `adaptive`.

To evaluate an original phone photo without reprojection, add `"capture":"raw"`, an independent manual corner annotation, and a framing safety label:

```json
{
  "id": "passport_phone_01",
  "category": "passport",
  "documentKey": "identity",
  "layout": "passport",
  "path": "/absolute/private/path/phone_photo.jpg",
  "capture": "raw",
  "rawQuad": [[0.17,0.13],[0.83,0.16],[0.80,0.87],[0.19,0.85]],
  "framingSafe": true,
  "qualityConcern": "glare",
  "split": "holdout"
}
```

`rawQuad` is **top-left, top-right, bottom-right, bottom-left**, normalized to the EXIF-oriented image, with origin at the image's top left. Label corners by hand, independently of this detector. For a clipped or absent document, set `"framingSafe":false`; `rawQuad` can be omitted when a true full boundary cannot be annotated. Coordinates from -0.5 to 1.5 allow an annotated boundary to extend beyond the photo. `qualityConcern` is optional metadata such as `glare`, `blur`, or `low_contrast`. The `severe_blur` label additionally requires both paths to reject capture; other labels are descriptive, not scored as readability tests. Raw captures retain their actual dimensions for aspect ratio and corner error. Each raw sample runs once through live/still detection and a held observation sequence; generated variants apply only to document crops.

An optional top-level `"requiredCategories":["passport","identity_card"]` list can declare the categories that must appear in a selected run.

From any directory, run:

```sh
/absolute/path/to/scanner-mobile/tools/scanner_stress/run.sh --manifest /absolute/private/manifest.json --output /absolute/private/results --variants 40
```

For a short tuning run or a held-out run, add `--limit 5`, `--split tuning`, or `--split holdout`. `--variants` accepts 1–40; use all 40 for the full positive and negative gate. `--diagnostics 20` saves at most 20 failing frame PNGs under the private output directory. They contain source document pixels. Without that flag, no frame images are written. `--smoke --output /absolute/private/smoke --variants 40` uses an in-memory synthetic page and needs no manifest.

By default, the tool writes results and exits successfully even when a category fails; this supports exploratory runs. Add `--require-pass` for release gating: after writing metrics and reports, it exits with status 1 if any tested category is `FAIL` or `PARTIAL`, or if a manifest `requiredCategories` entry is absent from the selected run. `gate.json` records the overall pass value, missing category names, and per-category gates. The gate also fails when a severe-blur image is accepted, even if the selected corners match the expected boundary.

The 40 fixed variants include normal distances, 0/90/180/270° rotation, perspective, four backgrounds, low contrast, texture, blur, shadow, localized glare, competing and inner rectangles, edge clipping, a partial corner, a tiny document, and a no-document scene. Six cases are framing negatives. Severe glare and blur are framing-safe images with separate quality-concern labels: framing may be correct even when text is unreadable. Normal positives require complete/profile-accepted corners, maximum corner error at most 3% of the true document diagonal, and polygon IoU at least 0.85. The generated category gate is `PARTIAL` until all eight normal and six framing-negative cases per generated source are run. It fails for any eligible inaccurate live or still crop across **all** cases, any unsafe held auto capture, or a normal frame that is inaccurate in live/still detection or fails to become ready when held. Hard-positive misses remain visible as retakes in the all-positive count and CSV. A raw-only category passes the **framing safety** gate if no unsafe live or still crop or held auto capture occurs and at least one annotated positive is detected accurately by both paths; negative-only raw runs remain `PARTIAL`. Detection misses still appear in the accuracy count.

`metrics.json` holds per-frame and sequence results; `metrics.csv` has per-frame values; `report.md` summarizes tested categories and names any required categories missing from the selected run. `gate.json` records the same per-category gate calculation used by the report, plus coverage status. Timings are live detection milliseconds, with still detection recorded separately, and peak process resident memory is included. Repeat the same manifest and options to reproduce frame geometry and effects; detection timing can vary with machine load.

Generated frames are a **simulation of real document content**. Raw samples test the original annotated photos. The pixel detector rejects severe defocus, but neither mode verifies all text legibility or OCR. Finish acceptance on a physical low-end iPhone/TestFlight with live motion, focus, glare, capture, crop, and upload checks.

Diagnostic images draw the independent expected boundary in solid green, the live prediction in dashed cyan, and the still prediction in dotted pink. Missing predictions have no line. These private overlays expose wrong inner rectangles and clipped-page selections directly on real document content. They must never be committed or published.

Use `--seed 20261017` for a reproducible additional sweep: distances vary by up to 2%, rotations by 2°, tilt by 0.005, and placement by 15 pixels. Seed 0 keeps the original benchmark. The ground truth is regenerated from the perturbed geometry, and all existing coverage and accuracy requirements remain unchanged. The seed is recorded in `metrics.json`. These are additional simulations of known source documents, not new independent customers.

Run `tools/scanner_stress/test_gate.sh` for regressions that inject a safe live result with an unsafe still crop, and an accurately framed but severely blurred still. It uses a generated fixture and no customer data.
