import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fyp_foreseeme/core/theme/theme_provider.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/core/widgets/medical_disclaimer.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resource_field_state.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/services/hospital_actions.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_chrome.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_field.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_sheets.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_center_style.dart';
import 'package:fyp_foreseeme/features/risk/presentation/risk_provider.dart';

/// The **Resource Center**, implemented natively from the approved prototype
/// (`docs/Design/ForeSeeMe Resource Center.html`).
///
/// Composition only: every value on screen comes from providers that already
/// existed — the article catalogue ([resourceArticlesAsyncProvider]), the
/// context-aware topic order ([resourceTopicOrderProvider]), the current risk
/// estimate ([currentCityRiskProvider]), the emergency contact, the Places
/// lookup ([nearbyHospitalsProvider]) and the shared launcher. The screen
/// touches no repository and no external SDK (Golden Rule 1), and adds no
/// business rule of its own: the field's energy, context line and weighting
/// caption are derived in `resource_field_state.dart` from the same Low /
/// Medium / High signal every other surface reads.
///
/// **Deliberate departures from the prototype**, recorded here so each is a
/// decision rather than a drift:
///
///  * The prototype's left-hand tooling rail (scenario picker, viewport and
///    appearance switches), phone bezel and mock status bar are prototype
///    furniture and are dropped. The appearance toggle survives as the header
///    control the prototype also has, wired to the app's existing
///    [themeNotifierProvider].
///  * The prototype's own bottom navigation is dropped in favour of
///    `AppShell` / `AppBottomNavBar`, which this screen must not redesign. The
///    scroll padding still reserves the prototype's clearance so the last row
///    clears the bar by the same margin.
///  * The prototype's seven fixture categories become the four topics the app
///    actually stores. Drawing `CARDIOVASCULAR` or `MEDICATION` filters that
///    can never return an article would be inventing a catalogue.
///  * Every card's meta line is the prototype's `N MIN · SOURCE` shape filled
///    with the article's real reading estimate and its real cited source, in
///    place of `FIXTURE SOURCE`.
///  * `CARE NEAR YOU` does not fetch on arrival. The Places lookup needs the
///    device location, and silently prompting for it because the user opened
///    the Learn tab would be a surprise; the section opens in the prototype's
///    own "no facilities" panel with an explicit control. Permission failures
///    hand off to `/nearby-hospitals`, which already owns that whole flow.
///  * The prototype's emergency sheet links a fixture "severe episode" article.
///    Production routes that action to the real care directory — see
///    [showRcEmergencySheet].
class ResourceCenterScreen extends ConsumerStatefulWidget {
  const ResourceCenterScreen({super.key});

  @override
  ConsumerState<ResourceCenterScreen> createState() =>
      _ResourceCenterScreenState();
}

class _ResourceCenterScreenState extends ConsumerState<ResourceCenterScreen> {
  final ScrollController _scroll = ScrollController();

  /// `null` is the prototype's `ALL`.
  ResourceTopic? _topic;

  /// Whether the user has asked for the nearby-care lookup this session. See
  /// the class doc — the Places call is never made unprompted.
  bool _careRequested = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── Interactions ───────────────────────────────────────────────────────────

  void _openArticle(ResourceArticle article) {
    context.push('/resources/article/${article.id}');
  }

  void _toggleTheme() {
    final next = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    ref.read(themeNotifierProvider.notifier).setThemeMode(next);
  }

