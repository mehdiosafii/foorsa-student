"""Publish exactly the signed bundle built from this commit, to one Play track."""
import os
from pathlib import Path
import re
import subprocess

import google.auth
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

# Release notes, one file per Play listing language (fr-FR.txt, ar.txt, ...).
# Play caps a language's notes at 500 characters.
RELEASE_NOTES = Path('android/play-release-notes')


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True, check=True).stdout


def release_notes(commit=None):
    """The notes in the checkout, or as they stood at `commit`."""
    if commit is None:
        files = [(path.stem, path.read_text(encoding='utf-8')) for path in sorted(RELEASE_NOTES.glob('*.txt'))]
    else:
        names = git('ls-tree', '--name-only', commit, f'{RELEASE_NOTES.as_posix()}/').split()
        files = [(Path(name).stem, git('show', f'{commit}:{name}')) for name in sorted(names) if name.endswith('.txt')]
    notes = []
    for language, raw in files:
        text = raw.strip()
        if not text:
            continue
        if len(text) > 500:
            raise SystemExit(f'{language}.txt is over Play\'s 500 characters')
        notes.append({'language': language, 'text': text})
    return notes


def last_commit_of_version(name, number):
    """The last commit on this history whose pubspec.yaml still said this version.

    A version promoted after main has moved on keeps the notes it was released
    with: they are the notes of its last commit, the parent of the commit that
    replaced its version line. None when the version is still main's.
    """
    line = f'version: {name}+{number}'
    if re.search(rf'^{re.escape(line)}\s*$', Path('pubspec.yaml').read_text(), re.M):
        return None
    # Newest first: the first commit that changed how often the line appears
    # is the one that replaced it.
    changes = git('log', '--format=%H', '-S', line, '--', 'pubspec.yaml').split()
    if not changes:
        raise SystemExit(f'{name} ({number}) was never the version in pubspec.yaml on this branch.')
    return git('rev-parse', f'{changes[0]}^').strip()


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
    # PLAY_PROMOTE=1: send a build already in Play to the track
    # (google-play.yml's promote job, from .github/google-play-promote.txt):
    # pubspec.yaml's build number, or the version the file names
    # (PLAY_PROMOTE_VERSION, e.g. 1.2.31+62) once main has moved past it.
    promote = os.environ.get('PLAY_PROMOTE') == '1'
    named = os.environ.get('PLAY_PROMOTE_VERSION', '').strip()
    notes_commit = None
    if promote and named:
        match = re.fullmatch(r'([\d.]+)\+(\d+)', named)
        if not match:
            raise SystemExit('PLAY_PROMOTE_VERSION must look like 1.2.31+62')
        name, number = match.groups()
        notes_commit = last_commit_of_version(name, number)
    notes = release_notes(notes_commit)
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
        if promote:
            # Sent to another track as it is: the bundle an earlier run uploaded
            # for this build number, never a rebuilt one (Play keeps one bundle
            # per version code).
            bundles = edits.bundles().list(packageName=package, editId=edit).execute().get('bundles', [])
            if not any(str(item.get('versionCode')) == number for item in bundles):
                raise SystemExit(f'Bundle {number} is not in Google Play yet; publish it before promoting it.')
        else:
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
            summary.write(f'Google Play accepted **{name} ({number})** for **{track}**'
                          f'{" (promoted, not rebuilt)" if promote else ""}.\n\n'
                          f'Commit: `{os.environ["GITHUB_SHA"]}`. Google review/managed publishing may delay availability.\n')
            if notes_commit:
                summary.write(f'\nRelease notes as they stood for that version, at `{notes_commit}`.\n')
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
