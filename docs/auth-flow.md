# Authentication Flow: ForeSeeMe

## Authentication Architecture

### Overview

ForeSeeMe uses **Firebase Authentication** with two primary sign-in methods:
1. Email/password (email-based account)
2. Google OAuth (federated identity)

All authentication is handled client-side via Firebase Auth SDK, no backend API required.

## Sign-Up Flow

### User Journey: Registration

```
[RegisterScreen]
    ↓
User enters: Email, Password, Display Name
    ↓
Form validation (email format, password length)
    ↓
[Tap "Create Account"]
    ↓
AuthNotifier.signUp(email, password, displayName)
    ↓
FirebaseAuthRepository.signUpWithEmail()
    ↓
Firebase Auth SDK: createUserWithEmailAndPassword()
    ↓
SUCCESS: User account created in Firebase
    ↓
updateDisplayName() on Firebase User
    ↓
UserModel.fromFirebaseUser() created
    ↓
authStateProvider emits UserModel
    ↓
Router: redirect to /health-profile (setup)
    ↓
[HealthProfileScreen] - Setup mode
    ↓
User completes profile (city, conditions)
    ↓
HealthProfileNotifier.saveProfile()
    ↓
Firestore: users/{uid}/profile/data created
    ↓
Router: redirect to /home
    ↓
[Home Screen] - App accessible
```

### Code Implementation

**File:** `lib/features/auth/presentation/auth_notifier.dart`

```dart
Future<void> signUp({
  required String email,
  required String password,
  required String displayName,
}) async {
  state = const AuthStateLoading();
  
  final result = await _repository.signUpWithEmail(
    email: email,
    password: password,
    displayName: displayName,
  );

  state = result.fold(
    (error) => AuthStateError(error.message),
    (user) => AuthStateAuthenticated(user),
  );
}
```

## Sign-In Flow

### Email/Password Sign-In

```
[LoginScreen] - Email/Password Tab
    ↓
User enters: Email, Password
    ↓
Form validation
    ↓
[Tap "Sign In"]
    ↓
AuthNotifier.signIn(email, password)
    ↓
FirebaseAuthRepository.signInWithEmail()
    ↓
Firebase Auth SDK: signInWithEmailAndPassword()
    ↓
SUCCESS: User authenticated
    ↓
UserModel created from Firebase user
    ↓
authStateProvider streams UserModel
    ↓
Router: evaluates redirect logic
    ↓
Is user's health profile complete?
  ├─ No → /health-profile (setup)
  └─ Yes → /home (app access)
    ↓
[Authenticated State]
```

### Google OAuth Sign-In

```
[LoginScreen] - Google Tab
    ↓
[Tap "Sign In with Google"]
    ↓
GoogleSignIn.signIn() - Opens Google login dialog
    ↓
User authenticates with Google account
    ↓
GoogleSignInAuthentication obtained (accessToken, idToken)
    ↓
Firebase Auth SDK: signInWithCredential(GoogleAuthProvider)
    ↓
SUCCESS: Firebase user created/linked
    ↓
UserModel from Firebase user (email + displayName from Google)
    ↓
authStateProvider streams UserModel
    ↓
Router: redirect to /health-profile or /home
```

### Code Implementation

**File:** `lib/features/auth/data/repositories/firebase_auth_repository.dart`

```dart
@override
Future<Either<AuthException, UserModel>> signInWithGoogle() async {
  try {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      return const Left(AuthException('Google sign in cancelled'));
    }

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    return Right(UserModel.fromFirebaseUser(userCredential.user!));
  } catch (e) {
    return Left(AuthException(e.toString()));
  }
}
```

## Password Reset Flow

### Forgot Password

