import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/risk/domain/services/aqi_band.dart';

void main() {
  group('aqiBandFor', () {
    test('classifies each EPA band by its upper boundary', () {
      expect(aqiBandFor(0), AqiBand.good);
      expect(aqiBandFor(50), AqiBand.good);
      expect(aqiBandFor(51), AqiBand.moderate);
      expect(aqiBandFor(100), AqiBand.moderate);
      expect(aqiBandFor(101), AqiBand.unhealthyForSensitiveGroups);
      expect(aqiBandFor(150), AqiBand.unhealthyForSensitiveGroups);
      expect(aqiBandFor(151), AqiBand.unhealthy);
      expect(aqiBandFor(200), AqiBand.unhealthy);
      expect(aqiBandFor(201), AqiBand.veryUnhealthy);
      expect(aqiBandFor(300), AqiBand.veryUnhealthy);
      expect(aqiBandFor(301), AqiBand.hazardous);
      expect(aqiBandFor(500), AqiBand.hazardous);
    });

    test(
      'an unusual negative reading degrades to Good rather than throwing',
      () {
        expect(aqiBandFor(-10), AqiBand.good);
      },
    );

    test('labels are plain-language and non-empty for every band', () {
      for (final band in AqiBand.values) {
        expect(band.label, isNotEmpty);
      }
    });
  });
}
