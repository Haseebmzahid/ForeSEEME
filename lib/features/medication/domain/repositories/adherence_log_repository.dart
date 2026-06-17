import '../models/adherence_log_model.dart';
import '../enums/medication_enums.dart';

/// Abstract interface for Adherence Log data operations.
/// Defines pure data operations without business logic.
abstract class AdherenceLogRepository {
  /// Logs a new adherence dose event.
  Future<void> logDose(AdherenceLogModel log);

  /// Retrieves a real-time stream of adherence logs for a specific date.
  Stream<List<AdherenceLogModel>> getLogsForDate(String uid, DateTime date);

  /// Retrieves a real-time stream of adherence logs for a date range.
  Stream<List<AdherenceLogModel>> getLogsForDateRange(
    String uid,
    DateTime startDate,
    DateTime endDate,
  );

  /// Updates the status of an adherence log (e.g., from pending to taken/missed).
  Future<void> updateLogStatus(
    String uid,
    String logId,
    AdherenceStatus status,
  );
}
