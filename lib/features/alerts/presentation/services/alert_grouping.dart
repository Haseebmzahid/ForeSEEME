import 'package:fyp_foreseeme/features/alerts/domain/models/user_alert.dart';

/// One calendar-day bucket of alerts for the inbox's date grouping
/// (Sprint 6A, S6A-05).
class AlertDateGroup {
  final String header;
  final List<UserAlertModel> alerts;

  const AlertDateGroup({required this.header, required this.alerts});
}

const _monthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Groups [alerts] into ordered, contiguous calendar-day buckets for display
/// (Today / Yesterday / an absolute date).
///
/// Pure `data → buckets` mapping, mirroring [AlertDeepLinkRouter]/
/// [AlertIdResolver]: no Firebase, no widget, fully unit-testable. [alerts]
/// must already be newest-first — the repository's `watchAlerts` query
/// guarantees this — so grouping only detects day boundaries as it walks the
/// list; it never re-sorts.
///
/// A `null` createdAt (a malformed doc, per [UserAlertModel]'s own doc
/// comment) can't be dated, so those alerts collect into one trailing
/// "Earlier" bucket rather than being silently dropped.
///
/// [now] is an injectable clock (mirrors `RiskStalenessNotice`'s pattern) so
/// "Today"/"Yesterday" boundaries are deterministic in tests.
List<AlertDateGroup> groupAlertsByDate(
  List<UserAlertModel> alerts, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final groups = <AlertDateGroup>[];
  String? currentHeader;
  var currentBucket = <UserAlertModel>[];
  final undated = <UserAlertModel>[];

  void flush() {
    if (currentHeader != null && currentBucket.isNotEmpty) {
      groups.add(
        AlertDateGroup(header: currentHeader, alerts: currentBucket),
      );
    }
  }

  for (final alert in alerts) {
    final createdAt = alert.createdAt;
    if (createdAt == null) {
      undated.add(alert);
      continue;
    }
    final header = _headerFor(createdAt, today: today, yesterday: yesterday);
    if (header != currentHeader) {
      flush();
      currentHeader = header;
      currentBucket = <UserAlertModel>[];
    }
    currentBucket.add(alert);
  }
  flush();

  if (undated.isNotEmpty) {
    groups.add(AlertDateGroup(header: 'Earlier', alerts: undated));
  }

  return groups;
}

String _headerFor(
  DateTime createdAt, {
  required DateTime today,
  required DateTime yesterday,
}) {
  final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  final month = _monthAbbrev[day.month - 1];
  return day.year == today.year
      ? '$month ${day.day}'
      : '$month ${day.day}, ${day.year}';
}
