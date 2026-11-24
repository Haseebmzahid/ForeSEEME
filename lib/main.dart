import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/routes/app_router.dart';
import 'core/theme/foreseeme_palette.dart';
import 'core/theme/foreseeme_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/platform_config_service.dart';
import 'features/alerts/presentation/alerts_providers.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/auth/presentation/auth_state.dart';
import 'features/medication/presentation/notification_refresh_provider.dart';
import 'features/resources/presentation/nearby_hospitals_providers.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notifications service
  await LocalNotificationService.initialize();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.NONE);
  }

  final preferences = await SharedPreferences.getInstance();

  // Resolve the Maps/Places key once (dart-define → native manifest) so the
  // Nearby Hospitals feature reuses the already-configured key at runtime.
  final mapsApiKey = await resolveMapsApiKey();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        placesApiKeyProvider.overrideWithValue(mapsApiKey),
      ],
      child: const ForeSeeMeApp(),
    ),
  );
}

class ForeSeeMeApp extends ConsumerStatefulWidget {
  const ForeSeeMeApp({super.key});

  @override
  ConsumerState<ForeSeeMeApp> createState() => _ForeSeeMeAppState();
}

class _ForeSeeMeAppState extends ConsumerState<ForeSeeMeApp>
    with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start FCM message handling once the first frame (and router) are ready,
    // so a terminated-launch tap can be routed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(fcmMessageHandlerProvider).start();
      unawaited(_openLocalPush());
      _syncPushRegistration();
      // Same pattern for medication-notification taps (Sprint UX-M2.5,
      // Phase 6) — a separate handler, its own deep-link vocabulary.
      ref.read(medicationNotificationTapHandlerProvider).start();
    });
  }

  Future<void> _openLocalPush() async {
    final payload = await LocalNotificationService.consumeLaunchPayload(
      push: true,
    );
    if (mounted && payload != null) {
      await ref
          .read(fcmMessageHandlerProvider)
          .openLocalPayload(
            payload.substring(
              LocalNotificationService.pushPayloadPrefix.length,
            ),
            restoring: true,
          );
    }
  }

  void _syncPushRegistration() {
    unawaited(
      ref.read(alertsControllerProvider.notifier).syncGrantedPermission(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncPushRegistration();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the auth-scoped registration listener active across routed screens.
    ref.listen(alertsControllerProvider, (_, _) {});
    ref.listen(authNotifierProvider, (_, state) {
      if (state is AuthStateLogoutUnconfirmed) {
        _messenger.currentState?.showSnackBar(
          SnackBar(content: Text(state.message)),
        );
      }
    });
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    return MaterialApp.router(
      title: 'ForeSeeMe',
      theme: ForeSeeMeTheme.light,
      darkTheme: ForeSeeMeTheme.dark,
      themeMode: themeMode,
      scaffoldMessengerKey: _messenger,
      builder: _applyThemeChrome,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Root theme bridge, applied once above the router.
///
/// Applies the ForeSeeMe status-/navigation-bar overlay globally (via an
/// [AnnotatedRegion]) so system chrome switches live with the theme — even on
/// screens that have no [AppBar] to carry `systemOverlayStyle`.
Widget _applyThemeChrome(BuildContext context, Widget? child) {
  final brightness = Theme.of(context).brightness;
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: ForeSeeMeTheme.overlayStyleFor(ForeSeeMePalette.of(brightness)),
    child: child ?? const SizedBox.shrink(),
  );
}
