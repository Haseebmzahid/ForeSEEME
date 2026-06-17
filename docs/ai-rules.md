# AI Rules: Strict Instructions for All AI Coding Agents

**These rules are MANDATORY for all AI agents (Copilot, Codex, Cursor, Claude, etc.) working on this project.**

## Rule 1: No Code Duplication

**❌ DO NOT duplicate code**

### Violation Examples

```dart
// ✗ VIOLATION: Duplicated button styling
RaisedButton(
  color: Color(0xFF006D77),
  child: Text('Save'),
  onPressed: () => {},
)

// In another file...
RaisedButton(
  color: Color(0xFF006D77),
  child: Text('Submit'),
  onPressed: () => {},
)

// ✓ CORRECT: Use existing AppButton widget
AppButton(
  label: 'Save',
  onPressed: () => {},
)
```

### Before Writing Code

1. **Search for existing components**: `lib/core/widgets/`
2. **Search for existing utilities**: `lib/core/utils/`
3. **Search across feature folders** for similar patterns
4. **Reuse existing services**: `LocalNotificationService`, repositories

### Reusable Assets

| Asset | Location | Purpose |
|-------|----------|---------|
| AppButton | `core/widgets/app_button.dart` | Primary CTA |
| AppTextField | `core/widgets/app_text_field.dart` | Input fields |
| EmptyStateWidget | `core/widgets/empty_state_widget.dart` | No data states |
| SectionHeader | `core/widgets/section_header.dart` | Section titles |
| StatusBadge | `core/widgets/status_badge.dart` | Status indicators |
| Either | `core/utils/either.dart` | Error handling monad |
| AppColors | `core/theme/app_theme.dart` | Design tokens |
| LocalNotificationService | `core/services/local_notification_service.dart` | Notifications |

## Rule 2: Reuse Existing Services & Repositories

**❌ DO NOT create new services that duplicate existing ones**

### Existing Services

| Service | Location | Use Case |
|---------|----------|----------|
| FirebaseAuthRepository | `auth/data/repositories/` | All auth operations |
| FirestoreHealthProfileRepository | `health_profile/data/repositories/` | Health profile CRUD |
| FirestoreMedicationRepository | `medication/data/repositories/` | Medication CRUD |
| FirestoreAdherenceLogRepository | `medication/data/repositories/` | Adherence tracking |
| LocalNotificationService | `core/services/` | All notifications |

### Pattern

```dart
// ✗ DO NOT create MedicationService when repository exists
class MedicationService {
  Future<void> add(Medication med) => repository.addMedication(med);
}

// ✓ USE existing repository directly
final repository = ref.watch(medicationRepositoryProvider);
await repository.addMedication(med);
```

## Rule 3: Maintain Architecture Consistency

**❌ DO NOT break the domain/data/presentation structure**

### Required Structure per Feature

```
feature/
├── data/
│   └── repositories/
│       └── concrete_implementation.dart   ✓ Must exist
├── domain/
│   ├── models/
│   │   └── feature_model.dart            ✓ Must exist
│   ├── repositories/
│   │   └── abstract_interface.dart       ✓ Must exist
│   └── exceptions/
│       └── feature_exception.dart        ✓ Must exist
└── presentation/
    ├── feature_screen.dart               ✓ Must exist
    ├── feature_notifier.dart             ✓ Must exist
    ├── feature_providers.dart            ✓ Must exist
    └── widgets/
        └── component.dart                ✓ Must exist
```

### Violation Examples

```dart
// ✗ VIOLATION: Business logic in presentation
class MedicationScreen extends ConsumerWidget {
  @override
  build() {
    // ✗ Should be in notifier
    final result = await firestore.addMedication();
  }
}

// ✗ VIOLATION: Repository not abstracted
class FirebaseMedicationRepository implements MedicationRepository {
  // But used directly without interface
  repository.getMedications();  // Should inject interface
}

// ✓ CORRECT: Follow 3-layer pattern
// domain/ defines interface
abstract class MedicationRepository { }

// data/ implements it
class FirestoreMedicationRepository implements MedicationRepository { }

// presentation/ uses abstraction via Riverpod
final repo = ref.watch(medicationRepositoryProvider);
```

