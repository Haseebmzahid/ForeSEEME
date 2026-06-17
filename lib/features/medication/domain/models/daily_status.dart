enum DailyAdherenceStatus { taken, skipped, pending, noSchedule }

class DailyStatus {
  final DateTime date;
  final DailyAdherenceStatus status;

  const DailyStatus({required this.date, required this.status});

  DailyStatus copyWith({DateTime? date, DailyAdherenceStatus? status}) {
    return DailyStatus(date: date ?? this.date, status: status ?? this.status);
  }

  @override
  String toString() {
    return 'DailyStatus(date: $date, status: ${status.name})';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DailyStatus && other.date == date && other.status == status;
  }

  @override
  int get hashCode => Object.hash(date, status);
}
