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
Future<void> openHospitalDirections(
  BuildContext context,
  WidgetRef ref,
  Hospital h,
) async {
  var opened = false;
  try {
    opened = await ref
        .read(launcherServiceProvider)
        .openExternalUrl(hospitalDirectionsUrl(h));
  } catch (_) {
    // A platform may have no app to handle the maps URL.
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open directions on this device.'),
      ),
    );
  }
}

/// Dials [h]'s phone number, when it has one. Shows a snackbar if the dialer
/// couldn't be opened (never if the hospital simply has no number — the Call
/// button is disabled for that case, so this shouldn't be reachable).
Future<void> callHospital(
  BuildContext context,
  WidgetRef ref,
  Hospital h,
) async {
  if (!h.hasPhone) return;
  await dialResourceNumber(context, ref, h.phoneNumber!.trim());
}

Future<void> dialResourceNumber(
  BuildContext context,
  WidgetRef ref,
  String phone,
) async {
  var ok = false;
  try {
    ok = await ref.read(launcherServiceProvider).dialPhone(phone);
  } catch (_) {
    // The platform may reject the intent even when a number is available.
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open the dialer. Dial $phone manually.'),
      ),
    );
  }
}
