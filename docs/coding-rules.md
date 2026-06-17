# Coding Rules & Conventions: ForeSeeMe

## File Organization

### Feature Folder Structure

```
features/
└── feature_name/
    ├── data/
    │   ├── models/                  # (Optional, if not using domain models directly)
    │   └── repositories/
    │       └── firestore_feature_repository.dart
    ├── domain/
    │   ├── enums/
    │   │   └── feature_enums.dart   # (If needed)
    │   ├── exceptions/
    │   │   └── feature_exception.dart
    │   ├── models/
    │   │   └── feature_model.dart
    │   └── repositories/
    │       └── feature_repository.dart
    └── presentation/
        ├── feature_screen.dart      # Main screen
        ├── feature_notifier.dart    # State mutations
        ├── feature_providers.dart   # Riverpod setup
        ├── feature_state.dart       # State classes (if using sealed)
        └── widgets/
            ├── component_widget.dart
            └── another_widget.dart
```

### Core Layer

```
core/
├── models/                          # Cross-feature models (if any)
├── repositories/                    # Shared repository contracts
├── routes/
│   └── app_router.dart             # Navigation
├── services/
│   └── local_notification_service.dart
├── theme/
│   └── app_theme.dart              # Design system
├── utils/
│   ├── either.dart                 # Error handling monad
│   └── (other utilities)
└── widgets/                         # Reusable UI components
    ├── app_button.dart
    ├── app_text_field.dart
    ├── empty_state_widget.dart
    ├── section_header.dart
    └── status_badge.dart
```

## Naming Conventions

### Files

```dart
// Dart convention: snake_case for files
feature_model.dart          // ✓ Correct
feature_screen.dart         // ✓ Correct
FeatureModel.dart           // ✗ Wrong (use snake_case)
```

### Classes & Types

```dart
// PascalCase for class names
class UserModel { }         // ✓ Model
class LoginScreen { }       // ✓ Screen
class AuthRepository { }    // ✓ Interface/Abstract
class FirebaseAuthRepository { } // ✓ Implementation
class AuthException { }     // ✓ Exception
class AuthState { }         // ✓ State class
```

### Enums

```dart
// PascalCase for enum name, lowercase for values
enum MedicationType {
  pill,                     // ✓ lowercase
  syrup,
}

// Extensions: PascalCase + X suffix
extension MedicationTypeX on MedicationType { }
```

### Variables & Constants

```dart
// camelCase for variables
final userData = fetchUser();  // ✓
var medicationList = [];       // ✓

// SCREAMING_SNAKE_CASE for constants
const int MAX_MEDICATIONS = 100;  // ✓
const String APP_NAME = 'ForeSeeMe'; // ✓

// Special: kCamelCase for static const (Flutter convention)
static const kMedicationLimit = 100;  // ✓
```

### Functions/Methods

```dart
// camelCase for function names
Future<void> fetchUserData() { }     // ✓
void updateMedicationStatus() { }    // ✓

// Private functions: _camelCase
void _internalHelper() { }           // ✓
```

### Providers (Riverpod)

```dart
// Suffix: Provider
final userProvider = Provider<User>(...);

// Suffix: NotifierProvider
final userNotifierProvider = NotifierProvider<UserNotifier, User>(...);

// Suffix: StreamProvider
final userStreamProvider = StreamProvider<User>(...);

// Suffix: Family (for parameterized)
final logsByDateProvider = StreamProvider.family<List<Log>, DateTime>(...);
```

## Dart/Flutter Best Practices

### Imports

```dart
// 1. Dart imports first
import 'dart:async';
import 'dart:convert';

// 2. Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 3. Package imports
import 'package:firebase_auth/firebase_auth.dart';

// 4. Relative imports (for local files)
import '../models/user_model.dart';
import 'auth_providers.dart';
```

### Null Safety

```dart
// Always use null-safe Dart
String name = '';              // ✓ Non-nullable
String? nickname;              // ✓ Nullable (with ?)

// Check before use
if (nickname != null) {
  print(nickname);             // ✓ Safe
}

// Use ?? operator
String display = nickname ?? 'Anonymous';  // ✓

// Use ?. for optional chaining
user?.profile?.update();       // ✓ Null-safe

// Avoid ! (force unwrap) unless absolutely certain
user!.name;                    // ✗ Avoid - can throw
```

### Constants vs Final

