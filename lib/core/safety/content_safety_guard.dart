/// Content-safety guard (Sprint 5, Prompt 4).
///
/// Codifies GOLDEN_RULES **Rule 11** as a testable, runtime-checkable guarantee:
/// every user-facing advisory — a recommendation today, a Phase-3 explanation /
/// attribution tomorrow — must be a **cited lookup or a deterministic
/// attribution** that carries a real source, and must never be produced by a
/// generative path.
///
/// Framework-free and dependency-light: it operates on the primitive attribution
/// fields (a source label + a source URL), so `core` takes **no** dependency on
/// any feature model. Callers pass the citation fields of whatever cited object
/// they hold (e.g. a `HealthRecommendation`, or a future attribution record).
///
/// This does not, and cannot, prove the *absence* of a generative code path by
/// itself — that guarantee is upheld by the accompanying tests, which assert
/// that content is only ever drawn from the fixed, cited library. This guard is
/// the composition-point check that a specific value reaching the user is cited.
class ContentSafetyGuard {
  const ContentSafetyGuard._();

  /// A citation is valid when it names a non-empty [source] and links to a
  /// verifiable authority ([sourceUrl] is an `https://` URL).
  static bool isCited({required String source, required String sourceUrl}) {
    return source.trim().isNotEmpty && sourceUrl.trim().startsWith('https://');
  }

  /// Throws [ContentSafetyViolation] when [isCited] is false.
  ///
  /// Use at content-composition points so an un-sourced advisory can never reach
  /// the user. Because callers surface advisories through providers whose UI
  /// handles the error state by hiding (never crashing), a violation fails safe
  /// *and* is caught in CI by the guard tests.
  static void requireCited({
    required String label,
    required String source,
    required String sourceUrl,
  }) {
    if (!isCited(source: source, sourceUrl: sourceUrl)) {
      throw ContentSafetyViolation(
        '$label is not cited (source="$source", sourceUrl="$sourceUrl"). '
        'All advisory content must be a cited lookup or deterministic '
        'attribution — never generated (Rule 11).',
      );
    }
  }
}

/// Raised when advisory content lacks a valid citation (Rule 11 breach).
class ContentSafetyViolation implements Exception {
  final String message;
  const ContentSafetyViolation(this.message);

  @override
  String toString() => 'ContentSafetyViolation: $message';
}
