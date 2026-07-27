/// Topic of a self-care article — maps to an icon/accent in the presentation
/// layer (kept SDK-free here so the domain imports no Flutter).
enum ResourceTopic {
  lungs,
  asthma,
  airQuality,
  heat;

  /// Serialises to the stored contract string (Sprint M8.3), mirroring
  /// [RiskLevel.toJson]'s enum + companion pattern.
  String toJson() => switch (this) {
    ResourceTopic.lungs => 'lungs',
    ResourceTopic.asthma => 'asthma',
    ResourceTopic.airQuality => 'airQuality',
    ResourceTopic.heat => 'heat',
  };
}

extension ResourceTopicX on ResourceTopic {
  /// Deserialises from a contract string. Unrecognised/missing values default
  /// to [ResourceTopic.lungs] (the same defensive-default convention as
  /// [RiskLevelX.fromJson]) — content is never dropped for a bad topic value.
  static ResourceTopic fromJson(String? value) => switch (value) {
    'lungs' => ResourceTopic.lungs,
    'asthma' => ResourceTopic.asthma,
    'airQuality' => ResourceTopic.airQuality,
    'heat' => ResourceTopic.heat,
    _ => ResourceTopic.lungs,
  };
}

/// The kind of reading block inside an article's [ResourceArticle.content].
///
/// Kept deliberately small — a heading breaks the guidance into sections, a
/// paragraph is body copy, a tip is a short highlighted aside, and a warning is
/// a stronger callout (e.g. "seek medical care promptly"). No block type ever
/// carries anything other than plain, sourced text — there is no path for
/// generated or unsourced content to enter an article.
enum ArticleBlockKind { heading, paragraph, tip, warning }

/// One block of an article's reading content.
class ArticleBlock {
  final ArticleBlockKind kind;
  final String text;

  const ArticleBlock.heading(this.text) : kind = ArticleBlockKind.heading;
  const ArticleBlock.paragraph(this.text) : kind = ArticleBlockKind.paragraph;
  const ArticleBlock.tip(this.text) : kind = ArticleBlockKind.tip;
  const ArticleBlock.warning(this.text) : kind = ArticleBlockKind.warning;

  /// Sprint M8.3: the CMS reads/writes blocks as JSON. [kind] is stored by its
  /// enum name (`"heading"`/`"paragraph"`/`"tip"`/`"warning"`); an unrecognised
  /// or missing kind defaults to [ArticleBlockKind.paragraph] rather than
  /// dropping the block's text.
  factory ArticleBlock.fromJson(Map<String, dynamic> json) {
    final text = (json['text'] as String?) ?? '';
    final kind = ArticleBlockKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ArticleBlockKind.paragraph,
    );
    return switch (kind) {
      ArticleBlockKind.heading => ArticleBlock.heading(text),
      ArticleBlockKind.paragraph => ArticleBlock.paragraph(text),
      ArticleBlockKind.tip => ArticleBlock.tip(text),
      ArticleBlockKind.warning => ArticleBlock.warning(text),
    };
  }

  Map<String, dynamic> toJson() => {'kind': kind.name, 'text': text};
}

/// An immutable, **sourced** self-care guide.
///
/// Every article carries a real [sourceName] + [sourceUrl] and a [verified]
/// flag; the content is conservative, widely-accepted public-health guidance
/// (no fabricated or unsourced medical claims). [content] is a small sequence
/// of [ArticleBlock]s (headings/paragraphs/tips/warnings) rather than a flat
/// list of strings, so the reading experience can render real structure.
class ResourceArticle {
  final String id;
  final String title;
  final String summary;
  final List<ArticleBlock> content;

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
    required this.content,
    required this.sourceName,
    required this.sourceUrl,
    required this.topic,
    this.verified = true,
  });

  /// Sprint M8.3: the CMS's read/write contract for `articles/{id}` — [id] is
  /// NOT read from the body (it is the Firestore document id, passed in
  /// separately), mirroring how `overrides/{city}`'s `city` is the doc id.
  factory ResourceArticle.fromJson(Map<String, dynamic> json, {required String id}) {
    return ResourceArticle(
      id: id,
      title: (json['title'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      content: (json['content'] as List<dynamic>? ?? const [])
          .map((b) => ArticleBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      sourceName: (json['sourceName'] as String?) ?? '',
      sourceUrl: (json['sourceUrl'] as String?) ?? '',
      topic: ResourceTopicX.fromJson(json['topic'] as String?),
      verified: (json['verified'] as bool?) ?? true,
    );
  }

  /// Serialises for the write path. [id] is never included — it is the
  /// document id, not a field (mirrors [ResourceArticle.fromJson]).
  Map<String, dynamic> toJson() => {
    'title': title,
    'summary': summary,
    'content': content.map((b) => b.toJson()).toList(),
    'sourceName': sourceName,
    'sourceUrl': sourceUrl,
    'topic': topic.toJson(),
    'verified': verified,
  };

  /// Estimated reading time from the readable word count (paragraphs, tips and
  /// warnings — headings are excluded as they aren't prose), at a conservative
  /// 200 words/minute, rounded up and never below one minute.
  int get readingMinutes {
    final words = content
        .where((b) => b.kind != ArticleBlockKind.heading)
        .fold<int>(0, (sum, b) => sum + b.text.trim().split(RegExp(r'\s+')).length);
    return words == 0 ? 1 : (words / 200).ceil().clamp(1, 999);
  }
}
