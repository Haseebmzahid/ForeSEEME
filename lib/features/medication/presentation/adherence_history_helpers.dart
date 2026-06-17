import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:fyp_foreseeme/core/theme/app_colors.dart';
import 'package:fyp_foreseeme/features/medication/domain/models/daily_status.dart';

Color statusFill(DailyAdherenceStatus status) => switch (status) {
  DailyAdherenceStatus.taken => AppColors.adherencePrimary,
  DailyAdherenceStatus.skipped => AppColors.adherenceCoral,
  DailyAdherenceStatus.noSchedule => AppColors.adherenceSurface,
  DailyAdherenceStatus.pending => AppColors.adherenceSurface,
};

class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({super.key, required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, .08),
      end: Offset.zero,
    ).animate(curve);
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

class DashboardLoading extends StatelessWidget {
  const DashboardLoading({super.key});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: AppColors.adherenceSurface,
    highlightColor: AppColors.adherenceSurfaceHighlight,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 104),
      children: const [
        _SkeletonCard(height: 290),
        SizedBox(height: 18),
        _SkeletonCard(height: 260),
        SizedBox(height: 18),
        _SkeletonCard(height: 104),
        SizedBox(height: 18),
        _SkeletonCard(height: 130),
      ],
    ),
  );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.adherenceSurface,
      borderRadius: BorderRadius.circular(16),
    ),
  );
}

class CenterDashboardMessage extends StatelessWidget {
  const CenterDashboardMessage({
    super.key,
    this.message,
    this.showIcon = false,
  });
  final String? message;
  final bool showIcon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon)
            Icon(
              Icons.bar_chart_rounded,
              size: 80,
              color: AppColors.adherencePrimary,
            ),
          if (showIcon) const SizedBox(height: 18),
          Text(
            message ??
                'Start taking your medications to see your progress here',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: AppColors.adherenceTextMuted,
              fontSize: 16,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
