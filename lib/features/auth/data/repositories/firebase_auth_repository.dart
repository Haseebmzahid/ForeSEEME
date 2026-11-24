import 'dart:async';

import '../../domain/models/second_factor_challenge.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/domain/exceptions/auth_exception.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final Future<void> Function(String)? _revokeSessions;
  final Future<void> Function(String uid, String bearer)?
  _unregisterNotifications;

  FirebaseAuthRepository({
    firebase_auth.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    Future<void> Function(String)? revokeSessions,
    Future<void> Function(String uid, String bearer)? unregisterNotifications,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn(),
       _revokeSessions = revokeSessions,
       _unregisterNotifications = unregisterNotifications;

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
    } on firebase_auth.FirebaseAuthMultiFactorException catch (e) {
      return Left(_challenge(e));
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
        return const Left(
          AuthException('Google sign in cancelled by user', 'cancelled'),
        );
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final firebase_auth.OAuthCredential credential =
          firebase_auth.GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );

      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );
      final user = userCredential.user;

      if (user == null) {
        return const Left(AuthException('Google sign in failed: User is null'));
      }

      return Right(UserModel.fromFirebaseUser(user));
    } on firebase_auth.FirebaseAuthMultiFactorException catch (e) {
      return Left(_challenge(e));
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Google sign in failed', e.code));
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }

  AuthException _challenge(
    firebase_auth.FirebaseAuthMultiFactorException error,
  ) {
    final resolver = error.resolver;

    Future<UserModel> resolve(
      firebase_auth.MultiFactorAssertion assertion,
    ) async {
      final credential = await resolver.resolveSignIn(assertion);
      final user = credential.user;
      if (user == null) {
        throw const AuthException('Sign-in could not be completed.');
      }
      return UserModel.fromFirebaseUser(user);
    }

    return AuthException(
      'Complete sign-in with an enrolled second factor.',
      'multi-factor-required',
      [
        for (final hint in resolver.hints)
          if (hint is firebase_auth.TotpMultiFactorInfo)
            SecondFactorChoice(
              hint.displayName ?? 'Authenticator app',
              () async {
                return (code) async => resolve(
                  await firebase_auth
                      .TotpMultiFactorGenerator.getAssertionForSignIn(
                    hint.uid,
                    code,
                  ),
                );
              },
            )
          else if (hint is firebase_auth.PhoneMultiFactorInfo)
            SecondFactorChoice(hint.displayName ?? hint.phoneNumber, () async {
              final verification = Completer<String>();
              await _firebaseAuth.verifyPhoneNumber(
                multiFactorSession: resolver.session,
                multiFactorInfo: hint,
                verificationCompleted: (_) {},
                verificationFailed: (error) {
                  if (!verification.isCompleted) {
                    verification.completeError(error);
                  }
                },
                codeSent: (id, _) {
                  if (!verification.isCompleted) verification.complete(id);
                },
                codeAutoRetrievalTimeout: (id) {
                  if (!verification.isCompleted) verification.complete(id);
                },
              );
              final id = await verification.future.timeout(
                const Duration(seconds: 60),
              );
              return (code) => resolve(
                firebase_auth.PhoneMultiFactorGenerator.getAssertion(
                  firebase_auth.PhoneAuthProvider.credential(
                    verificationId: id,
                    smsCode: code,
                  ),
                ),
              );
            }),
      ],
    );
  }

  @override
  Future<Either<AuthException, void>> signOut() async {
    var revocationConfirmed = true;
    var notificationsConfirmed = true;
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      try {
        final revoke = _revokeSessions;
        final token = await user.getIdToken().timeout(
          const Duration(seconds: 5),
        );
        if (revoke == null || token == null) {
          throw StateError('Session service unavailable');
        }
        try {
          await _unregisterNotifications
              ?.call(user.uid, token)
              .timeout(const Duration(seconds: 6));
        } on Object {
          notificationsConfirmed = false;
        }
        await revoke(token);
      } on Object {
        revocationConfirmed = false;
      }
    }
    try {
      final currentUid = _firebaseAuth.currentUser?.uid;
      if (currentUid == null || currentUid == user?.uid) {
        await Future.wait([_firebaseAuth.signOut(), _googleSignIn.signOut()]);
      }
    } on Object {
      return Left(
        AuthException(
          revocationConfirmed
              ? 'Local sign-out could not be fully confirmed.'
              : 'Local sign-out and global session revocation could not be fully confirmed.',
          'logout_unconfirmed',
        ),
      );
    }
    if (!revocationConfirmed) {
      return Left(
        AuthException(
          'Signed out on this device. Sign-out on other devices could not be confirmed.',
          'logout_unconfirmed',
        ),
      );
    }
    if (!notificationsConfirmed) {
      return const Left(
        AuthException(
          'Signed out. Notification cleanup could not be confirmed.',
          'logout_unconfirmed',
        ),
      );
    }
    return const Right(null);
  }

  @override
  Future<Either<AuthException, void>> sendPasswordReset(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      return const Right(null);
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(
        AuthException(
          e.message ?? 'Failed to send password reset email',
          e.code,
        ),
      );
    } catch (e) {
      return Left(AuthException(e.toString()));
    }
  }
}
