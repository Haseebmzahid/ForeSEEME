import '../domain/models/second_factor_challenge.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';

sealed class AuthState {
  const AuthState();
}

class AuthStateUnauthenticated extends AuthState {
  const AuthStateUnauthenticated();
}

class AuthStateAuthenticated extends AuthState {
  final UserModel user;
  const AuthStateAuthenticated(this.user);
}

class AuthStateLoading extends AuthState {
  const AuthStateLoading();
}

class AuthStateError extends AuthState {
  final String message;
  const AuthStateError(this.message);
}

class AuthStateSecondFactor extends AuthState {
  final List<SecondFactorChoice> choices;
  const AuthStateSecondFactor(this.choices);
}
