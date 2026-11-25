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
  final Map<String, DateTime> _verificationRequestedAt = {};

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
    return _firebaseAuth
        .userChanges()
        .asyncMap((user) async {
          if (user == null) return null;
          var verified = false;
          if (user.emailVerified) {
            try {
              verified = await _hasVerifiedToken(user);
            } catch (_) {
              // Stay pending and let the account holder retry from the screen.
            }
          }
          if (_firebaseAuth.currentUser?.uid != user.uid) return null;
          return UserModel.fromFirebaseUser(user, emailVerified: verified);
        })
        .distinct((previous, next) {
          return previous?.uid == next?.uid &&
              previous?.emailVerified == next?.emailVerified &&
              previous?.email == next?.email &&
              previous?.displayName == next?.displayName &&
              previous?.photoUrl == next?.photoUrl;
        });
  }

  Future<bool> _hasVerifiedToken(firebase_auth.User user) async {
    final current = await user.getIdTokenResult();
    if (current.claims?['email_verified'] == true) return true;
    // A browser action can verify the Auth record before the ID token updates.
    final refreshed = await user.getIdTokenResult(true);
    return refreshed.claims?['email_verified'] == true;
  }

  @override
  Future<Either<AuthException, void>> sendEmailVerification(
    String uid,
  ) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || user.uid != uid || user.emailVerified) {
      return const Left(
        AuthException('Verification is unavailable for this session.'),
      );
    }
    final now = DateTime.now();
    final previous = _verificationRequestedAt[uid];
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 1)) {
      return const Left(
        AuthException('Please wait one minute between requests.'),
      );
    }
    _verificationRequestedAt[uid] = now;
    try {
      await user.sendEmailVerification();
      return const Right(null);
    } catch (_) {
      return const Left(
        AuthException(
          'The verification email could not be sent. Please wait a minute and try again.',
        ),
      );
    }
  }

  @override
  Future<Either<AuthException, bool>> refreshEmailVerification(
    String uid,
  ) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || user.uid != uid) {
      return const Left(AuthException('This sign-in session has ended.'));
    }
    try {
      await user.reload();
      final refreshed = _firebaseAuth.currentUser;
      if (refreshed == null || refreshed.uid != uid) {
        return const Left(AuthException('This sign-in session has ended.'));
      }
      return Right(refreshed.emailVerified && await _hasVerifiedToken(refreshed));
    } catch (_) {
      return const Left(
        AuthException(
          'Verification status could not be checked. Please try again.',
        ),
      );
    }
  }

  @override
  Future<Either<AuthException, UserModel>> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final name = displayName?.trim() ?? '';
    if (name.isEmpty || name.length > 160) {
      return const Left(
        AuthException('Enter your full name (up to 160 characters).'),
      );
    }
    if (password.length < 8) {
      return const Left(
        AuthException('Password must be at least 8 characters.'),
      );
    }
    try {
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        return const Left(AuthException('Could not complete registration.'));
      }

      try {
        await user.updateDisplayName(name);
      } catch (_) {
        return const Left(AuthException(
          'Your account was created, but your name could not be saved. You can request a verification email here.',
        ));
      }

      final updatedUser = _firebaseAuth.currentUser ?? user;
      return Right(UserModel.fromFirebaseUser(updatedUser));
    } on firebase_auth.FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' =>
          'This password does not meet the password policy.',
        _ => _safeError(
          e.code,
          'Could not create an account. Try again, sign in, or reset your password.',
        ),
      };
      return Left(AuthException(message, e.code));
    } catch (_) {
      return const Left(
        AuthException('Could not finish registration. Please try again.'),
      );
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
        return const Left(AuthException('Sign-in could not be completed.'));
      }
      return Right(UserModel.fromFirebaseUser(user));
    } on firebase_auth.FirebaseAuthMultiFactorException catch (e) {
      return Left(_challenge(e));
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(
        AuthException(
          _safeError(
            e.code,
            'Sign-in failed. Check your email and password and try again.',
          ),
          e.code,
        ),
      );
    } catch (_) {
      return const Left(AuthException('Sign-in failed. Please try again.'));
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
        return const Left(AuthException('Google sign-in failed. Please try again.'));
      }

      return Right(UserModel.fromFirebaseUser(user));
    } on firebase_auth.FirebaseAuthMultiFactorException catch (e) {
      return Left(_challenge(e));
    } on firebase_auth.FirebaseAuthException catch (e) {
      return Left(
        AuthException(
          _safeError(e.code, 'Google sign-in failed. Please try again.'),
          e.code,
        ),
      );
    } catch (_) {
      return const Left(
        AuthException('Google sign-in failed. Please try again.'),
      );
    }
  }

  String _safeError(String code, String fallback) => switch (code) {
    'network-request-failed' => 'Check your connection and try again.',
    'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
    _ => fallback,
  };

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
          'Could not request a password reset.',
          e.code,
        ),
      );
    } catch (_) {
      return const Left(AuthException('Could not request a password reset.'));
    }
  }
}
