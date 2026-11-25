import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../domain/repositories/disclaimer_repository.dart';
import 'health_profile_providers.dart';

final disclaimerAcceptedProvider = FutureProvider<bool>((ref) async {
  final repository = ref.watch(disclaimerRepositoryProvider);
  final user = await ref.watch(authStateProvider.future);
  return user != null &&
      user.emailVerified &&
      await repository.hasAccepted(user.uid, currentDisclaimerVersion);
});

final acceptDisclaimerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final user = ref.read(authStateProvider).value;
    if (user == null) throw StateError('Sign-in required');
    await ref
        .read(disclaimerRepositoryProvider)
        .accept(user.uid, currentDisclaimerVersion);
    if (ref.read(authStateProvider).value?.uid == user.uid) {
      ref.invalidate(disclaimerAcceptedProvider);
    }
  };
});
