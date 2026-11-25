import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_button.dart';
import 'auth_providers.dart';
import 'auth_state.dart';
import 'widgets/emergency_help_button.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() =>
      _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check(silent: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check(silent: true));
  }

  Future<void> _run(Future<String?> Function(String uid) operation) async {
    final user = ref.read(authStateProvider).value;
    if (_busy ||
        user == null ||
        user.emailVerified ||
        ref.read(authNotifierProvider) is AuthStateLoading) {
      return;
    }
    setState(() => _busy = true);
    final message = await operation(user.uid);
    if (mounted) {
      setState(() {
        _busy = false;
        if (ref.read(authStateProvider).value?.uid == user.uid &&
            message != null) {
          _message = message;
        }
      });
    }
  }

  Future<void> _check({bool silent = false}) => _run((uid) async {
    final result = await ref
        .read(authRepositoryProvider)
        .refreshEmailVerification(uid);
    return result.fold(
      (error) => silent ? null : error.message,
      (verified) => verified || silent
          ? null
          : 'Email verification is still pending. Open the link in your inbox, then check again.',
    );
  });

  Future<void> _resend() => _run((uid) async {
    final result = await ref
        .read(authRepositoryProvider)
        .sendEmailVerification(uid);
    return result.fold(
      (error) => error.message,
      (_) => 'Verification email sent. Check your inbox.',
    );
  });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final auth = ref.watch(authNotifierProvider);
    final busy = _busy || auth is AuthStateLoading;
    final status =
        _message ??
        switch (auth) {
          AuthStateVerificationPending(:final user, :final message)
              when user.uid == ref.read(authStateProvider).value?.uid =>
            message,
          AuthStateError(:final message) => message,
          _ => null,
        };
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Open the verification link for ${user?.email ?? 'your email address'} '
              'to activate your account. Return here after opening the link.',
            ),
            const SizedBox(height: 16),
            if (busy) const LinearProgressIndicator(),
            if (status != null)
              Semantics(liveRegion: true, child: Text(status)),
            const SizedBox(height: 16),
            AppButton(
              text: 'Check verification',
              onPressed: busy ? null : _check,
            ),
            TextButton(
              onPressed: busy ? null : _resend,
              child: const Text('Resend verification email'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => context.push('/forgot-password'),
              child: const Text('Reset password'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => ref.read(authNotifierProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
            const EmergencyHelpButton(),
          ],
        ),
      ),
    );
  }
}
