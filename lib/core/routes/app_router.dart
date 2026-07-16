import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/widgets/app_motion.dart';

import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/login_screen.dart';
import 'package:fyp_foreseeme/features/auth/presentation/register_screen.dart';
import 'package:fyp_foreseeme/features/auth/presentation/forgot_password_screen.dart';

import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_screen.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/profile_ready_screen.dart';

import 'package:fyp_foreseeme/features/dashboard/presentation/dashboard_screen.dart';
import 'package:fyp_foreseeme/core/routes/splash_screen.dart';
import 'package:fyp_foreseeme/core/routes/app_shell.dart';
import 'package:fyp_foreseeme/features/medication/presentation/medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/add_medication_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/check_in_screen.dart';
import 'package:fyp_foreseeme/features/medication/presentation/adherence_history_screen.dart';

import 'package:fyp_foreseeme/features/resources/presentation/resource_center_screen.dart';
import 'package:fyp_foreseeme/features/profile/presentation/profile_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_map_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/risk_details_screen.dart';
import 'package:fyp_foreseeme/features/risk/presentation/screens/comparison_screen.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_permission_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/notification_settings_screen.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alert_inbox_screen.dart';
import 'package:fyp_foreseeme/features/insights/presentation/health_insights_screen.dart';
import 'package:fyp_foreseeme/features/insights/presentation/model_transparency_screen.dart';
import 'package:fyp_foreseeme/features/insights/presentation/weekly_report_screen.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_override_screen.dart';

/// Shared page for Sprint-3/4 pushed routes — a consistent, reduced-motion-aware
/// fade-through transition (see [AppMotion.pageTransition]). Routes, paths and
/// redirects are unchanged; this only styles how a page animates in.
CustomTransitionPage<void> _motionPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.page,
    reverseTransitionDuration: AppMotion.page,
    transitionsBuilder: AppMotion.pageTransition,
    child: child,
  );
}

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
      GoRoute(
        path: '/profile-ready',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final city = extra is Map ? extra['city'] as String? : null;
          final conditions = extra is Map
              ? (extra['conditions'] as List?)?.cast<String>()
              : null;
          return _motionPage(
            state,
            ProfileReadyScreen(
              city: city ?? '',
              conditions: conditions ?? const [],
            ),
          );
        },
      ),
      GoRoute(
        path: '/risk-map',
        pageBuilder: (context, state) =>
            _motionPage(state, const RiskMapScreen()),
      ),
      GoRoute(
        path: '/risk-details',
        pageBuilder: (context, state) =>
            _motionPage(state, const RiskDetailsScreen()),
      ),
      GoRoute(
        path: '/compare',
        pageBuilder: (context, state) =>
            _motionPage(state, const ComparisonScreen()),
      ),
      GoRoute(
        path: '/nearby-hospitals',
        pageBuilder: (context, state) =>
            _motionPage(state, const NearbyHospitalsScreen()),
      ),
      GoRoute(
        path: '/notifications/permission',
        pageBuilder: (context, state) =>
            _motionPage(state, const NotificationPermissionScreen()),
      ),
      GoRoute(
        path: '/notifications/settings',
        pageBuilder: (context, state) =>
            _motionPage(state, const NotificationSettingsScreen()),
      ),
      GoRoute(
        path: '/alerts',
        pageBuilder: (context, state) =>
            _motionPage(state, const AlertInboxScreen()),
      ),
      GoRoute(
        path: '/health-insights',
        pageBuilder: (context, state) =>
            _motionPage(state, const HealthInsightsScreen()),
      ),
      GoRoute(
        path: '/model-transparency',
        pageBuilder: (context, state) =>
            _motionPage(state, const ModelTransparencyScreen()),
      ),
      GoRoute(
        path: '/weekly-report',
        pageBuilder: (context, state) =>
            _motionPage(state, const WeeklyReportScreen()),
      ),
      GoRoute(
        path: '/admin/risk-override',
        pageBuilder: (context, state) =>
            _motionPage(state, const AdminOverrideScreen()),
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
                builder: (context, state) => const ResourceCenterScreen(),
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
