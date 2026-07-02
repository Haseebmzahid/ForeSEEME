import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/insights/presentation/model_transparency_content.dart';
import 'package:fyp_foreseeme/features/insights/presentation/model_transparency_screen.dart';

/// All section text (titles + paragraphs + bullets) flattened, for substring
/// assertions over the sourced content.
String allContent() {
  final buffer = StringBuffer(kNotClinicalStatement);
  for (final section in kModelTransparencySections) {
    buffer.writeln(section.title);
    section.paragraphs.forEach(buffer.writeln);
    section.bullets.forEach(buffer.writeln);
  }
  for (final citation in kTransparencyCitations) {
    buffer.writeln(citation);
  }
  buffer.writeln(kTransparencyFooter);
  return buffer.toString();
}

void main() {
  group('Model transparency content (sourced)', () {
    test('states environmental risk, not outbreak/clinical prediction', () {
      expect(kNotClinicalStatement, contains('not'));
      expect(kNotClinicalStatement.toLowerCase(), contains('outbreak'));
      expect(kNotClinicalStatement.toLowerCase(), contains('clinical'));
      expect(kNotClinicalStatement.toLowerCase(), contains('environmental'));
    });

    test('documents data provenance', () {
      final content = allContent();
      expect(content, contains('Open-Meteo'));
      expect(content, contains('CAMS'));
      // Cities and the real, bounded data window.
      expect(content, contains('Lahore'));
      expect(content, contains('2022'));
      // Honest: no fabricated data.
      expect(content.toLowerCase(), contains('no records are fabricated'));
    });

    test('documents label methodology with cited determinants', () {
      final content = allContent();
      expect(content.toLowerCase(), contains('suitability'));
      expect(content, contains('PM2.5'));
      // Peer-reviewed sources are listed.
      expect(kTransparencyCitations, isNotEmpty);
      expect(allContent(), contains('Mordecai'));
    });

    test('states limitations plainly', () {
      final titles = kModelTransparencySections.map((s) => s.title).toList();
      expect(titles, contains('Limitations'));
      final content = allContent().toLowerCase();
      expect(content, contains('not incidence'));
      expect(content, contains('not clinically validated'));
      expect(content, contains('design choices'));
    });

    test('pins the exact model version for provenance', () {
      expect(kTransparencyFooter, contains('rf-1.0.0'));
    });
  });

  group('ModelTransparencyScreen', () {
    // A tall viewport so the lazily-built ListView renders every section.
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('renders provenance, limitations and the not-clinical statement', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 7200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: ModelTransparencyScreen()),
      );
      await tester.pumpAndSettle();

      // Page title + headline honesty statement.
      expect(find.text('Model Transparency'), findsOneWidget);
      expect(find.text(kNotClinicalStatement), findsOneWidget);

      // Provenance and limitations sections are on the page.
      expect(find.text('Where the data comes from'), findsOneWidget);
      expect(find.textContaining('Open-Meteo'), findsOneWidget);
      expect(find.text('Limitations'), findsOneWidget);

      // Provenance footer pins the model version.
      expect(find.textContaining('rf-1.0.0'), findsOneWidget);
    });
  });
}