## Rule 4: Avoid Unnecessary Abstractions

**❌ DO NOT add abstraction where it's not needed**

### Good Abstractions

```dart
// ✓ Abstracts Firestore implementation - testable, swappable
abstract class MedicationRepository {
  Stream<List<MedicationModel>> getMedications(String uid);
}

// ✓ Abstracts Firebase Auth implementation
abstract class AuthRepository {
  Future<Either<AuthException, UserModel>> signInWithEmail(...);
}
```

### Bad Abstractions

```dart
// ✗ Unnecessary - used in only one place
abstract class MedicationValidator {
  bool validate(MedicationModel med);
}
class FirebaseMedicationValidator implements MedicationValidator { }

// ✓ JUST USE: Helper function or extension
bool isValidMedication(MedicationModel med) => med.name.isNotEmpty;

// OR: Add to model directly
extension MedicationValidation on MedicationModel {
  bool get isValid => name.isNotEmpty;
}
```

## Rule 5: Keep Files Modular

**❌ DO NOT create files >300 lines**

### Target File Sizes

| Type | Target Size | Max Size |
|------|-----------|----------|
| Model class | 100-150 lines | 200 lines |
| Repository | 100-200 lines | 300 lines |
| Screen widget | 200-300 lines | 400 lines |
| Notifier | 100-150 lines | 250 lines |
| Utility/helper | 50-100 lines | 150 lines |

### If File Gets Too Large: Refactor

```dart
// ✗ File too large (400+ lines)
class DailyCheckInScreen extends ConsumerStatefulWidget {
  // Screen code
  // Helper methods
  // Business logic
  // Filtering logic
  // Grouping logic
}

// ✓ Extract to separate widgets
class DailyCheckInScreen extends ConsumerStatefulWidget { }  // ~150 lines
class _GroupedMedicationList extends StatelessWidget { }     // ~100 lines
class _MedicationCard extends StatelessWidget { }            // ~80 lines
class _DateNavigationBar extends StatelessWidget { }         // ~100 lines
```

## Rule 6: Follow Existing Naming Conventions

**❌ DO NOT invent new naming patterns**

### Strict Naming Rules

| Type | Pattern | Example |
|------|---------|---------|
| Files | snake_case | `user_model.dart` |
| Classes | PascalCase | `UserModel`, `LoginScreen` |
| Screens | `{Feature}Screen` | `LoginScreen`, `DailyCheckInScreen` |
| Widgets | `{Purpose}Widget` or descriptive | `MedicationCardWidget`, `DateNavigationBar` |
| Notifiers | `{Feature}Notifier` | `AuthNotifier`, `AdherenceNotifier` |
| Providers | `{feature}{Type}Provider` | `authRepositoryProvider`, `authNotifierProvider` |
| Enums | PascalCase | `MedicationType`, `AdherenceStatus` |
| Exceptions | `{Feature}Exception` | `AuthException`, `HealthProfileException` |
| Variables | camelCase | `medicationList`, `selectedDate` |
| Constants | kCamelCase (Flutter) | `kMaxMedications` |

### Before Creating New File: Check Naming

- [ ] Does filename match `snake_case`?
- [ ] Does class name match existing convention?
- [ ] Does provider name follow `{feature}{Type}Provider`?

## Rule 7: Always Check for Existing Utilities

**❌ DO NOT write new utility code without checking reusable utilities first**

### Common Utilities Location

```
lib/core/utils/
├── either.dart                # Either monad - USE THIS FOR ERROR HANDLING
└── (other utilities)
```

### Utility Checklist

Before writing utility function, check:
- [ ] Exists in `core/utils/`?
- [ ] Exists as extension method on existing type?
- [ ] Is it already in another feature?
- [ ] Can it be replaced by Dart standard library?

