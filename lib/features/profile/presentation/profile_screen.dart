import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/theme_provider.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/admin_mfa_enrollment.dart';
import 'package:fyp_foreseeme/features/alerts/presentation/alerts_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/health_profile/domain/services/profile_completeness_service.dart';
import 'package:fyp_foreseeme/features/health_profile/presentation/health_profile_providers.dart';

import 'profile_hub_providers.dart';
import 'widgets/profile_hub_chrome.dart';
import 'widgets/profile_hub_hero.dart';
import 'widgets/profile_hub_style.dart';

/// The **Profile Hub** — the app's profile tab, implemented natively from the
/// approved prototype (`docs/Design/ForeSeeMe Profile Hub (1).html`).
///
/// Composition only: every value on screen comes from an existing provider, and
/// every visual token from [ProfileHubTheme], which transcribes the prototype's
/// own `THEMES` map. The screen touches no repository and no Firebase SDK
/// (Golden Rule 1).
///
/// **Deliberate departures from the prototype**, all recorded here so the
/// difference is a decision rather than a drift:
///
///  * The prototype's mock status bar (`9:41`, `LTE`, a battery) is dropped. It
///    is prototype furniture standing in for the real OS status bar, and
///    drawing a fake `9:41` in a shipping app would be fabricated information.
///  * The prototype's own bottom navigation is dropped in favour of the app's
///    existing `AppShell` / `AppBottomNavBar`, which this screen must not
///    redesign. The scroll padding still reserves the prototype's 130px so the
///    last card clears the bar by the same margin.
///  * Cards the app has nowhere to send the user to (Reminders, Privacy, About)
///    are rendered without press feedback or button semantics. The prototype
///    marks them `cursor: pointer`, but a card that visibly depresses and then
///    does nothing is worse than one that plainly does not invite a tap. These
///    were already dead in the previous screen; no destination was invented.
///  * Sign-out is not in the prototype, which stops at the admin slab. It is
///    kept because removing it would strand the user, and it is built from the
///    prototype's own slab material rather than a foreign control.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Version string for the About card.
  ///
  /// Mirrors `pubspec.yaml`'s `version:` field. Reading the real build would
  /// need `package_info_plus`, which the project's dependency policy does not
  /// allow, so the value is stated here instead. **Keep in step with pubspec.**
  static const String _appVersion = 'v1.0.0 · BUILD 1';

  final ScrollController _scroll = ScrollController();

  bool _expanded = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final user = ref.watch(authStateProvider).value;
    final completeness = ref.watch(profileCompletenessProvider);
    final hasProfile = ref.watch(profileExistsProvider).value ?? false;

    final percent = completeness.value?.percent;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'Your profile';

    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          _Backdrop(scroll: _scroll),
          SafeArea(
            bottom: false,
            child: ListView(
              controller: _scroll,
              // The prototype's `padding: 46px 18px 130px`. The 46px top is its
              // status-bar allowance, which SafeArea now provides, so the top
              // inset drops to the 4px margin the hero carries itself.
              //
              // The 18px side inset is applied per child rather than on the
              // list, because the hero cancels it (`margin: 0 -18px`) to span
              // the full width.
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 130),
              children: [
                _HeroSection(
                  scroll: _scroll,
                  percent: percent ?? 0,
                  photoUrl: user?.photoUrl,
                  initial: _initialOf(name, user?.email),
                  isReady: hasProfile,
                ),
                _inset(_NameBlock(name: name)),
                const SizedBox(height: 20),
                _inset(_ThemeRow()),
                const SizedBox(height: 14),
                _inset(
                  _HealthProfileCard(
                    completeness: completeness,
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                    onOpen: () => context.push(
                      '/health-profile',
                      extra: {'isEditMode': true},
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _inset(const _AlertsRow()),
                const SizedBox(height: 12),
                _inset(const _PrivacyCard()),
                const SizedBox(height: 12),
                _inset(_SupportRow(version: _appVersion)),
                if (ref.watch(isAdminProvider).value ?? false) ...[
                  const SizedBox(height: 12),
                  _inset(
                    _AdminSlab(onTap: () => context.push('/admin/dashboard')),
                  ),
                ],
                if (ref.watch(isAdminProvider).error case FirebaseException(
                  code: 'mfa-required',
                )) ...[
                  const SizedBox(height: 12),
                  _inset(
                    ListTile(
                      title: const Text('Set up administrator MFA'),
                      leading: const Icon(Icons.security),
                      onTap: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const AdminMfaEnrollment(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _inset(
                  _SignOutSlab(
                    onTap: () =>
                        ref.read(authNotifierProvider.notifier).signOut(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The prototype's 18px gutter.
  static Widget _inset(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: child);

  /// The glyph shown when the user has no photo: their initial, falling back to
  /// the email's, then to a neutral mark. Never a fabricated name.
  static String _initialOf(String name, String? email) {
    final source = name.trim().isNotEmpty && name != 'Your profile'
        ? name
        : (email ?? '');
    final first = source.trim();
    return first.isEmpty ? '·' : first.characters.first.toUpperCase();
  }
}

// ── Backdrop ─────────────────────────────────────────────────────────────────

/// The three ambient layers behind the content: the teal aurora (which parallax
/// -shifts with scroll), a cool orb in the lower left, and the receding
/// perspective floor grid.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            children: [
              // `top: -18%; height: 620px`, drifting at 0.12× scroll.
              AnimatedBuilder(
                animation: scroll,
                builder: (context, child) {
                  final y = scroll.hasClients ? scroll.offset : 0.0;
                  return Positioned(
                    left: -MediaQuery.sizeOf(context).width * 0.2,
                    right: -MediaQuery.sizeOf(context).width * 0.2,
                    top: -MediaQuery.sizeOf(context).height * 0.18 + y * 0.12,
                    height: 620,
                    child: child!,
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: theme.auroraFill),
                ),
              ),
              Positioned(
                left: -MediaQuery.sizeOf(context).width * 0.3,
                bottom: -MediaQuery.sizeOf(context).height * 0.1,
                width: 480,
                height: 420,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: theme.orbFill),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: -40,
                height: 300,
                child: CustomPaint(
                  painter: _FloorGridPainter(line: theme.line),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's floor: a 46px grid under
/// `transform: perspective(240px) rotateX(74deg)` with `transform-origin:
/// bottom center`, faded out toward the top by a mask.
///
/// Painted directly rather than transformed, because a projected grid is a few
/// lines of geometry and a `Transform` with that much foreshortening resamples
/// hairlines into mush.
class _FloorGridPainter extends CustomPainter {
  const _FloorGridPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    // The projection of a plane tilted 74° under a 240px perspective: depth d
    // maps to a screen height that falls off hyperbolically toward the horizon.
    double screenY(double depth) => h * (1 - 1 / (1 + depth * 3.2));

    for (var i = 0; i <= 14; i++) {
      final depth = i / 14;
      final y = screenY(depth);
      if (y >= h) continue;
      // The mask: opaque at the bottom, transparent at the top.
      final fade = (1 - depth).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = line.withValues(alpha: line.a * fade * 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, y), Offset(w, y), paint);
    }

    // Verticals converge on the vanishing point directly above centre.
    for (var i = -9; i <= 9; i++) {
      final xAtBase = centerX + i * 46.0;
      final paint = Paint()
        ..color = line.withValues(alpha: line.a * 0.5)
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            line.withValues(alpha: line.a * 0.5),
            line.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      canvas.drawLine(
        Offset(xAtBase, h),
        // Converging toward the vanishing point.
        Offset(centerX + i * 46.0 * 0.06, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloorGridPainter old) => old.line != line;
}

// ── Hero ─────────────────────────────────────────────────────────────────────

/// Wraps [ProfileHubHero] in the prototype's scroll response:
/// `translateY(y·0.28)`, `scale(max(0.86, 1 − y·0.0005))`,
/// `opacity(max(0, 1 − y/240))`.
class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.scroll,
    required this.percent,
    required this.photoUrl,
    required this.initial,
    required this.isReady,
  });

  final ScrollController scroll;
  final int percent;
  final String? photoUrl;
  final String initial;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final hero = ProfileHubHero(
      percent: percent,
      photoUrl: photoUrl,
      initial: initial,
      isReady: isReady,
    );

    if (AppMotion.reduceMotion(context)) return hero;

    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final y = scroll.hasClients ? scroll.offset : 0.0;
        final opacity = (1 - y / 240).clamp(0.0, 1.0);
        final scale = (1 - y * 0.0005).clamp(0.86, 1.0);

        return SizedBox(
          height: ProfileHubHero.height,
          // Fully faded: drop the subtree entirely, which also parks every
          // ambient loop inside it.
          child: opacity == 0
              ? null
              : Transform.translate(
                  offset: Offset(0, y * 0.28),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                ),
        );
      },
      child: hero,
    );
  }
}

class _NameBlock extends StatelessWidget {
  const _NameBlock({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Transform.translate(
      // `margin-top: -6px`.
      offset: const Offset(0, -6),
      child: Column(
        children: [
          Semantics(
            header: true,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: hubSans(
                context,
                size: 27,
                em: -0.03,
                color: theme.txt,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Your health system is under your control',
            textAlign: TextAlign.center,
            style: hubSans(context, size: 13, color: theme.txt2),
          ),
        ],
      ),
    );
  }
}

// ── Theme switcher ───────────────────────────────────────────────────────────

class _ThemeRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Matches the previous screen's reading of the active mode: `system`
    // resolves through the platform brightness, so the knob always reflects
    // what the user is actually looking at.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return HubThemeSwitch(
      isDarkSelected: isDark,
      onDark: () => ref
          .read(themeNotifierProvider.notifier)
          .setThemeMode(ThemeMode.dark),
      onLight: () => ref
          .read(themeNotifierProvider.notifier)
          .setThemeMode(ThemeMode.light),
    );
  }
}

// ── Health Profile ───────────────────────────────────────────────────────────

class _HealthProfileCard extends StatelessWidget {
  const _HealthProfileCard({
    required this.completeness,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final AsyncValue<ProfileCompleteness> completeness;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);
    final reduceMotion = AppMotion.reduceMotion(context);
    final value = completeness.value;
    final percent = value?.percent;

    return HubSlab(
      radius: 24,
      padding: const EdgeInsets.all(18),
      pressedScale: 0.986,
      blur: 20,
      saturate: true,
      underlay: const HubCornerBloom(),
      onTap: onToggle,
      semanticLabel: percent == null
          ? 'Health profile, your medical history'
          : 'Health profile, your medical history, $percent percent complete',
      semanticHint: expanded ? 'Collapse details' : 'Show details',
      expanded: expanded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HubProfileGlyph(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Profile',
                      style: hubSans(
                        context,
                        size: 18,
                        em: -0.02,
                        color: theme.txt,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your medical history',
                      style: hubSans(
                        context,
                        size: 13,
                        color: theme.txt2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    // Honest while the read is in flight or has failed:
                    // an em dash rather than a stand-in number.
                    percent == null ? '—' : '$percent%',
                    style: hubMono(
                      context,
                      size: 15,
                      color: theme.accent,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  HubChevron(expanded: expanded),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          HubProgressBar(percent: percent ?? 0),
          // `.35s` matches the chevron, so the card opens as one movement.
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 350),
            curve: const Cubic(0.2, 0.8, 0.2, 1),
            alignment: Alignment.topCenter,
            child: expanded
                ? _Breakdown(
                    completeness: completeness,
                    onOpen: onOpen,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.completeness, required this.onOpen});

  final AsyncValue<ProfileCompleteness> completeness;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.only(top: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.line)),
        ),
        child: completeness.when(
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final component in value.components) ...[
                HubBreakdownRow(
                  label: component.label,
                  percent: component.percent,
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 2),
              // The prototype's footer, made a real target so the instruction
              // it gives is one the user can actually follow.
              Semantics(
                button: true,
                label: 'Open full health profile',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: SizedBox(
                    height: 32,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'TAP TO OPEN FULL PROFILE',
                        style: hubMono(
                          context,
                          size: 10,
                          em: 0.14,
                          color: theme.txt2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'READING PROFILE…',
              style: hubMono(context, size: 10, em: 0.14, color: theme.txt2),
            ),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'PROFILE UNAVAILABLE · PULL TO RETRY',
              style: hubMono(context, size: 10, em: 0.14, color: theme.txt2),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notifications + Reminders ────────────────────────────────────────────────

class _AlertsRow extends ConsumerWidget {
  const _AlertsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ProfileHubTheme.of(context);
    final preferences = ref.watch(notificationPreferencesControllerProvider);
    final active = preferences.value == null
        ? null
        : notificationsActive(preferences.value!);
    final nextReminder = ref.watch(nextReminderTimeProvider).value;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: HubSlab(
              onTap: () => context.push('/notifications/settings'),
              semanticLabel: 'Notifications, alerts and sounds',
              semanticHint: 'Opens notification settings',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HubEqualizer(animate: active ?? false),
                      const Spacer(),
                      // The 48dp target overhangs into the card's own padding
                      // so the 42×24 pill still lands flush with the content
                      // box's top-right corner, where the prototype puts it.
                      // (48−42)/2 = 3 horizontally, (48−24)/2 = 12 vertically.
                      Transform.translate(
                        offset: const Offset(3, -12),
                        child: HubSwitch(
                          value: active ?? false,
                          semanticLabel: 'Risk alerts',
                          onChanged: active == null
                              ? null
                              : (value) => setNotificationsActive(ref, value),
                        ),
                      ),
                    ],
                  ),
                  const _CardTitle(
                    title: 'Notifications',
                    subtitle: 'Alerts & sounds',
                  ),
                  const SizedBox(height: 10),
                  HubStateLine(
                    label: active == null ? '—' : (active ? 'ACTIVE' : 'MUTED'),
                    color: (active ?? false) ? theme.accent : theme.txt2,
                    animateSwap: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: HubSlab(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HubReminderTimeline(animate: nextReminder != null),
                  const _CardTitle(
                    title: 'Reminders',
                    subtitle: 'Medication & check-ups',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    // Real: the next reminder the user has configured, or an
                    // honest empty state when they have configured none.
                    nextReminder == null
                        ? 'NONE SCHEDULED'
                        : 'NEXT · $nextReminder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hubMono(
                      context,
                      size: 10,
                      em: 0.14,
                      color: theme.txt,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The `15px / 12px` title + subtitle pair shared by the grid cards.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          style: hubSans(
            context,
            size: 15,
            em: -0.01,
            color: theme.txt,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: hubSans(context, size: 12, color: theme.txt2)),
      ],
    );
  }
}

// ── Privacy ──────────────────────────────────────────────────────────────────

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return HubSlab(
      padding: const EdgeInsets.all(16),
      pressedScale: 0.986,
      child: Row(
        children: [
          const HubPrivacyGlyph(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy',
                  style: hubSans(
                    context,
                    size: 16,
                    em: -0.01,
                    color: theme.txt,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Data & permissions',
                  style: hubSans(context, size: 12.5, color: theme.txt2),
                ),
                const SizedBox(height: 9),
                const HubSegments(lit: 2),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const HubAccentPill(label: 'SECURED'),
        ],
      ),
    );
  }
}

// ── Help + About ─────────────────────────────────────────────────────────────

class _SupportRow extends StatelessWidget {
  const _SupportRow({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `grid-template-columns: 1.25fr 1fr`.
          Expanded(
            flex: 125,
            child: HubSlab(
              // The prototype's "OPEN PORTAL →" leads to guides and FAQs,
              // which is precisely the app's existing Resource Center.
              onTap: () => context.push('/resources'),
              semanticLabel: 'Help Center, guides, FAQs and support',
              // The travelling hairline rides the card's top edge, clipped to
              // its corner radius.
              underlay: const HubSweepLine(animate: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '?',
                            style: hubSans(
                              context,
                              size: 14,
                              color: theme.accent,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Help Center',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hubSans(
                            context,
                            size: 15,
                            em: -0.01,
                            color: theme.txt,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Guides, FAQs & support',
                    style: hubSans(context, size: 12, color: theme.txt2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'OPEN PORTAL →',
                    style: hubMono(
                      context,
                      size: 10,
                      em: 0.14,
                      color: theme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 100,
            child: HubSlab(
              quiet: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: theme.glass2,
                      border: Border.all(color: theme.line),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      Text(
                        'About',
                        style: hubSans(
                          context,
                          size: 15,
                          em: -0.01,
                          color: theme.txt,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        version,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hubMono(context, size: 11, color: theme.txt2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Admin ────────────────────────────────────────────────────────────────────

/// Operator-only. Shown when the signed-in user carries the admin claim;
/// Firestore rules enforce it server-side regardless.
class _AdminSlab extends StatelessWidget {
  const _AdminSlab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return HubSlab(
      radius: 12,
      padding: const EdgeInsets.all(16),
      pressedScale: 0.988,
      blur: 16,
      onTap: onTap,
      semanticLabel: 'Admin panel, system operations, restricted',
      underlay: const HubAdminOrnament(),
      child: Row(
        children: [
          const HubAdminGlyph(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ADMIN PANEL',
                  style: hubMono(
                    context,
                    size: 13,
                    em: 0.14,
                    color: theme.txt,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SYSTEM OPERATIONS · RESTRICTED',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: hubMono(
                    context,
                    size: 10,
                    em: 0.1,
                    color: theme.txt2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          HubStateLine(
            label: 'OPERATOR',
            color: theme.operatorInk,
            em: 0.12,
            pulse: true,
          ),
        ],
      ),
    );
  }
}

// ── Sign out ─────────────────────────────────────────────────────────────────

/// Not in the prototype — see the note on [ProfileScreen]. Built from the same
/// slab material so it reads as part of the hub rather than a bolted-on control.
class _SignOutSlab extends StatelessWidget {
  const _SignOutSlab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ProfileHubTheme.of(context);

    return HubSlab(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      pressedScale: 0.986,
      onTap: onTap,
      semanticLabel: 'Sign out',
      child: Center(
        child: Text(
          'SIGN OUT',
          style: hubMono(context, size: 11, em: 0.2, color: theme.txt2),
        ),
      ),
    );
  }
}
