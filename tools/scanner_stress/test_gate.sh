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
PY

cat > "$test_dir/StubDetector.swift" <<'SWIFT'
import CoreImage
import Vision
enum ScannerDetectionPurpose { case live, still }
enum ScannerRectangleDetector {
  static func detect(in image: CIImage, profile: FoorsaScannerProfile,
                     purpose: ScannerDetectionPurpose) throws -> VNRectangleObservation? {
    if purpose == .live { return nil }
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
assert len(outcomes) == 2
assert not outcomes[0]['unsafeAuto']
assert outcomes[0]['unsafeStill']
assert not gate['pass']
assert outcomes[1]['stillAccurate']
assert not outcomes[1]['unsafeStill']
assert outcomes[1]['unsafeQuality']
assert all(row['gate'] == 'FAIL' for row in gate['categories'])
print('PASS: both an unsafe still crop and severe blur with correct corners block release.')
PY