### Examples

```dart
// ✗ DO NOT write custom Either (already exists)
class Result<T> { }  // ✗ Don't create this

// ✓ USE existing
import 'core/utils/either.dart';
Either<Exception, T> result = ...;

// ✗ DO NOT format date manually
String format(DateTime d) => "${d.year}-${d.month}...";

// ✓ USE Dart built-in
d.toIso8601String()
"${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}"

// ✗ DO NOT write case insensitive string compare
bool equals(String a, String b) => a.toLowerCase() == b.toLowerCase();

// ✓ USE String methods
a.toLowerCase() == b.toLowerCase()
```

## Rule 8: Preserve Folder Structure

**❌ DO NOT move or reorganize folders without architectural justification**

### Current Folder Structure is FIXED

```
lib/
├── core/          ✓ FROZEN - Do not reorganize
├── features/      ✓ FROZEN structure
│   ├── auth/      ✓ Follow domain/data/presentation
│   ├── health_profile/
│   └── medication/
└── main.dart      ✓ FIXED entry point
```

### Allowed Actions

✓ Add new files within existing folders
✓ Create new features following existing structure
✓ Add new models to `features/{feature}/domain/models/`

### NOT Allowed

❌ Move feature out of `features/` folder
❌ Rename `domain`, `data`, `presentation` folders
❌ Create new top-level folders (like `services/` at root)
❌ Flatten layer structure

## Rule 9: Follow Error Handling Pattern

**❌ DO NOT throw exceptions from repositories**

### Correct Error Handling

```dart
// ✓ REQUIRED: Return Either with explicit error type
Future<Either<AuthException, UserModel>> signInWithEmail(...) async {
  try {
    final result = await firebase.signInWithEmailAndPassword(...);
    return Right(UserModel.fromFirebaseUser(result.user!));
  } on FirebaseAuthException catch (e) {
    return Left(AuthException(e.message ?? 'Sign in failed', e.code));
  }
}

// ✗ WRONG: Throw exceptions
Future<UserModel> signInWithEmail(...) async {
  try {
    return UserModel.fromFirebaseUser(...);
  } catch (e) {
    throw AuthException(e.toString());  // ✗ Throws
  }
}
```

### In Presentation Layer

```dart
// ✓ Fold the Either
result.fold(
  (error) => AuthStateError(error.message),     // Handle left
  (user) => AuthStateAuthenticated(user),       // Handle right
);
```

## Rule 10: State Management Pattern (Riverpod)

**❌ DO NOT bypass Riverpod or use global singletons**

### Correct Riverpod Usage

```dart
// ✓ Repositories as providers
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

// ✓ Streams as providers
final medicationsStreamProvider = StreamProvider<List<MedicationModel>>((ref) {
  final repo = ref.watch(medicationRepositoryProvider);
  return repo.getMedications(uid);
});

// ✓ Notifiers as providers
final adherenceNotifierProvider = AsyncNotifierProvider<AdherenceNotifier, void>(
  () => AdherenceNotifier(),
);

// ✓ Use in widgets
@override
build(BuildContext context, WidgetRef ref) {
  final data = ref.watch(provider);
  ref.listen(provider, (prev, next) { });
  ref.read(provider.notifier).doAction();
}
```

### NOT Allowed

```dart
// ✗ Global singleton
class FirebaseAuthService {
  static final _instance = FirebaseAuthService._();
  factory FirebaseAuthService() => _instance;
}

// ✗ Direct Firebase access
import 'package:firebase_auth/firebase_auth.dart' as fb;
final user = fb.FirebaseAuth.instance.currentUser;  // ✗

// ✓ USE Riverpod provider
final user = ref.watch(authStateProvider);
```

## Rule 11: Immutable Models

**❌ DO NOT create mutable models**

### Required Pattern

