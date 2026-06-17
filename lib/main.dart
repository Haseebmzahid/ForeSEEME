import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/local_notification_service.dart';
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

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const ForeSeeMeApp(),
    ),
  );
}

class ForeSeeMeApp extends ConsumerWidget {
  const ForeSeeMeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    return MaterialApp.router(
      title: 'ForeSeeMe',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: AppTheme.applyColors,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
