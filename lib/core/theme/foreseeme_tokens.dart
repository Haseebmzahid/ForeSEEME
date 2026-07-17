import 'package:flutter/widgets.dart';

// ForeSeeMe premium design-system — primitive, colour-free tokens.
//
// These are the non-colour foundations (radius, elevation, spacing) that the
// ForeSeeMeTheme and its component themes are assembled from. Keeping them here
// — separate from the colour palette — means there is exactly one place to tune
// shape/rhythm, and the theme builder never hard-codes a magic number.
//
// This is the app's one spacing/radius/elevation system — every screen reads
// these tokens; there is no other set to migrate off of.

/// Corner-radius scale. `full` is an effectively-pill radius for chips/FABs.
class ForeSeeMeRadius {
  ForeSeeMeRadius._();

  static const double none = 0.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 28.0;
  static const double xxl = 36.0;
  static const double full = 999.0;

  static const Radius rxs = Radius.circular(xs);
  static const Radius rsm = Radius.circular(sm);
  static const Radius rmd = Radius.circular(md);
  static const Radius rlg = Radius.circular(lg);
  static const Radius rxl = Radius.circular(xl);

  static const BorderRadius card = BorderRadius.all(rlg);
  static const BorderRadius control = BorderRadius.all(rsm);
  static const BorderRadius input = BorderRadius.all(rsm);
  static const BorderRadius sheet = BorderRadius.vertical(top: rxl);
}

/// Elevation scale — numeric Material elevation *levels* (dp). The matching
/// [BoxShadow] recipes live in `ForeSeeMeShadows` (they need a palette colour).
class ForeSeeMeElevation {
  ForeSeeMeElevation._();

  static const double level0 = 0.0;
  static const double level1 = 1.0;
  static const double level2 = 3.0;
  static const double level3 = 6.0;
  static const double level4 = 8.0;
  static const double level5 = 12.0;
}

/// Spacing scale (4-pt base grid). Used for padding, gaps and insets.
class ForeSeeMeSpacing {
  ForeSeeMeSpacing._();

  static const double none = 0.0;
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 40.0;

  /// The app's default horizontal gutter for screen content.
  static const double gutter = 20.0;
}

/// Border / stroke widths used across the system.
class ForeSeeMeBorderWidth {
  ForeSeeMeBorderWidth._();

  static const double hairline = 0.8;
  static const double thin = 1.0;
  static const double thick = 1.5;
  static const double focus = 2.0;
}
