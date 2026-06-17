import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_foreseeme/features/medication/domain/enums/medication_enums.dart';

/// Immutable model representing a single adherence event for one dose.
///
/// Firestore path: `users/{uid}/adherence_logs/{id}`
///
/// The [date] field is stored as an ISO 8601 **date-only** string (e.g. "2025-05-02")
/// rather than a Timestamp, enabling efficient `where('date', isEqualTo, ...)` queries
/// without needing composite indexes on a truncated timestamp.
class AdherenceLogModel {
  final String id;
  final String medicationId;
  final String uid;
  final String scheduledTime;

  /// Date of the dose in local time, stored as "yyyy-MM-dd".
  /// Time component is always midnight — do NOT rely on the time part.
  final DateTime date;
  final DateTime selectedDate;

  final AdherenceStatus status;

  /// When the user confirmed (taken/missed). Null for [AdherenceStatus.pending].
  final DateTime? confirmedAt;
  final DateTime? timestamp;

  const AdherenceLogModel({
    required this.id,
    required this.medicationId,
    required this.uid,
    required this.scheduledTime,
    required this.date,
    required this.selectedDate,
    required this.status,
    this.confirmedAt,
    this.timestamp,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Deserialise from a Firestore document snapshot.
  /// [id] is the Firestore document ID.
  factory AdherenceLogModel.fromJson(String id, Map<String, dynamic> json) {
    DateTime? parseOptionalTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return null;
    }

    // date is stored as "yyyy-MM-dd" — parse to midnight local DateTime
    final dateStr = (json['date'] as String?) ?? '';
    final date = dateStr.isNotEmpty ? DateTime.parse(dateStr) : DateTime.now();
    final selectedDateStr = (json['selectedDate'] as String?) ?? dateStr;
    final selectedDate = selectedDateStr.isNotEmpty
        ? DateTime.parse(selectedDateStr)
        : date;

    return AdherenceLogModel(
      id: id,
      medicationId: (json['medicationId'] as String?) ?? '',
      uid: (json['uid'] as String?) ?? '',
      scheduledTime: (json['scheduledTime'] as String?) ?? '',
      date: DateTime(date.year, date.month, date.day), // strip any time
      selectedDate: DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      ),
      status: AdherenceStatusX.fromJson(json['status'] as String?),
      confirmedAt: parseOptionalTimestamp(json['confirmedAt']),
      timestamp: parseOptionalTimestamp(json['timestamp']),
    );
  }

  /// Serialise to a Firestore-compatible map.
  ///
  /// [date] → ISO 8601 date string "yyyy-MM-dd" for easy querying.
  /// [confirmedAt] → Firestore [Timestamp] when present, else `null`.
  Map<String, dynamic> toJson() {
    return {
      'medicationId': medicationId,
      'uid': uid,
      'scheduledTime': scheduledTime,
      'date': _dateOnlyString(date),
      'selectedDate': _dateOnlyString(selectedDate),
      'status': status.toJson(),
      'confirmedAt': confirmedAt != null
          ? Timestamp.fromDate(confirmedAt!)
          : null,
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Formats a [DateTime] to "yyyy-MM-dd".
  static String _dateOnlyString(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Convenience getter returning the stored date as a "yyyy-MM-dd" string.
  String get dateString => _dateOnlyString(date);

  AdherenceLogModel copyWith({
    String? id,
    String? medicationId,
    String? uid,
    String? scheduledTime,
    DateTime? date,
    DateTime? selectedDate,
    AdherenceStatus? status,
    DateTime? confirmedAt,
    DateTime? timestamp,
  }) {
    return AdherenceLogModel(
      id: id ?? this.id,
      medicationId: medicationId ?? this.medicationId,
      uid: uid ?? this.uid,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      date: date ?? this.date,
      selectedDate: selectedDate ?? this.selectedDate,
      status: status ?? this.status,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() =>
      'AdherenceLogModel(id: $id, medicationId: $medicationId, '
      'date: $dateString, status: ${status.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdherenceLogModel && other.id == id && other.uid == uid;

  @override
  int get hashCode => Object.hash(id, uid);
}
