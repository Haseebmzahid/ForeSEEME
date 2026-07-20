import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/presentation/resources_providers.dart';

/// Shared "Call" / "Directions" actions for a [Hospital] — one place, reused
/// by the hospital list, the map's detail sheet, and the list's modal detail
/// sheet, so the dial/maps behaviour never drifts between entry points.

/// A Google Maps directions URL to [h]'s real coordinates (no invented data).
String hospitalDirectionsUrl(Hospital h) =>
    'https://www.google.com/maps/dir/?api=1&destination=${h.latitude},${h.longitude}';

/// Opens external directions via the shared launcher.
Future<void> openHospitalDirections(WidgetRef ref, Hospital h) {
  return ref
      .read(launcherServiceProvider)
      .openExternalUrl(hospitalDirectionsUrl(h));
}

/// Dials [h]'s phone number, when it has one. Shows a snackbar if the dialer
/// couldn't be opened (never if the hospital simply has no number — the Call
/// button is disabled for that case, so this shouldn't be reachable).
Future<void> callHospital(BuildContext context, WidgetRef ref, Hospital h) async {
  final phone = h.phoneNumber;
  if (phone == null) return;
  final ok = await ref.read(launcherServiceProvider).dialPhone(phone);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the dialer.')),
    );
  }
}
