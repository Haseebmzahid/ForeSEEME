import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fyp_foreseeme/core/theme/theme_provider.dart';

const _kBookmarkedArticleIdsKey = 'resources_bookmarked_article_ids';

/// Local, on-device bookmark store — a handful of article ids, no backend.
///
/// Mirrors `MilestoneStore`'s direct-`SharedPreferences` usage (a repository
/// layer would be overkill for one string set) rather than adding a new
/// abstraction.
class ArticleBookmarkStore {
  final SharedPreferences _preferences;

  const ArticleBookmarkStore(this._preferences);

  Set<String> read() =>
      (_preferences.getStringList(_kBookmarkedArticleIdsKey) ?? const [])
          .toSet();

  Future<void> write(Set<String> ids) =>
      _preferences.setStringList(_kBookmarkedArticleIdsKey, ids.toList());
}

final articleBookmarkStoreProvider = Provider<ArticleBookmarkStore>((ref) {
  return ArticleBookmarkStore(ref.watch(sharedPreferencesProvider));
});

/// The current set of bookmarked article ids.
final bookmarkedArticleIdsProvider =
    StateNotifierProvider<BookmarkedArticleIdsNotifier, Set<String>>((ref) {
      final store = ref.watch(articleBookmarkStoreProvider);
      return BookmarkedArticleIdsNotifier(store);
    });

class BookmarkedArticleIdsNotifier extends StateNotifier<Set<String>> {
  BookmarkedArticleIdsNotifier(this._store) : super(_store.read());

  final ArticleBookmarkStore _store;

  Future<void> toggle(String articleId) async {
    final next = {...state};
    if (!next.remove(articleId)) next.add(articleId);
    state = next;
    await _store.write(next);
  }

  bool isBookmarked(String articleId) => state.contains(articleId);
}
