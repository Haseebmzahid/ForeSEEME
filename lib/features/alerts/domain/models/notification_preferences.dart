/// Condition categories the user can toggle alerts for (key → display label).
/// Stable keys are what Sprint 4's dispatch engine matches against.
const Map<String, String> kNotificationConditionLabels = {
  'respiratory': 'Respiratory',
  'cardiovascular': 'Cardiovascular',
};

/// The user's risk-alert preferences (consumed by Sprint 4's dispatch engine).
///
/// Immutable, SDK-free. Persisted at `users/{uid}.notificationPreferences`
/// (see `docs/notification-preferences-schema.md`). [fromJson] is defensive so a
/// missing/partial document reloads to sensible defaults.
class NotificationPreferences {
  /// Current schema version of the persisted shape.
  static const int schemaVersion = 1;

  final bool highRiskAlerts;
  final bool mediumRiskAlerts;
  final bool lowRiskUpdates;

  /// condition key → enabled. Keys come from [kNotificationConditionLabels].
  final Map<String, bool> conditions;

  const NotificationPreferences({
    required this.highRiskAlerts,
    required this.mediumRiskAlerts,
    required this.lowRiskUpdates,
    required this.conditions,
  });

  /// Sensible defaults: warn on High/Medium, quiet on Low; respiratory on.
  factory NotificationPreferences.defaults() => const NotificationPreferences(
    highRiskAlerts: true,
    mediumRiskAlerts: true,
    lowRiskUpdates: false,
    conditions: {'respiratory': true, 'cardiovascular': false},
  );

  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) {
    final defaults = NotificationPreferences.defaults();
    if (json == null) return defaults;

    final rawConditions = (json['conditions'] as Map?)?.cast<String, dynamic>();
    final conditions = <String, bool>{
      for (final key in kNotificationConditionLabels.keys)
        key: (rawConditions?[key] as bool?) ?? defaults.conditions[key]!,
    };

    return NotificationPreferences(
      highRiskAlerts:
          (json['highRiskAlerts'] as bool?) ?? defaults.highRiskAlerts,
      mediumRiskAlerts:
          (json['mediumRiskAlerts'] as bool?) ?? defaults.mediumRiskAlerts,
      lowRiskUpdates:
          (json['lowRiskUpdates'] as bool?) ?? defaults.lowRiskUpdates,
      conditions: conditions,
    );
  }

  Map<String, dynamic> toJson() => {
    'highRiskAlerts': highRiskAlerts,
    'mediumRiskAlerts': mediumRiskAlerts,
    'lowRiskUpdates': lowRiskUpdates,
    'conditions': conditions,
    'schemaVersion': schemaVersion,
  };

  NotificationPreferences copyWith({
    bool? highRiskAlerts,
    bool? mediumRiskAlerts,
    bool? lowRiskUpdates,
    Map<String, bool>? conditions,
  }) {
    return NotificationPreferences(
      highRiskAlerts: highRiskAlerts ?? this.highRiskAlerts,
      mediumRiskAlerts: mediumRiskAlerts ?? this.mediumRiskAlerts,
      lowRiskUpdates: lowRiskUpdates ?? this.lowRiskUpdates,
      conditions: conditions ?? this.conditions,
    );
  }

  /// Returns a copy with one condition [key] set to [enabled].
  NotificationPreferences withCondition(String key, bool enabled) {
    return copyWith(conditions: {...conditions, key: enabled});
  }

  static bool _mapEquals(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationPreferences &&
          other.highRiskAlerts == highRiskAlerts &&
          other.mediumRiskAlerts == mediumRiskAlerts &&
          other.lowRiskUpdates == lowRiskUpdates &&
          _mapEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(
    highRiskAlerts,
    mediumRiskAlerts,
    lowRiskUpdates,
    Object.hashAllUnordered(
      conditions.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
