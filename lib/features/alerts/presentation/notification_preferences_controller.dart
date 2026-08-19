import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

/// Loads, exposes and persists the signed-in user's [NotificationPreferences].
///
/// Toggles update optimistically then persist; a failed write reverts the state
/// so the UI never drifts from what is stored. These preferences directly gate
/// the backend's alert-dispatch engine.
class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  @override
  Future<NotificationPreferences> build() async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return NotificationPreferences.defaults();
    return ref.read(notificationPreferencesRepositoryProvider).load(user.uid);
  }

  Future<void> setHighRiskAlerts(bool value) =>
      _persist(state.requireValue.copyWith(highRiskAlerts: value));

  Future<void> setMediumRiskAlerts(bool value) =>
      _persist(state.requireValue.copyWith(mediumRiskAlerts: value));

  Future<void> setLowRiskUpdates(bool value) =>
      _persist(state.requireValue.copyWith(lowRiskUpdates: value));

  Future<void> setCondition(String key, bool value) =>
      _persist(state.requireValue.withCondition(key, value));

  /// Turns **all three** risk-alert categories on or off in a single write.
  ///
  /// Added for the Profile Hub, whose Notifications card carries one master
  /// switch over a contract that stores three independent booleans. Doing this
  /// through the three setters above would issue three writes and briefly
  /// persist a half-muted state, so the change is applied atomically here.
  ///
  /// Enabling restores [NotificationPreferences.defaults] rather than switching
  /// every category on: un-muting must not sign the user up for more than the
  /// app's documented default. Per-condition selections are left untouched.
  Future<void> setAllRiskCategories({required bool enabled}) {
    final defaults = NotificationPreferences.defaults();
    return _persist(
      state.requireValue.copyWith(
        highRiskAlerts: enabled && defaults.highRiskAlerts,
        mediumRiskAlerts: enabled && defaults.mediumRiskAlerts,
        lowRiskUpdates: enabled && defaults.lowRiskUpdates,
      ),
    );
  }

  Future<void> _persist(NotificationPreferences next) async {
    final previous = state.value;
    state = AsyncValue.data(next);

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      await ref
          .read(notificationPreferencesRepositoryProvider)
          .save(user.uid, next);
    } catch (error) {
      if (previous != null) state = AsyncValue.data(previous); // revert
      rethrow;
    }
  }
}
