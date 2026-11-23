import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'admin_read.dart';
import 'admin_content_providers.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/core/widgets/empty_state.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_providers.dart';
import 'package:fyp_foreseeme/features/admin/presentation/widgets/not_authorized_view.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';

/// Admin Content Management (Sprint M8.3, SDS FR8.3): lists every published
/// article and lets an admin add or edit one. There is no draft state — this
/// list IS the live Resource Center's content, exactly as end users see it
/// (SDS's "Published content must be immediately visible" business rule).
///
/// Hosted as a branch of [AdminShell] — it renders only its body content; the
/// shell provides the shared app bar/back button/bottom nav. Gates its own
/// content on `isAdminProvider`, matching the dashboard/override/logs screens;
/// the authoritative enforcement is server-side (`firestore.rules` denies
/// `articles` writes to non-admins regardless).
class AdminContentScreen extends ConsumerWidget {
  const AdminContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return SafeArea(
      child: isAdminAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: AdminReadError(
            message: 'Could not verify the administrator session.',
            error: error,
            retry: () => ref.invalidate(isAdminProvider),
          ),
        ),
        data: (isAdmin) =>
            isAdmin ? const _ArticleList() : const NotAuthorizedView(),
      ),
    );
  }
}

class _ArticleList extends ConsumerWidget {
  const _ArticleList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(adminArticlesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.md,
            ForeSeeMeSpacing.gutter,
            ForeSeeMeSpacing.sm,
          ),
          child: AppButton(
            text: 'Add article',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/admin/content/add'),
          ),
        ),
        Expanded(
          child: articlesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: AdminReadError(
                message: 'Could not load articles.',
                error: error,
                retry: () {
                  ref.invalidate(resourceArticlesAsyncProvider);
                  ref.invalidate(adminArticlesProvider);
                },
              ),
            ),
            data: (articles) {
              if (articles.isEmpty) {
                return const EmptyState(
                  icon: Icons.article_outlined,
                  title: 'No articles yet',
                  description: 'Add the first Resource Center guide above.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  ForeSeeMeSpacing.gutter,
                  0,
                  ForeSeeMeSpacing.gutter,
                  ForeSeeMeSpacing.xxxl,
                ),
                itemCount: articles.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ForeSeeMeSpacing.sm),
                itemBuilder: (context, i) =>
                    _ArticleListTile(article: articles[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArticleListTile extends StatelessWidget {
  final ResourceArticle article;
  const _ArticleListTile({required this.article});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final visual = ResourceTopicVisual.of(context, article.topic);

    return InkWell(
      borderRadius: BorderRadius.circular(ForeSeeMeRadius.md),
      onTap: () => context.push('/admin/content/edit', extra: article),
      child: Container(
        padding: const EdgeInsets.all(ForeSeeMeSpacing.lg),
        decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(visual.icon, color: visual.color, size: 18),
            ),
            const SizedBox(width: ForeSeeMeSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resourceTopicLabel(article.topic),
                    style: text.bodySmall?.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}