```dart
// ✓ REQUIRED: Immutable with final fields
class MedicationModel {
  final String id;
  final String name;
  final String dosage;

  const MedicationModel({
    required this.id,
    required this.name,
    required this.dosage,
  });

  // ✓ REQUIRED: copyWith for modifications
  MedicationModel copyWith({
    String? id,
    String? name,
    String? dosage,
  }) {
    return MedicationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
    );
  }

  // ✓ REQUIRED: toJson() and fromJson()
  Map<String, dynamic> toJson() => { ... };
  factory MedicationModel.fromJson(Map<String, dynamic> json) => ...;
}

// ✗ WRONG: Mutable model
class MedicationModel {
  String id;           // ✗ Not final
  String name;
  
  void updateName(String newName) {  // ✗ Mutation method
    name = newName;
  }
}
```

## Rule 12: Sealed Classes for State

**❌ DO NOT use enums or base classes for multi-state types**

### Correct Union Types

```dart
// ✓ REQUIRED: Sealed class for state unions
sealed class AuthState {}
class AuthStateUnauthenticated extends AuthState {}
class AuthStateAuthenticated extends AuthState {
  final UserModel user;
  AuthStateAuthenticated(this.user);
}
class AuthStateError extends AuthState {
  final String message;
  AuthStateError(this.message);
}

// Usage: switch exhaustiveness guaranteed
switch (state) {
  case AuthStateUnauthenticated _ => print('Not logged in');
  case AuthStateAuthenticated(:final user) => print('User: ${user.email}');
  case AuthStateError(:final message) => print('Error: $message');
}
```

## Rule 13: Documentation

**❌ DO NOT commit code without basic documentation**

### Required Documentation

| Component | Requirement |
|-----------|------------|
| Public functions | Doc comment (///) required |
| Complex business logic | Inline comments required |
| Public classes | Class doc comment required |
| Repository methods | Doc comment required |
| Models | Field descriptions if complex |

### Example

```dart
/// Fetches user health profile from Firestore.
///
/// Returns [Either<HealthProfileException, HealthProfileModel>]
/// - Left: Error occurred (network, not found, permissions)
/// - Right: Profile successfully fetched
///
/// Throws nothing - all errors returned as Left.
Future<Either<HealthProfileException, HealthProfileModel?>> getProfile(String uid);
```

## Rule 14: Model Conventions

**❌ DO NOT create models without Firestore serialization**

### Model Checklist

- [ ] All fields are `final`?
- [ ] Includes `toJson()` method?
- [ ] Includes `fromJson()` factory?
- [ ] Includes `copyWith()` method?
- [ ] Includes `==` and `hashCode`?
- [ ] Includes `toString()` for debugging?
- [ ] Handles both Firestore native types AND fallbacks?

### Template

```dart
class MyModel {
  final String id;
  final String name;
  
  const MyModel({
    required this.id,
    required this.name,
  });

  factory MyModel.fromJson(String id, Map<String, dynamic> json) {
    return MyModel(
      id: id,
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
  };

  MyModel copyWith({String? id, String? name}) => MyModel(
    id: id ?? this.id,
    name: name ?? this.name,
  );

  @override
  bool operator ==(Object other) => ...;

  @override
  int get hashCode => ...;

  @override
  String toString() => ...;
}
```

## Summary: Quick Reference

| Do | Don't |
|----|-------|
| ✓ Reuse existing widgets | ✗ Create duplicate widgets |
| ✓ Use Either for errors | ✗ Throw exceptions |
| ✓ Follow file structure | ✗ Reorganize folders |
| ✓ Use Riverpod providers | ✗ Use global singletons |
| ✓ Immutable models | ✗ Mutable state objects |
| ✓ Sealed classes for unions | ✗ Enum + base class patterns |
| ✓ Repository abstraction | ✗ Direct Firebase access |
| ✓ Document public APIs | ✗ Undocumented code |
| ✓ Check existing code first | ✗ Write new without search |
| ✓ Modular files (<300 lines) | ✗ God classes (500+ lines) |

**These rules are non-negotiable. Violation means rework required.**
