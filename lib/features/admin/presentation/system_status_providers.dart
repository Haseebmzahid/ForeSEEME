import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/firestore_system_status_repository.dart';
import '../domain/constants/monitored_jobs.dart';
import '../domain/models/job_heartbeat.dart';
import '../domain/models/model_status.dart';
import '../domain/models/operational_metrics.dart';
import '../domain/repositories/system_status_repository.dart';
import 'admin_providers.dart';
import 'admin_read.dart';

final systemStatusRepositoryProvider = Provider<SystemStatusRepository>((ref) {
  return FirestoreSystemStatusRepository();
});

final jobHeartbeatsProvider = FutureProvider.autoDispose<List<JobHeartbeat>>((
  ref,
) {
  final repository = ref.watch(systemStatusRepositoryProvider);
  ref.watch(isAdminProvider);
  return boundedAdminRead(
    'job heartbeats',
    () => repository.getJobHeartbeats(kMonitoredJobs),
  );
}, retry: (_, _) => null);

final alertVolumeProvider = FutureProvider.autoDispose<int?>((ref) {
  ref.watch(isAdminProvider);
  return boundedAdminRead(
    'alert volume',
    ref.watch(systemStatusRepositoryProvider).getAlertVolume,
  );
}, retry: (_, _) => null);

final latestModelStatusProvider = FutureProvider.autoDispose<ModelStatus?>((
  ref,
) {
  ref.watch(isAdminProvider);
  return boundedAdminRead(
    'latest estimate',
    ref.watch(systemStatusRepositoryProvider).getLatestModelStatus,
  );
}, retry: (_, _) => null);

final deployedModelProvider = FutureProvider.autoDispose<ModelStatus?>((ref) {
  ref.watch(isAdminProvider);
  return boundedAdminRead(
    'deployed model',
    ref.watch(systemStatusRepositoryProvider).getDeployedModel,
  );
}, retry: (_, _) => null);

final accountMetricsProvider = FutureProvider.autoDispose<AccountMetrics?>((
  ref,
) {
  ref.watch(isAdminProvider);
  return boundedAdminRead(
    'account metrics',
    ref.watch(systemStatusRepositoryProvider).getAccountMetrics,
  );
}, retry: (_, _) => null);
