"""Explicit cloud operations for compute-risk; importing this module is offline.

Requires pre-existing APIs, image, accounts and IAM. Never enables APIs or grants IAM.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import time
from datetime import datetime, timezone


SETTINGS = ("RISK_LOOKBACK_WEEKS", "RISK_DATA_DELAY_DAYS",
            "RISK_WEATHER_MAX_TRAILING_GAP_DAYS", "RISK_AQI_MAX_TRAILING_GAP_DAYS")
REQUIRED = ("PROJECT_ID", "REGION", "IMAGE", "SA_JOBS", "SA_SCHEDULER",
            "COMPUTE_RISK_JOB_NAME", "COMPUTE_RISK_SCHEDULER_NAME",
            "COMPUTE_RISK_SCHEDULE", "COMPUTE_RISK_TIME_ZONE", "COMPUTE_RISK_TIMEOUT",
            "COMPUTE_RISK_MEMORY", "COMPUTE_RISK_CPU", "LOG_LEVEL", "FIRESTORE_AUTH_MODE",
            "VERIFY_TIMEOUT_SECONDS", "VERIFY_MAX_AGE_SECONDS", "VERIFY_MIN_WRITTEN") + SETTINGS


APIS = {'run.googleapis.com', 'cloudscheduler.googleapis.com', 'artifactregistry.googleapis.com',
        'firestore.googleapis.com', 'iam.googleapis.com', 'cloudresourcemanager.googleapis.com',
        'serviceusage.googleapis.com', 'logging.googleapis.com', 'cloudbilling.googleapis.com'}

SCHEDULER_SETTINGS = {'SA_SCHEDULER', 'COMPUTE_RISK_SCHEDULER_NAME',
                      'COMPUTE_RISK_SCHEDULE', 'COMPUTE_RISK_TIME_ZONE'}
ONE_TIME_REQUIRED = tuple(key for key in REQUIRED if key not in SCHEDULER_SETTINGS)
ONE_TIME_APIS = APIS - {'cloudscheduler.googleapis.com'}


def validate_image(env):
    """Require an explicit immutable Artifact Registry reference, never a moving tag."""
    root = re.escape(f"{env['REGION']}-docker.pkg.dev/{env['PROJECT_ID']}/")
    if not re.fullmatch(root + r'[a-z0-9-]+/[a-zA-Z0-9_./-]+@sha256:[a-f0-9]{64}', env.get('IMAGE', '')):
        raise ValueError('IMAGE requires a reviewed sha256 digest in the configured project/region')


def validate_config(env, *, one_time=False):
    for key in ONE_TIME_REQUIRED if one_time else REQUIRED:
        if not env.get(key) or any(c in env[key] for c in '\n\r'):
            raise ValueError(f"Missing or invalid {key}")
    project = env['PROJECT_ID']
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]', project):
        raise ValueError('Invalid PROJECT_ID')
    for key in ('FIREBASE_PROJECT_ID', 'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT'):
        if env.get(key) and env[key] != project:
            raise ValueError('Conflicting project configuration')
    if env.get('FIRESTORE_AUTH_MODE') != 'attached':
        raise ValueError('Deployment requires FIRESTORE_AUTH_MODE=attached')
    if env.get('FIRESTORE_EMULATOR_HOST') or env.get('GOOGLE_APPLICATION_CREDENTIALS'):
        raise ValueError('Attached runtime conflicts with emulator or credential file')
    for key in ('SA_JOBS',) if one_time else ('SA_JOBS', 'SA_SCHEDULER'):
        if not re.fullmatch(r'[a-z0-9-]+@' + re.escape(project) + r'\.iam\.gserviceaccount\.com', env[key]):
            raise ValueError(f'{key} must belong to PROJECT_ID')
    validate_image(env)
    for key in SETTINGS + ('VERIFY_TIMEOUT_SECONDS', 'VERIFY_MAX_AGE_SECONDS', 'VERIFY_MIN_WRITTEN'):
        if not env[key].isdigit() or int(env[key]) < (1 if key in ('RISK_LOOKBACK_WEEKS', 'VERIFY_TIMEOUT_SECONDS', 'VERIFY_MAX_AGE_SECONDS', 'VERIFY_MIN_WRITTEN') else 0):
            raise ValueError(f'Invalid {key}')
    for key in ('COMPUTE_RISK_JOB_NAME', 'REGION') if one_time else ('COMPUTE_RISK_JOB_NAME', 'COMPUTE_RISK_SCHEDULER_NAME', 'REGION'):
        if not re.fullmatch(r'[a-z][a-z0-9-]*', env[key]):
            raise ValueError(f'Invalid {key}')
    if not one_time:
        validate_schedule(env)
    if not re.fullmatch(r'[1-9][0-9]*(Mi|Gi)', env['COMPUTE_RISK_MEMORY']) or env['COMPUTE_RISK_CPU'] not in ('1', '2', '4', '8'):
        raise ValueError('Invalid runtime resources')
    from ml.pipelines.clean import load_cities
    cities = load_cities()
    if int(env['VERIFY_MIN_WRITTEN']) > len(cities):
        raise ValueError('VERIFY_MIN_WRITTEN exceeds configured city count')
    if one_time and (len(cities) < 5 or len({city['name'] for city in cities}) != len(cities)):
        raise ValueError('One-time deployment requires at least five distinct configured cities')
    if not re.fullmatch(r'[1-9][0-9]*s', env['COMPUTE_RISK_TIMEOUT']):
        raise ValueError('COMPUTE_RISK_TIMEOUT must be positive seconds')
    if int(env['VERIFY_TIMEOUT_SECONDS']) <= int(env['COMPUTE_RISK_TIMEOUT'][:-1]):
        raise ValueError('Verification timeout must exceed task timeout')
    if env['LOG_LEVEL'] not in ('DEBUG', 'INFO'):
        raise ValueError('LOG_LEVEL must retain INFO run evidence')


def validate_schedule(env):
    fields = env['COMPUTE_RISK_SCHEDULE'].split()
    if len(fields) != 5:
        raise ValueError('Schedule requires five cron fields')
    for field, lower, upper in zip(fields, (0, 0, 1, 1, 0), (59, 23, 31, 12, 6)):
        for part in field.split(','):
            match = re.fullmatch(r'(\*|[0-9]+(?:-[0-9]+)?)(?:/([0-9]+))?', part)
            if not match or (match[2] is not None and int(match[2]) == 0):
                raise ValueError('Invalid numeric cron schedule')
            if match[1] != '*':
                bounds = [int(v) for v in match[1].split('-')]
                if any(v < lower or v > upper for v in bounds) or bounds[0] > bounds[-1]:
                    raise ValueError('Cron field out of range')
    # The documented job cadence uses UTC. Other zones require a reviewed policy.
    if env['COMPUTE_RISK_TIME_ZONE'] != 'UTC':
        raise ValueError('Compute-risk deployment requires UTC time zone')


def timestamp(value):
    result = value if isinstance(value, datetime) else datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('Timestamp requires timezone')
    return result


def execution_state(body):
    status = body.get('status', {})
    if any(int(status.get(k, 0)) for k in ('failedCount', 'cancelledCount')):
        raise RuntimeError('Execution failed or cancelled')
    conditions = status.get('conditions', [])
    for condition in conditions:
        if condition.get('type') == 'Completed':
            if condition.get('status') == 'False':
                raise RuntimeError(f"Execution unsuccessful: {condition.get('reason', 'unknown')}")
            if condition.get('status') == 'True':
                if int(status.get('succeededCount', 0)) != 1:
                    raise RuntimeError('Execution did not complete its single task')
                return True
    if status.get('completionTime'):
        raise RuntimeError('Execution terminated without success')
    return False


def assert_results(evidence, heartbeat, documents, cities, started, now, max_age, minimum):
    """Read-only assertions; exact persisted timestamps link logs to stored results."""
    began, finished, generated = [timestamp(evidence[k]) for k in ('startedAt', 'finishedAt', 'generatedAt')]
    if not started <= began <= generated <= finished <= now or (now - finished).total_seconds() > max_age:
        raise ValueError('Stale or unrelated run evidence')
    rows = evidence['cities']
    if len(rows) != len(cities) or {r['city'] for r in rows} != set(cities):
        raise ValueError('Insufficient city coverage')
    counts = {}
    for row in rows:
        if row['status'] not in ('written', 'error', 'skipped_no_data', 'skipped_insufficient'):
            raise ValueError('Unknown city outcome')
        counts[row['status']] = counts.get(row['status'], 0) + 1
    written = counts.get('written', 0)
    expected_status = 'ok' if written == len(cities) else 'degraded'
    if written < minimum or evidence['status'] != expected_status or evidence['counts'] != counts:
        raise ValueError('Insufficient or inconsistent results')
    if evidence.get('heartbeatWritten') is not True or heartbeat.get('job') != 'compute_risk' or heartbeat.get('status') != expected_status or heartbeat.get('counts') != counts:
        raise ValueError('Heartbeat failure or outcome mismatch')
    if timestamp(heartbeat['startedAt']) != began or timestamp(heartbeat['finishedAt']) != finished:
        raise ValueError('Heartbeat belongs to another run')
    if heartbeat.get('total') != len(cities) or heartbeat.get('ok') != (expected_status == 'ok') or heartbeat.get('error') is not None:
        raise ValueError('Invalid heartbeat')
    for row in rows:
        if row['status'] == 'written':
            doc = documents[row['doc_id']]
            if doc['city'] != row['city'] or timestamp(doc['generatedAt']) != generated:
                raise ValueError('Stale or unrelated risk document')
    return expected_status


class Controller:
    def __init__(self, env, call=None, clock=time.monotonic, sleep=time.sleep, db_factory=None, *, one_time=False):
        self.env = env
        self.one_time = one_time
        self.call = call or self._call
        self.clock, self.sleep = clock, sleep
        self.db_factory = db_factory
        self.deadline = None
        self.db = None
        self.job_exists = False

    def _call(self, args):
        if self.one_time and args[:1] == ['scheduler']:
            raise ValueError('Scheduler access is forbidden in one-time mode')
        # Defense in depth: this controller cannot provision prerequisite infrastructure.
        allowed = (
            ('config', 'get-value', 'project'), ('auth', 'list'),
            ('auth', 'application-default', 'print-access-token'), ('services', 'list'),
            ('artifacts', 'docker', 'images', 'describe'), ('iam', 'service-accounts', 'describe'),
            ('projects', 'get-iam-policy'), ('projects', 'describe'),
            ('billing', 'projects', 'describe'), ('logging', 'read'),
            *(('run', 'jobs', action) for action in ('list', 'describe', 'get-iam-policy', 'create', 'update', 'execute')),
            ('run', 'jobs', 'executions', 'describe'),
            *(('scheduler', 'jobs', action) for action in ('list', 'describe', 'pause', 'resume')),
            ('scheduler', 'jobs', 'create', 'http'), ('scheduler', 'jobs', 'update', 'http'),
        )
        if not any(tuple(args[:len(prefix)]) == prefix for prefix in allowed):
            raise ValueError('Forbidden compute-risk provisioning command')
        process_env = dict(os.environ)
        # gcloud can otherwise offer to enable disabled APIs even for read commands.
        process_env['CLOUDSDK_CORE_SHOULD_PROMPT_TO_ENABLE_API'] = 'false'
        process_env['CLOUDSDK_CORE_DISABLE_PROMPTS'] = 'true'
        timeout = self.remaining(60)
        try:
            return subprocess.run(['gcloud', *args, '--quiet'], check=True, text=True,
                                  capture_output=True, stdin=subprocess.DEVNULL,
                                  env=process_env, timeout=timeout).stdout.strip()
        except (subprocess.SubprocessError, OSError) as exc:
            raise RuntimeError(f'gcloud {args[0]} {args[1]} failed ({type(exc).__name__})') from None

    def remaining(self, maximum):
        if self.deadline is None:
            return maximum
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise TimeoutError("Verification deadline exceeded")
        return min(maximum, remaining)

    def run(self, *args, location=False):
        return self.call([*args, f"--project={self.env['PROJECT_ID']}",
                          f"--{'location' if location else 'region'}={self.env['REGION']}"])

    def operator_db(self):
        if self.db is None:
            if self.db_factory:
                self.db = self.db_factory()
            else:
                # The verifier uses operator ADC; the deployed job uses attached ADC.
                os.environ['FIREBASE_PROJECT_ID'] = self.env['PROJECT_ID']
                os.environ['FIRESTORE_AUTH_MODE'] = 'adc'
                from app.jobs.firestore_runtime import get_firestore_client
                self.db = get_firestore_client()
        return self.db

    def preflight(self):
        e = self.env
        validate_config(e, one_time=self.one_time)
        if self.call(['config', 'get-value', 'project']) != e['PROJECT_ID']:
            raise ValueError('gcloud active project mismatch')
        if not self.call(['auth', 'list', '--filter=status:ACTIVE', '--format=value(account)']):
            raise ValueError('No active gcloud identity')
        if not self.call(['auth', 'application-default', 'print-access-token']):
            raise ValueError('Operator ADC unavailable')
        enabled = set(self.call(['services', 'list', '--enabled', f'--project={e["PROJECT_ID"]}',
                                 '--format=value(config.name)']).splitlines())
        missing = (ONE_TIME_APIS if self.one_time else APIS) - enabled
        if missing:
            raise ValueError('Required APIs are not already enabled: ' + ', '.join(sorted(missing)))
        project = json.loads(self.call(['projects', 'describe', e['PROJECT_ID'], '--format=json']))
        if project.get('projectId') != e['PROJECT_ID'] or project.get('lifecycleState') != 'ACTIVE' or not str(project.get('projectNumber', '')).isdigit():
            raise ValueError('Project identity/state could not be confirmed')
        billing = json.loads(self.call(['billing', 'projects', 'describe', e['PROJECT_ID'], '--format=json']))
        if billing.get('projectId') != e['PROJECT_ID'] or billing.get('billingEnabled') is not True:
            raise ValueError('Project billing is not already enabled')
        self.call(['artifacts', 'docker', 'images', 'describe', e['IMAGE'], f'--project={e["PROJECT_ID"]}', '--format=json'])
        for key in ('SA_JOBS',) if self.one_time else ('SA_JOBS', 'SA_SCHEDULER'):
            account = json.loads(self.call(['iam', 'service-accounts', 'describe', e[key],
                                           f'--project={e["PROJECT_ID"]}', '--format=json']))
            if account.get('disabled') or account.get('email') != e[key]:
                raise ValueError(f'{key} is disabled or mismatched')
        jobs = json.loads(self.run('run', 'jobs', 'list', '--format=json'))
        self.job_exists = any(j['metadata']['name'] == e['COMPUTE_RISK_JOB_NAME'] for j in jobs)
        policy = json.loads(self.call(['projects', 'get-iam-policy', e['PROJECT_ID'], '--format=json']))
        def has_role(policy, email, role):
            return any(b.get('role') == role and 'serviceAccount:' + email in b.get('members', [])
                       and not b.get('condition') for b in policy.get('bindings', []))
        agent = f'service-{project["projectNumber"]}@gcp-sa-cloudscheduler.iam.gserviceaccount.com'
        if not self.one_time and not has_role(policy, agent, 'roles/cloudscheduler.serviceAgent'):
            raise ValueError('Scheduler service agent requires its pre-existing roles/cloudscheduler.serviceAgent binding')
        for role in ('roles/datastore.user',):
            if not has_role(policy, e['SA_JOBS'], role):
                raise ValueError(f'SA_JOBS requires pre-existing unconditional {role}')
        if not self.one_time and not has_role(policy, e['SA_SCHEDULER'], 'roles/run.invoker'):
            job_policy = json.loads(self.run('run', 'jobs', 'get-iam-policy', e['COMPUTE_RISK_JOB_NAME'], '--format=json')) if self.job_exists else {}
            if not has_role(job_policy, e['SA_SCHEDULER'], 'roles/run.invoker'):
                raise ValueError('SA_SCHEDULER requires pre-existing roles/run.invoker (project or existing job)')
        # Prove operator read access before scheduler mutation. An absent first-run heartbeat is allowed.
        self.operator_db().collection('jobHeartbeats').document('compute_risk').get(timeout=30)

        # Verification also reads risk documents; prove collection read access offline-testably.
        self.operator_db().collection('riskEstimates').limit(1).get(timeout=30)

    def pause_existing(self):
        # A successful list distinguishes absence from permission/transport failure.
        names = json.loads(self.run('scheduler', 'jobs', 'list', '--format=json', location=True))
        name = self.env['COMPUTE_RISK_SCHEDULER_NAME']
        exists = any(item['name'].split('/')[-1] == name for item in names)
        if exists:
            self.run('scheduler', 'jobs', 'pause', name, location=True)
            state = json.loads(self.run('scheduler', 'jobs', 'describe', name, '--format=json', location=True))
            if state.get('state') != 'PAUSED':
                raise ValueError('Scheduler pause was not confirmed')
        return exists

    def deploy_job(self):
        e = self.env
        names = json.loads(self.run('run', 'jobs', 'list', '--format=json'))
        action = 'update' if any(x['metadata']['name'] == e['COMPUTE_RISK_JOB_NAME'] for x in names) else 'create'
        variables = {k: e[k] for k in SETTINGS}
        variables.update(FIREBASE_PROJECT_ID=e['PROJECT_ID'], FIRESTORE_AUTH_MODE='attached', LOG_LEVEL=e['LOG_LEVEL'])
        self.run('run', 'jobs', action, e['COMPUTE_RISK_JOB_NAME'], f"--image={e['IMAGE']}",
                 f"--service-account={e['SA_JOBS']}", '--command=python', '--args=-m,app.jobs.compute_risk',
                 '--set-env-vars=' + ','.join(f'{k}={v}' for k, v in variables.items()),
                 f"--memory={e['COMPUTE_RISK_MEMORY']}", f"--cpu={e['COMPUTE_RISK_CPU']}",
                 f"--task-timeout={e['COMPUTE_RISK_TIMEOUT']}", '--max-retries=0', '--tasks=1')

    def verify_runtime(self):
        e = self.env
        job = json.loads(self.run('run', 'jobs', 'describe', e['COMPUTE_RISK_JOB_NAME'], '--format=json'))
        spec = job['spec']['template']['spec']['template']['spec']
        container = spec['containers'][0]
        variables = {v['name']: v.get('value') for v in container.get('env', [])}
        expected = {k: e[k] for k in SETTINGS}
        expected.update(FIREBASE_PROJECT_ID=e['PROJECT_ID'], FIRESTORE_AUTH_MODE='attached', LOG_LEVEL=e['LOG_LEVEL'])
        if int(job['spec']['template']['spec'].get('taskCount', 1)) != 1 or int(spec.get('maxRetries', 0)) != 0:
            raise ValueError('Verification requires one task and no retries')
        if container.get('command') != ['python'] or container.get('args') != ['-m', 'app.jobs.compute_risk'] or container.get('image') != e['IMAGE'] or spec.get('serviceAccountName') != e['SA_JOBS']:
            raise ValueError('Runtime command/image/identity mismatch')
        if any(variables.get(k) != v for k, v in expected.items()) or any(k in variables for k in ('FIRESTORE_EMULATOR_HOST', 'GOOGLE_APPLICATION_CREDENTIALS')):
            raise ValueError('Runtime project/authentication/freshness mismatch')
        if any(variables.get(k, e['PROJECT_ID']) != e['PROJECT_ID'] for k in ('GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT')):
            raise ValueError('Runtime project conflict')

    def verify(self):
        self.verify_runtime()
        started = datetime.now(timezone.utc)
        deadline = self.clock() + int(self.env['VERIFY_TIMEOUT_SECONDS'])
        self.deadline = deadline
        body = json.loads(self.run('run', 'jobs', 'execute', self.env['COMPUTE_RISK_JOB_NAME'], '--async', '--format=json'))
        execution = body.get('metadata', {}).get('name')
        if not execution or not re.fullmatch(r'[a-z0-9-]+', execution):
            raise ValueError('Execute did not return a specific execution')
        while self.clock() < deadline:
            body = json.loads(self.run('run', 'jobs', 'executions', 'describe', execution, '--format=json'))
            if body.get('metadata', {}).get('name') != execution or timestamp(body['metadata']['creationTimestamp']) < started:
                raise ValueError('Old or unrelated execution')
            if execution_state(body):
                break
            self.sleep(min(5, max(0, deadline - self.clock())))
        else:
            raise TimeoutError('Execution verification timed out; schedule remains paused/absent')
        # Log delivery can lag. Retry read-only evidence checks within the SAME deadline.
        query = (f'resource.type="cloud_run_job" AND resource.labels.job_name="{self.env["COMPUTE_RISK_JOB_NAME"]}" '
                 f'AND resource.labels.location="{self.env["REGION"]}" '
                 f'AND labels."run.googleapis.com/execution_name"="{execution}" AND jsonPayload.event="run_evidence"')
        while self.clock() < deadline:
            logs = json.loads(self.call(['logging', 'read', query, f'--project={self.env["PROJECT_ID"]}', '--format=json', '--limit=100']))
            if len(logs) == 1:
                evidence = logs[0]['jsonPayload']
                break
            if len(logs) > 1:
                raise ValueError('Ambiguous run evidence')
            self.sleep(5)
        else:
            raise TimeoutError('No exact execution evidence before deadline')
        db = self.operator_db()
        from ml.pipelines.clean import load_cities
        cities = [c['name'] for c in load_cities()]
        heartbeat = db.collection('jobHeartbeats').document('compute_risk').get(timeout=self.remaining(30)).to_dict() or {}
        documents = {r['doc_id']: db.collection('riskEstimates').document(r['doc_id']).get(timeout=self.remaining(30)).to_dict() or {}
                     for r in evidence['cities'] if r['status'] == 'written'}
        status = assert_results(evidence, heartbeat, documents, cities, started, datetime.now(timezone.utc),
                                int(self.env['VERIFY_MAX_AGE_SECONDS']),
                                max(5, len(cities), int(self.env['VERIFY_MIN_WRITTEN'])) if self.one_time
                                else int(self.env['VERIFY_MIN_WRITTEN']))
        self.remaining(1)
        self.deadline = None
        print(f'Verified {execution}: {status}; counts={evidence["counts"]}')
        return status

    def execute(self, provision=False):
        self.preflight()
        if self.one_time:
            # No scheduler reads, mutations or compensating cleanup on any outcome.
            # verify submits once and proves that exact execution; never retry here.
            self.deploy_job()
            return self.verify()
        try:
            exists = self.pause_existing()
            if provision:
                self.deploy_job()
            self.verify()
            if provision:
                e = self.env
                self.run('scheduler', 'jobs', 'update' if exists else 'create', 'http', e['COMPUTE_RISK_SCHEDULER_NAME'],
                         f'--schedule={e["COMPUTE_RISK_SCHEDULE"]}', f'--time-zone={e["COMPUTE_RISK_TIME_ZONE"]}',
                         f'--uri=https://{e["REGION"]}-run.googleapis.com/v2/projects/{e["PROJECT_ID"]}/locations/{e["REGION"]}/jobs/{e["COMPUTE_RISK_JOB_NAME"]}:run',
                         '--http-method=POST', f'--oauth-service-account-email={e["SA_SCHEDULER"]}', location=True)
                if exists:
                    self.run('scheduler', 'jobs', 'resume', e['COMPUTE_RISK_SCHEDULER_NAME'], location=True)
                state = json.loads(self.run('scheduler', 'jobs', 'describe', e['COMPUTE_RISK_SCHEDULER_NAME'], '--format=json', location=True))
                if state.get('state') != 'ENABLED':
                    raise ValueError('Scheduler activation was not confirmed')
        except Exception as failure:
            # Remote mutation may have succeeded despite a lost response. Cleanup
            # must have its own budget, even after verification timed out.
            self.deadline = None
            try:
                self.pause_existing()
            except Exception as cleanup:
                error = RuntimeError(
                    f'Compute-risk operation failed ({type(failure).__name__}); '
                    f'compensating scheduler pause also failed ({type(cleanup).__name__}). '
                    f'Schedule {self.env["COMPUTE_RISK_SCHEDULER_NAME"]} state is unknown; '
                    'operator action required: inspect and pause the schedule before retrying.')
                error.cleanup_error = cleanup
                raise error from failure
            raise


def main(argv=None):
    """Public modes share preflight; one-time never enters scheduler handling."""
    import sys
    argv = sys.argv[1:] if argv is None else argv
    try:
        if argv not in (['provision'], ['verify'], ['one-time']):
            raise ValueError('Use provision, verify or one-time explicitly')
        Controller(dict(os.environ), one_time=argv == ['one-time']).execute(
            provision=argv == ['provision'])
    except Exception as exc:
        print(f'Deployment/verification failed: {type(exc).__name__}: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    sys.exit(main())
