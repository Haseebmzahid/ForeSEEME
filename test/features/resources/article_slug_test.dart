import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/resources/domain/services/article_slug.dart';

void main() {
  group('slugifyArticleTitle', () {
    test('lowercases and hyphenates', () {
      expect(
        slugifyArticleTitle('Staying safe in extreme heat'),
        'staying-safe-in-extreme-heat',
      );
    });

    test('collapses punctuation and repeated separators', () {
      expect(
        slugifyArticleTitle('When to stay indoors (Air Quality Index)'),
        'when-to-stay-indoors-air-quality-index',
      );
    });

    test('trims leading/trailing hyphens', () {
      expect(slugifyArticleTitle('  --Hello World!--  '), 'hello-world');
    });

    test('an all-punctuation title falls back to a timestamp-based id', () {
      final now = DateTime.utc(2026, 7, 27);
      expect(
        slugifyArticleTitle('!!!', now: now),
        'article-${now.millisecondsSinceEpoch}',
      );
    });
  });
}
