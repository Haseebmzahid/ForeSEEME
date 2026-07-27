import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/firestore_admin_activity_log_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_activity_log_repository.dart';

/// Provides the concrete [AdminActivityLogRepository] (overridable in
/// tests/dev), mirroring [systemStatusRepositoryProvider]'s shape.
final adminActivityLogRepositoryProvider = Provider<AdminActivityLogRepository>((
  ref,
) {
  return FirestoreAdminActivityLogRepository();
});

/// The most recent admin actions, newest first (SDS FR8.4 log viewer).
/// Invalidated by [AdminOverrideController] after it appends a new entry, so
/// the Logs screen reflects an action taken moments ago without a manual
/// refresh.
final recentActivityLogProvider = FutureProvider<List<AdminActivityLogEntry>>((
  ref,
) async {
  return ref.watch(adminActivityLogRepositoryProvider).recent();
});
