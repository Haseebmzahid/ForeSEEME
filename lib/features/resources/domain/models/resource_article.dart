/// Topic of a self-care article — maps to an icon/accent in the presentation
/// layer (kept SDK-free here so the domain imports no Flutter).
enum ResourceTopic { lungs, asthma, airQuality, heat }

/// An immutable, **sourced** self-care guide.
///
/// Every article carries a real [sourceName] + [sourceUrl] and a [verified]
/// flag; the content is conservative, widely-accepted public-health guidance
/// (no fabricated or unsourced medical claims). [body] is a list of short,
/// plain-language points.
class ResourceArticle {
  final String id;
  final String title;
  final String summary;
  final List<String> body;

  /// Attribution — the authority the guidance is drawn from.
  final String sourceName;

  /// A stable URL for the source, openable from the article.
  final String sourceUrl;

  /// True when the content has been reviewed against its cited source.
  final bool verified;

  final ResourceTopic topic;

  const ResourceArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.sourceName,
    required this.sourceUrl,
    required this.topic,
    this.verified = true,
  });
}