  Future<void> _dial(String number) async {
    final launched = await ref.read(launcherServiceProvider).dialPhone(number);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer.')),
      );
    }
  }

  void _openSearch(ResourceCenterTheme theme, List<ResourceArticle> articles) {
    showRcSearch(
      context: context,
      theme: theme,
      articles: articles,
      metaLine: resourceMetaLine,
      onOpen: _openArticle,
    );
  }

  void _openEmergency(ResourceCenterTheme theme) {
    final contact = ref.read(emergencyContactProvider);
    showRcEmergencySheet(
      context: context,
      theme: theme,
      contactName: contact.name,
      contactDescription: contact.description.toUpperCase(),
      onCall: () => _dial(contact.number),
      onFindCare: () => context.push('/nearby-hospitals'),
    );
  }

  void _openFacility(ResourceCenterTheme theme, Hospital hospital, DateTime fetchedAt) {
    showRcFacilitySheet(
      context: context,
      theme: theme,
      name: hospital.name,
      type: _facilityType(hospital),
      distance: '${hospital.distanceKm.toStringAsFixed(1)} KM',
      hours: _facilityHours(hospital),
      updated: 'RECORD ${_relativeAge(fetchedAt)}',
      phone: hospital.hasPhone ? hospital.phoneNumber : null,
      onDirections: () => openHospitalDirections(context, ref, hospital),
      onCall: hospital.hasPhone
          ? () => callHospital(context, ref, hospital)
          : null,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final estimate = ref.watch(currentCityRiskProvider).asData?.value;
    final theme = ResourceCenterTheme.of(
      context,
      energy: resourceFieldEnergy(estimate),
    );
    final pad = rcPad(context);

    final articlesAsync = ref.watch(resourceArticlesAsyncProvider);
    final articles = ref.watch(orderedResourceArticlesProvider);
    final topicOrder = ref.watch(resourceTopicOrderProvider);
    final elevated = resourceSignalElevated(estimate);

    // Filters on the resource's full category list, so a WHO fact sheet that
    // is genuinely air-quality *and* lungs *and* heart guidance appears under
    // all three — the point of the multi-category model.
    final visible = _topic == null
        ? articles
        : articles.where((a) => a.categories.contains(_topic)).toList();

    // `AppShell` runs `Scaffold(extendBody: true)`, so Flutter already reports
    // `AppBottomNavBar`'s laid-out height as this body's bottom padding — that
    // inset *is* the bar's clearance. What is added on top is the gap between
    // the last row and the bar, the same 24dp the other rebuilt surfaces keep.
    final bottomInset = 24 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _Stage(theme: theme)),
          ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              0,
              MediaQuery.paddingOf(context).top + 12,
              0,
              bottomInset,
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: RcHeader(theme: theme, onToggleTheme: _toggleTheme),
              ),
              const SizedBox(height: 2),
              _ParallaxField(
                scroll: _scroll,
                child: ResourceField(
                  theme: theme,
                  pad: pad,
                  fieldLabel: resourceFieldLabel(estimate, topicOrder),
                  contextLine: resourceContextLine(estimate),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                child: Row(
                  children: [
                    Expanded(child: RcSearchButton(
                      theme: theme,
                      onTap: () => _openSearch(theme, visible),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Saved Articles',
                      color: theme.fg,
                      onPressed: () => context.push('/resources/saved'),
                      icon: const Icon(Icons.bookmarks_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
                child: RcEmergencyBanner(
                  theme: theme,
                  onTap: () => _openEmergency(theme),
                ),
              ),
              if (articlesAsync.isLoading && articles.isEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 26, pad, 0),
                  child: RcFieldSkeletons(theme: theme),
                )
              else ...[
                const SizedBox(height: 28),
                if (articles.length >= 2) ...[
                  _RelevantRail(
                    theme: theme,
                    pad: pad,
                    elevated: elevated,
                    articles: articles.take(2).toList(),
                    onOpen: _openArticle,
                  ),
                  const SizedBox(height: 30),
                ],
                _ExploreSection(
                  theme: theme,
                  pad: pad,
                  total: articles.length,
                  visible: visible,
                  selected: _topic,
                  onSelected: (topic) => setState(() => _topic = topic),
                  onReset: () => setState(() => _topic = null),
                  onOpen: _openArticle,
                ),
                const SizedBox(height: 30),
                _CareNearYou(
                  theme: theme,
                  pad: pad,
                  requested: _careRequested,
                  onRequest: () => setState(() => _careRequested = true),
                  onOpenDirectory: () => context.push('/nearby-hospitals'),
                  onOpenFacility: (hospital, fetchedAt) =>
                      _openFacility(theme, hospital, fetchedAt),
                ),
                const SizedBox(height: 30),
                _FullCatalogue(
                  theme: theme,
                  pad: pad,
                  articles: articles,
                  onOpen: _openArticle,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
                  child: const MedicalDisclaimer.inline(),
                ),
              ],
            ],
          ),
          // `height:118px; linear-gradient(180deg, transparent, bg 68%)` — the
          // fade the content scrolls out under, behind the floating navigation.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 118,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: theme.bottomScrim),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stage ────────────────────────────────────────────────────────────────────

/// The prototype's three ambient layers, in its own order:
/// `radial(120% 70% at 50% 0%, haloS)`,
/// `radial(90% 50% at 100% 100%, cyan .05)`,
/// over `linear(180deg, bg2, bg 46%)`.
class _Stage extends StatelessWidget {
  const _Stage({required this.theme});

  final ResourceCenterTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: AppMotion.reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(gradient: theme.stageFill),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(gradient: theme.stageCool),
              ),
              DecoratedBox(
                decoration: BoxDecoration(gradient: theme.stageHalo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's `onScroll` handler, verbatim: the hero sinks at `0.34×` the
/// scroll, shrinks by `0.00042` per pixel and fades out over 300px, with the
/// scroll offset clamped at 320.
class _ParallaxField extends StatelessWidget {
  const _ParallaxField({required this.scroll, required this.child});

  final ScrollController scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, inner) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        final y = offset.clamp(0.0, 320.0);
        return Opacity(
          opacity: (1 - y / 300).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, y * 0.34),
            child: Transform.scale(scale: 1 - y * 0.00042, child: inner),
          ),
        );
      },
    );
  }
}

