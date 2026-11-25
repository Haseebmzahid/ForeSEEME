import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import '../domain/models/second_factor_challenge.dart';
import '../domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_state.dart';

class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    return const AuthStateUnauthenticated();
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signUpWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    );

    final user = result.fold((_) => null, (u) => u);
    if (user == null) {
      state = result.fold(
        (error) => AuthStateError(error.message),
        _sessionState,
      );
      return;
    }
    final directory = ref.read(userDirectoryRepositoryProvider);
    final verification = await _repository.sendEmailVerification(user.uid);
    state = AuthStateVerificationPending(
      user,
      verification.fold(
        (error) => error.message,
        (_) => 'Verification email sent. Check your inbox.',
      ),
    );

    // The account and verification request are independent of the directory.
    try {
      await directory.register(
        uid: user.uid,
        email: user.email,
        name: displayName,
      );
    } catch (_) {
      // Directory registration is best effort.
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signInWithEmail(
      email: email,
      password: password,
    );

    state = result.fold(
      (error) => error.secondFactors.isEmpty
          ? AuthStateError(error.message)
          : AuthStateSecondFactor(error.secondFactors),
      _sessionState,
    );
  }

  Future<void> signInWithGoogle() async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signInWithGoogle();

    state = result.fold(
      (error) => error.secondFactors.isEmpty
          ? AuthStateError(error.message)
          : AuthStateSecondFactor(error.secondFactors),
      _sessionState,
    );
  }

  Future<void> completeSecondFactor(
    VerifySecondFactor verify,
    String code,
  ) async {
    final challenge = state;
    if (challenge is! AuthStateSecondFactor) return;
    final user = await verify(code);
    if (identical(state, challenge)) state = _sessionState(user);
  }

  AuthState _sessionState(UserModel user) => user.emailVerified
      ? AuthStateAuthenticated(user)
      : AuthStateVerificationPending(user);

  void cancelSecondFactor() {
    if (state is AuthStateSecondFactor) {
      state = const AuthStateUnauthenticated();
    }
  }

  Future<void> signOut() async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signOut();

    state = result.fold(
      (error) => AuthStateLogoutUnconfirmed(error.message),
      (_) => const AuthStateUnauthenticated(),
    );
  }

  Future<void> sendPasswordReset(String email) async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.sendPasswordReset(email);

    state = result.fold(
      (error) => error.secondFactors.isEmpty
          ? AuthStateError(error.message)
          : AuthStateSecondFactor(error.secondFactors),
      (_) =>
          const AuthStateUnauthenticated(), // Or maintain previous state if preferred
    );
  }
}
