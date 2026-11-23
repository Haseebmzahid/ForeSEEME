import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/admin_activity_log_entry.dart';
import '../../domain/repositories/admin_activity_log_repository.dart';

/// Firestore implementation of [AdminActivityLogRepository].
///
/// Reads the backend-maintained audit history.
class FirestoreAdminActivityLogRepository
    implements AdminActivityLogRepository {
  final FirebaseFirestore _firestore;

  FirestoreAdminActivityLogRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionPath = 'adminActivityLog';

  @override
  Future<List<AdminActivityLogEntry>> recent({int limit = 100}) async {
    final snapshot = await _firestore
        .collection(collectionPath)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.server));

    return snapshot.docs.map(_fromSnapshot).toList();
  }

  /// Maps one query document to an [AdminActivityLogEntry], tolerating a
  /// [Timestamp] for `createdAt` (mirrors
  /// [FirestoreRiskOverrideRepository.modelFromSnapshotData]).
  static AdminActivityLogEntry _fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final normalised = Map<String, dynamic>.from(doc.data());
    final createdAt = normalised['createdAt'];
    if (createdAt is Timestamp) {
      normalised['createdAt'] = createdAt.toDate().toUtc().toIso8601String();
    }
    return AdminActivityLogEntry.fromJson(normalised, id: doc.id);
  }
}