```dart
// Use const for compile-time constants
const int MAX = 100;           // ✓
const String TITLE = 'App';

// Use final for runtime constants
final int count = getData();   // ✓ (not known at compile time)
final now = DateTime.now();

// Never use var for public APIs
var user = User();             // ✗ In public code
User user = User();            // ✓ In public code
```

## Component Architecture

### Widget Naming

```dart
// Screens: {Feature}Screen
class LoginScreen extends ConsumerWidget { }           // ✓
class DailyCheckInScreen extends ConsumerStatefulWidget { } // ✓

// Components: {Purpose}Widget (or descriptive)
class MedicationCardWidget extends StatelessWidget { } // ✓
class DateNavigationBar extends StatelessWidget { }    // ✓

// (Avoid: Widget suffix optional in local widgets)
class UserTile extends StatelessWidget { }             // ✓ Also acceptable
```

### ConsumerWidget vs ConsumerStatefulWidget

```dart
// Use ConsumerWidget when only watching providers (no local state)
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(provider);
    return Text(data);
  }
}

// Use ConsumerStatefulWidget when you need local state (form, scrolling, etc.)
class MyForm extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyForm> createState() => _MyFormState();
}

class _MyFormState extends ConsumerState<MyForm> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Can use both local state and watch providers
  }
}
```

### ref.watch vs ref.read

```dart
// watch: Reactive, rebuilds when provider changes
final data = ref.watch(provider);   // ✓ Use in build()

// read: One-time access, no rebuild
ref.read(provider.notifier).doSomething();  // ✓ Use in callbacks

// WRONG: Don't use read() inside build()
@override
Widget build(BuildContext context, WidgetRef ref) {
  final data = ref.read(provider);  // ✗ Won't rebuild on change
}
```

## Domain/Data/Presentation Layers

### Domain Layer (Business Logic)

```dart
// Abstract interfaces (no implementation details)
abstract class AuthRepository {
  Future<Either<AuthException, UserModel>> signInWithEmail({
    required String email,
    required String password,
  });
}

// Pure models (immutable, no side effects)
class UserModel {
  final String uid;
  final String email;
  const UserModel({required this.uid, required this.email});
}

// Domain exceptions
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
}
```

### Data Layer (Implementation)

```dart
// Concrete implementation
class FirebaseAuthRepository implements AuthRepository {
  @override
  Future<Either<AuthException, UserModel>> signInWithEmail({...}) async {
    try {
      // Firebase logic here
      return Right(userModel);
    } on FirebaseAuthException catch (e) {
      return Left(AuthException(e.message ?? 'Sign in failed'));
    }
  }
}
```

### Presentation Layer (UI & State)

```dart
// State classes
sealed class AuthState { }
class AuthStateUnauthenticated extends AuthState { }
class AuthStateAuthenticated extends AuthState {
  final UserModel user;
  AuthStateAuthenticated(this.user);
}

// Notifiers (mutations)
class AuthNotifier extends Notifier<AuthState> {
  Future<void> signIn(String email, String password) async {
    final result = await repository.signInWithEmail(...);
    state = result.fold(
      (error) => AuthStateError(error.message),
      (user) => AuthStateAuthenticated(user),
    );
  }
}

// Providers
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(...);
```

## Error Handling

### Either Pattern (No Exceptions)

```dart
// Don't throw exceptions
Future<User> getUser() async {
  throw Exception('User not found');  // ✗
}

// Instead, return Either
Future<Either<UserException, User>> getUser() async {
  return Right(user);  // Success
  return Left(UserException('Not found'));  // Error
}

// Usage
final result = await getUser();
result.fold(
  (error) => handleError(error),
  (user) => handleSuccess(user),
);
```

### Try-Catch Only for Platform Exceptions

```dart
// Try-catch at data layer (Firebase, platform APIs)
try {
  await _firebaseAuth.signInWithEmailAndPassword(...);
} on FirebaseAuthException catch (e) {
  return Left(AuthException(e.message ?? 'Auth failed'));
}

// DON'T try-catch in presentation layer
@override
build() {
  try {
    return MyWidget();  // ✗ Don't catch widget building
  } catch (e) {
    return ErrorWidget();
  }
}
```

## Code Style

### Formatting

```dart
// Use official Dart formatter
flutter format .

// Line length: 80 characters recommended
// Break long lines at logical points

// Long parameter lists: one per line
MyFunction(
  parameter1: value1,
  parameter2: value2,
  parameter3: value3,
)

// Avoid deeply nested code
if (condition1) {
  if (condition2) {
    if (condition3) {  // ✗ Too deep, refactor
      doSomething();
    }
  }
}
```

