import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/repositories/disclaimer_repository.dart';

class FirestoreDisclaimerRepository implements DisclaimerRepository {
  FirestoreDisclaimerRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _record(String uid, String version) =>
      _firestore.doc('medicalDisclaimerAcceptances/$uid/versions/$version');

  bool _valid(Map<String, dynamic>? data, String version) =>
      data?.length == 2 &&
      data?['version'] == version &&
      data?['acceptedAt'] is Timestamp;

  @override
  Future<bool> hasAccepted(String uid, String version) async {
    // Previously committed acceptances remain available through Firestore's
    // cache. A pending local overlay cannot satisfy the gate.
    final record = await _record(uid, version).get();
    if (record.metadata.hasPendingWrites) {
      throw StateError('Disclaimer acceptance is pending');
    }
    return _valid(record.data(), version);
  }

  @override
  Future<void> accept(String uid, String version) async {
    final record = _record(uid, version);
    await _firestore.runTransaction<void>((transaction) async {
      final existing = await transaction.get(record);
      if (_valid(existing.data(), version)) return;
      if (existing.exists) throw StateError('Invalid disclaimer acceptance');
      transaction.set(record, {
        'version': version,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