// ── Sections ─────────────────────────────────────────────────────────────────

/// The contextual rail. Its heading and rationale change with the signal, and
/// nothing else does — the same two top-of-order guides are shown either way,
/// so an elevated day never conjures content that is not in the catalogue.
class _RelevantRail extends StatelessWidget {
  const _RelevantRail({
    required this.theme,
    required this.pad,
    required this.elevated,
    required this.articles,
    required this.onOpen,
  });

  final ResourceCenterTheme theme;
  final double pad;
  final bool elevated;
  final List<ResourceArticle> articles;
  final void Function(ResourceArticle) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  elevated ? 'RELEVANT FOR YOU' : 'EXPLORE',
                  style: rcMono(
                    context,
                    size: 9.5,
                    em: 0.24,
                    color: theme.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  elevated
                      ? 'Surfaced from your current environmental context.'
                      : 'Verified guidance from the ForeSeeMe catalogue.',
                  textAlign: TextAlign.right,
                  style: rcMono(
                    context,
                    size: 8.5,
                    em: 0.1,
                    color: theme.mono,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // The rail takes its height from the tallest card rather than the
        // prototype's fixed 184, so a large text scale lengthens the rail
        // instead of clipping a title. Only two cards ever ride it, so a plain
        // scroll view costs nothing over a lazy list.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(pad, 2, pad, 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < articles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  RcRelevantCard(
                    theme: theme,
                    article: articles[i],
                    metaLine: resourceMetaLine(articles[i]),
                    onTap: () => onOpen(articles[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `EXPLORE HEALTH KNOWLEDGE` — the dot filter over the two-column card field.
class _ExploreSection extends StatelessWidget {
  const _ExploreSection({
    required this.theme,
    required this.pad,
    required this.total,
    required this.visible,
    required this.selected,
    required this.onSelected,
    required this.onReset,
    required this.onOpen,
  });

  final ResourceCenterTheme theme;
  final double pad;
  final int total;
  final List<ResourceArticle> visible;
  final ResourceTopic? selected;
  final ValueChanged<ResourceTopic?> onSelected;
  final VoidCallback onReset;
  final void Function(ResourceArticle) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: RcSectionHeader(
            theme: theme,
            label: 'EXPLORE HEALTH KNOWLEDGE',
            trailing: '${visible.length} / $total',
          ),
        ),
        const SizedBox(height: 16),
        RcCategoryRail(
          theme: theme,
          pad: pad,
          selected: selected,
          onSelected: onSelected,
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: RcEmptyField(theme: theme, onReset: onReset),
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: _ResourceGrid(
              theme: theme,
              articles: visible,
              onOpen: onOpen,
            ),
          ),
      ],
    );
  }
}

/// The prototype's `grid-template-columns:1fr 1fr` with `data-span="2"` on
/// every third card — laid out here as rows so a wide card can genuinely take
/// the full width and a pair can share a row at matching heights.
class _ResourceGrid extends StatelessWidget {
  const _ResourceGrid({
    required this.theme,
    required this.articles,
    required this.onOpen,
  });

