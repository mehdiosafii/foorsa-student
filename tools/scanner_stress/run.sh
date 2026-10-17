#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
cd "$repo_root"
build_dir="$(mktemp -d /tmp/foorsa-scanner-stress.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
swiftc -O ios/Runner/ScannerGeometry.swift ios/Runner/ScannerRectangleDetector.swift tools/scanner_stress/main.swift -o "$build_dir/scanner-stress"
"$build_dir/scanner-stress" "$@"
