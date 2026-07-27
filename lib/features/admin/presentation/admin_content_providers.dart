import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/admin/domain/models/admin_activity_log_entry.dart';
import 'package:fyp_foreseeme/features/admin/domain/repositories/admin_activity_log_repository.dart';
import 'package:fyp_foreseeme/features/admin/presentation/activity_log_providers.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_providers.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_content_repository.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';

/// Write controller for the admin Resource Center CMS (Sprint M8.3, SDS FR8.3).
/// Mirrors [AdminOverrideController]: a thin delegate to the repository (the
/// repository's Firestore rules enforce the admin claim; the form screen
/// enforces required fields), then an activity-log entry — closing the same
/// "actions must be logged" expectation FR8.2's business rule stated for
/// overrides, applied here to content changes too (SDS FR8.4).
class AdminArticleFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  ResourceContentRepository get _repo =>
      ref.read(resourceContentRepositoryProvider);

  AdminActivityLogRepository get _activityLog =>
      ref.read(adminActivityLogRepositoryProvider);

  /// Create or update [article] (an upsert either way — [isNew] only changes
  /// the log's action code/wording). Since there is no draft/review workflow
  /// (SDS FR8.3's "if workflow enabled" is not enabled for v1), a successful
  /// save is immediately visible to every reader.
  Future<void> save(ResourceArticle article, {required bool isNew}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.saveArticle(article);
      // Every reader (not just this admin session) must see the edit, so the
      // shared async source is invalidated, not just a local cache.
      ref.invalidate(resourceArticlesAsyncProvider);
      await _logAction(article: article, isNew: isNew);
    });
  }

  /// Appends one activity-log entry. Non-fatal by design if it fails — mirrors
  /// [AdminOverrideController._logAction] exactly: the article write above has
  /// already succeeded, and the audit trail must never block the admin action.
  Future<void> _logAction({
    required ResourceArticle article,
    required bool isNew,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    try {
      await _activityLog.append(
        AdminActivityLogEntry(
          action: isNew ? 'article_create' : 'article_update',
          target: article.id,
          summary: isNew
              ? 'Created article "${article.title}"'
              : 'Updated article "${article.title}"',
          authorUid: user.uid,
          authorEmail: user.email,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      ref.invalidate(recentActivityLogProvider);
    } catch (_) {
      // Non-fatal — see doc comment above.
    }
  }
}

final adminArticleFormControllerProvider =
    AsyncNotifierProvider<AdminArticleFormController, void>(
      AdminArticleFormController.new,
    );