  final ResourceCenterTheme theme;
  final List<ResourceArticle> articles;
  final void Function(ResourceArticle) onOpen;

  /// `min-height:158px`.
  static const double _minCardHeight = 158;

  @override
  Widget build(BuildContext context) {
    final rows = <List<ResourceArticle>>[];
    final pending = <ResourceArticle>[];

    void flush() {
      if (pending.isEmpty) return;
      rows.add(List.of(pending));
      pending.clear();
    }

    for (var i = 0; i < articles.length; i++) {
      if (i % 3 == 0) {
        flush();
        rows.add([articles[i]]);
        continue;
      }
      pending.add(articles[i]);
      if (pending.length == 2) flush();
    }
    flush();

    var index = 0;
    final children = <Widget>[];
    for (final row in rows) {
      final wide = row.length == 1 && articles.indexOf(row.first) % 3 == 0;
      children.add(
        Padding(
          padding: EdgeInsets.only(bottom: children.isEmpty ? 12 : 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minCardHeight),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: AppReveal(
                        delayMs: (index * 45).clamp(0, 270),
                        offsetY: 26,
                        child: RcResourceCard(
                          theme: theme,
                          article: row[i],
                          metaLine: resourceMetaLine(row[i]),
                          onTap: () => onOpen(row[i]),
                        ),
                      ),
                    ),
                  ],
                  // A lone half-width card keeps its column rather than
                  // stretching, exactly as CSS grid auto-placement does.
                  if (row.length == 1 && !wide) const Spacer(),
                ],
              ),
            ),
          ),
        ),
      );
      index += row.length;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// `CARE NEAR YOU` — the radar head over the real Places result.
class _CareNearYou extends ConsumerWidget {
  const _CareNearYou({
    required this.theme,
    required this.pad,
    required this.requested,
    required this.onRequest,
    required this.onOpenDirectory,
    required this.onOpenFacility,
  });

  final ResourceCenterTheme theme;
  final double pad;
  final bool requested;
  final VoidCallback onRequest;
  final VoidCallback onOpenDirectory;
  final void Function(Hospital, DateTime) onOpenFacility;

