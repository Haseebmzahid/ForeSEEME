import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/repositories/firestore_article_bookmarks.dart';

final bookmarkOwnerProvider = Provider<String?>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  return user?.emailVerified == true ? user?.uid : null;
});

final articleBookmarkStoreProvider = Provider<FirestoreArticleBookmarks>((
  ref,
) {
  return FirestoreArticleBookmarks(FirebaseFirestore.instance);
});

final _bookmarksForOwner = StreamProvider.autoDispose
    .family<ArticleBookmarks, String>((ref, uid) {
      return ref.watch(articleBookmarkStoreProvider).watch(uid);
    });

final articleBookmarksProvider = Provider<AsyncValue<ArticleBookmarks>>((
  ref,
) {
  final uid = ref.watch(bookmarkOwnerProvider);
  if (uid == null) return const AsyncData(ArticleBookmarks());
  return ref.watch(_bookmarksForOwner(uid));
});
