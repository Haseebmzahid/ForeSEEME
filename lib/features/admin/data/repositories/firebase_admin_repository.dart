import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_repository.dart';

/// Firebase Auth implementation of [AdminRepository].
///
/// Reads the `admin` custom claim from the current user's ID token. Custom claims
/// can only be *set* by the backend Admin SDK (see `backend/scripts/set_admin_claim.py`),
/// so a client cannot forge one; this only reads it to decide whether to reveal
/// the admin surface. Firestore rules independently enforce the claim on writes.
class FirebaseAdminRepository implements AdminRepository {
  final firebase_auth.FirebaseAuth _auth;

  FirebaseAdminRepository({firebase_auth.FirebaseAuth? auth})
    : _auth = auth ?? firebase_auth.FirebaseAuth.instance;

  @override
  Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    // Force-refresh so a just-granted (or just-revoked) claim is picked up.
    final token = await user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }
}
