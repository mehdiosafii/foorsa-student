#!/usr/bin/env bash
# Signs the app inside an unsigned .xcarchive ad hoc, with the entitlements
# its Release build asks for, before Apple's export signs it for the store.
#
#   scripts/sign_archive_entitlements.sh <Runner.xcarchive> all        the project's
#                                       entitlements, aps-environment production
#   scripts/sign_archive_entitlements.sh <Runner.xcarchive> push-only  aps-environment
#                                       production and nothing else
#
# Apple's export signs an app with the entitlements its archived binary
# carries, kept to what the provisioning profile allows. `flutter build ipa
# --no-codesign` archives a binary that was never signed, so it carries none:
# the export of 1 Nov 2026 had no aps-environment, APNs refuses such an app,
# and no iPhone can register for notifications (docs/student-push.md). An ad
# hoc signature needs no certificate, no profile and nothing from Apple; the
# export replaces it with Apple's own. macOS only: codesign and plutil.
set -euo pipefail

archive="${1:?usage: sign_archive_entitlements.sh <Runner.xcarchive> all|push-only}"
set_name="${2:-all}"
root=$(cd "$(dirname "$0")/.." && pwd)
app=$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)
if [[ -z "$app" ]]; then
  echo "No app in $archive" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ent="$work/Runner.entitlements"
case "$set_name" in
  all)
    cp "$root/ios/Runner/Runner.entitlements" "$ent"
    plutil -replace aps-environment -string production "$ent"
    ;;
  push-only)
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0"><dict><key>aps-environment</key><string>production</string></dict></plist>' > "$ent"
    ;;
  *)
    echo "Unknown entitlement set '$set_name' (all, push-only)" >&2
    exit 1
    ;;
esac
# Every build setting the entitlements use must be resolved here.
if grep -q '\$(' "$ent"; then
  echo "Unresolved build setting in the entitlements: $(grep -o '\$([A-Za-z_]*)' "$ent" | sort -u | tr '\n' ' ')" >&2
  exit 1
fi
plutil -lint "$ent" >/dev/null

shopt -s nullglob
extensions=("$app"/PlugIns/*.appex "$app"/Extensions/*.appex)
if (( ${#extensions[@]} )); then
  echo "The app has extensions, which this script does not sign with their own entitlements." >&2
  exit 1
fi
# Nested code first, then the app with its entitlements.
for code in "$app"/Frameworks/*.framework "$app"/Frameworks/*.dylib; do
  codesign --force --sign - --timestamp=none "$code"
done
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$ent" "$app"

codesign -d --entitlements - --xml "$app" > "$work/signed.plist"
signed=$(plutil -extract aps-environment raw -o - "$work/signed.plist" 2>/dev/null || true)
if [[ "$signed" != production ]]; then
  echo "The ad hoc signature carries aps-environment '${signed:-none}', not production." >&2
  exit 1
fi
keys=$(plutil -convert json -o - "$work/signed.plist" | python3 -c 'import json, sys; print(", ".join(sorted(json.load(sys.stdin))))')
echo "Signed $(basename "$app") ad hoc with: $keys"
