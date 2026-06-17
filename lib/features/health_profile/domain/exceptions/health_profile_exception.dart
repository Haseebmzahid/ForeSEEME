/// Domain-level exception for health profile operations.
/// Wraps raw Firestore / platform errors so that callers receive a clean,
/// user-facing [message] without depending on Firebase internals.
class HealthProfileException implements Exception {
  final String message;
  final String? code;

  const HealthProfileException(this.message, [this.code]);

  @override
  String toString() =>
      'HealthProfileException: $message${code != null ? ' (Code: $code)' : ''}';
}
