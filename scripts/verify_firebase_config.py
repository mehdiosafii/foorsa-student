#!/usr/bin/env python3
"""Reject missing or mismatched Firebase client registrations before a build."""

import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_ID = "foorsa-d71c1"
SENDER_ID = "643586848398"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify():
    gradle = (ROOT / "android/app/build.gradle").read_text()
    package = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle).group(1)
    android = json.loads((ROOT / "android/app/google-services.json").read_text())
    project = android["project_info"]
    require(project["project_id"] == PROJECT_ID, "Android Firebase project mismatch")
    require(str(project["project_number"]) == SENDER_ID, "Android sender ID mismatch")
    clients = [c for c in android["client"]
               if c["client_info"].get("android_client_info", {}).get("package_name") == package]
    require(len(clients) == 1, "Expected one Firebase client for the Android applicationId")
    client = clients[0]
    require(client["client_info"]["mobilesdk_app_id"].startswith(f"1:{SENDER_ID}:android:"),
            "Android Firebase app ID mismatch")
    require(any(k.get("current_key") for k in client.get("api_key", [])),
            "Android Firebase API identifier is missing")

    project_file = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    bundles = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", project_file))
    bundles = {b for b in bundles if not b.endswith(".RunnerTests")}
    require(len(bundles) == 1, "Expected one iOS application bundle ID")
    ios = plistlib.loads((ROOT / "ios/Runner/GoogleService-Info.plist").read_bytes())
    require(ios["BUNDLE_ID"] in bundles, "iOS Firebase bundle ID mismatch")
    require(ios["PROJECT_ID"] == PROJECT_ID, "iOS Firebase project mismatch")
    require(ios["GCM_SENDER_ID"] == SENDER_ID, "iOS sender ID mismatch")
    require(ios["GOOGLE_APP_ID"].startswith(f"1:{SENDER_ID}:ios:"), "iOS Firebase app ID mismatch")
    require(bool(ios.get("API_KEY")) and ios.get("IS_GCM_ENABLED") is True,
            "iOS Firebase messaging configuration is missing")
    print(f"Firebase registrations verified: {PROJECT_ID}; Android {package}; iOS {ios['BUNDLE_ID']}")


if __name__ == "__main__":
    try:
        verify()
    except (OSError, KeyError, ValueError, AttributeError) as error:
        raise SystemExit(f"Firebase configuration check failed: {error}") from error
