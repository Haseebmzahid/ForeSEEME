// All enums related to the Medication feature.
// Every enum defines [toJson] and a companion extension with [fromJson]
// so Firestore serialization stays close to the enum definition.

// ── MedicationType ────────────────────────────────────────────────────────────

enum MedicationType {
  pill,
  syrup;

  /// Serialises to the string stored in Firestore (e.g. "pill").
  String toJson() => name;
}

extension MedicationTypeX on MedicationType {
  /// Deserialises from a Firestore string. Returns [MedicationType.pill]
  /// as a safe default if the stored value is unrecognised.
  static MedicationType fromJson(String? value) {
    return MedicationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MedicationType.pill,
    );
  }
}

// ── MedicationFrequency ───────────────────────────────────────────────────────

enum MedicationFrequency {
  onceDaily,
  twiceDaily,
  thriceDaily;

  /// Serialises to the string stored in Firestore (e.g. "onceDaily").
  String toJson() => name;

  /// Human-readable label used in the UI.
  String get label => switch (this) {
    MedicationFrequency.onceDaily => 'Once daily',
    MedicationFrequency.twiceDaily => 'Twice daily',
    MedicationFrequency.thriceDaily => 'Three times daily',
  };

  /// How many reminder times this frequency expects.
  int get expectedReminderCount => switch (this) {
    MedicationFrequency.onceDaily => 1,
    MedicationFrequency.twiceDaily => 2,
    MedicationFrequency.thriceDaily => 3,
  };
}

extension MedicationFrequencyX on MedicationFrequency {
  /// Deserialises from a Firestore string. Returns [MedicationFrequency.onceDaily]
  /// as a safe default if the stored value is unrecognised.
  static MedicationFrequency fromJson(String? value) {
    return MedicationFrequency.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MedicationFrequency.onceDaily,
    );
  }
}

// ── AdherenceStatus ───────────────────────────────────────────────────────────

enum AdherenceStatus {
  taken,
  missed,
  pending;

  /// Serialises to the string stored in Firestore (e.g. "taken").
  String toJson() => name;
}

extension AdherenceStatusX on AdherenceStatus {
  /// Deserialises from a Firestore string. Returns [AdherenceStatus.pending]
  /// as a safe default if the stored value is unrecognised.
  static AdherenceStatus fromJson(String? value) {
    if (value == 'skipped') return AdherenceStatus.missed;

    return AdherenceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AdherenceStatus.pending,
    );
  }
}
