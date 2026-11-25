import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';

abstract class AuthRepository {
  Stream<UserModel?> get currentUser;

  Future<Either<AuthException, UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<Either<AuthException, UserModel>> signInWithEmail({
    required String email,
    required String password,
  });

  Future<Either<AuthException, UserModel>> signInWithGoogle();

  Future<Either<AuthException, void>> sendEmailVerification(String uid);

  Future<Either<AuthException, bool>> refreshEmailVerification(String uid);

  Future<Either<AuthException, void>> signOut();

  Future<Either<AuthException, void>> sendPasswordReset(String email);
}
