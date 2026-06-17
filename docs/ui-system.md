# UI System: ForeSeeMe

## Design System Overview

ForeSeeMe follows a **premium medical aesthetic** with a teal color scheme designed to convey trust, health, and professionalism.

**Design Philosophy:**
- Clean, minimal, modern
- Accessibility-first (high contrast)
- Responsive across devices
- Premium feel (subtle shadows, refined typography)

## Color System

### Primary Brand Colors

```dart
// Teal family (medical context)
Color primary = Color(0xFF006D77)        // Deep teal (main CTA, headers)
Color primaryDark = Color(0xFF004D55)    // Darker teal (pressed states)
Color accent = Color(0xFF83C5BE)         // Light teal (secondary CTAs)
```

### Status Colors

```dart
Color success = Color(0xFF2A9D8F)        // Green (taken, confirmed)
Color pending = Color(0xFFF4A261)        // Orange (awaiting action)
Color error = Color(0xFFE63946)          // Red (error, skipped)
```

### Neutral Colors

```dart
Color background = Color(0xFFF7F9FC)     // Off-white (page background)
Color surface = Color(0xFFFFFFFF)        // White (cards, elevated)
Color surfaceElevated = Color(0xFFF1F5F9) // Slightly elevated
Color border = Color(0xFFE2E8F0)         // Light blue-gray borders
```

### Text Colors

```dart
Color textPrimary = Color(0xFF1E293B)    // Dark slate (headlines, body)
Color textSecondary = Color(0xFF64748B)  // Cool grey (secondary text)
Color textHint = Color(0xFF94A3B8)       // Light grey (hints, disabled)
```

### Gradients

```dart
// Primary gradient for buttons, headers
Gradient primaryGradient = LinearGradient(
  colors: [Color(0xFF006D77), Color(0xFF83C5BE)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)

// Background gradient
Gradient backgroundGradient = LinearGradient(
  colors: [Color(0xFFE2ECE9), Color(0xFFFFFFFF)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
)
```

## Spacing & Layout

### 8px Grid System

All spacing follows 8px increments for consistency:

```dart
// Spacing values
const double spacing_xs = 4.0;     // x-small (rarely used)
const double spacing_sm = 8.0;     // small
const double spacing_md = 16.0;    // medium (default)
const double spacing_lg = 24.0;    // large
const double spacing_xl = 32.0;    // extra large
const double spacing_xxl = 48.0;   // 2x large
```

### Safe Area Padding

```dart
// Typical screen padding
padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0)

// Cards within lists
padding: EdgeInsets.all(16.0)

// Form fields
padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0)
```

## Typography

### Font Family

- **Primary:** Google Fonts (configurable, responsive)
- **Fallback:** System default (Roboto on Android, SF Pro on iOS)

**Import:**
```dart
import 'package:google_fonts/google_fonts.dart';

// Usage
Text('Hello',
  style: GoogleFonts.poppins(  // or inter, montserrat, etc.
    fontSize: 16,
    fontWeight: FontWeight.w600,
  ),
)
```

### Text Styles

| Style | Size | Weight | Use Case |
|-------|------|--------|----------|
| **Headline1** | 32pt | Bold (800) | Screen titles |
| **Headline2** | 24pt | Bold (700) | Section headers |
| **Headline3** | 20pt | Semi-bold (600) | Card titles |
| **Body1** | 16pt | Regular (400) | Main text, paragraphs |
| **Body2** | 14pt | Regular (400) | Secondary text |
| **Button** | 16pt | Semi-bold (600) | CTA buttons |
| **Caption** | 12pt | Regular (400) | Hints, metadata |
| **Overline** | 12pt | Semi-bold (600) | Labels, chips |

### Line Height

```dart
// Default line height
height: 1.5  // 150% of font size (readable)

// Compact (lists, metadata)
height: 1.2  // 120% of font size

// Loose (long-form content)
height: 1.8  // 180% of font size
```

