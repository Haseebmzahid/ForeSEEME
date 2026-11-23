import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/data/repositories/admin_api_client.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'admin_read.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';

final adminArticlesProvider = FutureProvider.autoDispose<List<ResourceArticle>>(
  (ref) {
    final articles = ref.watch(resourceArticlesAsyncProvider.future);
    return boundedAdminRead('articles', () => articles);
  },
  retry: (_, _) => null,
);

class AdminArticleFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(ResourceArticle article, {required bool isNew}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final payload = article.toJson()
        ..remove('verified')
        ..remove('authority')
        ..remove('publishedAt')
        ..remove('lastVerifiedAt');
      await ref
          .read(adminApiClientProvider)
          .post(['articles', article.id], {...payload, 'create': isNew});
      ref.invalidate(resourceArticlesAsyncProvider);
      ref.invalidate(recentActivityLogProvider);
    });
  }
}

final adminArticleFormControllerProvider =
    AsyncNotifierProvider<AdminArticleFormController, void>(
      AdminArticleFormController.new,
    );
