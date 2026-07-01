# Architecture Document: ForeSeeMe

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter UI Layer                         │
│  (Screens, Widgets, State Notifiers)                            │
└─────────────────────────────────────────────────────────────────┘
                          ↕ (Riverpod)
┌─────────────────────────────────────────────────────────────────┐
│                    Domain Layer (Entities)                       │
│  (Models, Repositories Interfaces, Exceptions)                  │
└─────────────────────────────────────────────────────────────────┘
                          ↕ (Implementation)
┌─────────────────────────────────────────────────────────────────┐
│                      Data Layer                                 │
│  (Firebase Repositories, Local Storage)                         │
└─────────────────────────────────────────────────────────────────┘
                          ↕ (SDK)
┌─────────────────────────────────────────────────────────────────┐
│              External Services (Firebase)                       │
│  (Auth, Firestore, Cloud Functions)                             │
└─────────────────────────────────────────────────────────────────┘
```

## Folder Structure

```
lib/
├── main.dart                          # App bootstrap
├── core/                              # Shared infrastructure
│   ├── models/                        # (Currently empty - for future cross-feature models)
│   ├── repositories/                  # (Currently empty - for future shared repos)
│   ├── routes/
│   │   └── app_router.dart           # Go Router configuration + auth guards
│   ├── services/
│   │   └── local_notification_service.dart  # Notification scheduling
│   ├── theme/
│   │   └── app_theme.dart            # Design system, colors, dimensions
│   ├── utils/
│   │   └── either.dart               # Either<Left, Right> monad for error handling
│   └── widgets/                       # Reusable UI components
│       ├── app_button.dart
│       ├── app_text_field.dart
│       ├── empty_state_widget.dart
│       ├── section_header.dart
│       └── status_badge.dart
│
├── features/
│   ├── auth/                          # Authentication feature
│   │   ├── data/
│   │   │   └── repositories/
│   │   │       └── firebase_auth_repository.dart
│   │   ├── domain/
│   │   │   ├── exceptions/
│   │   │   │   └── auth_exception.dart
│   │   │   ├── models/
│   │   │   │   └── user_model.dart
│   │   │   └── repositories/
│   │   │       └── auth_repository.dart
│   │   └── presentation/
│   │       ├── auth_notifier.dart     # State management
│   │       ├── auth_providers.dart    # Riverpod providers
│   │       ├── auth_state.dart        # Auth state union types
│   │       ├── login_screen.dart
│   │       ├── register_screen.dart
│   │       ├── forgot_password_screen.dart
│   │       └── widgets/
│   │           ├── auth_text_field.dart
│   │           └── gradient_button.dart
│   │
│   ├── health_profile/                # Health profile feature
│   │   ├── data/
│   │   │   └── repositories/
│   │   │       └── firestore_health_profile_repository.dart
│   │   ├── domain/
│   │   │   ├── constants/
│   │   │   │   ├── cities_constants.dart
│   │   │   │   └── conditions_constants.dart
│   │   │   ├── exceptions/
│   │   │   │   └── health_profile_exception.dart
│   │   │   ├── models/
│   │   │   │   └── health_profile_model.dart
│   │   │   └── repositories/
│   │   │       └── health_profile_repository.dart
│   │   └── presentation/
│   │       ├── health_profile_notifier.dart
│   │       ├── health_profile_providers.dart
│   │       ├── health_profile_screen.dart
│   │       └── health_profile_state.dart
│   │
│   └── medication/                    # Medication management feature
│       ├── data/
│       │   └── repositories/
│       │       ├── firestore_medication_repository.dart
│       │       └── firestore_adherence_log_repository.dart
│       ├── domain/
│       │   ├── enums/
│       │   │   └── medication_enums.dart  # Type, Frequency, AdherenceStatus
│       │   ├── models/
│       │   │   ├── medication_model.dart
│       │   │   └── adherence_log_model.dart
│       │   └── repositories/
│       │       ├── medication_repository.dart
│       │       └── adherence_log_repository.dart
│       └── presentation/
│           ├── add_medication_screen.dart
│           ├── adherence_notifier.dart
│           ├── check_in_screen.dart    # DailyCheckInScreen + helper classes
│           ├── medication_notifier.dart
│           └── widgets/
│               ├── medication_card_widget.dart
│               ├── date_navigation_bar.dart
│               └── ... (other UI components)
```

## Data Flow Architecture

### Authentication Flow

```
User Input (LoginScreen)
    ↓