```
[LoginScreen]
    ↓
[Tap "Forgot password?"]
    ↓
[ForgotPasswordScreen]
    ↓
User enters: Email
    ↓
Form validation
    ↓
[Tap "Send Reset Link"]
    ↓
AuthNotifier.sendPasswordReset(email)
    ↓
FirebaseAuthRepository.sendPasswordReset()
    ↓
Firebase Auth SDK: sendPasswordResetEmail()
    ↓
Firebase sends email with reset link
    ↓
User receives email with reset link
    ↓
[Tap link in email]
    ↓
[Firebase Web Reset Page] (external)
    ↓
User sets new password
    ↓
Firebase updates user password
    ↓
User can now sign in with new password
```

## JWT/Session Logic

### Token Management

**Firebase Handles All Token Management:**

1. **ID Token** (JWT)
   - Auto-refreshed by Firebase SDK
   - Contains user identity claims
   - Valid for ~1 hour
   - Automatically renewed before expiry

2. **Refresh Token**
   - Stored securely by Firebase SDK
   - Used to obtain new ID tokens
   - Long-lived (months)

3. **Session Management**
   - Firebase persists auth state locally
   - `authStateChanges()` stream tracks session
   - Auto-restores session on app restart

### Code Implementation

**File:** `lib/features/auth/data/repositories/firebase_auth_repository.dart`

```dart
@override
Stream<UserModel?> get currentUser {
  return _firebaseAuth.authStateChanges().map((user) {
    if (user == null) return null;
    return UserModel.fromFirebaseUser(user);
  });
}
```

**Automatic Token Refresh:**
- Firebase SDK handles behind-the-scenes
- No explicit token management needed
- Requests to Firestore/Cloud Functions auto-include valid token

## Middleware Protection

### Route Guards (Go Router)

**File:** `lib/core/routes/app_router.dart`

```dart
final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ValueNotifier<AsyncValue<UserModel?>>(const AsyncLoading());
  
  ref.listen(authStateProvider, (_, next) {
    authNotifier.value = next;
  });

  return GoRouter(
    refreshListenable: authNotifier,  // ← Triggers redirect on auth change
    redirect: (context, state) {
      final authState = authNotifier.value;
      
      // Wait for auth to load
      if (authState.isLoading) return null;

      final isAuth = authState.value != null;
      final isLoggingIn = state.matchedLocation in [
        '/login',
        '/register',
        '/forgot-password',
      ];

      // Redirect unauthenticated to login
      if (!isAuth && !isLoggingIn) return '/login';
      
      // Block authenticated users from auth screens
      if (isAuth && isLoggingIn) return '/home';
      
      // Allow navigation
      return null;
    },
    routes: [ /* ... */ ],
  );
});
```

### Protection Strategy

1. **Unauthenticated users** → Force to `/login`
2. **Authenticated users** → Block from auth routes
3. **Loading state** → Show splash/loading, don't redirect yet
4. **Route transitions** → Immediate evaluation on state change

### Firestore Security Rules (Server-side)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User isolation - can only access own data
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth.uid == uid;
    }
  }
}
```

## Roles & Permissions

### Current State

**Simple Role Model:**
- User (default)
- (Future: Doctor, Caregiver, Administrator)

**Permission Examples:**
- Users can CRUD own data
- Users cannot access other users' data
- (Future: Doctors can read patient data with consent)

### Implementation (If Added)

```dart
// Future: Add role to UserModel
class UserModel {
  final String uid;
  final String email;
  final UserRole role;  // User, Doctor, Admin
}

// Enforce in Firestore rules
allow read: if hasRole('doctor') || request.auth.uid == uid;

// Check in app
if (currentUser.role == UserRole.doctor) {
  // Show doctor-specific features
}
```

## Token Lifecycle

### ID Token Lifecycle

```
Login
  ↓
Firebase generates ID Token (valid 1 hour)
  ↓
Token stored in device secure storage
  ↓
App uses token for Firestore requests
  ↓
Token expires (approaching 1 hour)
  ↓
Firebase SDK automatically refreshes using Refresh Token
  ↓
New ID Token obtained (1 hour validity)
  ↓
No user action needed - seamless
  ↓
Sign Out
  ↓
