"""Dispatch deployment regressions: CLI, Firestore, sleep and clocks are fake."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock
import json

import pytest
from deploy.dispatch_alerts_control import Controller, validate_config, assert_report, APIS
from app.jobs import dispatch_alerts, firestore_runtime


def config():
    return dict(PROJECT_ID='foreseeme-83587', REGION='us-central1',
        IMAGE='us-central1-docker.pkg.dev/foreseeme-83587/backend/image@sha256:' + 'a' * 64,
        SA_JOBS='risk-jobs-sa@foreseeme-83587.iam.gserviceaccount.com',
        SA_SCHEDULER='scheduler-sa@foreseeme-83587.iam.gserviceaccount.com',
        FIRESTORE_AUTH_MODE='attached', LOG_LEVEL='INFO', VERIFY_TIMEOUT_SECONDS='900', VERIFY_MAX_AGE_SECONDS='900',
        DISPATCH_ALERTS_JOB_NAME='dispatch-alerts-job', DISPATCH_ALERTS_SCHEDULER_NAME='dispatch-alerts-daily',
        DISPATCH_ALERTS_SCHEDULE='10 0 * * *', DISPATCH_ALERTS_TIME_ZONE='UTC', DISPATCH_ALERTS_TIMEOUT='300s',
        DISPATCH_ALERTS_MEMORY='512Mi', DISPATCH_ALERTS_CPU='1')


@pytest.mark.parametrize('key,value', [('PROJECT_ID', ''), ('FIREBASE_PROJECT_ID', 'other'),
    ('GOOGLE_CLOUD_PROJECT', 'other'), ('FIRESTORE_AUTH_MODE', 'adc'), ('GOOGLE_APPLICATION_CREDENTIALS', 'key.json'),
    ('FIRESTORE_EMULATOR_HOST', 'localhost:8080'), ('IMAGE', 'other/image:tag'), ('SA_JOBS', 'wrong@other'),
    ('DISPATCH_ALERTS_SCHEDULE', '99 * * * *'), ('DISPATCH_ALERTS_TIMEOUT', '-1s'),
    ('VERIFY_TIMEOUT_SECONDS', '300'), ('LOG_LEVEL', 'ERROR'), ('DISPATCH_ALERTS_JOB_NAME', 'unsafe"name')])
def test_bad_configuration_prevents_any_cloud_access(key, value):
    env = config(); env[key] = value
    call = Mock(side_effect=AssertionError('Cloud forbidden'))
    with pytest.raises(ValueError): Controller(env, call=call).execute(provision=True)
    call.assert_not_called()


def test_attached_identity_without_json_key_is_valid():
    validate_config(config())


def prerequisites(fault=None, job_exists=False, job_invoker=False):
    e = config(); calls = []; db = Mock()
    def call(args):
        calls.append(args)
        if args[:2] == ['config', 'get-value']: return 'other' if fault == 'project' else e['PROJECT_ID']
        if args[:2] == ['auth', 'list']: return '' if fault == 'cli_auth' else 'operator@example.com'
        if args[:3] == ['auth', 'application-default', 'print-access-token']: return '' if fault == 'adc' else 'FAKE_NOT_LOGGED'
        if args[:2] == ['services', 'list']: return '\n'.join(sorted(APIS - ({'fcm.googleapis.com'} if fault == 'api' else set())))
        if args[:2] == ['projects', 'describe']:
            return json.dumps({'projectId': e['PROJECT_ID'], 'lifecycleState': 'DELETE_REQUESTED' if fault == 'project_state' else 'ACTIVE', 'projectNumber': '123456'})
        if args[:3] == ['billing', 'projects', 'describe']:
            return json.dumps({'projectId': e['PROJECT_ID'], 'billingEnabled': fault != 'billing'})
        if args[:4] == ['artifacts', 'docker', 'images', 'describe']:
            if fault == 'image': raise RuntimeError('Missing reviewed image')
            return '{}'
        if args[:3] == ['iam', 'service-accounts', 'describe']:
            return json.dumps({'email': args[3], 'disabled': fault == 'disabled_account'})
        if args[:3] == ['run', 'jobs', 'list']:
            return json.dumps([{'metadata': {'name': e['DISPATCH_ALERTS_JOB_NAME']}}] if job_exists else [])
        if args[:2] == ['projects', 'get-iam-policy']:
            roles = [('SA_JOBS', 'roles/datastore.user'), ('SA_JOBS', 'roles/firebasemessaging.admin')]
            if not job_invoker: roles.append(('SA_SCHEDULER', 'roles/run.invoker'))
            bindings = [dict(role=role, members=['serviceAccount:' + e[sa]]) for sa, role in roles if role != fault]
            if fault != 'scheduler_agent':
                bindings.append(dict(role='roles/cloudscheduler.serviceAgent', members=['serviceAccount:service-123456@gcp-sa-cloudscheduler.iam.gserviceaccount.com']))
            if fault == 'conditional': bindings[0]['condition'] = {'expression': 'true'}
            return json.dumps({'bindings': bindings})
        if args[:3] == ['run', 'jobs', 'get-iam-policy']:
            return json.dumps({'bindings': [{'role': 'roles/run.invoker', 'members': ['serviceAccount:' + e['SA_SCHEDULER']]}]})
        raise AssertionError(f'Unexpected or mutating command: {args[:4]}')
    if fault == 'firestore_read':
        db.collection.return_value.document.return_value.get.side_effect = RuntimeError('Read denied')
    return Controller(e, call=call, db_factory=lambda: db), calls, db


@pytest.mark.parametrize('fault', ['project', 'cli_auth', 'adc', 'api', 'image', 'disabled_account',
                                  'roles/datastore.user', 'roles/firebasemessaging.admin', 'roles/run.invoker',
                                  'conditional', 'firestore_read', 'billing', 'project_state', 'scheduler_agent'])
def test_missing_prerequisite_prevents_scheduler_mutation(fault):
    controller, calls, db = prerequisites(fault)
    with pytest.raises((ValueError, RuntimeError)): controller.execute(provision=True)
    assert not any(args[:2] == ['scheduler', 'jobs'] for args in calls)
    assert not any('create' in args or 'update' in args for args in calls)


@pytest.mark.parametrize('job_invoker', [False, True])
def test_preflight_only_reads_prerequisites(job_invoker):
    controller, calls, db = prerequisites(job_exists=job_invoker, job_invoker=job_invoker)
    controller.preflight()
    db.collection.return_value.document.return_value.get.assert_called_once_with(timeout=30)
    assert not any(any(v in args for v in ('enable', 'submit', 'create', 'update', 'add-iam-policy-binding')) for args in calls)


@pytest.mark.parametrize('stage', ['pause', 'deploy', 'verify', 'activate'])
def test_failures_prevent_activation_and_attempt_cleanup(stage):
    c = Controller(config(), call=Mock(side_effect=AssertionError('No real CLI')))
    c.preflight = Mock()
    c.pause_existing = Mock(side_effect=[RuntimeError('pause lost response'), True] if stage == 'pause' else None, return_value=True)
    c.deploy_job = Mock(side_effect=RuntimeError('deployment failed') if stage == 'deploy' else None)
    c.verify = Mock(side_effect=TimeoutError('verification failed') if stage == 'verify' else None)
    c.activate = Mock(side_effect=RuntimeError('activation failed') if stage == 'activate' else None)
    with pytest.raises((RuntimeError, TimeoutError)): c.execute(provision=True)
    assert c.pause_existing.call_count == 2
    if stage != 'activate': c.activate.assert_not_called()


def test_cleanup_failure_is_explicit_and_preserves_original_failure():
    c = Controller(config(), call=Mock(side_effect=AssertionError('No CLI')))
    c.preflight = Mock(); c.pause_existing = Mock(side_effect=[True, RuntimeError('SECRET')])
    c.deploy_job = Mock(); c.verify = Mock(side_effect=TimeoutError('deadline')); c.activate = Mock()
    with pytest.raises(RuntimeError, match='compensating scheduler pause also failed') as caught:
        c.execute(provision=True)
    assert isinstance(caught.value.__cause__, TimeoutError)
    assert 'SECRET' not in str(caught.value) and 'operator action required' in str(caught.value)
    c.activate.assert_not_called()


@pytest.mark.parametrize('provision', [False, True])
def test_safe_order_and_verify_never_activates(provision):
    events = []; c = Controller(config(), call=Mock(side_effect=AssertionError('No CLI')))
    c.preflight = lambda: events.append('preflight')
    c.pause_existing = lambda: events.append('pause') or False
    c.deploy_job = lambda: events.append('deploy')
    c.verify = lambda: events.append('verified')
    c.activate = lambda exists: events.append('activate')
    c.execute(provision=provision)
    assert events == (['preflight', 'pause', 'deploy', 'verified', 'activate'] if provision else ['preflight', 'pause', 'verified'])


def test_deploy_sets_only_dispatch_runtime_configuration():
    call = Mock(); c = Controller(config(), call=call)
    c.deploy_job()
    args = call.call_args.args[0]
    assert args[:3] == ['run', 'jobs', 'create']
    assert '--command=python' in args and '--args=-m,app.jobs.dispatch_alerts' in args
    variables = next(a for a in args if a.startswith('--set-env-vars='))
    assert 'FIREBASE_PROJECT_ID=foreseeme-83587' in variables and 'FIRESTORE_AUTH_MODE=attached' in variables
    assert 'GOOGLE_APPLICATION_CREDENTIALS' not in variables and 'RISK_' not in variables
    assert '--tasks=1' in args and '--max-retries=0' in args


def runtime():
    e = config()
    variables = dict(LOG_LEVEL='INFO', FIREBASE_PROJECT_ID=e['PROJECT_ID'], FIRESTORE_AUTH_MODE='attached')
    container = dict(image=e['IMAGE'], command=['python'], args=['-m', 'app.jobs.dispatch_alerts'],
                     env=[dict(name=k, value=v) for k, v in variables.items()])
    spec = dict(containers=[container], serviceAccountName=e['SA_JOBS'], maxRetries=0)
    return dict(spec=dict(template=dict(spec=dict(taskCount=1, template=dict(spec=spec)))))


@pytest.mark.parametrize('fault', ['command', 'project', 'credentials', 'identity', 'retries', 'tasks'])
def test_runtime_mismatch_prevents_execution(fault):
    job = runtime(); template = job['spec']['template']['spec']; spec = template['template']['spec']; container = spec['containers'][0]
    if fault == 'command': container['args'] = ['-m', 'app.main']
    if fault == 'project': container['env'].append(dict(name='GCLOUD_PROJECT', value='other'))
    if fault == 'credentials': container['env'].append(dict(name='GOOGLE_APPLICATION_CREDENTIALS', value='key.json'))
    if fault == 'identity': spec['serviceAccountName'] = 'wrong'
    if fault == 'retries': spec['maxRetries'] = 1
    if fault == 'tasks': template['taskCount'] = 2
    call = Mock(return_value=json.dumps(job))
    with pytest.raises(ValueError): Controller(config(), call=call).verify()
    assert call.call_count == 1


@pytest.mark.parametrize('fault', ['old_name', 'old_time', 'timeout', 'failed', 'cancelled', 'completed_false', 'no_success', 'no_execution'])
def test_verification_cannot_accept_stale_or_unsuccessful_execution(fault):
    calls = []; tick = [0]
    def call(args):
        calls.append(args)
        if args[:3] == ['run', 'jobs', 'execute']:
            return json.dumps({'metadata': {'name': 'exact-execution'}} if fault != 'no_execution' else {})
        assert args[:4] == ['run', 'jobs', 'executions', 'describe']
        now = datetime.now(timezone.utc) - (timedelta(days=1) if fault == 'old_time' else timedelta())
        status = {'conditions': [{'type': 'Completed', 'status': 'True'}], 'succeededCount': 1}
        if fault == 'timeout': status = {}; tick[0] = 901
        if fault == 'failed': status['failedCount'] = 1
        if fault == 'cancelled': status['conditions'] = [{'type': 'Cancelled', 'status': 'True'}]
        if fault == 'completed_false': status['conditions'] = [{'type': 'Completed', 'status': 'False'}]
        if fault == 'no_success': status['succeededCount'] = 0
        return json.dumps({'metadata': {'name': 'old-execution' if fault == 'old_name' else 'exact-execution',
                            'creationTimestamp': now.isoformat()}, 'status': status})
    c = Controller(config(), call=call, clock=lambda: tick[0], sleep=lambda _: None)
    c.verify_runtime = Mock()
    with pytest.raises((ValueError, RuntimeError, TimeoutError)): c.verify()
    assert not any('list' in args for args in calls)


def report_fixture(counts=None):
    now = datetime.now(timezone.utc); started = now - timedelta(seconds=10)
    began = started + timedelta(seconds=1); finished = now - timedelta(seconds=1)
    counts = {} if counts is None else counts
    signal = dict(job='dispatch_alerts', status='ok', alert=False, error=None, counts=counts,
                  total=sum(counts.values()), heartbeatWritten=True, startedAt=began.isoformat(), finishedAt=finished.isoformat())
    heartbeat = dict(job='dispatch_alerts', status='ok', ok=True, error=None, counts=counts,
                     total=signal['total'], startedAt=began, finishedAt=finished)
    return signal, heartbeat, started, now, 900


def test_zero_sends_is_a_valid_success():
    assert assert_report(*report_fixture()) == {}


@pytest.mark.parametrize('fault', ['old_signal', 'old_heartbeat', 'failed', 'degraded', 'missing_heartbeat', 'counts', 'total', 'negative'])
def test_post_run_proof_must_match_exact_successful_run(fault):
    args = list(deepcopy(report_fixture())); signal, heartbeat = args[:2]
    if fault == 'old_signal': signal['startedAt'] = (args[2] - timedelta(days=1)).isoformat()
    if fault == 'old_heartbeat': heartbeat['finishedAt'] -= timedelta(days=1)
    if fault == 'failed': signal['counts'] = {'failed': 1}; signal['total'] = 1
    if fault == 'degraded': signal['status'] = 'degraded'
    if fault == 'missing_heartbeat': signal['heartbeatWritten'] = False
    if fault == 'counts': heartbeat['counts'] = {'sent': 1}
    if fault == 'total': signal['total'] = 1
    if fault == 'negative': signal['counts'] = {'sent': -1}
    with pytest.raises(ValueError): assert_report(*args)


def test_runtime_init_delegates_to_guarded_client(monkeypatch):
    client = Mock(); factory = Mock(return_value=client)
    monkeypatch.setattr(firestore_runtime, 'get_firestore_client', factory)
    assert dispatch_alerts.init_firestore() is client
    factory.assert_called_once_with()


def test_legacy_entrypoints_have_no_implicit_infrastructure_paths():
    root = Path(__file__).resolve().parents[1] / 'deploy'
    for name, mode in [('provision_dispatch_alerts.sh', 'provision'), ('verify_dispatch_alerts.sh', 'verify')]:
        script = (root / name).read_text()
        assert 'dispatch_alerts_control.py' in script and mode in script
        assert 'source ' not in script and 'gcloud ' not in script
    assert 'gcloud ' not in (root / 'common.sh').read_text()

@pytest.mark.parametrize('fault', [None, 'old_log', 'missing_logs', 'ambiguous_logs', 'heartbeat', 'degraded'])
def test_full_verification_uses_exact_execution_scoped_signal(fault):
    run = {}; calls = []; tick = [0]; db = Mock()
    def call(args):
        calls.append(args)
        if args[:3] == ['run', 'jobs', 'describe']: return json.dumps(runtime())
        if args[:3] == ['run', 'jobs', 'execute']:
            run['began'] = datetime.now(timezone.utc)
            return json.dumps({'metadata': {'name': 'dispatch-exact'}})
        if args[:4] == ['run', 'jobs', 'executions', 'describe']:
            assert args[4] == 'dispatch-exact'
            return json.dumps({'metadata': {'name': 'dispatch-exact', 'creationTimestamp': run['began'].isoformat()},
                'status': {'conditions': [{'type': 'Ready', 'status': 'True'}, {'type': 'Completed', 'status': 'True'}], 'succeededCount': 1}})
        assert args[:2] == ['logging', 'read']
        assert 'dispatch-exact' in args[2] and 'resource.labels.location="us-central1"' in args[2]
        assert 'jsonPayload.job="dispatch_alerts"' in args[2]
        if fault == 'missing_logs': tick[0] = 901; return '[]'
        began = run['began'] - (timedelta(days=1) if fault == 'old_log' else timedelta())
        finished = datetime.now(timezone.utc)
        signal = dict(job='dispatch_alerts', status='degraded' if fault == 'degraded' else 'ok', alert=False,
            error=None, counts={}, total=0, heartbeatWritten=True, startedAt=began.isoformat(), finishedAt=finished.isoformat())
        run['heartbeat'] = dict(job='dispatch_alerts', status='ok', ok=True, error=None, counts={}, total=0,
                                startedAt=began, finishedAt=finished - (timedelta(days=1) if fault == 'heartbeat' else timedelta()))
        return json.dumps([{'jsonPayload': signal}] * (2 if fault == 'ambiguous_logs' else 1))
    db.collection.return_value.document.return_value.get.side_effect = lambda **kwargs: Mock(to_dict=lambda: run['heartbeat'])
    c = Controller(config(), call=call, clock=lambda: tick[0], sleep=lambda _: None, db_factory=lambda: db)
    if fault is None: assert c.verify() == {}
    else:
        with pytest.raises((ValueError, TimeoutError)): c.verify()
    assert not any('list' in args for args in calls)


@pytest.mark.parametrize('exists', [False, True])
def test_scheduler_activation_confirms_enabled_state(exists):
    call = Mock(side_effect=['', '', '{"state": "ENABLED"}'] if exists else ['', '{"state": "ENABLED"}'])
    c = Controller(config(), call=call); c.activate(exists)
    commands = [entry.args[0] for entry in call.call_args_list]
    assert commands[0][:4] == ['scheduler', 'jobs', 'update' if exists else 'create', 'http']
    assert any('jobs/dispatch-alerts-job:run' in arg for arg in commands[0])
    assert any(cmd[:3] == ['scheduler', 'jobs', 'resume'] for cmd in commands) == exists
    assert commands[-1][:3] == ['scheduler', 'jobs', 'describe']


def test_failed_verification_cleanup_has_a_fresh_budget():
    c = Controller(config(), call=Mock(side_effect=AssertionError('No CLI')))
    c.preflight = Mock(); pauses = []
    def pause():
        pauses.append(c.deadline)
        return True
    c.pause_existing = pause; c.deploy_job = Mock()
    def verify():
        c.deadline = -1
        raise TimeoutError('deadline expired')
    c.verify = verify
    with pytest.raises(TimeoutError): c.execute(provision=True)
    assert pauses == [None, None]


def test_dispatch_attached_init_needs_no_certificate(monkeypatch):
    import firebase_admin
    from firebase_admin import credentials, firestore
    from types import SimpleNamespace
    for key in ('FIRESTORE_EMULATOR_HOST', 'GOOGLE_APPLICATION_CREDENTIALS', 'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT'):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv('FIREBASE_PROJECT_ID', 'foreseeme-83587')
    monkeypatch.setenv('FIRESTORE_AUTH_MODE', 'attached')
    monkeypatch.setattr(firestore_runtime, '_apps', {})
    monkeypatch.setattr(firestore_runtime, '_file_signature', lambda path: None)
    monkeypatch.setattr(firebase_admin, 'get_app', Mock(side_effect=ValueError('No app')))
    adc = Mock(); monkeypatch.setattr(credentials, 'ApplicationDefault', adc)
    certificate = Mock(side_effect=AssertionError('No key file'))
    monkeypatch.setattr(credentials, 'Certificate', certificate)
    app = SimpleNamespace(project_id='foreseeme-83587', credential=adc.return_value)
    initialize = Mock(return_value=app); monkeypatch.setattr(firebase_admin, 'initialize_app', initialize)
    client = Mock(); monkeypatch.setattr(firestore, 'client', client)
    assert dispatch_alerts.init_firestore() is client.return_value
    certificate.assert_not_called()
    adc.assert_called_once_with()
    initialize.assert_called_once_with(adc.return_value, options={'projectId': 'foreseeme-83587'})

@pytest.mark.parametrize('args', [
    ['services', 'enable', 'fcm.googleapis.com'], ['builds', 'submit', '.'],
    ['projects', 'add-iam-policy-binding', 'foreseeme-83587'],
    ['iam', 'service-accounts', 'create', 'account'],
    ['artifacts', 'repositories', 'create', 'repo'],
    ['run', 'jobs', 'add-iam-policy-binding', 'dispatch-alerts-job'],
    ['scheduler', 'jobs', 'run', 'dispatch-alerts-daily'],
])
def test_transport_refuses_forbidden_provisioning_side_effects(monkeypatch, args):
    import subprocess
    process = Mock(side_effect=AssertionError('No subprocess may run'))
    monkeypatch.setattr(subprocess, 'run', process)
    c = Controller(config())
    with pytest.raises(ValueError, match='Forbidden'): c._call(args)
    process.assert_not_called()


def test_transport_disables_implicit_api_enabling_and_interactive_prompts(monkeypatch):
    import subprocess
    from types import SimpleNamespace
    process = Mock(return_value=SimpleNamespace(stdout='[]'))
    monkeypatch.setattr(subprocess, 'run', process)
    assert Controller(config())._call(['services', 'list']) == '[]'
    kwargs = process.call_args.kwargs
    assert kwargs['env']['CLOUDSDK_CORE_SHOULD_PROMPT_TO_ENABLE_API'] == 'false'
    assert kwargs['env']['CLOUDSDK_CORE_DISABLE_PROMPTS'] == 'true'
    assert kwargs['stdin'] == subprocess.DEVNULL
    assert kwargs['timeout'] == 60 and process.call_args.args[0][-1] == '--quiet'

@pytest.mark.parametrize('value', [True, 0.5, -1, float('inf'), float('nan')])
def test_counter_validation_rejects_non_integral_or_non_finite_proof(value):
    args = report_fixture({'sent': value})
    with pytest.raises(ValueError): assert_report(*args)


def test_whole_json_float_counts_match_persisted_integer_counts():
    args = list(report_fixture({'sent': 1.0}))
    args[1]['counts'] = {'sent': 1}; args[1]['total'] = 1
    assert assert_report(*args) == {'sent': 1}


@pytest.mark.parametrize('image', ['', 'us-central1-docker.pkg.dev/foreseeme-83587/backend/image:latest',
    'us-central1-docker.pkg.dev/foreseeme-83587/backend/image:rc',
    'us-central1-docker.pkg.dev/foreseeme-83587/backend/image@sha256:abc',
    'us-central1-docker.pkg.dev/other-project/backend/image@sha256:' + 'a' * 64])
def test_dispatch_requires_explicit_digest_before_cloud_access(image):
    env = config(); env['IMAGE'] = image
    call = Mock(side_effect=AssertionError('Cloud forbidden'))
    with pytest.raises(ValueError): Controller(env, call=call).execute(provision=True)
    call.assert_not_called()


def test_dispatch_expired_deadline_prevents_cli_call(monkeypatch):
    import subprocess
    process = Mock(side_effect=AssertionError('No process after deadline'))
    monkeypatch.setattr(subprocess, 'run', process)
    c = Controller(config(), clock=lambda: 10); c.deadline = 10
    with pytest.raises(TimeoutError): c._call(['services', 'list'])
    process.assert_not_called()