AuthNotifier.signIn()
    ↓
AuthRepository.signInWithEmail()
    ↓
FirebaseAuthRepository (Firebase Auth SDK)
    ↓
UserModel created
    ↓
authStateProvider (Stream<UserModel?>) emits
    ↓
Router evaluates redirect logic
    ↓
Navigate to /home or /login
```

### Medication Check-In Flow

```
User opens DailyCheckInScreen
    ↓
Riverpod watches:
  - medicationsStreamProvider (List<MedicationModel>)
  - adherenceLogsStreamProvider (List<AdherenceLogModel>) for selected date
    ↓
Build medication doses grouped by time (Morning/Afternoon/Evening)
    ↓
User taps "Taken" or "Skipped" on MedicationCardWidget
    ↓
AdherenceNotifier.updateStatus()
    ↓
Generate deterministic log ID: {medId}_{date}_{time}
    ↓
AdherenceLogRepository.logDose()
    ↓
FirestoreMedicationRepository.update() → Firestore
    ↓
Stream re-emits, UI updates (reactive)
```

## State Management Pattern (Riverpod)

### Provider Types Used

1. **Simple Providers** (`Provider`)
   - Singleton dependencies
   - Example: `authRepositoryProvider`, `medicationRepositoryProvider`

2. **Stream Providers** (`StreamProvider`)
   - Real-time data subscriptions
   - Example: `authStateProvider`, `medicationsStreamProvider`, `adherenceLogsStreamProvider`

3. **Notifier Providers** (`NotifierProvider`, `AsyncNotifierProvider`)
   - State mutations and side effects
   - Example: `authNotifierProvider`, `adherenceNotifierProvider`

4. **Family Providers** (`.family`)
   - Parametrized providers
   - Example: `adherenceLogsStreamProvider.family<List<AdherenceLogModel>, DateTime>`

### State Management Example

```dart
// 1. Define state class (sealed union type)
sealed class AuthState { }
class AuthStateAuthenticated extends AuthState { final UserModel user; }
class AuthStateError extends AuthState { final String message; }

// 2. Create notifier for mutations
class AuthNotifier extends Notifier<AuthState> {
  Future<void> signIn(String email, String password) async {
    state = AuthStateLoading();
    final result = await repository.signInWithEmail(...);
    state = result.fold(
      (error) => AuthStateError(error.message),
      (user) => AuthStateAuthenticated(user),
    );
  }
}

// 3. Use in widgets
ConsumerWidget {
  @override
  build(context, ref) {
    ref.listen(authStateProvider, (prev, next) {
      if (next is AuthStateError) ScaffoldMessenger.show(SnackBar(...));
    });
  }
}
```

## Error Handling Pattern

### Either Monad

All async operations return `Either<Exception, T>`:

```dart
Either<AuthException, UserModel> result = await repository.signInWithEmail(...);

result.fold(
  (error) => handleError(error.message),     // Left (error)
  (user) => handleSuccess(user),             // Right (success)
);
```

### Benefits
- Explicit error types (no exceptions thrown)
- Functional composition
- Type-safe error handling
- No null coalescing needed

## Routing Architecture

### Route Structure

| Path | Screen | Auth Required | Purpose |
|------|--------|---|---------|
| `/` | Redirect | N/A | Root → /login or /home |
| `/login` | LoginScreen | ❌ No | Email/password + Google sign-in |
| `/register` | RegisterScreen | ❌ No | Create new account |
| `/forgot-password` | ForgotPasswordScreen | ❌ No | Password reset |
| `/health-profile` | HealthProfileScreen | ✅ Yes | Setup (onboarding) or Edit (settings) |
| `/home` | HomeScreen (WIP) | ✅ Yes | Main dashboard |
| `/add-medication` | AddMedicationScreen (WIP) | ✅ Yes | Create medication |
| `/check-in` | DailyCheckInScreen (WIP) | ✅ Yes | Daily adherence check-in |

### Route Guards

```dart
// In AppRouter
redirect: (context, state) {
  final isAuth = authNotifier.value?.value != null;
  final isLoggingIn = state.matchedLocation in ['/login', '/register', '/forgot-password'];
  
  if (authState.isLoading) return null;  // Wait for auth resolution
  if (!isAuth && !isLoggingIn) return '/login';  // Unauth → login
  if (isAuth && isLoggingIn) return '/home';    // Auth → block auth screens
  return null;  // Allow navigation
}
```

## Database Schema

### Firestore Collections

```
firestore-root/
└── users/                           # Main user collection
    └── {uid}/                       # User document by Firebase UID
        ├── profile/                 # Health profile subcollection
        │   └── data/               # Single health profile document
        │       ├── city: string
        │       ├── chronicConditions: array<string>
        │       └── lastUpdated: timestamp (server)
        │
        ├── medications/            # Medications subcollection
        │   └── {medId}/            # Medication document
        │       ├── name: string
        │       ├── dosage: string
        │       ├── type: string (enum: "pill" | "syrup")
        │       ├── frequency: string (enum: "onceDaily" | "twiceDaily" | "thriceDaily")
        │       ├── reminderTimes: array<string>  # ["08:00", "20:00"]
        │       ├── isActive: boolean
        │       └── createdAt: timestamp (server)
        │
        └── adherence_logs/         # Adherence tracking subcollection
            └── {logId}/            # Adherence log document
                ├── medicationId: string (ref to medication)
                ├── date: string    # ISO 8601 "yyyy-MM-dd" (date-only, not timestamp)
                ├── status: string  # enum: "taken" | "skipped" | "pending"
                ├── confirmedAt: timestamp (user confirmation time, or null)
