# Setup & Development Guide: ForeSeeMe

## System Requirements

### Minimum Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| Flutter | 3.10.0+ | Available from flutter.dev |
| Dart | 3.10.0+ | Included with Flutter |
| Android SDK | API 21+ | For Android development |
| Xcode | 14.0+ | For iOS development (macOS only) |
| CocoaPods | 1.11+ | For iOS pod management |
| Git | 2.0+ | Version control |

### Recommended Development Environment

- **macOS 12+** (easiest for iOS + Android)
- **Visual Studio Code** with Flutter extension
- **Android Studio** (or Android Emulator)
- **Xcode** (for iOS Simulator)

### Supported Platforms

- ✅ **Android** (5.0+ / API 21+)
- ✅ **iOS** (11.0+)
- ✅ **macOS** (10.11+)
- ✅ **Linux**
- ✅ **Windows**
- ⏳ **Web** (scaffolded, not priority)

## Installation

### 1. Install Flutter

Follow official guide: https://flutter.dev/docs/get-started/install

```bash
# Verify installation
flutter doctor

# Should show:
# ✓ Flutter (Channel stable, version 3.10.0+)
# ✓ Dart (version 3.10.0)
# ✓ Android toolchain
# ✓ Xcode (if on macOS)
```

### 2. Clone Project

```bash
git clone https://github.com/your-org/fyp_foreseeme.git
cd fyp_foreseeme
```

### 3. Install Dependencies

```bash
flutter pub get

# Outputs:
# Resolving dependencies...
# Downloading packages...
# Got dependencies!
```

### 4. Configure Firebase

**Already Configured for:**
- Project ID: `foreseeme-83587`
- Android: `google-services.json` included
- iOS: GoogleService-Info.plist needed

**If needed, regenerate Firebase config:**

```bash
# Using Firebase CLI
firebase init

# Or via FlutterFire CLI
flutterfire configure --project=foreseeme-83587
```

### 5. Generate Firebase Options (If Missing)

```bash
# On first run, Firebase options may be needed
# Uncomment in main.dart:
# await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

# If firebase_options.dart missing, generate it:
flutterfire configure
```

## Environment Setup

### Local Development Variables

**Create** `lib/config/env.dart` (NOT IN GIT):

```dart
// lib/config/env.dart (local only, .gitignore this)
// For local development secrets (if needed in future)
const String FIREBASE_PROJECT_ID = 'foreseeme-83587';
const bool DEBUG_LOGGING = true;
```

**Add to .gitignore:**
```
lib/config/env.dart
*.local
.env
```

### Firebase Console Access

