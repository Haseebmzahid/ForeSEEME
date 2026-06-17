# Frontend Architecture: ForeSeeMe

## Frontend Technology Stack

| Component | Library | Version | Purpose |
|-----------|---------|---------|---------|
| **UI Framework** | Flutter | 3.10+ | Cross-platform UI |
| **Language** | Dart | 3.10+ | Programming language |
| **State Management** | Flutter Riverpod | 3.3.1 | Reactive state, dependency injection |
| **Routing** | Go Router | 17.2.3 | Type-safe navigation with auth guards |
| **Icons** | Cupertino Icons | 1.0.8 | iOS-style icons (Material also available) |
| **Typography** | Google Fonts | 8.1.0 | Scalable typography |
| **Notifications** | Flutter Local Notifications | 21.0.0 | Local push notifications |

## Component Structure

### Core Reusable Widgets

Located in `lib/core/widgets/`:

| Widget | File | Purpose |
|--------|------|---------|
| **AppButton** | `app_button.dart` | Primary gradient button (teal theme) |
| **AppTextField** | `app_text_field.dart` | Stylized input field with validation |
| **EmptyStateWidget** | `empty_state_widget.dart` | Show when no data available |
| **SectionHeader** | `section_header.dart` | Section title with icon |
| **StatusBadge** | `status_badge.dart` | Adherence status indicator (Taken/Skipped/Pending) |

### Feature Screens

#### Authentication Feature (`features/auth/`)

**Screens:**
- **LoginScreen**: Email/password + Google sign-in
- **RegisterScreen**: New account creation
- **ForgotPasswordScreen**: Password reset flow

**Shared Widgets:**
- **AuthTextField**: Email/password input with validation
- **GradientButton**: Branded authentication button

**Key Features:**
- Fade-in animations on load
- Separate loading indicators per button
- Error display via SnackBar
- Form validation before submission
- Google sign-in with OAuth flow

#### Health Profile Feature (`features/health_profile/`)

**Screens:**
- **HealthProfileScreen**: 
  - Setup mode: Initial profile during onboarding
  - Edit mode: Modify profile from settings
  - City selection dropdown
  - Chronic conditions multi-select

**Form Validation:**
- City is required
- At least one condition required

**Navigation:**
- Setup mode → navigates to `/home`
- Edit mode → pops back to previous screen

#### Medication Feature (`features/medication/`)

**Screens:**
- **AddMedicationScreen**: Create new medication
- **DailyCheckInScreen**: Daily adherence tracking (PRIMARY UI)
- (Edit medication screen - Not Yet Implemented)

**Key Component: DailyCheckInScreen**

The main medication interface with:

1. **Date Navigation** (DateNavigationBar)
   - Horizontal scroll of date chips
   - Shows past 7 days + today + future 5 days (15 total)
   - Current date auto-centered
   - Tap to select different date

2. **Medication List** (GroupedMedicationList)
   - Grouped by time of day (Morning/Afternoon/Evening)
   - One MedicationCardWidget per dose

3. **Dose Card** (MedicationCardWidget)
   - Medication name + dosage
   - Reminder time
   - Current status badge
   - Action buttons (Taken/Skipped) - disabled for past dates
   - Only pending/upcoming doses are interactive

4. **Empty State**
   - Shows when no medications exist
   - Encourages user to add medication

## Routing Structure

### Route Configuration

File: `lib/core/routes/app_router.dart`

```dart
GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: authNotifier,  // Re-evaluate on auth state change
  redirect: (context, state) { ... },  // Auth guard logic
  routes: [
    GoRoute(path: '/', builder: ...),
    GoRoute(path: '/login', builder: ...),
    GoRoute(path: '/register', builder: ...),
    GoRoute(path: '/forgot-password', builder: ...),
    GoRoute(path: '/health-profile', builder: ...),
    GoRoute(path: '/home', builder: ...),
    GoRoute(path: '/add-medication', builder: ...),
    GoRoute(path: '/check-in', builder: ...),
  ],
)
```

### Navigation Patterns

**Programmatic Navigation:**
```dart
// Push screen
context.push('/health-profile');

// Navigate with replacement (after login)
context.go('/home');

// Pass extra data
context.push('/health-profile', extra: {'isEditMode': true});

// Back navigation
context.pop();
```

