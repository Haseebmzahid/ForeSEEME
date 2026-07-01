import 'package:cloud_firestore/cloud_firestore.dart';

/// A **cited** advisory attached to an alert (Sprint 4, Prompt 5).
///
/// Looked up from the verified content library by the backend engine — never
/// generated (Rule 11 / `docs/recommendation_rules.md`). Immutable; the app only
/// ever reads it. Mirrors the nested `recommendation` map written by the engine
/// (`dispatch_alerts._alert_body`).
class AlertRecommendation {
  final String id;
  final String text;
  final String source;
  final String sourceUrl;

  const AlertRecommendation({
    required this.id,
    required this.text,
    required this.source,
    required this.sourceUrl,
  });

  /// Parses the nested `recommendation` map; returns `null` when absent.
  static AlertRecommendation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return AlertRecommendation(
      id: (json['id'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      sourceUrl: (json['sourceUrl'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'source': source,
    'sourceUrl': sourceUrl,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertRecommendation &&
          other.id == id &&
          other.text == text &&
          other.source == source &&
          other.sourceUrl == sourceUrl;

  @override
  int get hashCode => Object.hash(id, text, source, sourceUrl);
}

/// Immutable model for one in-app inbox alert (Sprint 4, Prompt 5).
///
/// Firestore path: `userAlerts/{uid}/items/{alertId}` (frozen contract,
/// `docs/alert_dispatch_design.md` §4.2). The dispatch engine creates these via
/// the Admin SDK; the app only READS them and may MARK them read
/// (`read`/`readAt`). This mirrors the Timestamp-bearing `AdherenceLogModel`
/// convention (defensive `Timestamp | String | null` parsing).
class UserAlertModel {
  /// Firestore document id — the idempotency key
  /// `{uid}__{riskEstimateId}__{category}`.
  final String id;

  final String title;
  final String body;
  final String category;
  final String city;

  /// Risk level as the contract string (`Low` | `Medium` | `High`).
  final String riskLevel;
  final String disease;

  /// Cited advisory (looked up, never generated). `null` if the engine omitted it.
  final AlertRecommendation? recommendation;

  /// In-app route to open on tap, e.g. `/resources`, `/nearby-hospitals`.
  final String deepLink;
  final String riskEstimateId;

  /// When the engine delivered the alert. `null` only for malformed docs.
  final DateTime? createdAt;

  final bool read;

  /// When the user marked it read; `null` while unread.
  final DateTime? readAt;

  const UserAlertModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.city,
    required this.riskLevel,
    required this.disease,
    required this.recommendation,
    required this.deepLink,
    required this.riskEstimateId,
    required this.createdAt,
    required this.read,
    required this.readAt,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Deserialise from a Firestore document. [id] is the document id.
  factory UserAlertModel.fromJson(String id, Map<String, dynamic> json) {
    return UserAlertModel(
      id: id,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      riskLevel: (json['riskLevel'] as String?) ?? '',
      disease: (json['disease'] as String?) ?? '',
      recommendation: AlertRecommendation.fromJson(
        (json['recommendation'] as Map?)?.cast<String, dynamic>(),
      ),
      deepLink: (json['deepLink'] as String?) ?? '',
      riskEstimateId: (json['riskEstimateId'] as String?) ?? '',
      createdAt: _parseTimestamp(json['createdAt']),
      read: (json['read'] as bool?) ?? false,
      readAt: _parseTimestamp(json['readAt']),
    );
  }

  /// Serialise to a Firestore-compatible map. The app never writes these, but a
  /// symmetric `toJson` keeps document parsing unit-testable (fixtures/round-trip).
  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'category': category,
    'city': city,
    'riskLevel': riskLevel,
    'disease': disease,
    'recommendation': recommendation?.toJson(),
    'deepLink': deepLink,
    'riskEstimateId': riskEstimateId,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    'read': read,
    'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
  };

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Accepts a Firestore [Timestamp], an ISO-8601 string, or `null` — matching
  /// [AdherenceLogModel]'s defensive parsing so a mixed writer never crashes.
  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAlertModel &&
          other.id == id &&
          other.read == read &&
          other.readAt == readAt;

  @override
  int get hashCode => Object.hash(id, read, readAt);

  @override
  String toString() =>
      'UserAlertModel(id: $id, city: $city, riskLevel: $riskLevel, read: $read)';
}
