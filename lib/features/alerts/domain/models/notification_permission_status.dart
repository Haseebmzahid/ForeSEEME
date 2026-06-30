/// Outcome of requesting notification permission (domain-level, maps from the
/// platform's authorization status).
enum NotificationPermissionStatus {
  granted,
  provisional,
  denied,
  notDetermined,
}

extension NotificationPermissionStatusX on NotificationPermissionStatus {
  /// True when the app may deliver notifications (authorized or provisional).
  bool get isGranted =>
      this == NotificationPermissionStatus.granted ||
      this == NotificationPermissionStatus.provisional;
}