## Components

### Buttons

**Primary Button (Gradient)**
- Background: primaryGradient
- Text: White, semi-bold
- Padding: 16px horizontal, 12px vertical
- Border radius: 12px
- Shadow: premiumShadow

**Secondary Button**
- Background: transparent
- Border: 2px primary color
- Text: primary color, semi-bold
- Same padding/radius

**Icon Button**
- Background: transparent
- Icon: primary color (24px)
- Tap area: 48x48px (accessibility)

### Input Fields

**TextField**
- Background: white
- Border: 2px border color (default), 2px primary (focused)
- Corner radius: 12px
- Padding: 12px
- Hint text: textHint color
- Error state: red underline + error message

**Dropdown**
- Similar to TextField
- Chevron icon right-aligned
- Options list background: surface color
- Selected option: light primary background

### Cards

- Background: white (surface)
- Corner radius: 16px
- Shadow: premiumShadow
- Padding: 16px
- Border: 1px border color (optional subtle line)

### Status Badge

**Medication Adherence Statuses:**

| Status | Color | Icon | Text |
|--------|-------|------|------|
| **Taken** | success (green) | ✓ | "Taken" |
| **Skipped** | error (red) | ✗ | "Skipped" |
| **Pending** | pending (orange) | ? | "Pending" |

### List Items

- Height: 60-80px (touch target)
- Horizontal padding: 16px
- Vertical padding: 12px
- Divider: 1px border color
- Ripple effect on tap (Android)

## Responsive Design

### Breakpoints (Recommended)

```dart
// Screen size categories
const kMobileWidth = 480.0;    // Portrait phones
const kTabletWidth = 768.0;    // Tablets
const kDesktopWidth = 1024.0;  // Large tablets
```

### Mobile (480px and below)

- Full-width layout
- Single column
- Bottom sheets instead of dialogs
- Bottom navigation/tabs

### Tablet (768px+)

- Side-by-side layouts possible
- Wider content areas (max 600px)
- Split view navigation
- Larger tap targets

### Responsive Example

```dart
@override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isMobile = screenWidth < 768;

  return Row(
    children: [
      if (!isMobile)
        SizedBox(width: 300, child: NavigationRail(...)),
      Expanded(
        child: MainContent(),
      ),
    ],
  );
}
```

## Shadows & Elevation

### Premium Shadow System

```dart
// Used for cards, buttons, dialogs
static final List<BoxShadow> premiumShadow = [
  BoxShadow(
    color: const Color(0xFF0F172A).withOpacity(0.04),
    blurRadius: 16,
    offset: const Offset(0, 4),
  ),
  BoxShadow(
    color: const Color(0xFF0F172A).withOpacity(0.02),
    blurRadius: 4,
    offset: const Offset(0, 2),
  ),
];
```

### Elevation Levels

| Level | Use | Shadow |
|-------|-----|--------|
| **Elevation 1** | Cards, inputs | premiumShadow |
| **Elevation 2** | Buttons, FAB | premiumShadow + higher blur |
| **Elevation 3** | Dialogs, modals | Darkened background overlay |

## Dark Mode (Not Implemented)

### Future Implementation

When dark mode is added:

```dart
// In AppTheme
static final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: Color(0xFF1A9D8F),  // Brighter teal
  scaffoldBackgroundColor: Color(0xFF0F172A),  // Dark navy
  cardColor: Color(0xFF1E293B),  // Dark card
  // ... etc
);
```

**Color Adjustments for Dark Mode:**
- Primary: Remain teal (or slightly brighter)
- Background: Dark navy/charcoal
- Surface: Dark slate
- Text: White (primary), light gray (secondary)
- Borders: Dark gray (very subtle)
- Status colors: Remain same (have good contrast in dark)

## Icons

### Icon Set

Primary: **Material Icons** (built-in Flutter)