```

### Firestore Security Rules (Server-side)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Only users can access their own data
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth.uid == uid;
    }
  }
}
```

### Key Design Decisions

1. **Subcollections under user**
   - Isolation: users only access own data
   - Scalability: auto-partitioning by uid
   - Security: firestore rules can be simple

2. **Date stored as ISO 8601 string**
   - Enables efficient `where('date', isEqualTo, '2025-05-02')` queries
   - No composite indexes needed
   - Prevents timezone issues

3. **Server timestamps**
   - Consistency: server clock is authoritative
   - Prevents client clock skew
   - Automatic sync across devices

4. **Deterministic adherence log IDs**
   - Format: `{medId}_{yyyy-MM-dd}_{HHmm}`
   - Enables upsert semantics (create or overwrite)
   - Query by specific dose: `logId = 'med123_2025-05-02_0800'`

## Component Hierarchy

### Screen Composition Example: DailyCheckInScreen

```
DailyCheckInScreen (ConsumerStatefulWidget)
├── AppBar
│   └── DateNavigationBar
│       └── Row of date chips (scrollable)
│
├── Body: Column
│   └── ListView
│       ├── GroupedMedicationList (morning)
│       │   └── MedicationCardWidget (per dose)
│       │       ├── MedicationName + Dosage
│       │       ├── ReminderTime
│       │       ├── StatusBadge
│       │       └── ActionButtons (Taken/Skipped)
│       │
│       ├── GroupedMedicationList (afternoon)
│       └── GroupedMedicationList (evening)
│
└── EmptyStateWidget (if no medications)
```

## Design Patterns Used

### 1. Clean Architecture
- Domain layer: pure business logic, no framework dependencies
- Data layer: Firebase implementation
- Presentation layer: Flutter widgets, state management

### 2. Sealed Classes (Union Types)
```dart
sealed class AuthState { }
class AuthStateAuthenticated extends AuthState { }
class AuthStateError extends AuthState { }
```

### 3. Repository Pattern
- Abstract interface in domain
- Concrete implementation in data
- Dependency injection via Riverpod

### 4. Stream-based Reactivity
- Watch streams from Firestore
- Auto-rebuild on data change
- No manual state synchronization

### 5. Immutable Models
- All fields `final`
- `copyWith()` for modifications
- `.toJson()` / `.fromJson()` for serialization

## Scalability Considerations

### Current Bottlenecks
1. **No pagination**: All medications loaded at once
2. **No offline support**: Sync-only model
3. **UI performance**: Re-renders entire medication list

### Future Improvements
1. **Pagination**: Implement `PagedMedicationRepository`
2. **Offline-first**: Firebase Cloud Sync support
3. **Caching**: Local SQLite for read cache
4. **Lazy loading**: Virtual lists for large medication counts

## Key Architectural Principles Maintained

