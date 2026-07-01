import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';

/// The neutral, enumeration-safe confirmation shown whenever a reset request is
/// *accepted* — for a real account OR a non-existent one. It must never reveal
/// whether an account exists (Google's security model / no account enumeration).
const String kPasswordResetNeutralMessage =
    'Check your inbox. If an account exists for this email address, '
    "we've sent password reset instructions.";

/// State of a single password-reset request (dedicated to this flow so it never
/// touches the shared sign-in/up [AuthState]).
sealed class PasswordResetState {
  const PasswordResetState();
}

class PasswordResetIdle extends PasswordResetState {
  const PasswordResetIdle();
}

class PasswordResetSending extends PasswordResetState {
  const PasswordResetSending();
}

/// Request accepted — always paired with [kPasswordResetNeutralMessage]. Reached
/// on a genuine send AND on account-non-existence, so the two are indistinguishable.
class PasswordResetSent extends PasswordResetState {
  const PasswordResetSent();
}

/// A *real*, safe-to-surface failure (bad format, network, rate limit, config).
/// Never used for "no such account" — that maps to [PasswordResetSent].
class PasswordResetFailure extends PasswordResetState {
  final String message;
  const PasswordResetFailure(this.message);
}

/// Drives the Forgot Password flow through Clean Architecture: it calls the
/// existing [AuthRepository] (which invokes `FirebaseAuth.sendPasswordResetEmail`)
/// and applies the production security policy — no Firebase in the UI.
///
/// Security model:
/// * `user-not-found` / `user-disabled` → treated as **success** (neutral copy)
///   so the response cannot be used to enumerate accounts.
/// * format / network / rate-limit / config errors → mapped to specific,
///   non-revealing messages.
/// * the raw Firebase error is logged **in debug builds only**, never surfaced.
class PasswordResetController extends Notifier<PasswordResetState> {
  late final AuthRepository _repository;

  @override
  PasswordResetState build() {
    _repository = ref.watch(authRepositoryProvider);
    return const PasswordResetIdle();
  }

  /// Requests a Firebase password-reset email for [rawEmail].
  Future<void> sendResetEmail(String rawEmail) async {
    if (state is PasswordResetSending) return; // guard double-taps
    final email = rawEmail.trim();

    state = const PasswordResetSending();

    final result = await _repository.sendPasswordReset(email);

    state = result.fold(
      (error) => _mapError(error),
      (_) => const PasswordResetSent(),
    );
  }

  /// Clears the state back to idle (e.g. when re-opening the screen).
  void reset() => state = const PasswordResetIdle();

  /// Maps a repository [AuthException] to an enumeration-safe outcome.
  PasswordResetState _mapError(AuthException error) {
    // Dev-only diagnostics — the real Firebase code/message, never shown to users.
    if (kDebugMode) {
      debugPrint(
        '[password-reset] FirebaseAuthException '
        'code=${error.code ?? 'unknown'} message=${error.message}',
      );
    }

    switch (error.code) {
      // Enumeration safety: never confirm or deny that an account exists.
      case 'user-not-found':
      case 'user-disabled':
        return const PasswordResetSent();

      // Genuine, non-revealing input error (format).
      case 'invalid-email':
        return const PasswordResetFailure(
          'Please enter a valid email address.',
        );

      // Transient connectivity failure — the request never reached Firebase.
      case 'network-request-failed':
        return const PasswordResetFailure(
          'Network error. Please check your connection and try again.',
        );

      // Firebase rate limit (abuse protection).
      case 'too-many-requests':
        return const PasswordResetFailure(
          'Too many attempts. Please wait a moment and try again.',
        );

      // Email/Password provider disabled or project misconfigured — a config
      // problem for us to fix, surfaced generically (and logged above).
      case 'operation-not-allowed':
      case 'configuration-not-found':
        return const PasswordResetFailure(
          "We couldn't process your request right now. Please try again later.",
        );

      // Any unexpected exception — generic, safe message.
      default:
        return const PasswordResetFailure(
          'Something went wrong. Please try again.',
        );
    }
  }
}

/// DI for the Forgot Password flow. Dedicated to this screen so it never
/// collides with the shared sign-in/up notifier state.
final passwordResetControllerProvider =
    NotifierProvider<PasswordResetController, PasswordResetState>(
      PasswordResetController.new,
    );
