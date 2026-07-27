// Pure-Dart slug derivation for admin-authored articles (Sprint M8.3).
//
// Framework-free, mirroring the other domain services (`resource_prioritizer`,
// `risk_staleness`) — deterministic with an injectable clock for tests.

/// Derives a stable, Firestore-doc-id-safe slug from an article [title]:
/// lowercased, runs of non-alphanumeric characters collapsed to a single
/// hyphen, leading/trailing hyphens trimmed.
///
/// Assigned once, at creation (`AdminArticleFormController`), and never
/// changed by a later title edit — the id is what bookmarks and
/// `/resources/article/:id` deep links point at, so it must stay stable across
/// edits even if the slug would now read differently.
///
/// A title that slugifies to nothing (e.g. all punctuation) falls back to a
/// timestamp-based id — extremely unlikely in practice since the admin form
/// requires a non-empty title, but this keeps the function total rather than
/// ever handing Firestore an empty document id.
String slugifyArticleTitle(String title, {DateTime? now}) {
  final lower = title.trim().toLowerCase();
  final hyphenated = lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (hyphenated.isEmpty) {
    return 'article-${(now ?? DateTime.now()).millisecondsSinceEpoch}';
  }
  return hyphenated;
}
