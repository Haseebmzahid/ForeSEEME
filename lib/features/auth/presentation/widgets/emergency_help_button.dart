import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../resources/presentation/resources_providers.dart';

/// Uses the same bundled emergency contact as the Resource Center.
class EmergencyHelpButton extends ConsumerWidget {
  const EmergencyHelpButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(emergencyContactProvider);
    return TextButton.icon(
      icon: const Icon(Icons.phone_outlined),
      label: Text('Emergency help · ${contact.number}'),
      onPressed: () async {
        final launched = await ref
            .read(launcherServiceProvider)
            .dialPhone(contact.number);
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dial ${contact.number} for ${contact.name}.'),
            ),
          );
        }
      },
    );
  }
}
