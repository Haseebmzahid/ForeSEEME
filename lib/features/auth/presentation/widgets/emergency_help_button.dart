import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../resources/presentation/resources_providers.dart';
import '../../../resources/presentation/services/hospital_actions.dart';

/// Uses the same bundled emergency contact as the Resource Center.
class EmergencyHelpButton extends ConsumerWidget {
  const EmergencyHelpButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(emergencyContactProvider);
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.phone_outlined),
          label: Text('Emergency help · ${contact.number}'),
          onPressed: () => dialResourceNumber(context, ref, contact.number),
        ),
        TextButton(
          onPressed: () => context.push('/emergency'),
          child: const Text('Emergency resources'),
        ),
      ],
    );
  }
}