**Route Guards:**
- Unauthenticated users blocked from protected routes
- Authenticated users blocked from auth routes
- Loading state prevents premature redirects

## Design System

### Color Palette

File: `lib/core/theme/app_theme.dart`

**Primary Colors:**
- `primary`: #006D77 (Deep medical teal)
- `primaryDark`: #004D55 (Darker teal for contrast)
- `accent`: #83C5BE (Lighter teal, secondary)

**Status Colors:**
- `success`: #2A9D8F (Green - medication taken)
- `pending`: #F4A261 (Orange - awaiting action)
- `error`: #E63946 (Red - error/skipped)

**Neutral Colors:**
- `background`: #F7F9FC (Off-white, page background)
- `surface`: #FFFFFF (Pure white, card/surface)
- `surfaceElevated`: #F1F5F9 (Slightly elevated surface)
- `border`: #E2E8F0 (Soft border, very light blue-gray)

**Text Colors:**
- `textPrimary`: #1E293B (Dark slate, main text)
- `textSecondary`: #64748B (Cool grey, secondary text)
- `textHint`: #94A3B8 (Light grey, hints/placeholders)

**Gradients:**
- `primaryGradient`: #006D77 → #83C5BE (Used for buttons)
- `backgroundGradient`: #E2ECE9 → #FFFFFF (Used for page backgrounds)

### Typography

**Font Family:**
- Primary: Google Fonts (configurable, responsive)
- Fallback: System fonts (Roboto for Android, SF Pro for iOS)

**Text Styles:**
- Headline: Large, bold (24-32pt)
- Body: Regular, readable (16pt)
- Caption: Small, subtle (12-14pt)
- Button: Medium, semi-bold (14-16pt)

### Spacing & Dimensions

File: `lib/core/theme/app_theme.dart`

**Spacing Scale (8pt grid):**
- `small`: 8px
- `medium`: 16px
- `large`: 24px
- `extraLarge`: 32px

**Border Radius:**
- Default: 12px (components)
- Large: 16px (cards)
- Extra: 20px (rounded buttons)

### Shadows

**Premium Shadow System:**
```dart
premiumShadow = [
  BoxShadow(offset: 0,4, blur: 16, opacity: 0.04),
  BoxShadow(offset: 0,2, blur: 4, opacity: 0.02),
]
```

Used for:
- Card elevation
- Modal depth
- Button states

## Responsive Design Strategy

### Breakpoints (Not Explicitly Defined - Needs Update)

**Current Approach:**
- Mobile-first (single column, full width)
- Tablet scaling (MediaQuery for larger screens)
- Landscape orientation support

**Future Implementation:**
```dart
// Define breakpoints
const kMobileWidth = 480.0;
const kTabletWidth = 768.0;
const kDesktopWidth = 1024.0;

// Use in layout
if (MediaQuery.of(context).size.width > kTabletWidth) {
  // Tablet layout
} else {
  // Mobile layout
}
```

### Responsive Widgets

- **DateNavigationBar**: Horizontal scroll adapts to screen width
- **MedicationCardWidget**: Fixed width, scroll in mobile
- **FormFields**: Full-width on mobile, constrained on tablet

## Dark Mode Strategy

**Current Status:** Light theme only

**Future Implementation:**
```dart
// In main.dart
theme: AppTheme.lightTheme,
darkTheme: AppTheme.darkTheme,  // Not yet implemented
themeMode: ThemeMode.system,    // Follow device preference
```

**Design System for Dark Mode:**
- Same brand colors (teal remains primary)
- Inverted text colors
- Surfaces: dark gray instead of white
- Maintain contrast ratios (WCAG AA minimum)

## Animation Strategy

### Used Animations

1. **Fade-in on Load** (LoginScreen, HealthProfileScreen)
   ```dart
   AnimationController(duration: 600ms, vsync: this)..forward();
   CurvedAnimation(curve: Curves.easeOut);
   ```
   - Smooth entry visual
   - Improves perceived performance

2. **Date Chip Selection** (DateNavigationBar)
   - Scale animation on tap
   - Color transition

3. **Button Loading State**
   - Spinner overlay while submitting
   - Disabled state during request

