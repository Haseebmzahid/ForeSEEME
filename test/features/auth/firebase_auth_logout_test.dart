import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';

class _User extends Fake implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'firebase-test-token';
}

class _FirebaseAuth extends Fake implements FirebaseAuth {
  _FirebaseAuth(this.events);
  final List<String> events;

  @override
  User? currentUser = _User();

  @override
  Future<void> signOut() async {
    events.add('firebase');
    currentUser = null;
  }
}

class _GoogleSignIn extends Fake implements GoogleSignIn {
  _GoogleSignIn(this.events);
  final List<String> events;

  @override
  Future<GoogleSignInAccount?> signOut() async {
    events.add('google');
    return null;
  }
}

void main() {
  for (final confirmed in [true, false]) {
    test(
      'local cleanup after global revocation confirmation=$confirmed',
      () async {
        final events = <String>[];
        final auth = _FirebaseAuth(events);
        final repository = FirebaseAuthRepository(
          firebaseAuth: auth,
          googleSignIn: _GoogleSignIn(events),
          revokeSessions: (token) async {
            expect(token, 'firebase-test-token');
            events.add('revoke');
            if (!confirmed) throw StateError('Network response unavailable');
          },
        );
        final result = await repository.signOut();
        expect(events.first, 'revoke');
        expect(events.skip(1), unorderedEquals(['firebase', 'google']));
        expect(auth.currentUser, isNull);
        result.fold((error) {
          expect(confirmed, isFalse);
          expect(error.code, 'logout_unconfirmed');
          expect(error.message, contains('could not be confirmed'));
        }, (_) => expect(confirmed, isTrue));
      },
    );
  }
}
