import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
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

    state = result.fold(
      (error) => AuthStateError(error.message),
      (user) => AuthStateAuthenticated(user),
    );
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signInWithEmail(
      email: email,
      password: password,
    );

    state = result.fold(
      (error) => AuthStateError(error.message),
      (user) => AuthStateAuthenticated(user),
    );
  }

  Future<void> signInWithGoogle() async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signInWithGoogle();

    state = result.fold(
      (error) => AuthStateError(error.message),
      (user) => AuthStateAuthenticated(user),
    );
  }

  Future<void> signOut() async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.signOut();

    state = result.fold(
      (error) => AuthStateError(error.message),
      (_) => const AuthStateUnauthenticated(),
    );
  }

  Future<void> sendPasswordReset(String email) async {
    if (state is AuthStateLoading) return;
    state = const AuthStateLoading();

    final result = await _repository.sendPasswordReset(email);

    state = result.fold(
      (error) => AuthStateError(error.message),
      (_) => const AuthStateUnauthenticated(), // Or maintain previous state if preferred
    );
  }
}
