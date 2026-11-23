import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_providers.dart';
import 'admin_read.dart';

import 'package:fyp_foreseeme/features/auth/domain/models/user_directory_entry.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

/// The admin user directory list (Sprint M8.4, SDS FR8.5 "Display User List").
/// Read-only — this admin surface has no write path of its own; entries are
/// written by [AuthNotifier]/`HealthProfileNotifier` as a side effect of
/// account creation and profile completion.
final userDirectoryListProvider =
    FutureProvider.autoDispose<List<UserDirectoryEntry>>((ref) {
      ref.watch(isAdminProvider);
      final repository = ref.watch(userDirectoryRepositoryProvider);
      return boundedAdminRead(
        'user directory',
        () => repository.list(limit: 0),
      );
    }, retry: (_, _) => null);
