import 'package:fyp_foreseeme/features/alerts/domain/models/incoming_alert.dart';

/// Displays a foreground alert (Android doesn't auto-display push while the app
/// is open). Abstracted so the handler carries no notification-SDK dependency
/// and can be faked in tests.
abstract class AlertPresenter {
  Future<void> showForegroundAlert(IncomingAlert alert);
}
