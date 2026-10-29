"""Publish exactly the signed bundle built from this commit, to one Play track."""
import os
from pathlib import Path
import re

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


def main():
    package = 'ma.foorsa'
    track = os.environ['PLAY_TRACK']
    if track not in ('internal', 'alpha', 'beta', 'production'):
        raise SystemExit('Unsupported Google Play track')
    version = re.search(r'^version:\s*([\d.]+)\+(\d+)\s*$', Path('pubspec.yaml').read_text(), re.M)
    if not version:
        raise SystemExit('pubspec.yaml must contain a version name and numeric build number')
    name, number = version.groups()
    credentials = service_account.Credentials.from_service_account_file(
        Path(os.environ['RUNNER_TEMP']) / 'foorsa-play.json',
        scopes=['https://www.googleapis.com/auth/androidpublisher'],
    )
    edits = build('androidpublisher', 'v3', credentials=credentials, cache_discovery=False).edits()
    edit = edits.insert(packageName=package, body={}).execute()['id']
    committed = False
    try:
        current = edits.tracks().get(packageName=package, editId=edit, track=track).execute()
        if any(release.get('status') == 'inProgress' for release in current.get('releases', [])):
            raise SystemExit('An existing staged rollout is in progress; finish or halt it in Play Console first.')
        current_codes = [int(code) for release in current.get('releases', []) for code in release.get('versionCodes', [])]
        if current_codes and int(number) <= max(current_codes):
            raise SystemExit('Raise the shared pubspec.yaml build number above the version already on this Play track.')
        bundle = edits.bundles().upload(
            packageName=package, editId=edit,
            media_body=MediaFileUpload('build/app/outputs/bundle/release/app-release.aab',
                                      mimetype='application/octet-stream', resumable=True),
        ).execute()
        if str(bundle['versionCode']) != number:
            raise SystemExit('The bundle version does not match pubspec.yaml')
        edits.tracks().update(packageName=package, editId=edit, track=track, body={
            'track': track,
            'releases': [{'name': f'{name} ({number})', 'versionCodes': [number], 'status': 'completed'}],
        }).execute()
        edits.validate(packageName=package, editId=edit).execute()
        edits.commit(packageName=package, editId=edit).execute()
        committed = True
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(f'Google Play accepted **{name} ({number})** for **{track}**.\n\n'
                          f'Commit: `{os.environ["GITHUB_SHA"]}`. Google review/managed publishing may delay availability.\n')
    finally:
        if not committed:
            edits.delete(packageName=package, editId=edit).execute()


if __name__ == '__main__':
    main()
