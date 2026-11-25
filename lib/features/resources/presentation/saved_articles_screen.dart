import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'article_bookmark_provider.dart';
import 'resources_providers.dart';
import 'widgets/resource_article_card.dart';
import 'widgets/resource_center_style.dart';

class SavedArticlesScreen extends ConsumerWidget {
  const SavedArticlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ResourceCenterTheme.of(context);
    final bookmarks = ref.watch(articleBookmarksProvider);
    final catalogue = ref.watch(resourceArticlesAsyncProvider);

    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(title: const Text('Saved Articles')),
      body: SafeArea(
        child: bookmarks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Could not load saved articles.')),
          data: (saved) {
            final articles = catalogue.asData?.value ?? const [];
            final visible = articles
                .where((article) => saved.ids.contains(article.id))
                .toList();
            final missing = saved.ids.length - visible.length;
            return ListView(
              padding: EdgeInsets.all(rcPad(context)),
              children: [
                if (saved.pending)
                  const Text('Bookmark changes are waiting to sync.')
                else if (saved.cached)
                  const Text('Showing saved articles from this device.'),
                if (saved.ids.isEmpty)
                  Text(
                    saved.cached
                        ? 'No saved articles in this device’s cache.'
                        : 'No saved articles yet.',
                  )
                else if (catalogue.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (catalogue.hasError)
                  const Text('The article library is unavailable.')
                else ...[
                  for (final article in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ResourceArticleCard(
                        article: article,
                        bookmarked: true,
                        onTap: () => context.push(
                          '/resources/article/${Uri.encodeComponent(article.id)}',
                        ),
                      ),
                    ),
                  if (missing > 0)
                    Text(
                      missing == 1
                          ? 'One saved article is unavailable.'
                          : '$missing saved articles are unavailable.',
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
