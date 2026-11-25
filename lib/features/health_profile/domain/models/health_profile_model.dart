import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable model representing a user's health profile stored under
/// `users/{uid}/profile/{uid}` in Firestore.
class HealthProfileModel {
  final String uid;
  final String city;
  final List<String> chronicConditions;
  final List<String> customConditions;
  final DateTime lastUpdated;

  const HealthProfileModel({
    required this.uid,
    required this.city,
    required this.chronicConditions,
    this.customConditions = const [],
    required this.lastUpdated,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Deserialise from a Firestore document snapshot.
  /// Handles both [Timestamp] (Firestore native) and [String] (fallback / tests).
  factory HealthProfileModel.fromJson(String uid, Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return HealthProfileModel(
      uid: uid,
      city: (json['city'] as String?) ?? '',
      chronicConditions: List<String>.from(
        (json['chronicConditions'] as List<dynamic>?) ?? const [],
      ),
      customConditions: List<String>.from(
        (json['customConditions'] as List<dynamic>?) ?? const [],
      ),
      lastUpdated: parseDate(json['lastUpdated']),
    );
  }

  /// Serialise to a plain [Map] suitable for Firestore writes.
  /// Uses [FieldValue.serverTimestamp] so the write timestamp is authoritative.
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'city': city,
      'chronicConditions': chronicConditions,
      'customConditions': customConditions,
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  HealthProfileModel copyWith({
    String? uid,
    String? city,
    List<String>? chronicConditions,
    List<String>? customConditions,
    DateTime? lastUpdated,
  }) {
    return HealthProfileModel(
      uid: uid ?? this.uid,
      city: city ?? this.city,
      chronicConditions: chronicConditions ?? this.chronicConditions,
      customConditions: customConditions ?? this.customConditions,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  String toString() =>
      'HealthProfileModel(uid: $uid, city: $city, '
      'lastUpdated: $lastUpdated)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthProfileModel &&
          other.uid == uid &&
          other.city == city &&
          other.lastUpdated == lastUpdated;

  @override
  int get hashCode => Object.hash(uid, city, lastUpdated);
}