### Comments

```dart
// Use comments sparingly - code should be self-explanatory

/// Use doc comments for public APIs (///)
/// Explains purpose, parameters, returns
class UserRepository {
  /// Fetches user by ID from Firestore
  /// 
  /// Throws [UserException] if user not found
  /// Returns [Either] to avoid exceptions
  Future<Either<UserException, User>> getUser(String id) async { }
}

// Avoid obvious comments
int count = 0;  // Initialize count to 0  ✗ Obvious

// Use comments for why, not what
// Fetch old logs first to maintain chronological order
List<Log> logs = await repo.getOldestLogs();  ✓
```

## Testing Considerations

### Testability Principles

1. **Dependency Injection**: Pass dependencies via constructors
   ```dart
   class AuthRepository {
     AuthRepository(this.firebaseAuth);  // ✓ Testable
   }
   ```

2. **Avoid Global Singletons**: Use Riverpod for DI
   ```dart
   // ✗ Hard to test
   FirebaseAuth.instance.signIn();

   // ✓ Easy to mock
   repository.signIn();  // Repository injected via Riverpod
   ```

3. **Sealed Classes**: Enable exhaustive type checking
   ```dart
   sealed class AuthState { }  // Forces all subtypes handled
   ```

## Performance Optimization

### Provider Optimization

```dart
// Watch only needed fields
final email = ref.watch(user.select((u) => u.email));  // ✓ Fine-grained

// Don't rebuild entire list when one item changes
List<Item> items = ref.watch(itemsProvider);  // ✗ Rebuilds all items
final items = ref.watch(itemsProvider.select((i) => i));  // ✓ Still rebuilds list

// Use AsyncNotifier for async operations
final userAsync = ref.watch(userAsyncProvider);  // ✓ Auto-loading state
```

### List Performance

```dart
// Use PagedListView for large lists (future)
// Use .addAutomaticKeepAlives: true for scroll position

ListView(
  children: items.map((item) => ItemWidget(item)).toList(),
)

// Better: Use ListView.builder for large lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
)
```

## Documentation Standards

### README Sections

Each feature should have clear documentation:

```markdown
# Feature Name

## Overview
What does this feature do?

## Key Components
- Model: What data does it store?
- Repository: How is data persisted?
- Notifier: What mutations are available?

## Usage Example
```dart
// Show how to use the feature
```

## Common Gotchas
- Known issues
- Performance considerations
```

## Anti-Patterns to Avoid

### ❌ Anti-Pattern 1: God Classes

```dart
// ✗ Too many responsibilities
class UserManager {
  void createUser() { }
  void updateProfile() { }
  void deleteUser() { }
  void sendEmail() { }       // ✗ Unrelated responsibility
  void uploadPhoto() { }     // ✗ Unrelated
}

// ✓ Split into focused classes
class UserRepository { }    // User data only
class EmailService { }      // Email logic
class StorageService { }    // File uploads
```

### ❌ Anti-Pattern 2: Tight Coupling

```dart
// ✗ Hard to test
class LoginScreen extends StatelessWidget {
  @override
  build() {
    final user = FirebaseAuth.instance.currentUser;  // ✗ Direct dependency
  }
}

// ✓ Inject dependency
class LoginScreen extends ConsumerWidget {
  @override
  build(context, ref) {
    final user = ref.watch(authStateProvider);  // ✓ Injected
  }
}
```

### ❌ Anti-Pattern 3: Silent Failures

```dart
// ✗ Hides errors
Future<User> getUser() async {
  try {
    return await firestore.getUser();
  } catch (e) {
    return null;  // ✗ Silent failure
  }
}

// ✓ Explicit error handling
Future<Either<UserException, User>> getUser() async {
  try {
    return Right(await firestore.getUser());
  } on FirebaseException catch (e) {
    return Left(UserException(e.message));
  }
}
```

## Code Review Checklist

- [ ] Follows file organization structure?
- [ ] Uses correct naming conventions?
- [ ] Has immutable models (all final fields)?
- [ ] Uses Either for error handling, not exceptions?
- [ ] Separates domain/data/presentation?
- [ ] Avoids magic numbers (use constants)?
- [ ] No unnecessary null checks (null-safe Dart)?
- [ ] Proper use of ref.watch vs ref.read?
- [ ] Tests are included?
- [ ] Documentation updated?

