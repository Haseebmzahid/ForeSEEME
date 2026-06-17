import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';

/// Immutable model for a user's medication prescription.
///
/// Firestore path: `users/{uid}/medications/{id}`
class MedicationModel {
  final String id;
  final String uid;
  final String name;
  final String dosage;
  final MedicationType type;
  final MedicationFrequency frequency;

  /// List of reminder times in "HH:mm" 24-hour format (e.g. ["08:00", "20:00"]).
  /// Length should match [frequency.expectedReminderCount].
  final List<String> reminderTimes;

  final bool isActive;
  final DateTime createdAt;

  const MedicationModel({
    required this.id,
    required this.uid,
    required this.name,
    required this.dosage,
    required this.type,
    required this.frequency,
    required this.reminderTimes,
    required this.isActive,
    required this.createdAt,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Deserialise from a Firestore document snapshot.
  /// [id] comes from the document ID, not the document body.
  factory MedicationModel.fromJson(String id, Map<String, dynamic> json) {
    DateTime parseTimestamp(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return MedicationModel(
      id: id,
      uid: (json['uid'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      dosage: (json['dosage'] as String?) ?? '',
      type: MedicationTypeX.fromJson(json['type'] as String?),
      frequency: MedicationFrequencyX.fromJson(json['frequency'] as String?),
      reminderTimes: List<String>.from(
        (json['reminderTimes'] as List<dynamic>?) ?? const [],
      ),
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: parseTimestamp(json['createdAt']),
    );
  }

  /// Serialise to a Firestore-compatible map.
  /// [createdAt] is stored as a Firestore timestamp and kept stable so
  /// medication scheduling has a consistent local start date.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'dosage': dosage,
      'type': type.toJson(),
      'frequency': frequency.toJson(),
      'reminderTimes': reminderTimes,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  MedicationModel copyWith({
    String? id,
    String? uid,
    String? name,
    String? dosage,
    MedicationType? type,
    MedicationFrequency? frequency,
    List<String>? reminderTimes,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return MedicationModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      reminderTimes: reminderTimes ?? this.reminderTimes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'MedicationModel(id: $id, name: $name, type: ${type.name}, '
      'frequency: ${frequency.name}, active: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MedicationModel && other.id == id && other.uid == uid;

  @override
  int get hashCode => Object.hash(id, uid);
}
