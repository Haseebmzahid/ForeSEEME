import '../models/second_factor_challenge.dart';

class AuthException implements Exception {
  final String message;
  final String? code;

  final List<SecondFactorChoice> secondFactors;

  const AuthException(this.message, [this.code, this.secondFactors = const []]);

  @override
  String toString() =>
      'AuthException: $message${code != null ? ' (Code: $code)' : ''}';
}
