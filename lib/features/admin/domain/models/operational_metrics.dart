class AccountMetrics {
  final int totalUsers;
  final int activeUsers;
  final int windowDays;
  final DateTime generatedAt;

  const AccountMetrics({
    required this.totalUsers,
    required this.activeUsers,
    required this.windowDays,
    required this.generatedAt,
  });
}
