import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/resources/data/repositories/firestore_resource_content_repository.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/firestore_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';

void main() {
  group('FirestoreResourceRepository', () {
    test('reads back a seeded article', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('articles').doc('lungs-smog').set(
        const ResourceArticle(
          id: 'lungs-smog',
          title: 'Protecting your lungs on smog days',
          summary: 'Cut your exposure to fine particles when air quality is poor.',
          content: [ArticleBlock.paragraph('Check your AQI.')],
          sourceName: 'World Health Organization (WHO)',
          sourceUrl: 'https://www.who.int/health-topics/air-pollution',
          topic: ResourceTopic.lungs,
        ).toJson(),
      );
      final repo = FirestoreResourceRepository(firestore: firestore);

      final articles = await repo.articles();

      expect(articles, hasLength(1));
      expect(articles.single.id, 'lungs-smog');
      expect(articles.single.title, 'Protecting your lungs on smog days');
    });

    test('preserves sourced dates and omits a CMS creation date', () async {
      final firestore = FakeFirebaseFirestore();
      final source = (await const StaticResourceRepository().articles())
          .firstWhere((article) => article.publishedAt != null);
      final articles = firestore.collection('articles');
      await articles.doc(source.id).set(source.toJson());
      await articles.doc('cms-created').set({
        ...source.toJson(),
        'verified': false,
        'authority': 'other',
        'lastVerifiedAt': null,
        'publishedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
      });

      final result = await FirestoreResourceRepository(
        firestore: firestore,
      ).articles();
      final byId = {for (final article in result) article.id: article};
      expect(byId[source.id]?.publishedAt, source.publishedAt);
      expect(byId['cms-created']?.publishedAt, isNull);
    });

    test(
      'falls back to the static curated content when the collection is unseeded',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreResourceRepository(firestore: firestore);

        final articles = await repo.articles();
        final staticArticles = await const StaticResourceRepository().articles();

        expect(articles.map((a) => a.id), staticArticles.map((a) => a.id));
      },
    );

    test('emergencyContact returns the fixed Rescue 1122 contact', () {
      final repo = FirestoreResourceRepository(firestore: FakeFirebaseFirestore());
      expect(repo.emergencyContact().number, '1122');
    });
  });

  group('FirestoreResourceContentRepository', () {
    test('saveArticle creates a new article, readable by FirestoreResourceRepository', () async {
      final firestore = FakeFirebaseFirestore();
      final contentRepo = FirestoreResourceContentRepository(firestore: firestore);
      final readRepo = FirestoreResourceRepository(firestore: firestore);

      await contentRepo.saveArticle(
        const ResourceArticle(
          id: 'new-guide',
          title: 'A brand new guide',
          summary: 'Summary.',
          content: [ArticleBlock.paragraph('Body.')],
          sourceName: 'WHO',
          sourceUrl: 'https://www.who.int/',
          topic: ResourceTopic.heat,
        ),
      );

      final articles = await readRepo.articles();
      expect(articles, hasLength(1));
      expect(articles.single.id, 'new-guide');
      expect(articles.single.title, 'A brand new guide');
    });

    test('saveArticle on an existing id updates it in place (upsert)', () async {
      final firestore = FakeFirebaseFirestore();
      final contentRepo = FirestoreResourceContentRepository(firestore: firestore);
      final readRepo = FirestoreResourceRepository(firestore: firestore);

      const original = ResourceArticle(
        id: 'guide-1',
        title: 'Original title',
        summary: 'Summary.',
        content: [ArticleBlock.paragraph('Body.')],
        sourceName: 'WHO',
        sourceUrl: 'https://www.who.int/',
        topic: ResourceTopic.heat,
      );
      await contentRepo.saveArticle(original);
      await contentRepo.saveArticle(
        original.copyWithTitle('Updated title'),
      );

      final articles = await readRepo.articles();
      expect(articles, hasLength(1)); // upsert, not a duplicate
      expect(articles.single.title, 'Updated title');
      expect(articles.single.id, 'guide-1'); // id unchanged by the edit
    });
  });
}

extension _CopyWithTitle on ResourceArticle {
  ResourceArticle copyWithTitle(String title) => ResourceArticle(
    id: id,
    title: title,
    summary: summary,
    content: content,
    sourceName: sourceName,
    sourceUrl: sourceUrl,
    topic: topic,
    verified: verified,
  );
}