  /// The prototype lists three facilities under the radar; the full directory
  /// stays one tap away.
  static const int _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Deliberately conditional: the Places lookup (and the location permission
    // it needs) is only subscribed to once the user has asked for it.
    final result = requested ? ref.watch(nearbyHospitalsProvider) : null;
    final hospitals = result?.asData?.value.hospitals ?? const <Hospital>[];

    Widget body;
    if (result == null) {
      body = RcFacilityNotice(
        theme: theme,
        title: 'Find care near you',
        body: 'ForeSeeMe looks up verified facilities around you only when you '
            'ask. This uses your device location.',
        actionLabel: 'FIND CARE NEAR ME',
        onAction: onRequest,
      );
    } else if (result.isLoading) {
      body = RcFacilityNotice(
        theme: theme,
        title: 'Locating nearby care',
        body: 'Reading your location and querying the facility directory.',
        actionLabel: 'SEARCHING',
        onAction: () {},
        busy: true,
      );
    } else if (result.hasError) {
      body = RcFacilityNotice(
        theme: theme,
        title: 'No nearby facilities available',
        body: 'ForeSeeMe could not read verified facility data for this area. '
            'The care directory can retry with location access or your profile '
            'city.',
        actionLabel: 'OPEN CARE DIRECTORY',
        onAction: onOpenDirectory,
      );
    } else if (hospitals.isEmpty) {
      body = RcFacilityNotice(
        theme: theme,
        title: 'No nearby facilities available',
        body: 'The directory returned no verified facilities within the search '
            'radius. A wider search may return results.',
        actionLabel: 'OPEN CARE DIRECTORY',
        onAction: onOpenDirectory,
      );
    } else {
      final fetchedAt = result.asData!.value.fetchedAt;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: theme.line),
          for (final h in hospitals.take(_shown))
            RcFacilityRow(
              theme: theme,
              name: h.name,
              meta: '${_facilityType(h)} · ${_facilityHours(h)}',
              distance: '${h.distanceKm.toStringAsFixed(1)} km',
              onTap: () => onOpenFacility(h, fetchedAt),
            ),
          if (hospitals.length > _shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: RcPillButton(
                  theme: theme,
                  label: 'ALL ${hospitals.length} FACILITIES',
                  onTap: onOpenDirectory,
                  accented: false,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: RcSectionHeader(theme: theme, label: 'CARE NEAR YOU'),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: RcGlass(
            theme: theme,
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResourceRadar(
                  theme: theme,
                  label: hospitals.isEmpty
                      ? 'NO FACILITY DATA'
                      : 'APPROXIMATE POSITIONS · NOT TO SCALE',
                ),
                body,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `FULL CATALOGUE` — every stored guide, indexed, with its provenance footer.
class _FullCatalogue extends StatelessWidget {
  const _FullCatalogue({
    required this.theme,
    required this.pad,
    required this.articles,
    required this.onOpen,
  });

  final ResourceCenterTheme theme;
  final double pad;
  final List<ResourceArticle> articles;
  final void Function(ResourceArticle) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: RcSectionHeader(theme: theme, label: 'FULL CATALOGUE'),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < articles.length; i++)
                RcCatalogueRow(
                  theme: theme,
                  index: i + 1,
                  article: articles[i],
                  onTap: () => onOpen(articles[i]),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
          child: Text(
            // Counts only entries that actually earned it — a resource from an
            // unrecognised publisher is in the catalogue but not in this total.
            '${articles.where((a) => a.isTrustedSource).length} VERIFIED '
            'GUIDES · EVERY ENTRY CITES A PUBLIC-HEALTH AUTHORITY.',
            style: rcMono(
              context,
              size: 8.5,
              em: 0.1,
              color: theme.mono,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Facility copy ────────────────────────────────────────────────────────────

String _facilityType(Hospital hospital) => hospital.kind.label.toUpperCase();

/// Opening hours are shown only when Places actually returned them; otherwise
/// the prototype's own honest placeholder stands.
String _facilityHours(Hospital hospital) => switch (hospital.openNow) {
  true => 'OPEN NOW',
  false => 'CLOSED NOW',
  null => 'HOURS UNKNOWN',
};

/// `UPDATED 2H AGO` from the result's real fetch timestamp.
String _relativeAge(DateTime fetchedAt) {
  final delta = DateTime.now().difference(fetchedAt);
  if (delta.inMinutes < 1) return 'UPDATED JUST NOW';
  if (delta.inMinutes < 60) return 'UPDATED ${delta.inMinutes}M AGO';
  if (delta.inHours < 24) return 'UPDATED ${delta.inHours}H AGO';
  return 'UPDATED ${delta.inDays}D AGO';
}
