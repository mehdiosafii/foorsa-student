#!/usr/bin/env bash
# The push entitlement of the app inside an IPA, as Apple will read it.
#
#   scripts/push_entitlement.sh <app.ipa>          prints aps-environment (production,
#                                                  development), or nothing when absent
#   scripts/push_entitlement.sh --keys <app.ipa>   prints every entitlement's name
#
# An iPhone app without aps-environment is refused by APNs ("no valid
# aps-environment entitlement string found for application"): it never gets
# the token firebase_messaging needs, so it can never register for
# notifications (docs/student-push.md). macOS only: codesign and plutil.
set -euo pipefail

mode=value
if [[ "${1:-}" == "--keys" ]]; then
  mode=keys
  shift
fi
ipa="${1:?usage: push_entitlement.sh [--keys] <app.ipa>}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$ipa" 'Payload/*' -d "$work"
app=$(find "$work/Payload" -maxdepth 1 -name '*.app' -print -quit)
[[ -n "$app" ]] || exit 0
# A signature that cannot be read is said so on stderr, so it is not mistaken
# for an app without entitlements.
if ! codesign -d --entitlements - --xml "$app" > "$work/entitlements.plist" 2> "$work/codesign.err"; then
  echo "codesign could not read the entitlements of $(basename "$app"): $(tr '\n' ' ' < "$work/codesign.err")" >&2
  exit 0
fi
[[ -s "$work/entitlements.plist" ]] || exit 0

if [[ "$mode" == keys ]]; then
  plutil -convert json -o - "$work/entitlements.plist" 2>/dev/null \
    | python3 -c 'import json, sys; print(", ".join(sorted(json.load(sys.stdin))))' || true
else
  plutil -extract aps-environment raw -o - "$work/entitlements.plist" 2>/dev/null || true
fi
