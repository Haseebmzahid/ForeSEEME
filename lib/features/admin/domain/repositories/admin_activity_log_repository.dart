import '../models/admin_activity_log_entry.dart';

abstract class AdminActivityLogRepository {
  Future<List<AdminActivityLogEntry>> recent({int limit = 100});
}
