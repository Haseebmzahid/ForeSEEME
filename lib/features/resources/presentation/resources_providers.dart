import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/core/services/launcher_service.dart';
import 'package:fyp_foreseeme/features/resources/data/repositories/static_resource_repository.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_repository.dart';

/// Concrete [ResourceRepository]. Depends on the abstract type so tests/dev can
/// override it with a fake library (mirrors `riskRepositoryProvider`).
final resourceRepositoryProvider = Provider<ResourceRepository>((ref) {
  return const StaticResourceRepository();
});

/// The curated self-care guides.
final resourceArticlesProvider = Provider<List<ResourceArticle>>((ref) {
  return ref.watch(resourceRepositoryProvider).articles();
});

/// The primary emergency contact (Rescue 1122).
final emergencyContactProvider = Provider<EmergencyContact>((ref) {
  return ref.watch(resourceRepositoryProvider).emergencyContact();
});

/// External launcher (dialer / browser). Overridable with a fake in tests so the
/// `tel:` intent can be asserted without a device.
final launcherServiceProvider = Provider<LauncherService>((ref) {
  return const UrlLauncherService();
});
