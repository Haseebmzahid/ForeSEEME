import 'package:fyp_foreseeme/features/alerts/domain/models/notification_preferences.dart';

/// Reads/writes the user's [NotificationPreferences] on their own document.
abstract class NotificationPreferencesRepository {
  /// Loads preferences for [uid], returning defaults when none are stored.
  Future<NotificationPreferences> load(String uid);

  /// Persists [preferences] for [uid].
  Future<void> save(String uid, NotificationPreferences preferences);
}