- **Project**: https://console.firebase.google.com/project/foreseeme-83587
- **Firestore**: Realtime database for users/{uid}/*
- **Authentication**: Email + Google OAuth

## Project Structure

```
fyp_foreseeme/
├── lib/                      # Source code
│   ├── main.dart            # Entry point
│   ├── core/                # Shared infrastructure
│   └── features/            # Feature modules
├── test/                     # Unit tests (scaffold)
├── pubspec.yaml             # Dependencies
├── analysis_options.yaml    # Linter rules
├── README.md                # Project README
└── docs/                    # Documentation (new)
    ├── project-context.md
    ├── architecture.md
    └── ... (other docs)
```

## Running the App

### Android

```bash
# List available emulators
flutter emulators

# Start an emulator
flutter emulators --launch Pixel_5_API_30

# Run on emulator
flutter run

# Run with verbose output (for debugging)
flutter run -v

# Build APK
flutter build apk

# Build App Bundle (for Google Play)
flutter build appbundle
```

### iOS

```bash
# Open iOS workspace (required for pods)
cd ios
open Runner.xcworkspace

# Run on simulator
cd .. && flutter run

# Build for physical device
flutter run -d <device-id>

# Build IPA for App Store
flutter build ipa
```

### Release Build

```bash
# Android release
flutter build apk --release
flutter build appbundle --release

# iOS release
flutter build ios --release

# Outputs location
# Android: build/app/outputs/flutter-apk/
# iOS: build/ios/ipa/
```

## Hot Reload / Hot Restart

```bash
# Hot reload: Updates code without losing state
r          # Command in terminal during flutter run

# Hot restart: Full app restart
R          # Command in terminal during flutter run

# This is essential for fast iteration during development
```

## Testing

### Run Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/features/auth/auth_test.dart

# Watch mode (rerun on changes)
flutter test --watch

# With verbose output
flutter test -v
```

### Test Coverage

```bash
# Generate coverage report (requires lcov)
flutter test --coverage

# View coverage (macOS)
open coverage/lcov-report/index.html
```

### (TODO) Unit Test Structure

Tests should follow:
```
test/
├── features/
│   ├── auth/
│   │   ├── auth_notifier_test.dart
│   │   └── auth_repository_test.dart
│   └── ...
└── core/
    └── utils/
        └── either_test.dart
```

## Code Analysis & Linting

### Run Analysis

```bash
# Analyze code for issues
flutter analyze

# Fixed by linter
dart fix --apply

# Format code
dart format .

# Also: flutter format .
```

### Lint Rules

Configured in `analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    # Custom rules can be added here
```

## Debugging

### VS Code Debugging

**Configuration**: `.vscode/launch.json`

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "console": "integratedTerminal",
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

### Print Debugging

```dart
print('Debug: $value');          // Simple
debugPrint('Debug: $value');     // Better (avoids log cutoff)

// VS Code: Click breakpoint line number to set breakpoints
// Flutter automatically pauses at breakpoints during debug run
```

### DevTools

```bash
# Open DevTools (web-based debugging UI)
flutter pub global run devtools

# Or directly
flutter pub global run devtools -- --port=9100

# Connect to running app:
# Open http://localhost:9100
# Select device from list
```

### Firebase Local Testing

```bash
# Install Firebase Emulator Suite
npm install -g firebase-tools

# Start emulator
firebase emulators:start

# Configure app to use local emulator
// In main.dart:
if (kDebugMode) {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Connect to emulator:
  // FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  // FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
```

## Dependency Management

### Update Dependencies

```bash
# Check for outdated packages
flutter pub outdated

# Update all dependencies (minor/patch)
flutter pub upgrade

# Update to major versions (breaking changes)
flutter pub upgrade --major-versions

# Add specific package version
flutter pub add package_name:^1.0.0

# Remove package
flutter pub remove package_name
```

### Adding New Packages

**Before adding a new package:**

1. Check existing packages (`pubspec.yaml`)
2. Verify it's not duplicating existing functionality
3. Check package health (likes, pub points, documentation)
4. Review breaking changes in new versions

```bash
# Add package
flutter pub add firebase_messaging

# Or manually edit pubspec.yaml and run
flutter pub get
```

### Common Packages

| Task | Package | Usage |
|------|---------|-------|
| State management | riverpod | Already added |
| Routing | go_router | Already added |
| Auth | firebase_auth | Already added |
| Database | cloud_firestore | Already added |
| Notifications | flutter_local_notifications | Already added |
| Timezone | timezone | Already added |
| Icons | google_fonts | Already added |

## Git Workflow

### Clone and Setup

```bash
# Clone repo
git clone https://github.com/your-org/fyp_foreseeme.git

# Create feature branch
git checkout -b feature/medication-tracking

# Make changes
# Test locally

# Commit with clear message
git commit -m "feat: implement medication check-in screen"

# Push to remote
git push origin feature/medication-tracking

# Create Pull Request on GitHub
```

### Commit Message Format

```
feat: add medication check-in screen
docs: update database schema
fix: correct adherence status calculation
refactor: extract medication card widget
test: add auth notifier tests
```

### Before Committing

```bash
# 1. Format code
flutter format .

# 2. Run analysis
flutter analyze

# 3. Run tests
flutter test

# 4. Commit formatted code
git add .
git commit -m "..."
```

## Building for Release

### Android Release

```bash
# 1. Configure signing
# Edit: android/app/build.gradle
# Add signing config

# 2. Build APK
flutter build apk --release

# 3. Build App Bundle (recommended for Play Store)
flutter build appbundle --release

# Output
# APK: build/app/outputs/flutter-apk/app-release.apk
# AAB: build/app/outputs/bundle/release/app-release.aab
```

### iOS Release

```bash
# 1. Update build number/version
# Edit: ios/Runner/Info.plist
# Or: pubspec.yaml version: 1.0.0+1

# 2. Build IPA
flutter build ipa --release

# Output
# IPA: build/ios/ipa/

# 3. Upload to App Store
# Use Xcode or Apple Transporter
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `pubspec.lock` conflicts | `flutter clean && flutter pub get` |
| Emulator won't start | `flutter emulators --launch <emulator-id>` |
| Firebase not initialized | Ensure `main.dart` calls `Firebase.initializeApp()` |
| Pod install fails | `cd ios && rm Podfile.lock && pod install` |
| Xcode build fails | `flutter clean && flutter pub get` |
| App crashes on launch | Check `firebase.json` configuration |
| Hot reload not working | Try hot restart with `R` |

### Clean Build

```bash
# When all else fails:
flutter clean                  # Remove build artifacts
flutter pub get               # Re-fetch dependencies
flutter run                   # Fresh build and run
```

## Documentation & Resources

### In This Project

- `docs/project-context.md` - Project overview
- `docs/architecture.md` - Architecture details
- `docs/frontend.md` - UI/UX guidelines
- `docs/database.md` - Firestore schema
- `docs/coding-rules.md` - Code standards

### External Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Documentation](https://dart.dev/guides)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Riverpod Documentation](https://riverpod.dev)
- [Go Router Documentation](https://pub.dev/packages/go_router)

## Common Development Tasks

### Add New Feature

1. Create folder: `lib/features/new_feature/`
2. Create subfolders: `data/`, `domain/`, `presentation/`
3. Follow architecture patterns (see `coding-rules.md`)
4. Create models, repositories, providers
5. Implement screens and notifiers
6. Update router in `lib/core/routes/app_router.dart`

### Add New Model

1. Create in `features/{feature}/domain/models/{name}_model.dart`
2. Add `fromJson()`, `toJson()`, `copyWith()`
3. Add serialization tests
4. Create repository in `data/repositories/`

### Modify Firestore Schema

1. Update model's `toJson()` / `fromJson()`
2. Handle backward compatibility
3. Update repository queries if needed
4. Test with existing data

### Submit Changes

1. Make changes following coding rules
2. Test locally (`flutter test`)
3. Run analysis (`flutter analyze`)
4. Format code (`flutter format .`)
5. Commit with clear message
6. Push and create PR
7. Request review

## Performance Profiling

### Identify Performance Issues

```bash
# Run with profiling
flutter run --profile

# Use DevTools Performance tab
# Monitor Frame rendering time
# Look for jank (drops below 60 FPS)
```

### Memory Profiling

```bash
# In DevTools → Memory tab
# Take snapshots
# Monitor heap size
# Look for memory leaks
```

## Next Steps for New Developer

1. ✅ Read `docs/project-context.md`
2. ✅ Read `docs/architecture.md`
3. ✅ Read `docs/ai-rules.md`
4. ✅ Clone project and run locally
5. ✅ Explore codebase (especially features/)
6. ✅ Try hot reload on a simple change
7. ✅ Create simple feature following patterns
8. ✅ Submit PR for code review
