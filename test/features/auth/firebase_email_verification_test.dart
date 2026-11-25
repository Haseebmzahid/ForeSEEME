import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/core/utils/either.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:google_sign_in/google_sign_in.dart';

class _Token extends Fake implements IdTokenResult {
  _Token(this.verified);
  final bool verified;

  @override
  Map<String, dynamic> get claims => {'email_verified': verified};
}

class _User extends Fake implements User {
  final changes = StreamController<User?>();
  bool verifiedOnServer = false;
  bool tokenVerified = false;
  bool failSend = false;
  int sends = 0;
  int reloads = 0;

  @override
  String get uid => 'fixture-user';
  @override
  String get email => 'fixture@example.test';
  @override
  String? displayName;
  @override
  String? get photoURL => null;
  @override
  UserMetadata get metadata => UserMetadata(null, null);
  @override
  bool emailVerified = false;

  @override
  Future<void> updateDisplayName(String? name) async => displayName = name;

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    sends++;
    if (failSend) throw FirebaseAuthException(code: 'network-request-failed');
  }

  @override
  Future<void> reload() async {
    reloads++;
    emailVerified = verifiedOnServer;
    changes.add(this);
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (forceRefresh) tokenVerified = verifiedOnServer;
    return _Token(tokenVerified);
  }
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
}

class _Auth extends Fake implements FirebaseAuth {
  final user = _User();
  int accountCreations = 0;
  String? errorCode;

  @override
  User get currentUser => user;

  @override
  Stream<User?> userChanges() async* {
    yield user;
    yield* user.changes.stream;
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    accountCreations++;
    if (errorCode case final code?) {
      throw FirebaseAuthException(code: code, message: 'Internal test detail');
    }
    return _Credential(user);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (errorCode case final code?) {
      throw FirebaseAuthException(code: code, message: 'Internal test detail');
    }
    return _Credential(user);
  }
}

class _Google extends Fake implements GoogleSignIn {}

void main() {
  late _Auth auth;
  late FirebaseAuthRepository repository;

  setUp(() {
    auth = _Auth();
    repository = FirebaseAuthRepository(firebaseAuth: auth, googleSignIn: _Google());
  });

  test('valid signup stores a trimmed name and returns a pending account', () async {
    final result = await repository.signUpWithEmail(
      email: 'fixture@example.test',
      password: '12345678',
      displayName: '  Test Account  ',
    );
    final user = result.fold((error) => throw error, (user) => user);
    expect(user.displayName, 'Test Account');
    expect(user.emailVerified, isFalse);
  });

  test('missing name and short passwords do not create an account', () async {
    for (final (name, password) in [(' ', '12345678'), ('Test', '1234567')]) {
      final result = await repository.signUpWithEmail(
        email: 'fixture@example.test', password: password, displayName: name,
      );
      expect(result, isA<Left>());
    }
    expect(auth.accountCreations, 0);
  });

  test('duplicate registration and invalid email surface safe errors', () async {
    for (final code in ['email-already-in-use', 'invalid-email']) {
      auth.errorCode = code;
      final result = await repository.signUpWithEmail(
        email: 'fixture@example.test', password: '12345678', displayName: 'Test',
      );
      result.fold((error) {
        expect(error.code, code);
        expect(error.message, isNot(contains('Internal test detail')));
      }, (_) => fail('Expected the Firebase failure'));
    }
  });

  test('wrong password, disabled user and unknown email use the same message', () async {
    final messages = <String>{};
    for (final code in ['wrong-password', 'invalid-credential', 'user-not-found', 'user-disabled']) {
      auth.errorCode = code;
      final result = await repository.signInWithEmail(
        email: 'fixture@example.test', password: '12345678',
      );
      result.fold((error) => messages.add(error.message), (_) => fail('Expected error'));
    }
    expect(messages, hasLength(1));
  });

  for (final fails in [false, true]) {
    test('verification send and cooldown when delivery request fails=$fails', () async {
      auth.user.failSend = fails;
      final first = await repository.sendEmailVerification(auth.user.uid);
      expect(first is Left, fails);
      expect(await repository.sendEmailVerification(auth.user.uid), isA<Left>());
      expect(await repository.sendEmailVerification('different-user'), isA<Left>());
      expect(auth.user.sends, 1);
    });
  }

  test('reload emits the verified state after the token claim refreshes', () async {
    final states = StreamIterator<UserModel?>(repository.currentUser);
    addTearDown(states.cancel);
    expect(await states.moveNext(), isTrue);
    expect(states.current?.emailVerified, isFalse);

    auth.user.verifiedOnServer = true;
    final next = states.moveNext();
    final result = await repository.refreshEmailVerification(auth.user.uid);
    expect(result.fold((_) => false, (verified) => verified), isTrue);
    expect(await next, isTrue);
    expect(auth.user.reloads, 1);
    expect(auth.user.tokenVerified, isTrue);
    expect(states.current?.emailVerified, isTrue);

    // A fresh subscription models Riverpod rebuilding the restored session.
    expect((await repository.currentUser.first)?.emailVerified, isTrue);
  });
}
