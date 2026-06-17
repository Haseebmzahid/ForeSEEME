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
