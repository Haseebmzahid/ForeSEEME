"""Deployment safety regressions: all CLI, clock and Firestore seams are fake."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import pytest
from deploy.compute_risk_control import Controller, assert_results, execution_state, validate_config, SETTINGS, ONE_TIME_REQUIRED
from app.jobs import observability, firestore_runtime, compute_risk


def config():
    return dict(PROJECT_ID='foreseeme-83587', REGION='us-central1',
                IMAGE='us-central1-docker.pkg.dev/foreseeme-83587/backend/image@sha256:' + 'a' * 64,
                SA_JOBS='risk-jobs-sa@foreseeme-83587.iam.gserviceaccount.com',
                SA_SCHEDULER='scheduler-sa@foreseeme-83587.iam.gserviceaccount.com',
                COMPUTE_RISK_JOB_NAME='compute-risk-job', COMPUTE_RISK_SCHEDULER_NAME='compute-risk-daily',
                COMPUTE_RISK_SCHEDULE='0 0 * * *', COMPUTE_RISK_TIME_ZONE='UTC',
                COMPUTE_RISK_TIMEOUT='600s', COMPUTE_RISK_MEMORY='512Mi', COMPUTE_RISK_CPU='1',
                LOG_LEVEL='INFO', FIRESTORE_AUTH_MODE='attached', RISK_LOOKBACK_WEEKS='12',
                RISK_DATA_DELAY_DAYS='5', RISK_WEATHER_MAX_TRAILING_GAP_DAYS='0', RISK_AQI_MAX_TRAILING_GAP_DAYS='0',
                VERIFY_TIMEOUT_SECONDS='900', VERIFY_MAX_AGE_SECONDS='900', VERIFY_MIN_WRITTEN='1')


@pytest.mark.parametrize('key,value', [('PROJECT_ID', ''), ('FIREBASE_PROJECT_ID', 'other'),
    ('FIRESTORE_AUTH_MODE', 'adc'), ('GOOGLE_APPLICATION_CREDENTIALS', 'secret.json'),
    ('FIRESTORE_EMULATOR_HOST', 'localhost:8080'), ('RISK_AQI_MAX_TRAILING_GAP_DAYS', '-1'),
    ('VERIFY_TIMEOUT_SECONDS', '600'), ('SA_JOBS', 'wrong@other.iam.gserviceaccount.com'),
    ('IMAGE', 'other/image'), ('RISK_DATA_DELAY_DAYS', '')])
def test_bad_config_never_calls_cloud(key, value):
    e = config(); e[key] = value
    call = Mock(side_effect=AssertionError('Cloud access forbidden'))
    with pytest.raises(ValueError):
        Controller(e, call=call).execute(provision=True)
    call.assert_not_called()


@pytest.mark.parametrize('stage', ['preflight', 'deploy', 'verify'])
def test_failure_never_activates_scheduler(stage):
    c = Controller(config(), call=Mock(side_effect=AssertionError('Cloud forbidden')))
    c.preflight = Mock(side_effect=ValueError('bad') if stage == 'preflight' else None)
    c.pause_existing = Mock(return_value=True)
    c.deploy_job = Mock(side_effect=RuntimeError('bad') if stage == 'deploy' else None)
    c.verify = Mock(side_effect=RuntimeError('bad') if stage == 'verify' else None)
    with pytest.raises((ValueError, RuntimeError)):
        c.execute(provision=True)
    c.call.assert_not_called()
    if stage == 'preflight':
        c.pause_existing.assert_not_called()
    else:
        assert c.pause_existing.call_count == 2


def test_verification_precedes_scheduler_activation():
    events = []
    def call(args):
        events.append(args)
        return '{"state": "ENABLED"}'
    c = Controller(config(), call=call)
    c.preflight = lambda: events.append('preflight')
    c.pause_existing = lambda: False
    c.deploy_job = lambda: events.append('deploy')
    c.verify = lambda: events.append('verified')
    c.execute(provision=True)
    assert events[:3] == ['preflight', 'deploy', 'verified']
    assert events[3][:4] == ['scheduler', 'jobs', 'create', 'http']


def test_scheduler_failure_attempts_pause():
    c = Controller(config(), call=Mock(side_effect=RuntimeError('lost response')))
    c.preflight = Mock(); c.pause_existing = Mock(return_value=False)
    c.deploy_job = Mock(); c.verify = Mock()
    with pytest.raises(RuntimeError): c.execute(provision=True)
    assert c.pause_existing.call_count == 2


@pytest.mark.parametrize('status', [
    {'conditions': [{'type': 'Completed', 'status': 'False', 'reason': 'Cancelled'}]},
    {'failedCount': 1}, {'cancelledCount': 1}, {'completionTime': 'now'},
    {'conditions': [{'type': 'Completed', 'status': 'True'}], 'succeededCount': 0},
])
def test_unsuccessful_terminal_states_fail(status):
    with pytest.raises(RuntimeError): execution_state({'status': status})


def test_conditions_are_not_position_dependent():
    assert execution_state({'status': {'conditions': [{'type': 'Ready', 'status': 'True'},
        {'type': 'Completed', 'status': 'True'}], 'succeededCount': 1}})


@pytest.mark.parametrize('old', [True, False])
def test_old_execution_or_timeout_cannot_pass(old):
    import json
    ticks = iter([0, 0, 901, 901])
    calls = []
    def call(args):
        calls.append(args)
        if args[:3] == ['run', 'jobs', 'execute']:
            return json.dumps({'metadata': {'name': 'new-execution'}})
        assert args[:4] == ['run', 'jobs', 'executions', 'describe']
        return json.dumps({'metadata': {'name': 'old-execution' if old else 'new-execution',
                            'creationTimestamp': datetime.now(timezone.utc).isoformat()}, 'status': {}})
    c = Controller(config(), call=call, clock=lambda: next(ticks), sleep=lambda _: None)
    c.verify_runtime = Mock()
    with pytest.raises(ValueError if old else TimeoutError): c.verify()
    assert not any('list' in args for args in calls)


def evidence_fixture():
    now = datetime.now(timezone.utc)
    started = now - timedelta(seconds=10)
    began = started + timedelta(seconds=1); finished = now - timedelta(seconds=1)
    evidence = dict(startedAt=began.isoformat(), finishedAt=finished.isoformat(), generatedAt=began.isoformat(),
                    status='degraded', counts={'written': 1, 'skipped_insufficient': 1}, heartbeatWritten=True,
                    cities=[dict(city='A', status='written', doc_id='A_today'),
                            dict(city='B', status='skipped_insufficient', doc_id=None)])
    heartbeat = observability.RunReport('compute_risk', 'degraded', began, finished, counts=evidence['counts']).to_document()
    docs = {'A_today': dict(city='A', generatedAt=began)}
    return evidence, heartbeat, docs, ['A', 'B'], started, now, 900, 1


def test_partial_contract_accepted_and_reported():
    assert assert_results(*evidence_fixture()) == 'degraded'


@pytest.mark.parametrize('fault', ['stale', 'old_heartbeat', 'old_doc', 'coverage', 'zero', 'heartbeat_failed', 'counts', 'minimum'])
def test_post_checks_reject_insufficient_or_unrelated_results(fault):
    args = list(deepcopy(evidence_fixture())); e, h, d = args[:3]
    if fault == 'stale': args[5] += timedelta(seconds=901)
    if fault == 'old_heartbeat': h['startedAt'] -= timedelta(days=1)
    if fault == 'old_doc': d['A_today']['generatedAt'] -= timedelta(days=1)
    if fault == 'coverage': e['cities'].pop()
    if fault == 'zero': e['cities'][0]['status'] = 'error'
    if fault == 'heartbeat_failed': e['heartbeatWritten'] = False
    if fault == 'counts': h['counts'] = {'written': 2}
    if fault == 'minimum': args[-1] = 2
    with pytest.raises((ValueError, KeyError)): assert_results(*args)


def test_heartbeat_failure_exposes_failed_report_and_signal(caplog):
    sink = Mock(); sink.write_heartbeat.side_effect = RuntimeError('secret token')
    now = datetime.now(timezone.utc)
    report = observability.RunReport('compute_risk', 'ok', now, now)
    import logging
    observability.emit(report, sink=sink, logger=logging.getLogger('test'))
    assert report.status == 'failed' and report.error == 'heartbeat_write_failed: RuntimeError'
    record = next(r for r in caplog.records if r.getMessage() == 'job_run')
    assert record.alert and not record.heartbeatWritten
    assert 'secret token' not in caplog.text


@pytest.mark.parametrize('changes', [{}, {'FIRESTORE_EMULATOR_HOST': 'localhost:8080'},
                                    {'GOOGLE_APPLICATION_CREDENTIALS': 'file.json'}])
def test_attached_auth_rejects_missing_project_or_conflicts(monkeypatch, changes):
    for key in ('FIREBASE_PROJECT_ID', 'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT',
                'GOOGLE_APPLICATION_CREDENTIALS', 'FIRESTORE_EMULATOR_HOST'):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv('FIRESTORE_AUTH_MODE', 'attached')
    for key, value in changes.items(): monkeypatch.setenv(key, value)
    with pytest.raises(ValueError, match='Attached identity'): firestore_runtime._configuration()


def test_job_main_failed_heartbeat_returns_failure(monkeypatch):
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(compute_risk, 'OpenMeteoWeeklyBaseProvider', Mock())
    monkeypatch.setattr(compute_risk, 'init_firestore_repository', Mock())
    monkeypatch.setattr(observability, 'init_firestore_heartbeat_sink', Mock())
    monkeypatch.setattr(compute_risk, 'run_and_report', Mock(return_value=(
        observability.RunReport('compute_risk', 'failed', now, now, error='heartbeat_write_failed'), [])))
    assert compute_risk.main([]) == 1

@pytest.mark.parametrize('fault', ['command', 'project', 'credential', 'tasks', 'retries'])
def test_runtime_mismatch_prevents_execution(fault):
    import json
    e = config()
    variables = {k: e[k] for k in SETTINGS}
    variables.update(FIREBASE_PROJECT_ID=e['PROJECT_ID'], FIRESTORE_AUTH_MODE='attached', LOG_LEVEL='INFO')
    container = dict(image=e['IMAGE'], command=['python'], args=['-m', 'app.jobs.compute_risk'],
                     env=[dict(name=k, value=v) for k, v in variables.items()])
    spec = dict(containers=[container], serviceAccountName=e['SA_JOBS'], maxRetries=0)
    template = dict(taskCount=1, template=dict(spec=spec))
    job = dict(spec=dict(template=dict(spec=template)))
    if fault == 'command': container['args'] = ['-m', 'app.main']
    if fault == 'project': container['env'][0] = dict(name='FIREBASE_PROJECT_ID', value='other')
    if fault == 'credential': container['env'].append(dict(name='GOOGLE_APPLICATION_CREDENTIALS', value='key'))
    if fault == 'tasks': template['taskCount'] = 2
    if fault == 'retries': spec['maxRetries'] = 1
    call = Mock(return_value=json.dumps(job))
    with pytest.raises(ValueError): Controller(e, call=call).verify()
    assert call.call_count == 1
    assert call.call_args.args[0][:3] == ['run', 'jobs', 'describe']


def test_run_wrapper_exposes_heartbeat_failure(monkeypatch):
    monkeypatch.setattr(compute_risk, 'run', Mock(return_value=[compute_risk.CityOutcome('A', 'written')]))
    sink = Mock(); sink.write_heartbeat.side_effect = RuntimeError('unavailable')
    report, outcomes = compute_risk.run_and_report(Mock(), Mock(), heartbeat=sink, cities=[dict(name='A')])
    assert report.status == 'failed' and report.counts == {'written': 1}
    assert len(outcomes) == 1


def test_degraded_main_is_explicit_and_permitted(monkeypatch, capsys):
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(compute_risk, 'OpenMeteoWeeklyBaseProvider', Mock())
    monkeypatch.setattr(compute_risk, 'init_firestore_repository', Mock())
    monkeypatch.setattr(observability, 'init_firestore_heartbeat_sink', Mock())
    monkeypatch.setattr(compute_risk, 'run_and_report', Mock(return_value=(
        observability.RunReport('compute_risk', 'degraded', now, now, counts={'written': 1}),
        [compute_risk.CityOutcome('A', 'written', 'A_today', 'Low', 'Smog')])))
    assert compute_risk.main([]) == 0
    assert '[degraded]' in capsys.readouterr().out


def test_full_verification_uses_exact_execution_logs_and_persisted_results(monkeypatch):
    import json
    from ml.pipelines import clean
    monkeypatch.setattr(clean, 'load_cities', lambda: [dict(name='A'), dict(name='B')])
    calls = []; run = {}
    def call(args):
        calls.append(args)
        if args[:3] == ['run', 'jobs', 'execute']:
            run['began'] = datetime.now(timezone.utc)
            return json.dumps({'metadata': {'name': 'exact-execution'}})
        if args[:4] == ['run', 'jobs', 'executions', 'describe']:
            return json.dumps({'metadata': {'name': 'exact-execution', 'creationTimestamp': run['began'].isoformat()},
                'status': {'conditions': [{'type': 'Completed', 'status': 'True'}], 'succeededCount': 1}})
        assert args[:2] == ['logging', 'read']
        assert 'exact-execution' in args[2] and 'run_evidence' in args[2]
        assert 'resource.labels.location="us-central1"' in args[2]
        run['finished'] = datetime.now(timezone.utc)
        run['evidence'] = dict(startedAt=run['began'].isoformat(), finishedAt=run['finished'].isoformat(),
            generatedAt=run['began'].isoformat(), counts={'written': 1, 'skipped_insufficient': 1}, status='degraded',
            heartbeatWritten=True, cities=[dict(city='A', status='written', doc_id='A_today'),
                                          dict(city='B', status='skipped_insufficient', doc_id=None)])
        return json.dumps([{'jsonPayload': run['evidence']}])
    db = Mock()
    def collection(name):
        result = Mock()
        if name == 'jobHeartbeats':
            body = observability.RunReport('compute_risk', 'degraded', run['began'], run['finished'],
                                          counts=run['evidence']['counts']).to_document()
        else:
            body = dict(city='A', generatedAt=run['began'])
        result.document.return_value.get.return_value.to_dict.return_value = body
        return result
    db.collection.side_effect = collection
    c = Controller(config(), call=call, db_factory=lambda: db)
    c.verify_runtime = Mock()
    assert c.verify() == 'degraded'
    assert not any('list' in args for args in calls)

@pytest.mark.parametrize('key,value', [('COMPUTE_RISK_SCHEDULE', '99 0 * * *'),
    ('COMPUTE_RISK_SCHEDULE', '* * * *'), ('COMPUTE_RISK_SCHEDULE', '*/0 * * * *'),
    ('COMPUTE_RISK_TIME_ZONE', 'invalid'), ('LOG_LEVEL', 'ERROR'), ('VERIFY_MIN_WRITTEN', '6')])
def test_invalid_schedule_or_hidden_evidence_fails_preflight(key, value):
    e = config(); e[key] = value
    call = Mock(side_effect=AssertionError('No cloud'))
    with pytest.raises(ValueError): Controller(e, call=call).execute(provision=True)
    call.assert_not_called()


@pytest.mark.parametrize('state', ['PAUSED', 'ENABLED'])
def test_existing_schedule_pause_must_be_confirmed(state):
    import json
    call = Mock(side_effect=[json.dumps([{'name': 'projects/p/locations/r/jobs/compute-risk-daily'}]),
                             '', json.dumps({'state': state})])
    c = Controller(config(), call=call)
    if state == 'PAUSED': assert c.pause_existing()
    else:
        with pytest.raises(ValueError, match='pause'): c.pause_existing()
    assert call.call_args_list[1].args[0][:3] == ['scheduler', 'jobs', 'pause']


def compute_prerequisites(fault=None, job_exists=False, job_invoker=False, one_time=False):
    import json
    from deploy.compute_risk_control import APIS
    e = config(); calls = []; db = Mock()
    if one_time:
        from deploy.compute_risk_control import SCHEDULER_SETTINGS
        for key in SCHEDULER_SETTINGS:
            e.pop(key)
    def call(args):
        calls.append(args)
        if args[:2] == ['config', 'get-value']: return 'other' if fault == 'project' else e['PROJECT_ID']
        if args[:2] == ['auth', 'list']: return '' if fault == 'cli_auth' else 'operator@example.test'
        if args[:3] == ['auth', 'application-default', 'print-access-token']: return '' if fault == 'adc' else 'FAKE_NOT_LOGGED'
        if args[:2] == ['services', 'list']:
            enabled = APIS - ({'cloudscheduler.googleapis.com'} if one_time else set())
            return '\n'.join(sorted(enabled - ({'firestore.googleapis.com'} if fault == 'api' else {fault})))
        if args[:2] == ['projects', 'describe']:
            return json.dumps({'projectId': 'other' if fault == 'identity' else e['PROJECT_ID'],
                'lifecycleState': 'DELETE_REQUESTED' if fault == 'project_state' else 'ACTIVE',
                'projectNumber': 'unknown' if fault == 'project_number' else '123456'})
        if args[:3] == ['billing', 'projects', 'describe']:
            return json.dumps({'projectId': e['PROJECT_ID'], 'billingEnabled': fault != 'billing'})
        if args[:4] == ['artifacts', 'docker', 'images', 'describe']:
            if fault == 'image': raise RuntimeError('Image absent')
            return '{}'
        if args[:3] == ['iam', 'service-accounts', 'describe']:
            return json.dumps({'email': 'other' if fault == 'account_identity' else args[3], 'disabled': fault == 'disabled_account'})
        if args[:3] == ['run', 'jobs', 'list']:
            return json.dumps([{'metadata': {'name': e['COMPUTE_RISK_JOB_NAME']}}] if job_exists else [])
        if args[:2] == ['projects', 'get-iam-policy']:
            roles = [('SA_JOBS', 'roles/datastore.user')]
            if not one_time and not job_invoker: roles.append(('SA_SCHEDULER', 'roles/run.invoker'))
            bindings = [dict(role=role, members=['serviceAccount:' + e[sa]]) for sa, role in roles if role != fault]
            if not one_time and fault != 'scheduler_agent':
                bindings.append(dict(role='roles/cloudscheduler.serviceAgent', members=['serviceAccount:service-123456@gcp-sa-cloudscheduler.iam.gserviceaccount.com']))
            if fault == 'conditional': bindings[0]['condition'] = {'expression': 'true'}
            return json.dumps({'bindings': bindings})
        if args[:3] == ['run', 'jobs', 'get-iam-policy']:
            return json.dumps({'bindings': [{'role': 'roles/run.invoker', 'members': ['serviceAccount:' + e['SA_SCHEDULER']]}]})
        raise AssertionError(f'Unexpected/mutating command: {args[:4]}')
    if fault == 'heartbeat_read': db.collection.return_value.document.return_value.get.side_effect = RuntimeError('Read denied')
    if fault == 'risk_read': db.collection.return_value.limit.return_value.get.side_effect = RuntimeError('Read denied')
    return Controller(e, call=call, db_factory=lambda: db, one_time=one_time), calls, db


@pytest.mark.parametrize('fault', ['project', 'cli_auth', 'adc', 'api', 'identity', 'project_state',
    'project_number', 'billing', 'image', 'disabled_account', 'account_identity', 'roles/datastore.user',
    'roles/run.invoker', 'conditional', 'scheduler_agent', 'heartbeat_read', 'risk_read'])
def test_compute_missing_prerequisite_prevents_mutation(fault):
    controller, calls, _ = compute_prerequisites(fault)
    with pytest.raises((ValueError, RuntimeError)): controller.execute(provision=True)
    assert not any(args[:2] == ['scheduler', 'jobs'] for args in calls)
    assert not any('create' in args or 'update' in args or 'execute' in args for args in calls)


@pytest.mark.parametrize('job_invoker', [False, True])
def test_compute_preflight_reads_only_and_needs_no_fcm_role(job_invoker):
    from deploy.compute_risk_control import APIS
    controller, calls, db = compute_prerequisites(job_exists=job_invoker, job_invoker=job_invoker)
    controller.preflight()
    assert 'fcm.googleapis.com' not in APIS
    assert controller.job_exists is job_invoker
    db.collection.return_value.document.return_value.get.assert_called_once_with(timeout=30)
    db.collection.return_value.limit.assert_called_once_with(1)
    db.collection.return_value.limit.return_value.get.assert_called_once_with(timeout=30)
    assert not any(any(v in args for v in ('enable', 'submit', 'create', 'update', 'execute', 'add-iam-policy-binding')) for args in calls)


@pytest.mark.parametrize('args', [
    ['services', 'enable', 'firestore.googleapis.com'], ['builds', 'submit', '.'],
    ['projects', 'add-iam-policy-binding', 'foreseeme-83587'], ['billing', 'projects', 'link', 'foreseeme-83587'],
    ['iam', 'service-accounts', 'create', 'account'], ['artifacts', 'repositories', 'create', 'repo'],
    ['run', 'jobs', 'add-iam-policy-binding', 'compute-risk-job'], ['scheduler', 'jobs', 'run', 'compute-risk-daily'],
])
def test_compute_transport_refuses_prerequisite_provisioning(monkeypatch, args):
    import subprocess
    process = Mock(side_effect=AssertionError('No subprocess allowed'))
    monkeypatch.setattr(subprocess, 'run', process)
    with pytest.raises(ValueError, match='Forbidden'): Controller(config())._call(args)
    process.assert_not_called()


def test_compute_transport_is_noninteractive_bounded_and_suppresses_api_prompts(monkeypatch):
    import subprocess
    from types import SimpleNamespace
    process = Mock(return_value=SimpleNamespace(stdout='[]'))
    monkeypatch.setattr(subprocess, 'run', process)
    c = Controller(config(), clock=lambda: 10)
    c.deadline = 15
    assert c._call(['services', 'list']) == '[]'
    kwargs = process.call_args.kwargs
    assert kwargs['env']['CLOUDSDK_CORE_SHOULD_PROMPT_TO_ENABLE_API'] == 'false'
    assert kwargs['env']['CLOUDSDK_CORE_DISABLE_PROMPTS'] == 'true'
    assert kwargs['stdin'] == subprocess.DEVNULL and kwargs['timeout'] == 5
    assert process.call_args.args[0][-1] == '--quiet'
    process.reset_mock(); c.deadline = 10
    with pytest.raises(TimeoutError): c._call(['services', 'list'])
    process.assert_not_called()


@pytest.mark.parametrize('stage', ['pause', 'deploy', 'verify', 'activation'])
def test_compute_cleanup_failure_retains_original_context_and_fresh_budget(stage):
    c = Controller(config(), call=Mock(side_effect=TimeoutError('secret activation detail')))
    original = TimeoutError('secret original detail'); cleanup = OSError('secret cleanup detail')
    c.preflight = Mock(); c.deploy_job = Mock(side_effect=original if stage == 'deploy' else None)
    c.verify = Mock(side_effect=original if stage == 'verify' else None)
    pauses = []
    def pause():
        pauses.append(c.deadline)
        if len(pauses) == 1:
            if stage == 'pause': raise original
            return False
        raise cleanup
    c.pause_existing = pause
    def activation(*args, **kwargs):
        c.deadline = -1
        raise original
    c.run = activation
    with pytest.raises(RuntimeError, match='state is unknown') as caught:
        c.execute(provision=True)
    assert caught.value.__cause__ is original
    assert caught.value.cleanup_error is cleanup
    assert 'TimeoutError' in str(caught.value) and 'OSError' in str(caught.value)
    assert 'compute-risk-daily' in str(caught.value) and 'inspect and pause' in str(caught.value)
    assert 'secret' not in str(caught.value)
    assert pauses == [None, None]


@pytest.mark.parametrize('image', ['', 'us-central1-docker.pkg.dev/foreseeme-83587/backend/image:latest',
    'us-central1-docker.pkg.dev/foreseeme-83587/backend/image:rc',
    'us-central1-docker.pkg.dev/foreseeme-83587/backend/image@sha256:abc',
    'us-central1-docker.pkg.dev/other-project/backend/image@sha256:' + 'a' * 64,
    'europe-west1-docker.pkg.dev/foreseeme-83587/backend/image@sha256:' + 'a' * 64])
def test_compute_unpinned_or_mismatched_image_fails_without_cloud_access(image):
    env = config(); env['IMAGE'] = image
    call = Mock(side_effect=AssertionError('Cloud forbidden'))
    with pytest.raises(ValueError): Controller(env, call=call).execute(provision=True)
    call.assert_not_called()


def test_image_example_has_no_implicit_default():
    from pathlib import Path
    text = (Path(__file__).resolve().parents[1] / 'deploy' / 'config.env.example').read_text()
    assert '\nIMAGE=\n' in text and 'IMAGE_TAG=' not in text


def test_compute_verify_only_never_activates_schedule():
    c = Controller(config(), call=Mock(side_effect=AssertionError('Cloud forbidden')))
    c.preflight = Mock(); c.pause_existing = Mock(return_value=True); c.verify = Mock()
    c.execute(provision=False)
    c.pause_existing.assert_called_once_with()
    c.verify.assert_called_once_with()
    c.call.assert_not_called()


def test_one_time_preflight_without_any_scheduler_prerequisites():
    c, calls, db = compute_prerequisites(one_time=True)
    c.preflight()
    assert not any(args[0] == 'scheduler' for args in calls)
    accounts = [args[3] for args in calls if args[:3] == ['iam', 'service-accounts', 'describe']]
    assert accounts == [c.env['SA_JOBS']]
    db.collection.return_value.document.return_value.get.assert_called_once_with(timeout=30)
    db.collection.return_value.limit.return_value.get.assert_called_once_with(timeout=30)


@pytest.mark.parametrize('fault', ['project', 'cli_auth', 'adc', 'identity', 'project_state',
    'project_number', 'billing', 'image', 'disabled_account', 'account_identity',
    'roles/datastore.user', 'conditional', 'heartbeat_read', 'risk_read',
    'run.googleapis.com', 'artifactregistry.googleapis.com', 'firestore.googleapis.com',
    'iam.googleapis.com', 'cloudresourcemanager.googleapis.com', 'serviceusage.googleapis.com',
    'logging.googleapis.com', 'cloudbilling.googleapis.com'])
def test_one_time_prerequisite_failure_prevents_all_mutations(fault):
    c, calls, _ = compute_prerequisites(fault, one_time=True)
    with pytest.raises((ValueError, RuntimeError)):
        c.execute()
    assert not any(args[0] == 'scheduler' for args in calls)
    assert not any(action in args for args in calls for action in ('create', 'update', 'execute'))


@pytest.mark.parametrize('key,value', [('IMAGE', 'mutable:latest'), ('FIREBASE_PROJECT_ID', 'other'),
    ('FIRESTORE_AUTH_MODE', 'adc'), ('GOOGLE_APPLICATION_CREDENTIALS', 'secret.json'),
    ('FIRESTORE_EMULATOR_HOST', 'localhost:8080'), ('VERIFY_TIMEOUT_SECONDS', '600'),
    ('RISK_DATA_DELAY_DAYS', ''), ('RISK_AQI_MAX_TRAILING_GAP_DAYS', '-1')])
def test_one_time_invalid_config_fails_before_cli(key, value):
    c, calls, _ = compute_prerequisites(one_time=True)
    c.env[key] = value
    with pytest.raises(ValueError): c.execute()
    assert calls == []


@pytest.mark.parametrize('action', ['list', 'describe', 'pause', 'resume', 'create', 'update', 'run'])
def test_one_time_transport_forbids_all_scheduler_access(monkeypatch, action):
    process = Mock(side_effect=AssertionError('Real subprocess forbidden'))
    monkeypatch.setattr('subprocess.run', process)
    with pytest.raises(ValueError, match='Scheduler access'):
        Controller(config(), one_time=True)._call(['scheduler', 'jobs', action])
    process.assert_not_called()


@pytest.mark.parametrize('stage', ['deploy', 'verify'])
def test_one_time_failure_never_attempts_scheduler_cleanup(stage):
    c, calls, _ = compute_prerequisites(one_time=True)
    c.deploy_job = Mock(side_effect=RuntimeError('failed') if stage == 'deploy' else None)
    c.verify = Mock(side_effect=TimeoutError('deadline') if stage == 'verify' else None)
    c.pause_existing = Mock(side_effect=AssertionError('Scheduler forbidden'))
    with pytest.raises((RuntimeError, TimeoutError)): c.execute()
    c.pause_existing.assert_not_called()
    assert not any(args[0] == 'scheduler' for args in calls)


def one_time_execution(monkeypatch, fault=None, job_exists=False):
    """Real controller flow, with only CLI/Firestore/time replaced; no inference."""
    import json
    import deploy.compute_risk_control as module
    from ml.pipelines.clean import load_cities
    fixed = datetime(2026, 10, 13, 12, tzinfo=timezone.utc)
    class ClockDateTime(datetime):
        @classmethod
        def now(cls, tz=None): return fixed
    fixed = ClockDateTime(2026, 10, 13, 12, tzinfo=timezone.utc)
    monkeypatch.setattr(module, 'datetime', ClockDateTime)
    c, calls, db = compute_prerequisites(one_time=True, job_exists=job_exists)
    prerequisites = c.call
    cities = [city['name'] for city in load_cities()]
    stamp = fixed.isoformat()
    evidence = dict(startedAt=stamp, finishedAt=stamp, generatedAt=stamp,
                    status='ok', counts={'written': len(cities)}, heartbeatWritten=True,
                    cities=[dict(city=name, status='written', doc_id=name + '_2026-10-13') for name in cities])
    if fault == 'partial':
        evidence.update(status='degraded', counts={'written': 4, 'skipped_insufficient': 1})
        evidence['cities'][-1].update(status='skipped_insufficient', doc_id=None)
    if fault == 'stale': evidence['finishedAt'] = (fixed - timedelta(hours=1)).isoformat()
    heartbeat = observability.RunReport('compute_risk', evidence['status'], fixed, fixed,
                                       counts=evidence['counts']).to_document()
    if fault == 'heartbeat': heartbeat['startedAt'] = (fixed - timedelta(seconds=1)).isoformat()
    ticks = [0]
    c.clock = lambda: ticks[0]
    c.sleep = lambda _: ticks.__setitem__(0, 901)
    def call(args):
        if args[0] == 'scheduler': raise AssertionError('Scheduler forbidden')
        if args[:3] in (['run', 'jobs', 'create'], ['run', 'jobs', 'update']):
            calls.append(args); return '{}'
        if args[:3] == ['run', 'jobs', 'describe']:
            calls.append(args)
            variables = {key: c.env[key] for key in SETTINGS}
            variables.update(FIREBASE_PROJECT_ID=c.env['PROJECT_ID'], FIRESTORE_AUTH_MODE='attached', LOG_LEVEL='INFO')
            container = dict(image=c.env['IMAGE'], command=['python'], args=['-m', 'app.jobs.compute_risk'],
                             env=[dict(name=k, value=v) for k, v in variables.items()])
            if fault == 'runtime': container['command'] = ['uvicorn']
            spec = dict(containers=[container], serviceAccountName=c.env['SA_JOBS'], maxRetries=0)
            return json.dumps({'spec': {'template': {'spec': {'taskCount': 1, 'template': {'spec': spec}}}}})
        if args[:3] == ['run', 'jobs', 'execute']:
            calls.append(args)
            return json.dumps({'metadata': {'name': '' if fault == 'identity' else 'exact-execution'}})
        if args[:4] == ['run', 'jobs', 'executions', 'describe']:
            calls.append(args); assert args[4] == 'exact-execution'
            status = dict(conditions=[dict(type='Completed', status='True')], succeededCount=1)
            if fault == 'failed': status = dict(failedCount=1)
            if fault == 'timeout': status = {}
            return json.dumps(dict(metadata=dict(name='other-execution' if fault == 'mismatch' else 'exact-execution',
                                                 creationTimestamp=stamp), status=status))
        if args[:2] == ['logging', 'read']:
            calls.append(args); assert 'exact-execution' in args[2]
            return json.dumps([{'jsonPayload': evidence}] * (2 if fault == 'ambiguous_logs' else 1))
        return prerequisites(args)
    c.call = call
    def collection(name):
        result = Mock()
        def document(doc_id):
            document = Mock()
            body = heartbeat if name == 'jobHeartbeats' else dict(city=doc_id.rsplit('_', 1)[0], generatedAt=stamp)
            if name == 'riskEstimates' and fault == 'document': body['generatedAt'] = (fixed - timedelta(days=1)).isoformat()
            document.get.return_value.to_dict.return_value = body
            return document
        result.document.side_effect = document
        return result
    db.collection.side_effect = collection
    return c, calls


@pytest.mark.parametrize('job_exists', [False, True])
def test_one_time_deploys_and_verifies_exactly_one_execution(monkeypatch, job_exists, capsys):
    c, calls = one_time_execution(monkeypatch, job_exists=job_exists)
    assert c.env['VERIFY_MIN_WRITTEN'] == '1'  # Shared default cannot weaken one-time acceptance.
    assert c.execute() == 'ok'
    assert sum(args[:3] == ['run', 'jobs', 'execute'] for args in calls) == 1
    assert sum(args[:3] == ['run', 'jobs', 'update' if job_exists else 'create'] for args in calls) == 1
    assert not any(args[0] == 'scheduler' for args in calls)
    assert 'Verified exact-execution: ok' in capsys.readouterr().out


@pytest.mark.parametrize('fault', ['runtime', 'identity', 'mismatch', 'failed', 'timeout',
                                  'ambiguous_logs', 'partial', 'stale', 'heartbeat', 'document'])
def test_one_time_rejects_unproven_execution_without_retry_or_scheduler(monkeypatch, fault, capsys):
    c, calls = one_time_execution(monkeypatch, fault)
    with pytest.raises((ValueError, RuntimeError, TimeoutError)): c.execute()
    assert sum(args[:3] == ['run', 'jobs', 'execute'] for args in calls) == (0 if fault == 'runtime' else 1)
    assert not any(args[0] == 'scheduler' for args in calls)
    assert 'Verified' not in capsys.readouterr().out


def test_one_time_ignores_invalid_scheduler_settings():
    c, _, _ = compute_prerequisites(one_time=True)
    from deploy.compute_risk_control import SCHEDULER_SETTINGS
    c.env.update({key: 'unused\ninvalid' for key in SCHEDULER_SETTINGS})
    c.preflight()


def test_one_time_requires_five_distinct_configured_cities(monkeypatch):
    c, calls, _ = compute_prerequisites(one_time=True)
    monkeypatch.setattr('ml.pipelines.clean.load_cities', lambda: [{'name': 'same'}] * 5)
    with pytest.raises(ValueError, match='five distinct'): c.execute()
    assert calls == []


@pytest.mark.parametrize('key', ONE_TIME_REQUIRED)
def test_one_time_keeps_all_non_scheduler_config_required(key):
    c, calls, _ = compute_prerequisites(one_time=True)
    c.env.pop(key)
    with pytest.raises(ValueError, match=key): c.execute()
    assert calls == []


@pytest.mark.parametrize('mode,one_time,provision', [
    ('one-time', True, False), ('provision', False, True), ('verify', False, False)])
def test_public_cli_selects_explicit_mode(monkeypatch, mode, one_time, provision):
    import deploy.compute_risk_control as module
    factory = Mock()
    monkeypatch.setattr(module, 'Controller', factory)
    monkeypatch.setattr(module.os, 'environ', {})
    assert module.main([mode]) == 0
    factory.assert_called_once_with({}, one_time=one_time)
    factory.return_value.execute.assert_called_once_with(provision=provision)


@pytest.mark.parametrize('argv', [[], ['one-time', 'verify'], ['unknown']])
def test_public_cli_rejects_ambiguous_mode_before_preflight(monkeypatch, argv):
    import deploy.compute_risk_control as module
    factory = Mock()
    monkeypatch.setattr(module, 'Controller', factory)
    assert module.main(argv) == 1
    factory.assert_not_called()
