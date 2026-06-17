import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/login_screen.dart';
import 'package:fyp_foreseeme/features/auth/presentation/register_screen.dart';
import 'package:fyp_foreseeme/features/auth/presentation/forgot_password_screen.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_screen.dart';

import 'package:fyp_foreseeme/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fyp_foreseeme/core/routes/splash_screen.dart';
import 'package:fyp_foreseeme/core/routes/app_shell.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/add_medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/check_in_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_screen.dart';

import 'package:fyp_foreseeme/features/resources/presentation/resources_screen.dart';
import 'package:fyp_foreseeme/features/profile/presentation/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorDashboardKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellDashboard');
final GlobalKey<NavigatorState> _shellNavigatorCheckInKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellCheckIn');
final GlobalKey<NavigatorState> _shellNavigatorMedsKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellMeds');
final GlobalKey<NavigatorState> _shellNavigatorResourcesKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellResources');
final GlobalKey<NavigatorState> _shellNavigatorProfileKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellProfile');

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();

  ref.listen(
    authStateProvider,
    (previous, next) => refreshNotifier.refresh(),
    fireImmediately: true,
  );
  ref.listen(
    profileExistsProvider,
    (previous, next) => refreshNotifier.refresh(),
    fireImmediately: true,
  );

  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final profileState = ref.read(profileExistsProvider);
      final location = state.matchedLocation;

      debugPrint('AppRouter: Current location: $location');
      debugPrint(
        'AppRouter: Auth isLoading: ${authState.isLoading}, isError: ${authState.hasError}, value: ${authState.value?.uid}',
      );
      debugPrint(
        'AppRouter: Profile isLoading: ${profileState.isLoading}, isError: ${profileState.hasError}, value: ${profileState.value}',
      );

      final isAuthRoute =
          location == '/login' ||
          location == '/register' ||
          location == '/forgot-password';

      if (authState.isLoading) {
        debugPrint(
          'AppRouter: Auth is loading, redirecting to / or null (splash).',
        );
        return location == '/' ? null : '/';
      }

      final isAuthenticated = authState.value != null;

      if (!isAuthenticated) {
        debugPrint(
          'AppRouter: User not authenticated, redirecting to /login (unless already on auth route).',
        );
        return isAuthRoute ? null : '/login';
      }

      if (profileState.isLoading) {
        debugPrint(
          'AppRouter: Profile is loading, redirecting to / or null (splash).',
        );
        return location == '/' ? null : '/';
      }

      final hasProfile = profileState.value ?? false;

      if (isAuthenticated && !hasProfile) {
        debugPrint(
          'AppRouter: Authenticated but no profile, redirecting to /health-profile.',
        );
        if (location == '/health-profile') return null;
        return '/health-profile';
      }

      if (isAuthenticated && hasProfile) {
        if (isAuthRoute || location == '/health-profile' || location == '/') {
          debugPrint(
            'AppRouter: Authenticated with profile, redirecting to /home.',
          );
          return '/home';
        }
      }

      debugPrint('AppRouter: No redirect needed, staying on $location');
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/health-profile',
        builder: (context, state) {
          final extra = state.extra;
          final isEditMode = extra is Map && extra['isEditMode'] == true;
          return HealthProfileScreen(isEditMode: isEditMode);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorDashboardKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorCheckInKey,
            routes: [
              GoRoute(
                path: '/check-in',
                builder: (context, state) => const DailyCheckInScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorMedsKey,
            routes: [
              GoRoute(
                path: '/medications',
                builder: (context, state) => const MedicationScreen(),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (context, state) => const AddMedicationScreen(),
                  ),
                ],
              ),
              GoRoute(
                path: '/adherence-history',
                builder: (context, state) => const AdherenceHistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorResourcesKey,
            routes: [
              GoRoute(
                path: '/resources',
                builder: (context, state) => const ResourcesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorProfileKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
