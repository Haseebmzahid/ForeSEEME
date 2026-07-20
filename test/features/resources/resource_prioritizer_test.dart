import 'package:flutter_test/flutter_test.dart';

import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/services/resource_prioritizer.dart';
import 'package:fyp_foreseeme/features/risk/domain/models/risk_estimate_model.dart';

RiskEstimateModel _estimate({
  required RiskLevel riskLevel,
  double aqi = 60,
  double temperature = 25,
  double humidity = 50,
}) {
  return RiskEstimateModel(
    city: 'Lahore',
    riskLevel: riskLevel,
    disease: 'Dengue',
    confidence: 0.8,
    temperature: temperature,
    humidity: humidity,
    aqi: aqi,
    generatedAt: DateTime.utc(2026, 6, 28),
    modelVersion: 'stub-0.0.0',
  );
}

ResourceArticle _article(String id, ResourceTopic topic) => ResourceArticle(
  id: id,
  title: id,
  summary: id,
  topic: topic,
  sourceName: 'Test',
  sourceUrl: 'https://example.com',
  content: const [ArticleBlock.paragraph('body')],
);

void main() {
  group('priorityTopicOrder', () {
    test('no estimate yet -> calm default order', () {
      expect(priorityTopicOrder(null), kDefaultTopicOrder);
    });

    test('Low risk -> calm default order regardless of driver', () {
      final estimate = _estimate(riskLevel: RiskLevel.low, aqi: 280);
      expect(priorityTopicOrder(estimate), kDefaultTopicOrder);
    });

    test('elevated air-quality driver promotes air-quality topics first', () {
      final estimate = _estimate(
        riskLevel: RiskLevel.high,
        aqi: 280,
        temperature: 22,
        humidity: 40,
      );
      final order = priorityTopicOrder(estimate);
      expect(order.first, ResourceTopic.airQuality);
      expect(order, contains(ResourceTopic.lungs));
      expect(order, contains(ResourceTopic.asthma));
    });

    test('elevated heat driver promotes heat first', () {
      final estimate = _estimate(
        riskLevel: RiskLevel.medium,
        aqi: 40,
        temperature: 40,
        humidity: 30,
      );
      expect(priorityTopicOrder(estimate).first, ResourceTopic.heat);
    });

    test('elevated humidity driver has no matching topic -> calm default', () {
      final estimate = _estimate(
        riskLevel: RiskLevel.medium,
        aqi: 10,
        temperature: 15,
        humidity: 95,
      );
      expect(priorityTopicOrder(estimate), kDefaultTopicOrder);
    });
  });

  group('orderArticlesByTopic', () {
    test('reorders by topic while keeping same-topic articles stable', () {
      final articles = [
        _article('lungs-1', ResourceTopic.lungs),
        _article('heat-1', ResourceTopic.heat),
        _article('lungs-2', ResourceTopic.lungs),
        _article('asthma-1', ResourceTopic.asthma),
      ];
      final ordered = orderArticlesByTopic(articles, const [
        ResourceTopic.heat,
        ResourceTopic.asthma,
        ResourceTopic.lungs,
        ResourceTopic.airQuality,
      ]);
      expect(ordered.map((a) => a.id).toList(), [
        'heat-1',
        'asthma-1',
        'lungs-1',
        'lungs-2',
      ]);
    });
  });

  group('featuredArticle', () {
    test('picks the first article matching the top-priority topic', () {
      final articles = [
        _article('lungs-1', ResourceTopic.lungs),
        _article('heat-1', ResourceTopic.heat),
        _article('heat-2', ResourceTopic.heat),
      ];
      final featured = featuredArticle(articles, const [
        ResourceTopic.heat,
        ResourceTopic.lungs,
        ResourceTopic.asthma,
        ResourceTopic.airQuality,
      ]);
      expect(featured?.id, 'heat-1');
    });

    test('empty article list -> null', () {
      expect(featuredArticle(const [], kDefaultTopicOrder), isNull);
    });
  });
}
