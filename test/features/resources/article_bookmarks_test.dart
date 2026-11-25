import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/firestore_article_bookmarks.dart';
import 'package:fyp_foreseeme/features/resources/presentation/article_bookmark_provider.dart';

class _ControlledStore extends Fake implements FirestoreArticleBookmarks {
  final feeds = <String, StreamController<ArticleBookmarks>>{};

  StreamController<ArticleBookmarks> feed(String uid) =>
      feeds.putIfAbsent(uid, StreamController<ArticleBookmarks>.broadcast);

  @override
  Stream<ArticleBookmarks> watch(String uid) => feed(uid).stream;
}

UserModel _verified(String uid) => UserModel(
  uid: uid,
  email: '$uid@example.test',
  emailVerified: true,
  createdAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Firestore records reload by UID and repeat saves and deletes remain single-record operations',
    () async {
      final db = FakeFirebaseFirestore();
      final first = FirestoreArticleBookmarks(db);
      final reopened = FirestoreArticleBookmarks(db);
      await first.setSaved('alice', 'guide', saved: true);
      await reopened.setSaved('alice', 'guide', saved: true);
      expect((await reopened.watch('alice').first).ids, {'guide'});
      expect((await reopened.watch('bob').first).ids, isEmpty);
      final stored = await db
          .doc('users/alice/profile/alice/bookmarks/guide')
          .get();
      expect(stored.data()?.keys, unorderedEquals(['articleId', 'savedAt']));
      await reopened.setSaved('alice', 'guide', saved: false);
      await first.setSaved('alice', 'guide', saved: false);
      expect((await first.watch('alice').first).ids, isEmpty);
    },
  );

  test(
    'account transitions drop the old snapshot even if its feed completes late',
    () async {
      final accounts = StreamController<UserModel?>.broadcast();
      final store = _ControlledStore();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => accounts.stream),
          articleBookmarkStoreProvider.overrideWithValue(store),
        ],
      );
      final keeper = container.listen(
        articleBookmarksProvider,
        (_, _) {},
        fireImmediately: true,
      );
      Future<void> settle() async {
        await Future<void>.delayed(Duration.zero);
        await container.pump();
      }

      try {
        accounts.add(_verified('alice'));
        await settle();
        store
            .feed('alice')
            .add(
              const ArticleBookmarks(
                ids: {'old'},
                pending: true,
                cached: true,
              ),
            );
        await settle();
        expect(container.read(articleBookmarksProvider).asData?.value.ids, {
          'old',
        });
        expect(
          container.read(articleBookmarksProvider).asData?.value.pending,
          isTrue,
        );

        accounts.add(_verified('bob'));
        await settle();
        expect(
          container.read(articleBookmarksProvider).asData?.value.ids,
          isNot({'old'}),
        );
        store.feed('alice').add(const ArticleBookmarks(ids: {'late'}));
        store.feed('bob').add(const ArticleBookmarks(ids: {'new'}));
        await settle();
        expect(container.read(articleBookmarksProvider).asData?.value.ids, {
          'new',
        });

        accounts.add(null);
        await settle();
        expect(
          container.read(articleBookmarksProvider).asData?.value.ids,
          isEmpty,
        );
      } finally {
        keeper.close();
        container.dispose();
        await accounts.close();
        for (final feed in store.feeds.values) {
          await feed.close();
        }
      }
    },
  );

  test(
    'ambiguous device-local bookmarks are neither imported nor removed',
    () async {
      const key = 'resources_bookmarked_article_ids';
      SharedPreferences.setMockInitialValues({
        key: ['legacy-unowned'],
      });
      final prefs = await SharedPreferences.getInstance();
      final store = FirestoreArticleBookmarks(FakeFirebaseFirestore());
      expect((await store.watch('alice').first).ids, isEmpty);
      await store.setSaved('alice', 'new', saved: true);
      expect(prefs.getStringList(key), ['legacy-unowned']);
    },
  );
}
