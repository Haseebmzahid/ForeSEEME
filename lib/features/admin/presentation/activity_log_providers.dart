import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_providers.dart';
import 'admin_read.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/firestore_admin_activity_log_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_activity_log_repository.dart';

/// Provides the concrete [AdminActivityLogRepository] (overridable in
/// tests/dev), mirroring [systemStatusRepositoryProvider]'s shape.
final adminActivityLogRepositoryProvider = Provider<AdminActivityLogRepository>(
  (ref) {
    return FirestoreAdminActivityLogRepository();
  },
);

class ActivityLogLimit extends Notifier<int> {
  @override
  int build() => 100;
  void loadOlder() => state += 100;
}

final activityLogLimitProvider =
    NotifierProvider.autoDispose<ActivityLogLimit, int>(ActivityLogLimit.new);

final recentActivityLogProvider =
    FutureProvider.autoDispose<List<AdminActivityLogEntry>>((ref) async {
      ref.watch(isAdminProvider);
      final limit = ref.watch(activityLogLimitProvider);
      final repository = ref.watch(adminActivityLogRepositoryProvider);
      return boundedAdminRead(
        'activity log',
        () => repository.recent(limit: limit),
      );
    }, retry: (_, _) => null);
