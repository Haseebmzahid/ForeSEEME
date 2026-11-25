import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'resources_providers.dart';
import 'services/hospital_actions.dart';
import 'widgets/emergency_card.dart';
import 'widgets/resource_center_style.dart';

class EmergencyResourcesScreen extends ConsumerWidget {
  const EmergencyResourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ResourceCenterTheme.of(context);
    final contact = ref.watch(emergencyContactProvider);
    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(title: const Text('Emergency Resources')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(rcPad(context)),
          children: [
            EmergencyCard(
              contact: contact,
              onCall: () => dialResourceNumber(context, ref, contact.number),
            ),
            const SizedBox(height: 12),
            Text(contact.description),
            const SizedBox(height: 16),
            const Text(
              'ForeSeeMe is not an emergency service. For immediate help, call your local emergency number.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.local_hospital_outlined),
              onPressed: () => context.push('/emergency/nearby'),
              label: const Text('Nearby hospitals and clinics'),
            ),
          ],
        ),
      ),
    );
  }
}
