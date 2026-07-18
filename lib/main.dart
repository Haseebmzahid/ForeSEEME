import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'core/routes/app_router.dart';
import 'core/theme/foreseeme_palette.dart';
import 'core/theme/foreseeme_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/platform_config_service.dart';
import 'features/alerts/presentation/alerts_providers.dart';
import 'features/medication/presentation/notification_refresh_provider.dart';
import 'features/resources/presentation/nearby_hospitals_providers.dart';
// TODO: import 'firebase_options.dart'; once generated

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notifications service
  await LocalNotificationService.initialize();

  // Initialize Firebase
  // Uncomment the following line when firebase_options.dart is generated
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Firebase.initializeApp();

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

class _ForeSeeMeAppState extends ConsumerState<ForeSeeMeApp> {
  @override
  void initState() {
    super.initState();
    // Start FCM message handling once the first frame (and router) are ready,
    // so a terminated-launch tap can be routed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fcmMessageHandlerProvider).start();
      // Same pattern for medication-notification taps (Sprint UX-M2.5,
      // Phase 6) — a separate handler, its own deep-link vocabulary.
      ref.read(medicationNotificationTapHandlerProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    return MaterialApp.router(
      title: 'ForeSeeMe',
      theme: ForeSeeMeTheme.light,
      darkTheme: ForeSeeMeTheme.dark,
      themeMode: themeMode,
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