| Principle | Implementation | Benefit |
|-----------|---|---|
| Single Responsibility | One notifier per feature | Easy to test/modify |
| Dependency Injection | Riverpod providers | Testability, flexibility |
| Immutability | Final fields, copyWith() | Predictability, debugging |
| Type Safety | Null-safe Dart | Fewer runtime errors |
| Error as Values | Either<E, T> monad | Explicit error handling |
| Reactive Data | Stream-based architecture | Real-time UI updates |

---

## Sprint 3 — Risk Consumption & Visualization Layer

Sprint 3 connects the Flutter client to the Sprint 2 `riskEstimates` feed and adds
the Resource Center and notification *prep*. All additive and feature-first; the
Sprint 2 ML pipeline, FastAPI service, and prediction contract are **untouched**.
Flutter reads risk **only** from Firestore `riskEstimates` and never calls
`/predict` (ADR-001).

### New / extended features

```
lib/features/
  risk/         data: getLatestRiskForCity, getRiskHistory, getLatestRiskAllCities
                presentation: risk_provider (currentCityRisk / riskTrend / allCitiesRisk),
                widgets: risk_card, trend_badge, risk_legend, risk_visuals;
                screens/risk_map_screen
  resources/    data: static_resource_repository, google_places_repository (cached);
                services: geolocator_location_service;
                presentation: resource_center_screen, nearby_hospitals_screen,
                widgets: emergency_card, resource_article_card, article_detail_sheet,
                         hospital_list, nearby_hospitals_entry
  alerts/       data: firestore_fcm_token_repository, firebase_push_messaging_service,
                      firestore_notification_preferences_repository;
                presentation: alerts_controller, notification_preferences_controller,
                              notification_permission_screen, notification_settings_screen
core/
  services/launcher_service.dart        # tel: dial + external URLs (url_launcher)
  theme/app_design_v2.dart              # v2 "Liquid Glass" design tokens (Sprint 3 surfaces)
```

### Data flow — risk view

```
Sprint 2 batch job ──(service-account write)──► Firestore: riskEstimates/{city}_{YYYY-MM-DD}
                                                       │ (authenticated read, ADR-001)
                                                       ▼
FirestoreRiskRepository
  getLatestRiskForCity(city)   ── latestRiskForCityProvider ─┐
  getRiskHistory(city, weeks)  ── riskHistoryProvider ──► riskTrendProvider (computeTrend)
  getLatestRiskAllCities(...)  ── allCitiesRiskProvider      │
                                                              ▼
userCityProvider (auth + health profile) ──► currentCityRiskProvider ──► RiskCard (dashboard)
                                                                          RiskMapScreen (zones)
```

Each read query (`where city == … orderBy generatedAt`) uses the composite index
`(city ASC, generatedAt DESC)` tracked in `firestore.indexes.json` and deployed to
the project.

### State handling (every risk surface)

`currentCityRiskProvider` maps to four UI states: **loading** (skeleton), **data**,
**empty** (`AsyncData(null)` → "no risk data yet for {city}"), **error/offline**
(retry). Offline reads are served from Firestore's local cache; an estimate older
than `kRiskStaleAfter` (9 days) shows a **"this estimate may be out of date"**
staleness hint. Accessibility: every risk signal pairs colour with a **label + a
distinct icon/glyph** (✓ ! △ ? and trend arrows / dash) — never colour alone.

### Integrations (client-side, restricted keys)

| Integration | Use | Key handling | Cost guard |
|---|---|---|---|
| Google Maps SDK (Android) | National risk map (colored zones) | `android/local.properties` → Gradle `manifestPlaceholders` (git-ignored) | n/a |
| Google Places (New) REST | Nearby hospitals | `--dart-define MAPS_API_KEY` from git-ignored `dart_defines.json` | TTL cache (15 min) + per-session live-call quota guard |
| `geolocator` | Search origin | runtime permission; **falls back to city centroid** when denied | n/a |
| `firebase_messaging` | FCM token capture (no dispatch) | n/a | n/a |
| `url_launcher` | Emergency `tel:` dial, source links, directions | n/a | n/a |

> Both keys must be **platform-restricted + API-restricted** in Cloud Console
> before release (Android app + SHA-1; Places New for the REST key).

### Firestore (additive)

```
riskEstimates/{city}_{YYYY-MM-DD}   # Sprint 2 writes; Sprint 3 reads (authenticated)
users/{uid}
  ├── fcmToken: string                       # Sprint 3 P7 (self-write)
  ├── fcmTokenUpdatedAt: timestamp
  └── notificationPreferences: map           # Sprint 3 P8 — see docs/notification-preferences-schema.md
```

