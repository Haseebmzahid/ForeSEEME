import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/repositories/adherence_log_repository.dart';
import '../../domain/models/adherence_log_model.dart';
import '../../domain/enums/medication_enums.dart';

/// Firestore implementation of [AdherenceLogRepository].
class FirestoreAdherenceLogRepository implements AdherenceLogRepository {
  final FirebaseFirestore _firestore;

  FirestoreAdherenceLogRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference _logsRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('adherence_logs');

  /// Internal helper to format a [DateTime] to "yyyy-MM-dd"
  String _dateOnlyString(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<void> logDose(AdherenceLogModel log) async {
    final docRef = log.id.isNotEmpty
        ? _logsRef(log.uid).doc(log.id)
        : _logsRef(log.uid).doc();

    await docRef.set(log.toJson());
  }

  @override
  Stream<List<AdherenceLogModel>> getLogsForDate(String uid, DateTime date) {
    final dateString = _dateOnlyString(date);

    // Queries Firestore where date string matches exactly
    return _logsRef(uid).where('date', isEqualTo: dateString).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return AdherenceLogModel.fromJson(
          doc.id,
          doc.data() as Map<String, dynamic>,
        );
      }).toList();
    });
  }

  @override
  Stream<List<AdherenceLogModel>> getLogsForDateRange(
    String uid,
    DateTime startDate,
    DateTime endDate,
  ) {
    final startString = _dateOnlyString(startDate);
    final endString = _dateOnlyString(endDate);

    return _logsRef(uid)
        .where('date', isGreaterThanOrEqualTo: startString)
        .where('date', isLessThanOrEqualTo: endString)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return AdherenceLogModel.fromJson(
              doc.id,
              doc.data() as Map<String, dynamic>,
            );
          }).toList();
        });
  }

  @override
  Future<void> updateLogStatus(
    String uid,
    String logId,
    AdherenceStatus status,
  ) async {
    final updates = <String, dynamic>{
      'status': status.toJson(),
      'confirmedAt': status != AdherenceStatus.pending
          ? FieldValue.serverTimestamp() // Log the exact time when confirmed
          : null,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _logsRef(uid).doc(logId).update(updates);
  }
}
