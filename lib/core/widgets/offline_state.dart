import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';

/// Is [error] a genuine **connectivity loss** — as opposed to a server error, a
/// permission denial, or empty data?
///
/// Detection is signature-based on the error's string form and deliberately NOT
/// typed against `firebase_*` / `http` / `dart:io`: GOLDEN_RULES §1 bars the
/// presentation layer from importing those SDKs. Feature screens that already
/// hold a typed transport exception (e.g. resources' `PlacesNetworkException`)
/// should route straight to [OfflineState] and skip this helper.
///
/// Pure presentation — it only classifies an error object the providers already
/// surface; it performs no I/O and changes no business logic.
bool isOfflineError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('connection refused') ||
      s.contains('network-request-failed') || // firebase_auth while offline
      s.contains('network error') ||
      s.contains('unavailable') || // cloud_firestore: client can't reach backend
      s.contains('timeoutexception');
}

/// Shared "No Internet Connection" surface for network-dependent screens.
///
/// One offline language across the app (Design System v2): a calm, branded panel
/// with an offline glyph, a fixed headline, a helpful explanation, and a Retry
/// button wired to the caller's existing provider refresh — replacing the
/// per-screen bespoke offline layouts.
///
/// * **Branding** — the ForeSeeMe mark sits above the offline glyph.
/// * **Theme-aware** — adapts text/glyph tints to the ambient brightness and
///   picks the white/black mark accordingly. The Sprint-3 hosts are dark shell,
///   but this stays legible on a light surface too.
/// * **Accessible** — the headline is a semantic header; the explanation reads as
///   text; Retry is a labelled button. Decorative art is excluded from semantics.
/// * **Reduced-motion** — a gentle fade-in that collapses to an instant show when
///   the platform requests reduced motion.
///
/// This is a pure presentation primitive: no providers, repositories, or I/O.
/// [onRetry] must invoke the screen's existing refresh (e.g. `ref.invalidate`).
class OfflineState extends StatelessWidget {
  /// Runs the caller's existing provider refresh. Presentation only.
  final VoidCallback onRetry;

  /// Optional override for the explanation line.
  final String? message;

  const OfflineState({super.key, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final titleColor =
        isDark ? AppColorsV2.textPrimary : const Color(0xFF0B1730);
    final bodyColor =
        isDark ? AppColorsV2.textSecondary : const Color(0xFF5A6478);
    final glyph = isDark ? Colors.white : const Color(0xFF0B1730);

    final explanation = message ??
        'We can’t reach ForeSeeMe right now. Check your Wi‑Fi or '
            'mobile data, then try again.';

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ForeSeeMe mark (theme-aware) + offline glyph — decorative.
        ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                isDark
                    ? 'assets/branding/logo/foreseeme-icon-white.svg'
                    : 'assets/branding/logo/foreseeme-icon-black.svg',
                width: 40,
                height: 40,
              ),
              const SizedBox(height: 22),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glyph.withValues(alpha: isDark ? 0.06 : 0.05),
                  border: Border.all(
                    color: glyph.withValues(alpha: isDark ? 0.14 : 0.12),
                  ),
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 38,
                  color: glyph.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Semantics(
          header: true,
          child: Text(
            'No Internet Connection',
            textAlign: TextAlign.center,
            style: AppTextStylesV2.headline.copyWith(
              color: titleColor,
              fontSize: 22,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          explanation,
          textAlign: TextAlign.center,
          style: AppTextStylesV2.body.copyWith(color: bodyColor),
        ),
        const SizedBox(height: 24),
        // Retry — runs the caller's existing provider refresh.
        OutlinedButton.icon(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColorsV2.teal,
            side: BorderSide(color: AppColorsV2.teal.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );

    // Gentle fade-in, dropped under reduced motion.
    final Widget body = reduceMotion
        ? content
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: content,
          );

    return Center(
      child: Padding(padding: const EdgeInsets.all(32), child: body),
    );
  }
}
