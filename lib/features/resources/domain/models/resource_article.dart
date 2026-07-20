/// Topic of a self-care article — maps to an icon/accent in the presentation
/// layer (kept SDK-free here so the domain imports no Flutter).
enum ResourceTopic { lungs, asthma, airQuality, heat }

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
