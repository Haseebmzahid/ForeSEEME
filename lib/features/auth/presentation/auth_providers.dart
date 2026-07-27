import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/domain/repositories/user_directory_repository.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:fyp_foreseeme/features/auth/data/repositories/firestore_user_directory_repository.dart';
import 'package:fyp_foreseeme/features/auth/domain/models/user_model.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_notifier.dart';
import 'package:fyp_foreseeme/features/auth/presentation/auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

/// The admin user directory (Sprint M8.4). Written by [AuthNotifier] /
/// `HealthProfileNotifier` as a best-effort side effect, read by the admin
/// surface.
final userDirectoryRepositoryProvider = Provider<UserDirectoryRepository>((ref) {
  return const FirestoreUserDirectoryRepository();
});

final authStateProvider = StreamProvider<UserModel?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.currentUser;
});

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
