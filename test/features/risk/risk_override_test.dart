import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_override.dart';

final _now = DateTime.utc(2026, 7, 2, 12);

RiskOverride _override({
  bool active = true,
  DateTime? expiresAt,
  DateTime? createdAt,
}) => RiskOverride(
  city: 'Lahore',
  riskLevel: RiskLevel.high,
  disease: 'Smog',
  reason: 'Pipeline delayed; AQI spiked per advisory.',
  authorUid: 'op-1',
  authorEmail: 'op@example.com',
  createdAt: createdAt ?? _now.subtract(const Duration(hours: 2)),
  active: active,
  expiresAt: expiresAt,
);

void main() {
  group('RiskOverride serialisation', () {
    test('round-trips through json with UTC normalisation', () {
      final o = _override(expiresAt: _now.add(const Duration(days: 2)));
      final restored = RiskOverride.fromJson(o.toJson());

      expect(restored.city, 'Lahore');
      expect(restored.riskLevel, RiskLevel.high);
      expect(restored.disease, 'Smog');
      expect(restored.reason, o.reason);
      expect(restored.authorUid, 'op-1');
      expect(restored.authorEmail, 'op@example.com');
      expect(restored.active, isTrue);
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.expiresAt, isNotNull);
    });

    test('tolerates a missing/absent expiresAt', () {
      final json = _override().toJson()..remove('expiresAt');
      final restored = RiskOverride.fromJson(json);
      expect(restored.expiresAt, isNull);
    });

    test('audit fields are recorded on the document', () {
      final json = _override().toJson();
      expect(json['authorUid'], 'op-1');
      expect(json['authorEmail'], 'op@example.com');
      expect(json['reason'], isNotEmpty);
      expect(json['createdAt'], isA<String>());
    });
  });

  group('RiskOverride.isActive', () {
    test('active with no expiry applies', () {
      expect(_override().isActive(now: _now), isTrue);
    });

    test('inactive (cleared) never applies', () {
      expect(_override(active: false).isActive(now: _now), isFalse);
    });

    test('past expiry no longer applies even if active', () {
      final expired = _override(
        expiresAt: _now.subtract(const Duration(minutes: 1)),
      );
      expect(expired.isActive(now: _now), isFalse);
    });

    test('future expiry still applies', () {
      final live = _override(expiresAt: _now.add(const Duration(days: 1)));
      expect(live.isActive(now: _now), isTrue);
    });
  });
}
