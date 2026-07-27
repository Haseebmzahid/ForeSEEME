import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/firestore_system_status_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/constants/monitored_jobs.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/job_heartbeat.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/model_status.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/system_status_repository.dart';

/// Provides the concrete [SystemStatusRepository] (overridable in tests/dev),
/// mirroring [riskOverrideRepositoryProvider]'s shape.
final systemStatusRepositoryProvider = Provider<SystemStatusRepository>((ref) {
  return FirestoreSystemStatusRepository();
});

/// Latest heartbeat for each monitored job (SDS FR8.1 job health / last run
/// time). Firestore rules deny this to anyone without the `admin` claim, so a
/// non-admin caller resolves to an [AsyncError] — the dashboard only watches
/// this once [isAdminProvider] is confirmed true, matching the admin-override
/// screen's own gating pattern.
final jobHeartbeatsProvider = FutureProvider<List<JobHeartbeat>>((ref) async {
  return ref.watch(systemStatusRepositoryProvider).getJobHeartbeats(kMonitoredJobs);
});

/// Total dispatched-alert count (SDS FR8.1 "alerts count").
final alertVolumeProvider = FutureProvider<int>((ref) async {
  return ref.watch(systemStatusRepositoryProvider).getAlertVolume();
});

/// Model version + recency of the most recent risk computation across all
/// cities (SDS FR8.1 "model version"). `null` means no estimate exists yet.
final latestModelStatusProvider = FutureProvider<ModelStatus?>((ref) async {
  return ref.watch(systemStatusRepositoryProvider).getLatestModelStatus();
});
