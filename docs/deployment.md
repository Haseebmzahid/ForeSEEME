## Scheduled backend release readiness

For compute-risk, follow [the backend deployment workflow](../backend/deploy/README.md#compute-risk-release-candidate-workflow-authoritative).
Its `one-time` mode uses attached identity and explicit freshness settings,
verifies one exact execution plus all five persisted city results, and never
accesses Scheduler. The separately authorized recurring mode pauses existing
recurrence, verifies the initial execution, then schedules.
The compute-risk controller requires an explicit reviewed SHA-256 digest-pinned image;
mutable tags and the empty example IMAGE fail preflight. Existing APIs/billing/IAM
are prerequisites; local readiness testing does not grant
permission to deploy or write live data. The mobile release guide below is
separate and does not establish backend readiness.

# Deployment Guide: ForeSeeMe

## Deployment Strategy

**Current State**: MVP Phase (Pre-production)

**Target Platforms**: Android (primary), iOS (secondary)

**Hosting**: Firebase (backend), App Stores (distribution)

## Development Environments

### 1. Local Development (Dev)

- **Purpose**: Individual feature development
- **Branch**: `dev`, `feature/*`
- **Trigger**: Manual (`flutter run`)
- **Firebase**: `foreseeme-83587` (development)
- **Access**: All developers

### 2. Testing/Staging (Optional - Not Yet Configured)

- **Purpose**: QA and integration testing
- **Branch**: `staging`
- **Trigger**: Manual merge to staging
- **Firebase**: Separate project (recommended)
- **Access**: QA team + developers

### 3. Production (Future)

- **Purpose**: Live app for end users
- **Branch**: `main`
- **Trigger**: Git tag / Release
- **Firebase**: Production project (separate)
- **Access**: Limited (CI/CD + release manager)

## Firebase Project Configuration

### Current Setup

| Aspect | Configuration |
|--------|---|
| Project ID | `foreseeme-83587` |
| Region | `us-central1` |
| Authentication | Email + Google OAuth enabled |
| Firestore | Initialized, security rules applied |
| Storage | Not configured (future) |

### Required Credentials

**Already in .gitignore:**
- `android/app/google-services.json` ✓
- Firebase Auth credentials ✓
- Firestore API keys ✓

**Never commit:**
- Private keys
- Service account JSON
- OAuth client secrets

## Build & Release Process

### Android Release Process

**Step 1: Version Bump**

```bash
# Update version in pubspec.yaml
# Format: version: {major}.{minor}.{patch}+{build}
# Example: version: 1.0.0+1

# Commit and tag
git tag v1.0.0
git push origin v1.0.0
```

**Step 2: Configure Signing**

**File:** `android/app/build.gradle`

```gradle
android {
  signingConfigs {
    release {
      keyAlias keyAliasName          // From keystore
      keyPassword keyPassword        // From keystore
      storeFile file(keyStorePath)
      storePassword keyStorePassword // From keystore
    }
  }

  buildTypes {
    release {
      signingConfig signingConfigs.release
      minifyEnabled true            // Enable code shrinking
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt')
    }
  }
}
```

**Step 3: Build Release APK/AAB**

```bash
# Build App Bundle (recommended for Play Store)
flutter build appbundle --release

# Build APK (for direct distribution)
flutter build apk --release --split-per-abi

# Output locations
# APK: build/app/outputs/flutter-apk/
# AAB: build/app/outputs/bundle/release/app-release.aab
```

**Step 4: Upload to Play Store**

```bash
# Using bundletool or Google Play Console UI
# File: build/app/outputs/bundle/release/app-release.aab

# Via command line (if configured)
gcloud app deploy build/app/outputs/bundle/release/app-release.aab
```

### iOS Release Process

**Step 1: Update Version**

**File:** `ios/Runner/Info.plist`

```xml
<key>CFBundleVersion</key>
<string>1</string>           <!-- Build number -->
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>       <!-- Version -->
```

**Step 2: Configure Signing**

- Open `ios/Runner.xcworkspace` in Xcode
- Select Runner → Signing & Capabilities
- Choose development team
- Configure provisioning profile

**Step 3: Build for App Store**

```bash
flutter build ipa --release

# Output
# IPA: build/ios/ipa/ForeSeeMe.ipa
```

**Step 4: Upload to App Store**

```bash
# Option 1: Xcode Organizer
# Open Xcode → Window → Organizer → Upload

# Option 2: Apple Transporter
# Download from App Store Connect
# Upload IPA directly

# Option 3: Command line
xcrun altool --upload-app --file build/ios/ipa/ForeSeeMe.ipa --type ios
```

## Environment Configuration

### Android Environment Variables

**File:** `android/local.properties`

```properties
sdk.dir=/path/to/Android/sdk
flutter.sdk=/path/to/flutter
flutter.versionName=1.0.0
flutter.versionCode=1
```

### iOS Environment Variables

**File:** `ios/Runner/Info.plist`

```xml
<dict>
  <key>UIDeviceFamily</key>
  <array>
    <integer>1</integer>  <!-- iPhone -->
    <integer>2</integer>  <!-- iPad -->
  </array>
  <key>MinimumOSVersion</key>
  <string>11.0</string>
</dict>
```

## Continuous Integration (CI/CD) - Future

### Recommended Setup: GitHub Actions

**File:** `.github/workflows/deploy.yml` (Not Yet Configured)

```yaml
name: Build & Deploy

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.10.0'
      
      - run: flutter pub get
      - run: flutter build appbundle --release
      
      - name: Upload to Play Store
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_STORE_KEY }}
          packageName: com.foreseeme.app
          releaseFiles: 'build/app/outputs/bundle/release/app-release.aab'
          track: internal  # internal, alpha, beta, production
```

## Deployment Checklist

### Pre-Release

- [ ] All features tested locally
- [ ] Code review completed
- [ ] Tests passing (`flutter test`)
- [ ] Analysis clean (`flutter analyze`)
- [ ] Version bumped in `pubspec.yaml`
- [ ] Changelog updated
- [ ] Git tag created (`git tag v1.0.0`)
- [ ] Branch merged to `main`

### Release

- [ ] Firebase project verified
- [ ] Build signed with valid certificate
- [ ] APK/AAB size acceptable (<150MB)
- [ ] App tested on device
- [ ] Screenshots ready for store

### Post-Release

- [ ] Monitor crash logs (Crashlytics - future)
- [ ] Monitor user feedback (Ratings)
- [ ] Check performance metrics
- [ ] Prepare hotfix if needed
- [ ] Document any issues

## Rollback Plan

### If Release Has Critical Bug

```bash
# 1. Mark previous version as active in Play Store
# Console: Google Play Console → Your app → Release Management → Releases

# 2. Or release hotfix
git checkout v1.0.0
git checkout -b hotfix/critical-bug
# Fix bug
flutter build appbundle --release
# Upload new version 1.0.1

# 3. Monitor crash logs closely
```

## Monitoring Post-Launch

### Firebase Monitoring

- **Firestore Usage**: Console shows read/write counts
- **Auth Issues**: Monitor sign-in/sign-up failures
- **Performance**: Monitor database query latency

### App Store Monitoring

- **Crashes**: Monitor crash rates
- **Ratings**: Track user ratings and reviews
- **Uninstalls**: Monitor retention

### Analytics (Future - Not Configured)

```dart
// When Firebase Analytics added:
await FirebaseAnalytics.instance.logEvent(
  name: 'medication_check_in',
  parameters: {'status': 'taken'},
);
```

## Update Strategy

### Minor/Patch Updates (Bug fixes)

```bash
# Version: 1.0.0 → 1.0.1
# No forced update needed
# Users can update at own pace
```

### Major Updates (New features)

```bash
# Version: 1.0.0 → 2.0.0
# May require data migration
# Test backward compatibility
```

### Force Update (Security fixes)

**In-app check (future implementation):**

```dart
// Check minimum version required
if (currentVersion < minRequiredVersion) {
  showDialog(
    title: 'Update Required',
    message: 'Please update to continue',
    actions: [
      TextButton(label: 'Update', onPressed: () => openStore()),
    ],
  );
}
```

## Hosting & Infrastructure

### Firebase Hosting (Future)

For web dashboard (not in MVP):

```bash
# Configure Firebase hosting
firebase init hosting

# Deploy
firebase deploy --only hosting
```

### Firestore Backups

Automatic daily backups retained for 7 days.

**Manual backup:**

```bash
gcloud firestore export gs://foreseeme-83587-backups/backup_$(date +%Y%m%d)
```

## Security Best Practices

### Before Release

- [ ] Firebase security rules reviewed
- [ ] No hardcoded secrets
- [ ] API keys restricted
- [ ] HTTPS enforced (Firebase default)
- [ ] User data encryption (at-rest + in-transit)

### App Signing

- [ ] Android keystore secured
- [ ] iOS certificates current
- [ ] No credentials in git

### Access Control

- [ ] Firebase Console access limited
- [ ] Play Store access limited
- [ ] CI/CD credentials secured

## Troubleshooting Deployment Issues

| Issue | Solution |
|-------|----------|
| Build fails | `flutter clean && flutter pub get` |
| Signing fails | Check keystore path and credentials |
| Firebase init issue | Verify `google-services.json` present |
| Store upload fails | Check file size, signatures |
| App crashes on startup | Check `main.dart` Firebase init |

## Future Deployment Enhancements

- [ ] Implement Firebase Crashlytics (crash reporting)
- [ ] Add Firebase Analytics (user insights)
- [ ] Configure CI/CD pipeline (GitHub Actions)
- [ ] Add feature flags (remote config)
- [ ] Implement staged rollouts (10% → 25% → 100%)
- [ ] Add in-app update prompts
- [ ] Configure App Store Connect automation
