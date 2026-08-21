/// Topic of a self-care article — maps to an icon/accent in the presentation
/// layer (kept SDK-free here so the domain imports no Flutter).
///
/// This is the app's **one** category vocabulary. It is used in two ways and
/// there is deliberately no second taxonomy alongside it:
///  * [ResourceArticle.topic] — the single *primary* topic, which drives the
///    risk-aware ordering in `resource_prioritizer.dart` and the card artwork;
///  * [ResourceArticle.categories] — every topic the resource is filed under,
///    which is what the Resource Center's category rail filters on. A WHO
///    ambient-air-pollution fact sheet is genuinely air-quality *and* lungs
///    *and* heart guidance, and a single-topic model could only ever show it
///    under one of them.
enum ResourceTopic {
  lungs,
  asthma,
  airQuality,
  heat,
  heart;

  /// Serialises to the stored contract string (Sprint M8.3), mirroring
  /// [RiskLevel.toJson]'s enum + companion pattern.
  String toJson() => switch (this) {
    ResourceTopic.lungs => 'lungs',
    ResourceTopic.asthma => 'asthma',
    ResourceTopic.airQuality => 'airQuality',
    ResourceTopic.heat => 'heat',
    ResourceTopic.heart => 'heart',
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
    'heart' => ResourceTopic.heart,
    _ => ResourceTopic.lungs,
  };
}

/// The organisation a resource is published by.
///
/// This is what makes "verified" mean something. A resource may only be
/// *presented* as verified when its publisher is a recognised public-health
/// authority ([isTrusted]) **and** its content has been checked against that
/// publisher ([ResourceArticle.verified]); see
/// [ResourceArticle.isTrustedSource], which is the only thing the UI reads.
/// Anything published elsewhere stays [ResourceAuthority.other] and never
/// earns the badge, whatever its `verified` flag says.
enum ResourceAuthority {
  who,
  cdc,
  epa,
  nih,
  nhs,

  /// Any publisher that is not a recognised public-health authority.
  other;

  bool get isTrusted => this != ResourceAuthority.other;

  /// The restrained badge label the UI prints, e.g. `WHO`.
  String get shortLabel => switch (this) {
    ResourceAuthority.who => 'WHO',
    ResourceAuthority.cdc => 'CDC',
    ResourceAuthority.epa => 'AIRNOW',
    ResourceAuthority.nih => 'NIH',
    ResourceAuthority.nhs => 'NHS',
    ResourceAuthority.other => 'SOURCE',
  };

  String toJson() => name;
}

extension ResourceAuthorityX on ResourceAuthority {
  /// Unrecognised/missing values fall back to [ResourceAuthority.other] — the
  /// *untrusted* end of the scale, so a bad value can never promote a resource
  /// into the verified badge.
  static ResourceAuthority fromJson(String? value) =>
      ResourceAuthority.values.firstWhere(
        (a) => a.name == value,
        orElse: () => ResourceAuthority.other,
      );
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

  /// True when the content has been reviewed against its cited source. On its
  /// own this is NOT enough to show the verified badge — see [isTrustedSource].
  final bool verified;

  /// The publisher, which decides whether "verified" may be shown at all.
  final ResourceAuthority authority;

  /// The primary topic: what the resource is *mostly* about. Drives the
  /// risk-aware ordering and the card artwork.
  final ResourceTopic topic;

  /// When the **source** published or last revised its guidance, when the
  /// publisher states one. `null` when it does not — never a stand-in for
  /// [lastVerifiedAt], and never invented.
  final DateTime? publishedAt;

  /// When a curator last checked this entry against [sourceUrl]. Deliberately
  /// distinct from [publishedAt]: ForeSeeMe checking a link today says nothing
  /// about when the authority wrote the guidance.
  final DateTime? lastVerifiedAt;

  final List<ResourceTopic> _categories;

  const ResourceArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.sourceName,
    required this.sourceUrl,
    required this.topic,
    this.verified = true,
    this.authority = ResourceAuthority.other,
    this.publishedAt,
    this.lastVerifiedAt,
    List<ResourceTopic> categories = const [],
  }) : _categories = categories;

  /// Every topic this resource is filed under, [topic] always among them.
  ///
  /// A resource authored before multi-category support (or by an admin form
  /// that only picks a primary topic) simply files under its own [topic], so
  /// the category rail keeps working for stored content that predates this.
  List<ResourceTopic> get categories {
    if (_categories.isEmpty) return [topic];
    if (_categories.contains(topic)) return _categories;
    return [topic, ..._categories];
  }

  /// The only trust signal the UI is allowed to act on: content checked against
  /// a source **and** a publisher that is a recognised authority.
  bool get isTrustedSource => verified && authority.isTrusted;

  /// Sprint M8.3: the CMS's read/write contract for `articles/{id}` — [id] is
  /// NOT read from the body (it is the Firestore document id, passed in
  /// separately), mirroring how `overrides/{city}`'s `city` is the doc id.
  ///
  /// Every field added for the production catalogue is optional here, so a
  /// document written before it (or by the admin form, which only edits the
  /// original fields) still deserialises without loss.
  factory ResourceArticle.fromJson(Map<String, dynamic> json, {required String id}) {
    DateTime? date(String key) {
      final raw = json[key];
      return raw is String ? DateTime.tryParse(raw) : null;
    }

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
      authority: ResourceAuthorityX.fromJson(json['authority'] as String?),
      publishedAt: date('publishedAt'),
      lastVerifiedAt: date('lastVerifiedAt'),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .map((c) => ResourceTopicX.fromJson(c as String?))
          .toList(),
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
    'authority': authority.toJson(),
    'categories': [for (final c in categories) c.toJson()],
    if (publishedAt != null)
      'publishedAt': publishedAt!.toIso8601String(),
    if (lastVerifiedAt != null)
      'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
  };

  /// Estimated reading time from the readable word count (paragraphs, tips and
  /// warnings — headings are excluded as they aren't prose), at a conservative
  /// 200 words/minute, rounded up and never below one minute.
  ///
  /// This measures **ForeSeeMe's own summary**, not the external page it links
  /// to — the length of a third-party article is not something the catalogue
  /// knows.
  int get readingMinutes {
    final words = content
        .where((b) => b.kind != ArticleBlockKind.heading)
        .fold<int>(0, (sum, b) => sum + b.text.trim().split(RegExp(r'\s+')).length);
    return words == 0 ? 1 : (words / 200).ceil().clamp(1, 999);
  }
}

/// `20 Aug 2026` — the restrained date form the Resource Center prints for
/// provenance. Lives here rather than in a widget so the article screen and
/// the citation card can never drift apart, and so no date-formatting package
/// is pulled in for two lines of output.
String formatResourceDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
