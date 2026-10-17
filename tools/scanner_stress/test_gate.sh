#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
cd "$repo_root"
test_dir="$(mktemp -d /tmp/foorsa-scanner-gate.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT

# This fixture has no document. The stub deliberately returns an eligible
# wrong crop only in the still path, isolating that path from live failures.
python3 - "$test_dir" <<'PY'
import json, pathlib, struct, sys, zlib
root = pathlib.Path(sys.argv[1])
def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
pixels = b''.join(b'\x00' + b'\x88\x88\x88' * 8 for _ in range(8))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
(root / 'fixture.png').write_bytes(png)
(root / 'manifest.json').write_text(json.dumps({
    'requiredCategories': ['synthetic_negative', 'synthetic_blur'],
    'samples': [{'id': 'still_only_negative', 'category': 'synthetic_negative',
                 'documentKey': 'drive_files', 'layout': 'adaptive',
                 'path': str(root / 'fixture.png'), 'capture': 'raw', 'framingSafe': False},
                {'id': 'blur_correct_outline', 'category': 'synthetic_blur',
                 'documentKey': 'drive_files', 'layout': 'adaptive',
                 'path': str(root / 'fixture.png'), 'capture': 'raw', 'framingSafe': True,
                 'qualityConcern': 'severe_blur',
                 'rawQuad': [[0.2,0.2],[0.8,0.2],[0.8,0.8],[0.2,0.8]]}]
}))
# Add two same-category safe raw positives with distinct image widths for the stub.
def png(width, height):
    pixels = b''.join(b'\x00' + b'\x88\x88\x88' * width for _ in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
(root / 'positive.png').write_bytes(png(10, 10))
(root / 'miss.png').write_bytes(png(16, 8))
manifest = json.loads((root / 'manifest.json').read_text())
for sid, path in [('required_success', 'positive.png'), ('optional_miss', 'miss.png')]:
    manifest['samples'].append({'id': sid, 'category': 'raw_positive', 'documentKey': 'drive_files',
        'layout': 'adaptive', 'path': str(root / path), 'capture': 'raw', 'framingSafe': True,
        'rawQuad': [[0.2,0.2],[0.8,0.2],[0.8,0.8],[0.2,0.8]]})
(root / 'manifest.json').write_text(json.dumps(manifest))
PY

cat > "$test_dir/StubDetector.swift" <<'SWIFT'
import CoreImage
import Vision
enum ScannerDetectionPurpose { case live, still }
enum ScannerRectangleDetector {
  static func detect(in image: CIImage, profile: FoorsaScannerProfile,
                     purpose: ScannerDetectionPurpose) throws -> VNRectangleObservation? {
    if image.extent.width == 16 || (purpose == .live && image.extent.width == 8) { return nil }
    return VNRectangleObservation(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
  }
}
SWIFT
swiftc -O ios/Runner/ScannerGeometry.swift "$test_dir/StubDetector.swift" tools/scanner_stress/main.swift -o "$test_dir/gate-test"
result=0
"$test_dir/gate-test" --manifest "$test_dir/manifest.json" --output "$test_dir/results" --require-pass || result=$?
if [[ "$result" != 1 ]]; then
  print -u2 "Expected release-gate exit 1; received $result"
  exit 1
fi
python3 - "$test_dir/results" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
outcomes = json.loads((root / 'metrics.json').read_text())['outcomes']
gate = json.loads((root / 'gate.json').read_text())
assert len(outcomes) == 4
assert not outcomes[0]['unsafeAuto']
assert outcomes[0]['unsafeStill']
assert not gate['pass']
assert outcomes[1]['stillAccurate']
assert not outcomes[1]['unsafeStill']
assert outcomes[1]['unsafeQuality']
assert all(next(row['gate'] for row in gate['categories'] if row['category'] == category) == 'FAIL'
           for category in ('synthetic_negative', 'synthetic_blur'))
assert next(row['gate'] for row in gate['categories'] if row['category'] == 'raw_positive') == 'PASS'
print('PASS: both an unsafe still crop and severe blur with correct corners block release.')
PY

# The optional raw-positive contract leaves the legacy category gate unchanged,
# requires a selected ID to pass every capture path, and blocks selection omissions.
python3 - "$test_dir/manifest.json" "$test_dir" <<'PY'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
root = pathlib.Path(sys.argv[2])
manifest['samples'] = [sample for sample in manifest['samples'] if sample['category'] == 'raw_positive']
manifest['requiredCategories'] = ['raw_positive']
(root / 'raw.json').write_text(json.dumps(manifest))
manifest['requiredRawPositives'] = ['required_success']
(root / 'required-success.json').write_text(json.dumps(manifest))
manifest['requiredRawPositives'] = ['optional_miss']
(root / 'required-miss.json').write_text(json.dumps(manifest))
manifest['requiredRawPositives'] = ['still_only_negative']
(root / 'required-negative.json').write_text(json.dumps(manifest))
manifest['requiredRawPositives'] = ['does_not_exist']
(root / 'required-unknown.json').write_text(json.dumps(manifest))
manifest['requiredRawPositives'] = ['required_success', 'required_success']
(root / 'required-duplicate.json').write_text(json.dumps(manifest))
PY
run_gate() {
  local manifest="$1" output="$2" expected="$3"
  local exit_code=0
  "$test_dir/gate-test" --manifest "$manifest" --output "$output" --require-pass "${@:4}" || exit_code=$?
  if [[ "$exit_code" != "$expected" ]]; then
    print -u2 "Expected exit $expected for $manifest; received $exit_code"
    exit 1
  fi
}
run_gate "$test_dir/raw.json" "$test_dir/raw-results" 0
run_gate "$test_dir/required-success.json" "$test_dir/required-success-results" 0
run_gate "$test_dir/required-miss.json" "$test_dir/required-miss-results" 1
run_gate "$test_dir/required-miss.json" "$test_dir/limited-results" 1 --limit 1
run_gate "$test_dir/required-negative.json" "$test_dir/negative-results" 2
run_gate "$test_dir/required-unknown.json" "$test_dir/unknown-results" 2
run_gate "$test_dir/required-duplicate.json" "$test_dir/duplicate-results" 2
python3 - "$test_dir" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
legacy = json.loads((root / 'raw-results/gate.json').read_text())
assert legacy['pass'] and not legacy['failedRequiredRawPositives']
success = json.loads((root / 'required-success-results/gate.json').read_text())
assert success['pass'] and not success['failedRequiredRawPositives']
miss = json.loads((root / 'required-miss-results/gate.json').read_text())
assert not miss['pass'] and miss['failedRequiredRawPositives'] == ['optional_miss']
limited = json.loads((root / 'limited-results/gate.json').read_text())
assert not limited['pass'] and limited['failedRequiredRawPositives'] == ['optional_miss']
report = (root / 'limited-results/report.md').read_text()
assert 'optional_miss' in report
print('PASS: opt-in required raw positives enforce accurate held capture and selection coverage.')
PY
