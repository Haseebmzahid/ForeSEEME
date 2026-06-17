# Project Context: ForeSeeMe

## Project Overview

**ForeSeeMe** is a Flutter-based mobile application designed to help users manage medication adherence through daily check-ins, health profile management, and medication tracking with local notification reminders.

## Purpose

Enable patients with chronic conditions to:
- Track medication adherence with daily check-ins
- Maintain health profile (location, chronic conditions)
- Receive timely medication reminders
- View medication history and compliance patterns

## Target Users

- Patients with chronic conditions requiring regular medication
- Healthcare consumers in South Asian markets (Lahore, Islamabad, Karachi, Rawalpindi, Peshawar)
- Users aged 18+

## Major Features

### 1. Authentication
- Email/password sign-up and sign-in
- Google OAuth sign-in
- Password reset functionality
- Firebase Auth backend

### 2. Health Profile
- User health profile setup during onboarding
- Support for multiple chronic conditions
- City selection (air quality context for future features)
- Profile update capability

### 3. Medication Management
- Add new medications with:
  - Name, dosage, type (pill/syrup)
  - Frequency (once/twice/thrice daily)
  - Custom reminder times
- List active medications
- Deactivate medications (soft delete)
- Real-time stream updates

### 4. Daily Check-In
- Date navigation (view past 7 days, current day, future 5 days)
- Medications grouped by time of day (morning/afternoon/evening)
- Status tracking: pending/taken/skipped
- Past date restrictions (read-only view)
- Adherence visualization

### 5. Notifications
- Local push notifications for medication reminders
- Platform-specific (Android/iOS/macOS)
- Timezone-aware scheduling
- User permission handling

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| **UI Framework** | Flutter | 3.10+ |
| **Language** | Dart | 3.10+ |
| **State Management** | Flutter Riverpod | 3.3.1 |
| **Routing** | Go Router | 17.2.3 |
| **Authentication** | Firebase Auth | 6.4.0 |
| **Database** | Cloud Firestore | 6.3.0 |
| **OAuth** | Google Sign-In | 6.2.1 |
| **Notifications** | Flutter Local Notifications | 21.0.0 |
| **Typography** | Google Fonts | 8.1.0 |
| **Timezone** | Timezone | 0.11.0 |
| **Code Quality** | Flutter Lints | 6.0.0 |

## Architecture Philosophy

### Design Principles

1. **Clean Architecture**
   - Separation of concerns: domain/data/presentation
   - Business logic isolated from UI and data access
   - Independent, testable layers

2. **Reactive Programming**
   - Stream-based data flow with Riverpod
   - Real-time UI updates without manual polling
   - Provider-based dependency injection

3. **Type Safety**
   - Null-safe Dart throughout
   - Sealed classes for union types (auth states)
   - Either<Exception, T> pattern for error handling

4. **Immutability**
   - All domain models are immutable
   - Copy-with pattern for modifications
   - Firestore serialization with explicit toJson/fromJson

5. **Reusability**
   - Shared core layer (theme, routing, widgets, utilities)
   - Feature-scoped modules (auth, medication, health_profile)
   - No cross-feature dependency coupling

## Current Development Status

**Phase: MVP Development**

### Completed
- ✅ Project scaffold with clean architecture
- ✅ Firebase integration (auth, firestore)
- ✅ Authentication feature (email, Google sign-in, password reset)
- ✅ Routing structure with auth guards
- ✅ Health profile feature (setup/edit)
- ✅ Medication model and repository
- ✅ Adherence tracking model
- ✅ Daily check-in UI structure
- ✅ Theme system and design tokens
- ✅ Core utilities (Either, notifications, widgets)

### In Progress
- 🔄 Medication management screens (add/edit/list)
- 🔄 Check-in screen refinement and integration
- 🔄 Adherence notifier business logic completion
- 🔄 Notification scheduling implementation

### Pending
- ⏳ Analytics and insights dashboard
- ⏳ Medication history reports
- ⏳ Integration with health APIs (Apple Health, Google Fit)
- ⏳ Advanced adherence patterns
- ⏳ Multi-user/caregiver features
- ⏳ Testing infrastructure (unit, widget, integration)
- ⏳ CI/CD pipeline

## Important Constraints

### Platform Constraints
- **Minimum Flutter SDK**: 3.10.0
- **Supported Platforms**: Android, iOS, macOS, Linux, Windows
- **Primary Targets**: Android, iOS (mobile-first)

### Data Constraints
- Firebase Firestore (NoSQL)
- Real-time synchronization enabled
- Document-based structure (not tabular)
- Server timestamps for consistency
- ISO 8601 date format for date-only fields

### Security Constraints
- Firebase Auth with security rules (server-side)
- User isolation: users can only access own data
- No API keys in client code
- Google Cloud project ID: `foreseeme-83587`

### Design Constraints
- Premium medical aesthetic (teal color scheme)
- Responsive design for various screen sizes
- Accessibility considerations (color contrast, text sizing)
- Material Design 3 compliance

## Project Goals

### Short-term (MVP)
1. Complete medication management UI
2. Integrate adherence tracking with notifications
3. Implement daily check-in workflow
4. Deploy to Firebase (Android)
5. Functional user testing

### Medium-term (v1.0)
1. iOS app deployment
2. Adherence reports and insights
3. Health API integrations
4. Push notification improvements
5. Caregiver support

### Long-term (Scalability)
1. Multi-language support (Urdu, English)
2. Offline-first capabilities
3. Wearable integration
4. Predictive adherence alerts
5. Doctor/clinic portal integration

## Repository Metadata

- **Project ID**: `fyp_foreseeme`
- **Firebase Project**: `foreseeme-83587`
- **Platform**: Flutter (cross-platform mobile)
- **License**: Not yet specified
- **Maintainers**: FYP Development Team

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, theme, router setup |
| `lib/core/theme/app_theme.dart` | Design system, colors, typography |
| `lib/core/routes/app_router.dart` | Navigation routes and guards |
| `pubspec.yaml` | Dependencies and project config |
| `firebase.json` | Firebase configuration mapping |
| `analysis_options.yaml` | Dart linter rules |
