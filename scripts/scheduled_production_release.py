"""Start the production release once Google Play accepts the reset upload key.

Run hourly by .github/workflows/production-release-schedule.yml. Each run
starts google-play.yml on main for the production track and waits for it:

- Play accepted the bundle: switch the schedule off. Done.
- Play refused only because the reset upload key is not valid yet: leave the
  schedule on, so the next hour tries again.
- Anything else (a real failure, a run that never finished): switch the
  schedule off and fail, so a person looks before anything is retried.

The schedule also switches itself off outside its year, so the cron's
"31 October" never fires again next year.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

RELEASE_WORKFLOW = 'google-play.yml'
SCHEDULE_WORKFLOW = 'production-release-schedule.yml'
RELEASE_YEAR = 2026
# The first scheduled hour. A production run that succeeded since then is this
# schedule's own, so a run queued behind it does not publish a second time.
WINDOW_START = datetime(2026, 10, 31, 18, 0, tzinfo=timezone.utc)
KEY_NOT_VALID_YET = 'not yet valid because it has been recently reset'
FIND_RUN_SECONDS = 300
FINISH_RUN_SECONDS = 70 * 60
POLL_SECONDS = 30


def gh(*args, check=True):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f'gh {" ".join(args[:3])} failed: {result.stderr.strip()[:500]}')
    return result.stdout


def gh_json(path):
    return json.loads(gh('api', path))


def summary(text):
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a') as handle:
            handle.write(text + '\n')
    print(text)


def switch_off(reason):
    gh('workflow', 'disable', SCHEDULE_WORKFLOW, '--repo', os.environ['REPO'])
    summary(f'Schedule switched off: {reason}')


def release_runs(repo):
    path = f'repos/{repo}/actions/workflows/{RELEASE_WORKFLOW}/runs?per_page=20'
    return gh_json(path).get('workflow_runs', [])


def started_after(run, moment):
    created = datetime.fromisoformat(run['created_at'].replace('Z', '+00:00'))
    return created >= moment


def publish_log(repo, run_id):
    jobs = gh_json(f'repos/{repo}/actions/runs/{run_id}/jobs').get('jobs', [])
    publish = next((job for job in jobs if job.get('name') == 'publish'), None)
    if not publish:
        return ''
    return gh('api', f'repos/{repo}/actions/jobs/{publish["id"]}/logs', check=False)


def decide(conclusion, log):
    """What one finished release run means: 'done', 'wait' or 'stop'."""
    if conclusion == 'success':
        return 'done'
    if conclusion == 'failure' and KEY_NOT_VALID_YET in log:
        return 'wait'
    return 'stop'


def main():
    repo = os.environ['REPO']
    now = datetime.now(timezone.utc)
    if now.year != RELEASE_YEAR:
        switch_off(f'the {RELEASE_YEAR} release window is over')
        return 0

    runs = release_runs(repo)
    if any(run.get('event') == 'workflow_dispatch' and run.get('conclusion') == 'success'
           and started_after(run, WINDOW_START) for run in runs):
        switch_off('a production release already succeeded')
        return 0
    busy = [run for run in runs if run.get('status') in ('requested', 'queued', 'in_progress', 'waiting', 'pending')]
    if busy:
        summary(f'A Google Play run is already going ({busy[0]["html_url"]}); trying again next hour.')
        return 0

    start = now.replace(microsecond=0)
    gh('workflow', 'run', RELEASE_WORKFLOW, '--repo', repo, '--ref', 'main', '-f', 'track=production')

    run = None
    deadline = time.time() + FIND_RUN_SECONDS
    while run is None and time.time() < deadline:
        time.sleep(10)
        run = next((candidate for candidate in release_runs(repo)
                    if candidate.get('event') == 'workflow_dispatch' and started_after(candidate, start)), None)
    if run is None:
        switch_off('the production run did not appear after it was started')
        return 1
    summary(f'Started the production release: {run["html_url"]}')

    deadline = time.time() + FINISH_RUN_SECONDS
    while run.get('status') != 'completed' and time.time() < deadline:
        time.sleep(POLL_SECONDS)
        run = gh_json(f'repos/{repo}/actions/runs/{run["id"]}')
    if run.get('status') != 'completed':
        switch_off('the production run did not finish in time; check it before retrying')
        return 1

    outcome = decide(run.get('conclusion'), publish_log(repo, run['id']))
    if outcome == 'done':
        summary('Google Play accepted the release for the production track.')
        switch_off('the production release was accepted')
        return 0
    if outcome == 'wait':
        summary('Google Play does not accept the reset upload key yet; trying again next hour.')
        return 0
    switch_off(f'the production run ended "{run.get("conclusion")}" for a reason other than the key date')
    return 1


if __name__ == '__main__':
    sys.exit(main())