```dart
Icons.check              // Taken ✓
Icons.close              // Skipped ✗
Icons.schedule           // Pending/time
Icons.medical_services   // Medical context
Icons.calendar_today     // Date selection
Icons.notifications      // Notifications
Icons.person             // User profile
Icons.settings           // Settings
Icons.logout             // Sign out
```

### Icon Sizing

```dart
Icons.small = 16.0       // Metadata, secondary
Icons.normal = 24.0      // Buttons, list items (default)
Icons.large = 32.0       // Hero icons, large buttons
Icons.xlarge = 48.0      // Splash screen, hero elements
```

## Animations

### Standard Durations

```dart
Duration transition_short = Duration(milliseconds: 300);
Duration transition_default = Duration(milliseconds: 500);
Duration transition_long = Duration(milliseconds: 800);
```

### Common Animations

1. **Fade-in** (300ms, easeOut)
   - Screen entrance
   - Image load

2. **Slide-in** (400ms, easeOut)
   - Navigation transitions
   - List item appearance

3. **Scale** (300ms, easeInOut)
   - Button press feedback
   - Expanded/collapsed states

4. **Color transition** (300ms, easeInOut)
   - Status changes
   - Hover states

## Accessibility

### Color Contrast

Minimum **WCAG AA** compliance:
- Text on background: 4.5:1 ratio (normal text)
- UI components: 3:1 ratio (large text)
- Graphics: 3:1 ratio

**Example:** textPrimary (#1E293B) on background (#F7F9FC) = 14.5:1 ✓

### Touch Targets

- Minimum: 48x48dp (Material Design)
- Comfortable: 56-64dp
- Buttons, chips, icons meet minimum

### Text Sizing

- Minimum: 12sp (captions only)
- Standard: 14-16sp (body text)
- Large: 18-24sp (headlines)
- Responsive: Scale with device size via `MediaQuery.textScaleFactor`

### Semantic Labels

```dart
// Always label interactive elements
Semantics(
  label: 'Mark medication as taken',
  button: true,
  enabled: true,
  child: IconButton(
    onPressed: () => {},
    icon: Icon(Icons.check),
  ),
)
```

## UI Conventions

### Screen Structure

```dart
Scaffold(
  appBar: AppBar(...),           // Title + back button
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        FormField1(),
        SizedBox(height: 16),
        FormField2(),
        SizedBox(height: 24),    // Larger space before button
        PrimaryButton(...)
      ],
    ),
  ),
)
```

### Form Design

```dart
// Inputs stack vertically with consistent spacing
Column(
  children: [
    TextFormField(
      decoration: InputDecoration(
        labelText: 'Email',
        hintText: 'Enter your email',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    SizedBox(height: 16),
    TextFormField(...)
  ],
)
```

### Loading States

- **Progress Indicator**: Centered, circular, primary color
- **Skeleton Loading**: Gray placeholder shapes
- **Disabled Buttons**: Lower opacity (0.5), not interactive

### Empty States

```dart
// When no data available
Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.inbox, size: 64, color: Colors.grey),
      SizedBox(height: 16),
      Text('No medications', style: headlineStyle),
      SizedBox(height: 8),
      Text('Add your first medication to get started'),
    ],
  ),
)
```

## Known UI Issues

1. **Date chip auto-scroll timing** - May not center properly on first load
2. **Medication card overflow** - Text can overflow on small screens
3. **Empty state text** - Generic, not contextual to screen
4. **Loading indicators** - Missing from some async operations
5. **Error recovery** - No retry button in error messages
6. **Keyboard handling** - May cover form fields on small screens

## Future UI Enhancements

- [ ] Implement dark mode
- [ ] Add haptic feedback
- [ ] Smooth page transitions
- [ ] Skeleton loaders for lists
- [ ] Pull-to-refresh on medication list
- [ ] Swipe actions (delete, edit)
- [ ] Custom animations for status changes
- [ ] Microinteractions (button ripple, toast)
- [ ] Neumorphic design elements (optional)