Tokens cleared from device
```

### Token Refresh Flow (Automatic)

```dart
// Firebase handles this internally
// Developers don't need to manage token refresh
// Firestore SDK automatically sends valid tokens with each request
```

## Sign-Out Flow

### Logout Process

```
User selects "Logout" from settings
    ↓
AuthNotifier.signOut()
    ↓
FirebaseAuthRepository.signOut()
    ↓
Firebase Auth SDK: signOut()
    ↓
SUCCESS: User logged out
    ↓
authStateProvider streams null
    ↓
Router: evaluates redirect logic
    ↓
Is authenticated? No
    ↓
Router: redirect to /login
    ↓
[LoginScreen] shown
    ↓
Local tokens cleared
```

### Code Implementation

```dart
Future<void> signOut() async {
  state = const AuthStateLoading();

  final result = await _repository.signOut();

  state = result.fold(
    (error) => AuthStateError(error.message),
    (_) => const AuthStateUnauthenticated(),
  );
}
```

## Error Handling

### Auth Exceptions

**File:** `lib/features/auth/domain/exceptions/auth_exception.dart`

```dart
class AuthException implements Exception {
  final String message;
  final String? code;
  
  const AuthException(this.message, [this.code]);
}
```

### Common Error Scenarios

| Error | Code | Handling |
|-------|------|----------|
| User not found | `user-not-found` | Show "Email not registered" |
| Wrong password | `wrong-password` | Show "Invalid password" |
| Email in use | `email-already-in-use` | Show "Email already registered" |
| Weak password | `weak-password` | Show "Password too weak (min 6 chars)" |
| Network error | (native exception) | Show "Check internet connection" |
| Google cancelled | `cancelled` | Silent (user cancelled) |

### UI Error Display

```dart
ref.listenManual(authNotifierProvider, (prev, next) {
  if (next is AuthStateError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(next.message)),
    );
  }
});
```

## Security Considerations

### Best Practices Implemented

✅ **No hardcoded credentials**: Firebase config from environment
✅ **HTTPS only**: Firebase enforces TLS
✅ **Secure token storage**: Firebase SDK uses platform keychain
✅ **No password exposure**: Never logged or displayed
✅ **Email verification**: (Optional, can be enabled)
✅ **Firestore rules**: User isolation enforced server-side

### Future Security Enhancements

- [ ] Email verification on sign-up
- [ ] Two-factor authentication (2FA)
- [ ] Account recovery via security questions
- [ ] Biometric authentication (fingerprint, face)
- [ ] Session timeout on inactivity
- [ ] IP address restrictions (for admin panel)

## Testing Authentication

### Manual Testing Checklist

- [ ] Sign up with email/password
- [ ] Verify user redirected to health profile setup
- [ ] Sign in with email/password
- [ ] Verify user redirected to home
- [ ] Sign in with Google
- [ ] Test forgot password flow
- [ ] Verify sign-out returns to login
- [ ] Test unauthenticated route access (should redirect)
- [ ] Test network disconnect during auth
- [ ] Verify session persists across app restart

### (Future) Automated Testing

```dart
// Example unit test structure
test('signIn returns UserModel on success', () async {
  when(mockFirebaseAuth.signInWithEmailAndPassword(...))
    .thenAnswer((_) async => mockUserCredential);
  
  final result = await repository.signInWithEmail(...);
  
  expect(result, isA<Right>());
});
```

## Firebase Project Configuration

**Project ID:** `foreseeme-83587`

### Configured Services
- ✅ Firebase Auth (Email + Google OAuth)
- ✅ Firestore Database
- ✅ (Future: Cloud Functions for custom logic)

### Google OAuth Credentials
- Android: OAuth client ID configured in Google Cloud Console
- iOS: OAuth client ID configured + Info.plist signing
- Web: OAuth client ID + redirect URIs

### Next Steps
- [ ] Enable email verification
- [ ] Configure custom email templates
- [ ] Set password policy requirements
- [ ] Enable account activity logs
