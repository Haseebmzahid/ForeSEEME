"""Explicit dispatch deployment/verification; imports perform no cloud operations.

Reuses compute-risk's deadline, execution-state and scheduler pause checks.
Dispatch logic and stored document shapes remain in the runtime job.
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

# The shell entrypoints execute this file directly; make backend importable first.
if __package__ in (None, ''):
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from deploy.compute_risk_control import Controller as ComputeController
from deploy.compute_risk_control import execution_state, timestamp, validate_image

PREFIX = 'DISPATCH_ALERTS_'
REQUIRED = ('PROJECT_ID', 'REGION', 'IMAGE', 'SA_JOBS', 'SA_SCHEDULER',
            'FIRESTORE_AUTH_MODE', 'LOG_LEVEL', 'VERIFY_TIMEOUT_SECONDS',
            'VERIFY_MAX_AGE_SECONDS') + tuple(PREFIX + k for k in
                ('JOB_NAME', 'SCHEDULER_NAME', 'SCHEDULE', 'TIME_ZONE', 'TIMEOUT', 'MEMORY', 'CPU'))
APIS = {'run.googleapis.com', 'cloudscheduler.googleapis.com', 'artifactregistry.googleapis.com',
        'firestore.googleapis.com', 'fcm.googleapis.com', 'iam.googleapis.com',
        'cloudresourcemanager.googleapis.com', 'serviceusage.googleapis.com', 'logging.googleapis.com',
        'cloudbilling.googleapis.com'}
OUTCOMES = {'sent', 'token_invalid', 'skipped_idempotent', 'skipped_throttled', 'failed'}


def validate_config(env):
    for key in REQUIRED:
        if not env.get(key) or any(c in env[key] for c in '\n\r'):
            raise ValueError(f'Missing or invalid {key}')
    project = env['PROJECT_ID']
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]', project):
        raise ValueError('Invalid PROJECT_ID')
    for key in ('FIREBASE_PROJECT_ID', 'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT'):
        if env.get(key) and env[key] != project:
            raise ValueError('Conflicting project configuration')
    if env['FIRESTORE_AUTH_MODE'] != 'attached' or env.get('FIRESTORE_EMULATOR_HOST') or env.get('GOOGLE_APPLICATION_CREDENTIALS'):
        raise ValueError('Dispatch deployment requires attached identity, explicit project, no emulator/key file')
    for key in ('SA_JOBS', 'SA_SCHEDULER'):
        if not re.fullmatch(r'[a-z0-9-]+@' + re.escape(project) + r'\.iam\.gserviceaccount\.com', env[key]):
            raise ValueError(f'{key} must belong to PROJECT_ID')
    for key in ('REGION', PREFIX + 'JOB_NAME', PREFIX + 'SCHEDULER_NAME'):
        if not re.fullmatch(r'[a-z][a-z0-9-]{0,62}', env[key]):
            raise ValueError(f'Invalid {key}')
    validate_image(env)
    for key in ('VERIFY_TIMEOUT_SECONDS', 'VERIFY_MAX_AGE_SECONDS'):
        if not env[key].isdigit() or int(env[key]) < 1:
            raise ValueError(f'Invalid {key}')
    if not re.fullmatch(r'[1-9][0-9]*s', env[PREFIX + 'TIMEOUT']):
        raise ValueError('DISPATCH_ALERTS_TIMEOUT must be positive seconds')
    if int(env['VERIFY_TIMEOUT_SECONDS']) <= int(env[PREFIX + 'TIMEOUT'][:-1]):
        raise ValueError('Verification timeout must exceed task timeout')
    if not re.fullmatch(r'[1-9][0-9]*(Mi|Gi)', env[PREFIX + 'MEMORY']) or env[PREFIX + 'CPU'] not in ('1', '2', '4', '8'):
        raise ValueError('Invalid dispatch runtime resources')
    if env['LOG_LEVEL'] not in ('INFO', 'DEBUG'):
        raise ValueError('LOG_LEVEL must retain INFO job_run evidence')
    if env[PREFIX + 'TIME_ZONE'] != 'UTC':
        raise ValueError('Dispatch deployment requires UTC time zone')
    fields = env[PREFIX + 'SCHEDULE'].split()
    if len(fields) != 5:
        raise ValueError('Schedule requires five numeric cron fields')
    for field, lower, upper in zip(fields, (0, 0, 1, 1, 0), (59, 23, 31, 12, 6)):
        for part in field.split(','):
            match = re.fullmatch(r'(\*|[0-9]+(?:-[0-9]+)?)(?:/([0-9]+))?', part)
            if not match or (match[2] is not None and int(match[2]) == 0):
                raise ValueError('Invalid numeric cron schedule')
            if match[1] != '*':
                bounds = [int(v) for v in match[1].split('-')]
                if any(v < lower or v > upper for v in bounds) or bounds[0] > bounds[-1]:
                    raise ValueError('Cron field out of range')


def valid_count(value):
    # Cloud Logging JSON numbers may serialize whole counts as doubles.
    return type(value) in (int, float) and math.isfinite(value) and value >= 0 and value == int(value)


def assert_report(signal, heartbeat, started, now, max_age):
    began, finished = timestamp(signal['startedAt']), timestamp(signal['finishedAt'])
    if not started <= began <= finished <= now or (now - finished).total_seconds() > max_age:
        raise ValueError('Stale or unrelated dispatch signal')
    counts = signal['counts']
    if not isinstance(counts, dict) or any(k not in OUTCOMES or not valid_count(v) for k, v in counts.items()):
        raise ValueError('Invalid dispatch outcome counts')
    if counts.get('failed', 0) or signal.get('status') != 'ok' or signal.get('job') != 'dispatch_alerts' or signal.get('heartbeatWritten') is not True or signal.get('alert') is not False or signal.get('error') is not None:
        raise ValueError('Dispatch run is failed/degraded or heartbeat was not written')
    if not valid_count(signal.get('total')) or signal['total'] != sum(counts.values()):
        raise ValueError('Inconsistent dispatch total')
    if not isinstance(heartbeat.get('counts'), dict) or any(not valid_count(v) for v in heartbeat['counts'].values()) or not valid_count(heartbeat.get('total')):
        raise ValueError('Invalid persisted heartbeat counts')
    if heartbeat.get('job') != 'dispatch_alerts' or heartbeat.get('status') != 'ok' or heartbeat.get('ok') is not True or heartbeat.get('error') is not None or heartbeat.get('counts') != counts or heartbeat.get('total') != signal['total']:
        raise ValueError('Persisted heartbeat does not prove successful dispatch')
    if timestamp(heartbeat['startedAt']) != began or timestamp(heartbeat['finishedAt']) != finished:
        raise ValueError('Heartbeat belongs to another dispatch run')
    # Zero sends is healthy per the existing job contract; not proof of device delivery.
    return counts


class Controller(ComputeController):
    def __init__(self, env, **kwargs):
        # Map only the names used by the reference transport/pause helper.
        # No risk settings are supplied, required or deployed for dispatch.
        env = dict(env)
        env['COMPUTE_RISK_JOB_NAME'] = env.get(PREFIX + 'JOB_NAME', '')
        env['COMPUTE_RISK_SCHEDULER_NAME'] = env.get(PREFIX + 'SCHEDULER_NAME', '')
        super().__init__(env, **kwargs)
        self.db = None
        self.job_exists = False

    def _call(self, args):
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
            raise ValueError('Forbidden dispatch provisioning command')
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
        validate_config(e)
        if self.call(['config', 'get-value', 'project']) != e['PROJECT_ID']:
            raise ValueError('gcloud active project mismatch')
        if not self.call(['auth', 'list', '--filter=status:ACTIVE', '--format=value(account)']):
            raise ValueError('No active gcloud identity')
        if not self.call(['auth', 'application-default', 'print-access-token']):
            raise ValueError('Operator ADC unavailable')
        enabled = set(self.call(['services', 'list', '--enabled', f'--project={e["PROJECT_ID"]}',
                                 '--format=value(config.name)']).splitlines())
        missing = APIS - enabled
        if missing:
            raise ValueError('Required APIs are not already enabled: ' + ', '.join(sorted(missing)))
        project = json.loads(self.call(['projects', 'describe', e['PROJECT_ID'], '--format=json']))
        if project.get('projectId') != e['PROJECT_ID'] or project.get('lifecycleState') != 'ACTIVE' or not str(project.get('projectNumber', '')).isdigit():
            raise ValueError('Project identity/state could not be confirmed')
        billing = json.loads(self.call(['billing', 'projects', 'describe', e['PROJECT_ID'], '--format=json']))
        if billing.get('projectId') != e['PROJECT_ID'] or billing.get('billingEnabled') is not True:
            raise ValueError('Project billing is not already enabled')
        self.call(['artifacts', 'docker', 'images', 'describe', e['IMAGE'], f'--project={e["PROJECT_ID"]}', '--format=json'])
        for key in ('SA_JOBS', 'SA_SCHEDULER'):
            account = json.loads(self.call(['iam', 'service-accounts', 'describe', e[key],
                                           f'--project={e["PROJECT_ID"]}', '--format=json']))
            if account.get('disabled') or account.get('email') != e[key]:
                raise ValueError(f'{key} is disabled or mismatched')
        jobs = json.loads(self.run('run', 'jobs', 'list', '--format=json'))
        self.job_exists = any(j['metadata']['name'] == e[PREFIX + 'JOB_NAME'] for j in jobs)
        policy = json.loads(self.call(['projects', 'get-iam-policy', e['PROJECT_ID'], '--format=json']))
        def has_role(policy, email, role):
            return any(b.get('role') == role and 'serviceAccount:' + email in b.get('members', [])
                       and not b.get('condition') for b in policy.get('bindings', []))
        agent = f'service-{project["projectNumber"]}@gcp-sa-cloudscheduler.iam.gserviceaccount.com'
        if not has_role(policy, agent, 'roles/cloudscheduler.serviceAgent'):
            raise ValueError('Scheduler service agent requires its pre-existing roles/cloudscheduler.serviceAgent binding')
        for role in ('roles/datastore.user', 'roles/firebasemessaging.admin'):
            if not has_role(policy, e['SA_JOBS'], role):
                raise ValueError(f'SA_JOBS requires pre-existing unconditional {role}')
        if not has_role(policy, e['SA_SCHEDULER'], 'roles/run.invoker'):
            job_policy = json.loads(self.run('run', 'jobs', 'get-iam-policy', e[PREFIX + 'JOB_NAME'], '--format=json')) if self.job_exists else {}
            if not has_role(job_policy, e['SA_SCHEDULER'], 'roles/run.invoker'):
                raise ValueError('SA_SCHEDULER requires pre-existing roles/run.invoker (project or existing job)')
        # Prove operator read access before scheduler mutation. An absent first-run heartbeat is allowed.
        self.operator_db().collection('jobHeartbeats').document('dispatch_alerts').get(timeout=30)

    def deploy_job(self):
        e = self.env
        self.run('run', 'jobs', 'update' if self.job_exists else 'create', e[PREFIX + 'JOB_NAME'],
                 f'--image={e["IMAGE"]}', f'--service-account={e["SA_JOBS"]}', '--command=python',
                 '--args=-m,app.jobs.dispatch_alerts',
                 f'--set-env-vars=LOG_LEVEL={e["LOG_LEVEL"]},FIREBASE_PROJECT_ID={e["PROJECT_ID"]},FIRESTORE_AUTH_MODE=attached',
                 f'--memory={e[PREFIX + "MEMORY"]}', f'--cpu={e[PREFIX + "CPU"]}',
                 f'--task-timeout={e[PREFIX + "TIMEOUT"]}', '--tasks=1', '--max-retries=0')

    def verify_runtime(self):
        e = self.env
        job = json.loads(self.run('run', 'jobs', 'describe', e[PREFIX + 'JOB_NAME'], '--format=json'))
        template = job['spec']['template']['spec']
        spec = template['template']['spec']
        if len(spec['containers']) != 1 or int(template.get('taskCount', 1)) != 1 or int(spec.get('maxRetries', 3)) != 0:
            raise ValueError('Dispatch verification requires one container/task and zero retries')
        container = spec['containers'][0]
        if container.get('image') != e['IMAGE'] or container.get('command') != ['python'] or container.get('args') != ['-m', 'app.jobs.dispatch_alerts'] or spec.get('serviceAccountName') != e['SA_JOBS']:
            raise ValueError('Dispatch runtime command/image/identity mismatch')
        variables = {v['name']: v.get('value') for v in container.get('env', [])}
        expected = dict(LOG_LEVEL=e['LOG_LEVEL'], FIREBASE_PROJECT_ID=e['PROJECT_ID'], FIRESTORE_AUTH_MODE='attached')
        if any(variables.get(k) != v for k, v in expected.items()) or any(k in variables for k in ('GOOGLE_APPLICATION_CREDENTIALS', 'FIRESTORE_EMULATOR_HOST')):
            raise ValueError('Dispatch runtime project/authentication mismatch')
        if any(variables.get(k, e['PROJECT_ID']) != e['PROJECT_ID'] for k in ('GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT')):
            raise ValueError('Dispatch runtime project conflict')

    def verify(self):
        self.verify_runtime()
        started = datetime.now(timezone.utc)
        self.deadline = self.clock() + int(self.env['VERIFY_TIMEOUT_SECONDS'])
        response = json.loads(self.run('run', 'jobs', 'execute', self.env[PREFIX + 'JOB_NAME'], '--async', '--format=json'))
        execution = response.get('metadata', {}).get('name')
        if not execution or not re.fullmatch(r'[a-z0-9-]+', execution):
            raise ValueError('Execute did not return a specific dispatch execution')
        while True:
            self.remaining(1)
            body = json.loads(self.run('run', 'jobs', 'executions', 'describe', execution, '--format=json'))
            if body.get('metadata', {}).get('name') != execution or timestamp(body['metadata']['creationTimestamp']) < started:
                raise ValueError('Old or unrelated dispatch execution')
            if any(c.get('type') in ('Failed', 'Cancelled') and c.get('status') == 'True' for c in body.get('status', {}).get('conditions', [])):
                raise RuntimeError('Dispatch execution failed or cancelled')
            if execution_state(body):
                break
            self.sleep(self.remaining(5))
        query = (f'resource.type="cloud_run_job" AND resource.labels.job_name="{self.env[PREFIX + "JOB_NAME"]}" '
                 f'AND resource.labels.location="{self.env["REGION"]}" '
                 f'AND labels."run.googleapis.com/execution_name"="{execution}" '
                 'AND jsonPayload.event="job_run" AND jsonPayload.job="dispatch_alerts"')
        while True:
            self.remaining(1)
            logs = json.loads(self.call(['logging', 'read', query, f'--project={self.env["PROJECT_ID"]}', '--format=json', '--limit=100']))
            if len(logs) > 1:
                raise ValueError('Ambiguous dispatch run signal')
            if logs:
                signal = logs[0]['jsonPayload']
                break
            self.sleep(self.remaining(5))
        heartbeat = self.operator_db().collection('jobHeartbeats').document('dispatch_alerts').get(timeout=self.remaining(30)).to_dict() or {}
        counts = assert_report(signal, heartbeat, started, datetime.now(timezone.utc), int(self.env['VERIFY_MAX_AGE_SECONDS']))
        self.remaining(1)
        self.deadline = None
        print(f'Verified dispatch execution {execution}: ok; counts={counts}')
        return counts

    def activate(self, exists):
        e = self.env
        self.run('scheduler', 'jobs', 'update' if exists else 'create', 'http', e[PREFIX + 'SCHEDULER_NAME'],
                 f'--schedule={e[PREFIX + "SCHEDULE"]}', f'--time-zone={e[PREFIX + "TIME_ZONE"]}',
                 f'--uri=https://{e["REGION"]}-run.googleapis.com/v2/projects/{e["PROJECT_ID"]}/locations/{e["REGION"]}/jobs/{e[PREFIX + "JOB_NAME"]}:run',
                 '--http-method=POST', f'--oauth-service-account-email={e["SA_SCHEDULER"]}', location=True)
        if exists:
            self.run('scheduler', 'jobs', 'resume', e[PREFIX + 'SCHEDULER_NAME'], location=True)
        state = json.loads(self.run('scheduler', 'jobs', 'describe', e[PREFIX + 'SCHEDULER_NAME'], '--format=json', location=True))
        if state.get('state') != 'ENABLED':
            raise ValueError('Dispatch scheduler activation was not confirmed')

    def execute(self, provision=False):
        self.preflight()  # No mutation unless all required prerequisites are confirmed.
        try:
            exists = self.pause_existing()
            if provision:
                self.deploy_job()
            self.verify()
            if provision:
                self.activate(exists)
        except Exception as failure:
            # A CLI timeout can occur after remote success. Use a fresh cleanup budget.
            self.deadline = None
            try:
                self.pause_existing()
            except Exception as cleanup:
                raise RuntimeError(f'Dispatch operation failed ({type(failure).__name__}); compensating scheduler pause also failed ({type(cleanup).__name__}). Schedule state is unknown; operator action required.') from failure
            raise


def main(argv=None):
    import sys
    argv = sys.argv[1:] if argv is None else argv
    if argv not in (['provision'], ['verify']):
        raise ValueError('Use provision or verify explicitly; configuration comes from exported environment')
    Controller(dict(os.environ)).execute(provision=argv == ['provision'])
    return 0


if __name__ == '__main__':
    import sys
    try:
        sys.exit(main())
    except Exception as exc:
        print(f'Dispatch deployment/verification failed: {type(exc).__name__}: {exc}', file=sys.stderr)
        sys.exit(1)
