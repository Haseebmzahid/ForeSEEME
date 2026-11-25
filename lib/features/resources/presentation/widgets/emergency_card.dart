import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';

/// One-tap emergency dial card. Tapping anywhere on the card (or the call
/// button) triggers [onCall], which dials the contact. The urgent tone comes
/// from the design system's `error` token, resolved for the ambient brightness.
class EmergencyCard extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onCall;

  const EmergencyCard({super.key, required this.contact, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    final text = context.fsmText;
    final urgent = palette.error;

    return Semantics(
      button: true,
      label: 'Call ${contact.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onCall,
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ForeSeeMeRadius.lg),
              gradient: LinearGradient(
                colors: [
                  urgent.withValues(alpha: 0.16),
                  ForeSeeMeSurface.fill(context),
                ],
                begin: const Alignment(-0.8, -1),
                end: const Alignment(0.8, 1),
              ),
              border: Border.all(color: urgent.withValues(alpha: 0.36)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: urgent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                  ),
                  child: Icon(Icons.emergency_share_rounded, color: urgent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency · ${contact.name}',
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Call ${contact.number}',
                        style: text.bodySmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: urgent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: urgent.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(Icons.call_rounded, color: palette.onError),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
