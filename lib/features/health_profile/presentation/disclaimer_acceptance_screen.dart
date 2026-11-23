import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/medical_disclaimer.dart';
import '../../auth/presentation/auth_providers.dart';
import 'disclaimer_providers.dart';

class DisclaimerAcceptanceScreen extends ConsumerStatefulWidget {
  const DisclaimerAcceptanceScreen({super.key});

  @override
  ConsumerState<DisclaimerAcceptanceScreen> createState() =>
      _DisclaimerAcceptanceScreenState();
}

class _DisclaimerAcceptanceScreenState
    extends ConsumerState<DisclaimerAcceptanceScreen> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await ref.read(acceptDisclaimerProvider)();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acceptance = ref.watch(disclaimerAcceptedProvider);
    final busy = _saving || acceptance.isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Health disclaimer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const MedicalDisclaimer.banner(),
            const SizedBox(height: 24),
            if (_failed || acceptance.hasError)
              Semantics(
                liveRegion: true,
                child: const Text(
                  'We couldn’t confirm acceptance. Check your connection and try again.',
                ),
              ),
            FilledButton(
              onPressed: busy ? null : _accept,
              child: Text(busy ? 'Checking acceptance…' : 'I accept'),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => ref.read(authNotifierProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
