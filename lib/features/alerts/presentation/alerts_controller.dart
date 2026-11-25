import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/models/notification_permission_status.dart';
import 'alerts_providers.dart';

/// Owns the refresh subscription and invalidates pending work at auth changes.
class AlertsController extends AsyncNotifier<NotificationPermissionStatus?> {
  StreamSubscription<String>? _refresh;
  Future<void> _pending = Future<void>.value();
  String? _uid;
  String? _registeredToken;
  String? _attemptedToken;
  int _generation = 0;
  bool _signingOut = false;

  @override
  NotificationPermissionStatus? build() {
    ref.listen(authStateProvider, (previous, next) {
      if (next.isLoading) return;
      final user = next.asData?.value;
      final uid = user?.emailVerified == true ? user?.uid : null;
      if (uid == _uid) return;
      _reset(uid);
      unawaited(syncGrantedPermission());
    });
    ref.onDispose(() => _reset(null));
    return null;
  }

  void _reset(String? uid) {
    _generation++;
    _uid = uid;
    _signingOut = false;
    _registeredToken = null;
    _attemptedToken = null;
    unawaited(_refresh?.cancel());
    _refresh = null;
  }

  bool _isCurrent(int generation) =>
      !_signingOut &&
      generation == _generation &&
      _uid != null &&
      _verifiedUid() == _uid;

  String? _verifiedUid() {
    final account = ref.read(authStateProvider).asData?.value;
    final user = ref.read(notificationAuthUserProvider)();
    return account?.emailVerified == true && account?.uid == user?.uid
        ? account?.uid
        : null;
  }

  Future<void> syncGrantedPermission() async {
    try {
      await _enable(requestPermission: false);
    } catch (_) {
      // Retry on a token change, resume, or an explicit permission request.
    }
  }

  Future<NotificationPermissionStatus> enableNotifications() =>
      _enable(requestPermission: true);

  Future<NotificationPermissionStatus> _enable({
    required bool requestPermission,
  }) async {
    if (_signingOut) return NotificationPermissionStatus.notDetermined;
    final uid = _verifiedUid();
    if (uid != _uid) _reset(uid);
    final generation = _generation;
    if (!_isCurrent(generation)) {
      return NotificationPermissionStatus.notDetermined;
    }

    final messaging = ref.read(pushMessagingServiceProvider);
    if (requestPermission) state = const AsyncLoading();
    try {
      final status = requestPermission
          ? await messaging.requestPermission()
          : await messaging.permissionStatus();
      if (!_isCurrent(generation)) return status;
      if (status.isGranted) {
        _refresh ??= messaging.onTokenRefresh().listen(
          (_) => unawaited(_syncInBackground(generation)),
          onError: (Object _) {},
        );
        await _enqueue(generation);
      } else {
        unawaited(_refresh?.cancel());
        _refresh = null;
      }
      if (_isCurrent(generation)) state = AsyncData(status);
      return status;
    } catch (_) {
      final error = StateError('Notification registration is unavailable');
      if (_isCurrent(generation)) state = AsyncError(error, StackTrace.current);
      throw error;
    }
  }

  Future<void> _syncInBackground(int generation) async {
    try {
      await _enqueue(generation);
    } catch (_) {
      // FCM and HTTP exceptions are deliberately kept out of logs.
    }
  }

  Future<void> _enqueue(int generation) {
    final operation = _pending.then((_) async {
      if (!_isCurrent(generation)) return;
      final messaging = ref.read(pushMessagingServiceProvider);
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 5),
      );
      if (!_isCurrent(generation)) return;
      if (token == null || token.isEmpty) {
        throw StateError('Notification registration is unavailable');
      }
      final user = ref.read(notificationAuthUserProvider)();
      final bearer = await user?.getIdToken().timeout(
        const Duration(seconds: 5),
      );
      if (!_isCurrent(generation)) return;
      if (bearer == null) {
        throw StateError('Notification registration is unavailable');
      }
      final api = ref.read(sessionApiClientProvider);
      final uncertainToken = _attemptedToken;
      if (uncertainToken != null &&
          uncertainToken != token &&
          uncertainToken != _registeredToken) {
        await api.unregisterNotification(bearer, uncertainToken);
        if (!_isCurrent(generation)) return;
      }
      _attemptedToken = token;
      await api.registerNotification(
        bearer,
        token,
        previousToken: _registeredToken == token ? null : _registeredToken,
      );
      if (_isCurrent(generation)) {
        _registeredToken = token;
        _attemptedToken = null;
      }
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// Invalidate callbacks before the network request. The supplied bearer was
  /// captured by Auth from the departing user, while they were still signed in.
  Future<void> unregister(String uid, String bearer) async {
    if (ref.read(notificationAuthUserProvider)()?.uid != uid) {
      throw StateError('Notification session changed');
    }
    if (_uid != uid) _reset(uid);
    final tokens = <String>{?_registeredToken, ?_attemptedToken};
    _signingOut = true;
    final generation = ++_generation;
    final subscription = _refresh;
    _refresh = null;
    await subscription?.cancel();
    final messaging = ref.read(pushMessagingServiceProvider);
    final api = ref.read(sessionApiClientProvider);
    var lookupConfirmed = true;
    try {
      if ((await messaging.permissionStatus().timeout(
        const Duration(seconds: 2),
      )).isGranted) {
        final token = await messaging.getToken().timeout(
          const Duration(seconds: 2),
        );
        if (token != null && token.isNotEmpty) tokens.add(token);
      }
    } catch (_) {
      // Known registrations can still be retired if SDK token lookup fails.
      lookupConfirmed = false;
    }
    if (generation != _generation ||
        ref.read(notificationAuthUserProvider)()?.uid != uid) {
      throw StateError('Notification session changed');
    }
    await Future.wait(
      tokens.map((token) => api.unregisterNotification(bearer, token)),
    );
    if (!lookupConfirmed) {
      throw StateError('Notification cleanup is unconfirmed');
    }
  }
}
