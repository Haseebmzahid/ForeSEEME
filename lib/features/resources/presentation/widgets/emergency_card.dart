import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/app_design_v2.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';

/// One-tap emergency dial card. Tapping anywhere on the card (or the call
/// button) triggers [onCall], which dials the contact.
class EmergencyCard extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onCall;

  const EmergencyCard({super.key, required this.contact, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Call ${contact.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onCall,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  AppColorsV2.riskHigh.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.03),
                ],
                begin: const Alignment(-0.8, -1),
                end: const Alignment(0.8, 1),
              ),
              border: Border.all(
                color: AppColorsV2.riskHigh.withValues(alpha: 0.36),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColorsV2.riskHigh.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.emergency_share_rounded,
                    color: AppColorsV2.riskHigh,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency · ${contact.name}',
                        style: AppTextStylesV2.cardTitle.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text('Tap to call now', style: AppTextStylesV2.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColorsV2.riskHigh,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColorsV2.riskHigh.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