**Rules** (deployed + verified active): authenticated read of `riskEstimates`,
no client writes; `users/{uid}` (+ subtree) owner-only read/write
(`request.auth.uid == uid`) — self-write allowed, cross-user denied; covers
`fcmToken`, `notificationPreferences`, and the existing profile / medication /
adherence subcollections. No new collections.

### Sprint 4 hand-off

FCM tokens + `notificationPreferences` are **captured and stored, never consumed**
in Sprint 3. Sprint 4's dispatch engine reads them (severity toggle on AND
condition enabled → send to `fcmToken`, with a 24h throttle + audit log).

---

## Sprint 4 — Proactive alerting & insights (delivered)

Sprint 4 turns the platform from predictive to **proactive**, additively over the
frozen Sprint 1–3 foundation. Nothing in the risk/ML pipeline, prediction
contract, or existing feature internals changed.

### Dispatch engine (backend, scheduled)

A new scheduled Cloud Run job `backend/app/jobs/dispatch_alerts.py` (sibling of
`compute_risk`, same firebase-admin service account) turns a **rising city-risk
transition** into a personalized, consented, throttled FCM alert. **Flutter never
dispatches and never calls `/predict`** (ADR-001). Supporting pure modules:
`alerting/targeting.py` (transition × vulnerability × consent predicate),
`alerting/throttle.py` (24h window + per-estimate idempotency), `alerting/
messaging.py` (firebase-admin send + token-invalid handling), `alerting/
recommendation_lookup.py` (deterministic cited advisory).

```
Cloud Scheduler → dispatch_alerts
  read riskEstimates (latest+prev) + healthProfiles + users(token,prefs) + alertDispatchLog
  → transition? → vulnerable ∧ consented? → idempotent ∧ not throttled?
  → send FCM (+ cited recommendation) → write alertDispatchLog + userAlerts
  (token invalid → prune users.fcmToken)
```

Safeguards (fatigue + cost): transition-triggering, 24h per-(user,category)
throttle, per-estimate idempotency key `{uid}__{riskEstimateId}__{category}`, and
token pruning. Proven end-to-end in `backend/tests/test_e2e_dispatch.py`
(repeated runs → no spam/duplicates) — see `docs/alert_fatigue_cost_audit.md`.

### New Firestore collections (additive; rules tested)

```
alertDispatchLog/{logId}            # ops audit + throttle/idempotency ledger
                                    #   service-account ONLY — allow read,write: if false
userAlerts/{uid}/items/{alertId}    # in-app inbox — engine writes (Admin SDK)
  ├── title, body, category, city, riskLevel, disease
  ├── recommendation: {id, text, source, sourceUrl}   # cited, never generated
  ├── deepLink, riskEstimateId, createdAt
  └── read, readAt                  #   owner read; owner may set read/readAt only
```

Rules are additive (existing rules untouched) and verified on the emulator
(`test_rules/firestore_rules.test.mjs`: owner read, cross-user denied, scoped
mark-read, no create/delete). Contract frozen in `docs/alert_dispatch_design.md`.

### Flutter (additive, feature-first)

- **`alerts`** (extended): FCM message handlers (fg/bg/terminated) + deep-link
  router (P4), user-scoped **inbox** with unread badge + mark-read (P5), and an
  `AlertAnalytics` deep-link engagement seam (P9, `logAlertOpened(route,source)`).
- **`insights`** (new): a deterministic **cited recommendation** engine mirroring
  the backend lookup field-for-field (P6), **supportive read-only adherence
  intelligence** over existing logs (P7), and a non-diagnostic **Health Insights**
  summary composing risk + recommendation + adherence with a medical disclaimer
  (P8). Recommendations are looked up, never generated (Rule 11); insights carry
  no failure scoring.

### APIs / packages

FCM send is backend-only via firebase-admin; **no client API changes** and no new
Flutter packages. Deep-link opens are recorded through the in-app analytics seam
(default: debug sink; swappable in production via `alertAnalyticsProvider`).

> **Screenshots** of the new surfaces (alert inbox, recommendation card, adherence
> insights, health-insights summary) are captured manually on device and attached
> to the Sprint 4 report — the automated suite covers behaviour, and device
> capture (like the Sprint 3 map render) remains a manual step.

