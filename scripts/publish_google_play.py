"""Publish exactly the signed bundle built from this commit, to one Play track."""
import os
from pathlib import Path
import re

import google.auth
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

# Release notes, one file per Play listing language (fr-FR.txt, ar.txt, ...).
# Play caps a language's notes at 500 characters.
RELEASE_NOTES = Path('android/play-release-notes')


def release_notes():
    notes = []
    for path in sorted(RELEASE_NOTES.glob('*.txt')):
        text = path.read_text(encoding='utf-8').strip()
        if not text:
            continue
        if len(text) > 500:
            raise SystemExit(f'{path} is over Play\'s 500 characters')
        notes.append({'language': path.stem, 'text': text})
    return notes


def needs_manual_review_send(error):
    # Play refuses to send an edit for review by itself while Play Console
    # holds other changes that are waiting to be sent (a declaration, the
    # reviewer sign-in details). The edit can still be committed; it then
    # waits in Publishing overview for "Send changes for review".
    return error.resp.status == 400 and b'changesNotSentForReview' in (error.content or b'')


def main():
    package = 'ma.foorsa'
    track = os.environ['PLAY_TRACK']
    if track not in ('internal', 'alpha', 'beta', 'production'):
        raise SystemExit('Unsupported Google Play track')
    version = re.search(r'^version:\s*([\d.]+)\+(\d+)\s*$', Path('pubspec.yaml').read_text(), re.M)
    if not version:
        raise SystemExit('pubspec.yaml must contain a version name and numeric build number')
    name, number = version.groups()
    notes = release_notes()
    # Short-lived credentials from google-github-actions/auth (Workload Identity
    # Federation impersonating the Play publisher service account). No key file.
    credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/androidpublisher'])
    edits = build('androidpublisher', 'v3', credentials=credentials, cache_discovery=False).edits()
    edit = edits.insert(packageName=package, body={}).execute()['id']
    committed = False
    waiting_for_send = False
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
        release = {'name': f'{name} ({number})', 'versionCodes': [number], 'status': 'completed'}
        if notes:
            release['releaseNotes'] = notes
        # The track's releases are replaced: a draft left on it in Play
        # Console (an earlier bundle) gives way to this one.
        edits.tracks().update(packageName=package, editId=edit, track=track, body={
            'track': track,
            'releases': [release],
        }).execute()
        edits.validate(packageName=package, editId=edit).execute()
        try:
            edits.commit(packageName=package, editId=edit).execute()
        except HttpError as error:
            if not needs_manual_review_send(error):
                raise
            edits.commit(packageName=package, editId=edit, changesNotSentForReview=True).execute()
            waiting_for_send = True
        committed = True
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(f'Google Play accepted **{name} ({number})** for **{track}**.\n\n'
                          f'Commit: `{os.environ["GITHUB_SHA"]}`. Google review/managed publishing may delay availability.\n')
            if waiting_for_send:
                summary.write('\nPlay Console holds other changes waiting to be sent, so this release is saved '
                              'but not yet sent: Publishing overview → **Send changes for review**.\n')
        if waiting_for_send:
            print('::notice::Saved in Play Console. Send it for review there: Publishing overview → Send changes for review.')
    finally:
        if not committed:
            edits.delete(packageName=package, editId=edit).execute()


if __name__ == '__main__':
    main()
