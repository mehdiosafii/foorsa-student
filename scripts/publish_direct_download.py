"""The Android app as a download from Foorsa's own domain, for students in mainland China.

Google Play does not open in mainland China, so a student there cannot install or update the
app from it (measured 6 Nov 2026: Google's servers timed out on every Chinese network tried).
This sends Google Play's own universal APK of a released version to Foorsa
(foorsa-reward, server/routes/app-release.routes.ts), which serves it at
https://student.foorsa.ma/android and offers it to phones in China.

It is Play's APK, signed with the app signing key Play installs carry, so it installs as an
update over the app from Play and the other way round. Nothing is built or signed here.

The version is pubspec.yaml's, or DIRECT_DOWNLOAD_VERSION (1.2.39+70). Google is reached with
the short-lived credentials google-github-actions/auth left (no key file); Foorsa with this
run's GitHub identity token, which Foorsa checks names google-play.yml on main of this
repository (no stored secret either).
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request

PACKAGE = 'ma.foorsa'
AUDIENCE = 'foorsa-app-release'
FOORSA = os.environ.get('FOORSA_RELEASE_HOST', 'https://home.foorsa.ma').rstrip('/')
MIN_BYTES = 5 * 1024 * 1024
MAX_BYTES = 300 * 1024 * 1024


def release_version():
    named = os.environ.get('DIRECT_DOWNLOAD_VERSION', '').strip()
    if named:
        match = re.fullmatch(r'(\d{1,3}\.\d{1,3}\.\d{1,4})\+(\d{1,6})', named)
        if not match:
            raise SystemExit('DIRECT_DOWNLOAD_VERSION must look like 1.2.39+70')
        return match.group(1), int(match.group(2))
    match = re.search(r'^version:\s*(\d{1,3}\.\d{1,3}\.\d{1,4})\+(\d{1,6})\s*$', Path('pubspec.yaml').read_text(), re.M)
    if not match:
        raise SystemExit('pubspec.yaml must contain a version name and numeric build number')
    return match.group(1), int(match.group(2))


def play_universal_apk(version_code, destination):
    """Downloads Play's universal APK of this version code into destination."""
    import google.auth
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseDownload

    credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/androidpublisher'])
    service = build('androidpublisher', 'v3', credentials=credentials, cache_discovery=False)
    # Play makes the APKs a little after a bundle is uploaded: wait for them.
    download_id = None
    for attempt in range(10):
        listed = service.generatedapks().list(packageName=PACKAGE, versionCode=version_code).execute()
        for entry in listed.get('generatedApks', []):
            universal = (entry.get('generatedUniversalApk') or {}).get('downloadId')
            if universal:
                download_id = universal
                break
        if download_id:
            break
        print(f'Play has no universal APK for {version_code} yet; waiting ({attempt + 1}/10)')
        time.sleep(60)
    if not download_id:
        raise SystemExit(f'Play has no universal APK for version code {version_code}')
    request = service.generatedapks().download_media(packageName=PACKAGE, versionCode=version_code, downloadId=download_id)
    with open(destination, 'wb') as handle:
        downloader = MediaIoBaseDownload(handle, request, chunksize=8 * 1024 * 1024)
        done = False
        while not done:
            _, done = downloader.next_chunk()


def describe(path):
    """The file's size and SHA-256, after checking it is a ZIP of a sensible size."""
    size = os.path.getsize(path)
    if size < MIN_BYTES or size > MAX_BYTES:
        raise SystemExit(f'The APK is {size} bytes, outside {MIN_BYTES} to {MAX_BYTES}')
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        if handle.read(2) != b'PK':
            raise SystemExit('The file Play returned is not an APK')
        handle.seek(0)
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return size, digest.hexdigest()


def github_identity():
    """This run's identity token for Foorsa (the job needs id-token: write)."""
    url = os.environ.get('ACTIONS_ID_TOKEN_REQUEST_URL')
    bearer = os.environ.get('ACTIONS_ID_TOKEN_REQUEST_TOKEN')
    if not url or not bearer:
        raise SystemExit('No GitHub identity token: the job needs permissions id-token: write')
    separator = '&' if '?' in url else '?'
    request = urllib.request.Request(f'{url}{separator}audience={AUDIENCE}', headers={'Authorization': f'Bearer {bearer}'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)['value']


def foorsa(path, body, token):
    request = urllib.request.Request(
        f'{FOORSA}{path}',
        data=json.dumps(body).encode(),
        method='POST',
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {token}'},
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Foorsa answered {error.code} on {path}: {error.read()[:300].decode(errors="replace")}')


def upload(signed_url, path):
    if not signed_url.startswith('https://') or '.supabase.co/' not in signed_url:
        raise SystemExit('Foorsa did not hand out a storage upload address')
    with open(path, 'rb') as handle:
        data = handle.read()
    request = urllib.request.Request(
        signed_url, data=data, method='PUT',
        headers={'Content-Type': 'application/vnd.android.package-archive', 'x-upsert': 'true'},
    )
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            response.read()
    except urllib.error.HTTPError as error:
        raise SystemExit(f'Storage answered {error.code}: {error.read()[:300].decode(errors="replace")}')


def main():
    name, code = release_version()
    print(f'Direct download for {name} ({code})')
    with tempfile.TemporaryDirectory() as folder:
        apk = os.path.join(folder, 'foorsa-student.apk')
        play_universal_apk(code, apk)
        size, sha256 = describe(apk)
        print(f'Play universal APK: {size} bytes, sha256 {sha256}')
        release = {'version': name, 'build': code, 'sha256': sha256, 'sizeBytes': size}
        token = github_identity()
        target = foorsa('/api/internal/app-release/android/upload-url', release, token)
        upload(target['signedUrl'], apk)
        # A fresh token: the first may be minutes old by now.
        published = foorsa('/api/internal/app-release/android/publish', release, github_identity())
        if published.get('published'):
            print(f'Published: https://student.foorsa.ma/android ({published["latest"]["url"]})')
        else:
            print(f'Uploaded, but Foorsa keeps a newer version: {published.get("latest")}')


if __name__ == '__main__':
    sys.exit(main())
