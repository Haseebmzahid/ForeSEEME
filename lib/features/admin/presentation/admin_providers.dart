import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/admin_api_client.dart';
import 'package:fyp_foreseeme/features/admin/data/repositories/firebase_admin_repository.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_repository.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_read.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_override_provider.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return FirebaseAdminRepository();
});

final isAdminProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateProvider);
  return boundedAdminRead(
    'admin session',
    ref.watch(adminRepositoryProvider).isCurrentUserAdmin,
  );
}, retry: (_, _) => null);

class AdminOverrideController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit({
    required String city,
    required RiskLevel riskLevel,
    required String disease,
    required String reason,
    DateTime? expiresAt,
    DateTime? now,
  }) => _change(
    city,
    ['overrides', city],
    {
      'riskLevel': riskLevel.toJson(),
      'disease': disease,
      'reason': reason.trim(),
      'expiresAt':
          (expiresAt ?? (now ?? DateTime.now()).add(const Duration(hours: 24)))
              .toUtc()
              .toIso8601String(),
    },
  );

  Future<void> clear(String city) =>
      _change(city, ['overrides', city, 'clear']);

  Future<void> _change(
    String city,
    List<String> path, [
    Map<String, dynamic>? payload,
  ]) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(adminApiClientProvider).post(path, payload);
      ref.invalidate(activeOverrideForCityProvider(city));
      ref.invalidate(currentCityOverrideProvider);
      ref.invalidate(recentActivityLogProvider);
    });
  }
}

final adminOverrideControllerProvider =
    AsyncNotifierProvider<AdminOverrideController, void>(
      AdminOverrideController.new,
    );