### Animation Principles
- Duration: 300-600ms (quick, snappy)
- Curves: easeOut (most common), easeInOut (transitions)
- Avoid excessive motion (respect accessibility)

## Accessibility Considerations

### Implemented
- High contrast ratios (WCAG AA)
- Text size responsive via MediaQuery
- Touch targets minimum 48x48dp
- Semantic labels on buttons

### Future Work
- Semantic widgets (Semantics, MergeSemantics)
- Screen reader optimization
- Keyboard navigation support
- Reduced motion support

## Frontend Conventions

### File Organization

```
feature/
├── data/
├── domain/
├── presentation/
│   ├── feature_name_screen.dart      # Main screen
│   ├── feature_name_notifier.dart    # State mutations
│   ├── feature_name_providers.dart   # Riverpod setup
│   ├── feature_name_state.dart       # State classes
│   └── widgets/
│       ├── component_widget.dart
│       └── another_component.dart
```

### Widget Naming

- **Screens**: `{Feature}Screen` (e.g., `LoginScreen`, `DailyCheckInScreen`)
- **Components**: `{Purpose}Widget` (e.g., `MedicationCardWidget`, `DateNavigationBar`)
- **Notifiers**: `{Feature}Notifier` (e.g., `AuthNotifier`, `AdherenceNotifier`)
- **Providers**: `{feature}Provider` (e.g., `authRepositoryProvider`, `adherenceNotifierProvider`)

### Riverpod Conventions

```dart
// Repositories
final featureRepositoryProvider = Provider<Repository>(...);

// Streams (real-time data)
final dataStreamProvider = StreamProvider<List<Model>>(...);

// State notifiers
final notifierProvider = NotifierProvider<Notifier, State>(...);

// Async operations
final asyncProvider = AsyncNotifierProvider<Notifier, Result>(...);

// Family (parameterized)
final parameterizedProvider = StreamProvider.family<Data, Param>(...);
```

### Component Best Practices

1. **Use ConsumerWidget for reactive components**
   ```dart
   class MyWidget extends ConsumerWidget {
     @override
     Widget build(BuildContext context, WidgetRef ref) {
       final data = ref.watch(provider);
       return ...;
     }
   }
   ```

2. **Use ConsumerStatefulWidget when local state needed**
   ```dart
   class MyStatefulWidget extends ConsumerStatefulWidget {
     @override
     ConsumerState<MyStatefulWidget> createState() => _MyWidgetState();
   }
   ```

3. **Prefer ref.watch() over ref.read()**
   - watch: reactive, rebuilds on change
   - read: one-time access (callbacks, init)

4. **Clean up resources in dispose()**
   ```dart
   @override
   void dispose() {
     scrollController.dispose();
     super.dispose();
   }
   ```

## Performance Optimization

### Current State
- Simple list rendering (no virtualization)
- No image caching strategy
- Firebase real-time sync on all screens

### Optimization Opportunities

1. **List Performance**
   - Use ListView with `shrinkWrap: false` for better memory
   - Implement `ExtendedListView` for large medication counts
   - Add `addAutomaticKeepAlives: true` to maintain scroll position

2. **Rebuild Optimization**
   - Selector pattern for specific provider properties
   - `select()` to watch only needed fields
   - Avoid ref.watch entire objects

3. **Image Handling**
   - Add image caching strategy for user photos
   - Placeholder images during load

Example Selector Usage:
```dart
// Instead of watching entire user
final user = ref.watch(userProvider);  // Rebuilds on any user change

// Watch only what's needed
final email = ref.watch(userProvider.select((u) => u.email));  // Rebuilds only on email change
```

## Known UI/UX Issues

1. **Date navigation auto-scroll**: May not work on first load (WidgetsBinding timing)
2. **Past date medication state**: Display-only, but UI could be clearer
3. **Empty state**: Generic text, should be more contextual
4. **Loading states**: Some screens lack loading indicators
5. **Error recovery**: No retry mechanism in error messages

## Future UI Enhancements

- [ ] Add medication edit screen
- [ ] Implement home dashboard with adherence summary
- [ ] Add medication history/calendar view
- [ ] Implement settings screen (profile, notifications, logout)
- [ ] Add share adherence reports feature
- [ ] Implement dark mode
- [ ] Add custom notification sounds
- [ ] Add haptic feedback on dose tracking
