import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  FirebaseAuthRepository({
    firebase_auth.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  @override
  Stream<UserModel?> get currentUser {
    return _firebaseAuth.authStateChanges().map((user) {
      if (user == null) return null;
      return UserModel.fromFirebaseUser(user);
    });
  }

  @override
  Future<Either<AuthException, UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        return const Left(AuthException('User creation failed: User is null'));
      }
      
      if (displayName != null) {
        await user.updateDisplayName(displayName);
        // Force refresh the user token so that subsequent currentUser emits the updated info
        await user.reload();
      }
      
      final updatedUser = _firebaseAuth.currentUser ?? user;
      return Right(UserModel.fromFirebaseUser(updatedUser));
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Sign up failed', e.code));
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }

  @override
  Future<Either<AuthException, UserModel>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        return const Left(AuthException('Sign in failed: User is null'));
      }
      return Right(UserModel.fromFirebaseUser(user));
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Sign in failed', e.code));
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }

  @override
  Future<Either<AuthException, UserModel>> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const Left(AuthException('Google sign in cancelled by user', 'cancelled'));
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final firebase_auth.OAuthCredential credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final user = userCredential.user;
      
      if (user == null) {
        return const Left(AuthException('Google sign in failed: User is null'));
      }
      
      return Right(UserModel.fromFirebaseUser(user));
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Google sign in failed', e.code));
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }

  @override
  Future<Either<AuthException, void>> signOut() async {
    try {
      await Future.wait([
        _firebaseAuth.signOut(),
        _googleSignIn.signOut(),
      ]);
      return const Right(null);
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Sign out failed', e.code));
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }

  @override
  Future<Either<AuthException, void>> sendPasswordReset(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      return const Right(null);
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Failed to send password reset email', e.code));
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }
}
