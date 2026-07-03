// Pure-Dart model for an operator's manual risk override (Sprint 5, Prompt 13).
//
// Framework-free: imports NO `package:flutter` and NO `cloud_firestore` (mirrors
// [RiskEstimateModel]). An override is the long-flagged safety valve for when the
// scheduled pipeline lags or errs (audit H2): an authorised operator sets a city's
// displayed risk, transparently and auditably, until the pipeline recovers.
//
// It is a *separate* Firestore collection (`overrides/{city}`) — the genuine
// `riskEstimates` documents are never mutated, so the real model output and history
// stay intact (GOLDEN_RULES: never fabricate/overwrite genuine model data). The app
// overlays an active override on the risk surfaces with a clear "operator-set"
// label; when no override is active the genuine estimate shows unchanged.

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

/// An auditable, operator-authored override of a city's displayed risk.
class RiskOverride {
  /// City this override applies to (the Firestore document id).
  final String city;

  /// The operator-set risk level shown in place of the model estimate.
  final RiskLevel riskLevel;

  /// The disease the override refers to (kept honest with the risk surfaces).
  final String disease;

  /// Required human-readable justification, surfaced to users for transparency.
  final String reason;

  /// Audit: the authenticated operator who wrote the override.
  final String authorUid;
  final String authorEmail;

  /// Audit: when the override was written (UTC).
  final DateTime createdAt;

  /// Whether the override is currently in force. Cleared overrides are kept with
  /// `active == false` as an audit record rather than deleted.
  final bool active;

  /// Optional safety auto-expiry (UTC): after this instant the override no longer
  /// applies even if [active], so a forgotten override cannot mask a recovered
  /// pipeline forever. `null` means it applies until explicitly cleared.
  final DateTime? expiresAt;

  const RiskOverride({
    required this.city,
    required this.riskLevel,
    required this.disease,
    required this.reason,
    required this.authorUid,
    required this.authorEmail,
    required this.createdAt,
    this.active = true,
    this.expiresAt,
  });

  /// True when the override should be applied to the UI right now: it is [active]
  /// and not past [expiresAt]. [now] is injectable for deterministic tests.
  bool isActive({DateTime? now}) {
    if (!active) return false;
    if (expiresAt == null) return true;
    final reference = (now ?? DateTime.now()).toUtc();
    return reference.isBefore(expiresAt!.toUtc());
  }

  factory RiskOverride.fromJson(Map<String, dynamic> json) {
    return RiskOverride(
      city: (json['city'] as String?) ?? '',
      riskLevel: RiskLevelX.fromJson(json['riskLevel'] as String?),
      disease: (json['disease'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      authorUid: (json['authorUid'] as String?) ?? '',
      authorEmail: (json['authorEmail'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      active: (json['active'] as bool?) ?? true,
      expiresAt: json['expiresAt'] is String
          ? DateTime.parse(json['expiresAt'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'city': city,
      'riskLevel': riskLevel.toJson(),
      'disease': disease,
      'reason': reason,
      'authorUid': authorUid,
      'authorEmail': authorEmail,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'active': active,
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
    };
  }

  RiskOverride copyWith({
    String? city,
    RiskLevel? riskLevel,
    String? disease,
    String? reason,
    String? authorUid,
    String? authorEmail,
    DateTime? createdAt,
    bool? active,
    DateTime? expiresAt,
  }) {
    return RiskOverride(
      city: city ?? this.city,
      riskLevel: riskLevel ?? this.riskLevel,
      disease: disease ?? this.disease,
      reason: reason ?? this.reason,
      authorUid: authorUid ?? this.authorUid,
      authorEmail: authorEmail ?? this.authorEmail,
      createdAt: createdAt ?? this.createdAt,
      active: active ?? this.active,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
