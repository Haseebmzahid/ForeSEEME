import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_foreseeme/features/alerts/data/services/firebase_push_messaging_service.dart';
import 'package:fyp_foreseeme/features/alerts/domain/models/notification_permission_status.dart';

class _PermissionSettings extends Fake implements NotificationSettings {
  @override
  final AuthorizationStatus authorizationStatus;

  _PermissionSettings(this.authorizationStatus);
}

class _Messaging extends Fake implements FirebaseMessaging {
  final AuthorizationStatus status;

  _Messaging(this.status);

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async => _PermissionSettings(status);
}

void main() {
  const expectedStatuses = {
    AuthorizationStatus.authorized: NotificationPermissionStatus.granted,
    AuthorizationStatus.provisional: NotificationPermissionStatus.provisional,
    AuthorizationStatus.denied: NotificationPermissionStatus.denied,
    AuthorizationStatus.deniedPermanently: NotificationPermissionStatus.denied,
    AuthorizationStatus.notDetermined:
        NotificationPermissionStatus.notDetermined,
  };

  for (final entry in expectedStatuses.entries) {
    test('maps ${entry.key.name} to ${entry.value.name}', () async {
      final service = FirebasePushMessagingService(
        messaging: _Messaging(entry.key),
      );
      expect(await service.requestPermission(), entry.value);
    });
  }
}
