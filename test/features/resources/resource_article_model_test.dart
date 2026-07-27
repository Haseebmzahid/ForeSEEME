import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

void main() {
  group('ArticleBlock JSON', () {
    test('round-trips every kind', () {
      for (final block in [
        ArticleBlock.heading('H'),
        ArticleBlock.paragraph('P'),
        ArticleBlock.tip('T'),
        ArticleBlock.warning('W'),
      ]) {
        final restored = ArticleBlock.fromJson(block.toJson());
        expect(restored.kind, block.kind);
        expect(restored.text, block.text);
      }
    });

    test('an unrecognised kind defaults to paragraph, keeping the text', () {
      final block = ArticleBlock.fromJson({'kind': 'nonsense', 'text': 'kept'});
      expect(block.kind, ArticleBlockKind.paragraph);
      expect(block.text, 'kept');
    });
  });

  group('ResourceTopic JSON', () {
    test('round-trips every value', () {
      for (final topic in ResourceTopic.values) {
        expect(ResourceTopicX.fromJson(topic.toJson()), topic);
      }
    });

    test('an unrecognised/missing value defaults to lungs', () {
      expect(ResourceTopicX.fromJson('nonsense'), ResourceTopic.lungs);
      expect(ResourceTopicX.fromJson(null), ResourceTopic.lungs);
    });
  });

  group('ResourceArticle JSON', () {
    final article = const ResourceArticle(
      id: 'extreme-heat',
      title: 'Staying safe in extreme heat',
      summary: 'Reduce heat-illness risk during hot spells.',
      content: [
        ArticleBlock.heading('Through the day'),
        ArticleBlock.warning('Watch for heat exhaustion.'),
      ],
      sourceName: 'World Health Organization (WHO)',
      sourceUrl: 'https://www.who.int/health-topics/heatwaves',
      topic: ResourceTopic.heat,
    );

    test('round-trips every field except id (which is the doc id)', () {
      final json = article.toJson();
      expect(json.containsKey('id'), isFalse);

      final restored = ResourceArticle.fromJson(json, id: article.id);

      expect(restored.id, article.id);
      expect(restored.title, article.title);
      expect(restored.summary, article.summary);
      expect(restored.sourceName, article.sourceName);
      expect(restored.sourceUrl, article.sourceUrl);
      expect(restored.topic, article.topic);
      expect(restored.verified, article.verified);
      expect(restored.content.map((b) => (b.kind, b.text)), [
        (ArticleBlockKind.heading, 'Through the day'),
        (ArticleBlockKind.warning, 'Watch for heat exhaustion.'),
      ]);
    });

    test('missing fields degrade to safe defaults, never a throw', () {
      final restored = ResourceArticle.fromJson({}, id: 'x');
      expect(restored.id, 'x');
      expect(restored.title, '');
      expect(restored.content, isEmpty);
      expect(restored.verified, isTrue);
      expect(restored.topic, ResourceTopic.lungs);
    });
  });
}
