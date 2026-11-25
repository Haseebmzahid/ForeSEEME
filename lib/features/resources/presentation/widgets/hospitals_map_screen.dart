import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fyp_foreseeme/core/maps/dark_map_style.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_care_tracking.dart';
import 'package:fyp_foreseeme/features/resources/presentation/services/hospital_actions.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_detail_sheet.dart';

class NearbyCareTrackedMap extends StatelessWidget {
  const NearbyCareTrackedMap({super.key, required this.arguments});

  final NearbyCareMapArguments arguments;

  @override
  Widget build(BuildContext context) => NearbyCareTracking(
    initial: arguments.initial,
    builder: (result, loss, lookupDelayed) => HospitalsMapScreen(
      hospitals: arguments.filter(result.hospitals),
      position: loss == null ? result.devicePosition : null,
      statusMessage: loss != null
          ? 'Device location unavailable. Return to the directory to retry.'
          : lookupDelayed
          ? 'Could not refresh this area. Showing the previous search.'
          : null,
    ),
  );
}

/// Full-screen map of the nearby hospitals ("View on map") — visually and
/// interactionally the same family as the Geospatial Risk Map: dark map
/// style in dark mode, a persistent bottom-anchored detail sheet driven by
/// marker **selection** (not a bare InfoWindow), reached with the same
/// [AppMotion.sheetTransition]. Self-sufficient via the shared launcher
/// (Call/Directions), so callers only need to hand it the hospital list.
class HospitalsMapScreen extends ConsumerStatefulWidget {
  final List<Hospital> hospitals;

  final LocationResult? position;
  final String? statusMessage;

  const HospitalsMapScreen({
    super.key,
    required this.hospitals,
    this.position,
    this.statusMessage,
  });

  @override
  ConsumerState<HospitalsMapScreen> createState() =>
      _HospitalsMapScreenState();
}

Set<Marker> nearbyCareMarkers(
  List<Hospital> facilities,
  ValueChanged<Hospital> onSelect,
) => {
  for (final facility in facilities)
    Marker(
      markerId: MarkerId(facility.id),
      position: LatLng(facility.latitude, facility.longitude),
      infoWindow: InfoWindow(
        title: facility.name,
        snippet:
            '${facility.kind.label} · ${facility.distanceKm.toStringAsFixed(1)} km away',
      ),
      onTap: () => onSelect(facility),
    ),
};

class _HospitalsMapScreenState extends ConsumerState<HospitalsMapScreen> {
  GoogleMapController? _controller;
  String? _selectedHospitalId;
  LocationResult? _lastCentered;
  final _sinceCameraMove = Stopwatch();

  @override
  void didUpdateWidget(HospitalsMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != null &&
        !identical(widget.position, oldWidget.position)) {
      _followPosition();
    }
  }

  Future<void> _followPosition({bool recenter = false}) async {
    final controller = _controller;
    final position = widget.position;
    if (controller == null ||
        position == null ||
        (!recenter && _selected != null)) {
      return;
    }
    final center = nearbyCareCameraTarget(
      previous: recenter ? null : _lastCentered,
      position: position,
      elapsed: _sinceCameraMove.elapsed,
    );
    if (center == null) return;
    _lastCentered = position;
    _sinceCameraMove
      ..reset()
      ..start();
    try {
      await controller.moveCamera(CameraUpdate.newLatLng(center));
    } on PlatformException {
      // The native map may be unavailable while the route transitions.
    } on StateError {
      // The controller can be detached before a queued camera update executes.
    }
  }

  LatLng get _center {
    final position = widget.position;
    if (position != null) {
      return LatLng(position.latitude!, position.longitude!);
    }
    final h = widget.hospitals.reduce(
      (first, second) =>
          first.distanceKm <= second.distanceKm ? first : second,
    );
    return LatLng(h.latitude, h.longitude);
  }

  Hospital? get _selected {
    if (_selectedHospitalId == null) return null;
    for (final h in widget.hospitals) {
      if (h.id == _selectedHospitalId) return h;
    }
    return null;
  }

  void _selectHospital(Hospital h) {
    setState(() => _selectedHospitalId = h.id);
    _controller?.animateCamera(
      CameraUpdate.newLatLng(LatLng(h.latitude, h.longitude)),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapSupported =
        kIsWeb ||
        const {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform);
    if (!mapSupported ||
        (widget.hospitals.isEmpty && widget.position == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nearby care map')),
        body: Center(
          child: Text(
            widget.statusMessage ??
                'Map unavailable. Return to the directory to open directions.',
          ),
        ),
      );
    }
    final palette = context.fsmPalette;
    final selected = _selected;

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Nearby care map', style: context.fsmText.titleLarge),
        actions: [
          if (widget.position != null)
            IconButton(
              tooltip: 'Center on my location',
              icon: const Icon(Icons.my_location_rounded),
              onPressed: () {
                setState(() => _selectedHospitalId = null);
                _followPosition(recenter: true);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 12,
              ),
              style: palette.isDark ? kDarkMapStyle : null,
              markers: {
                ...nearbyCareMarkers(widget.hospitals, _selectHospital),
                if (widget.position case final fix?)
                  Marker(
                    markerId: const MarkerId('foreseeme-device-location'),
                    position: LatLng(fix.latitude!, fix.longitude!),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                    infoWindow: const InfoWindow(title: 'Your location'),
                  ),
              },
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onTap: (_) => setState(() => _selectedHospitalId = null),
              onMapCreated: (c) {
                _controller = c;
                _lastCentered = widget.position;
                _sinceCameraMove.start();
                if (_lastCentered == null) _fitToMarkers();
              },
            ),
          ),
          if (widget.statusMessage != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(widget.statusMessage!),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.reduceMotion(context)
                  ? Duration.zero
                  : AppMotion.medium,
              transitionBuilder: AppMotion.sheetTransition,
              child: selected == null
                  ? const SizedBox.shrink(key: ValueKey('no-selection'))
                  : HospitalDetailSheet(
                      key: ValueKey(selected.id),
                      hospital: selected,
                      onCall: () => callHospital(context, ref, selected),
                      onDirections: () =>
                          openHospitalDirections(context, ref, selected),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Frames all markers once the map is ready (falls back silently if the single
  /// point can't form bounds).
  Future<void> _fitToMarkers() async {
    if (widget.hospitals.length < 2 || _controller == null) return;
    var minLat = widget.hospitals.first.latitude;
    var maxLat = minLat;
    var minLon = widget.hospitals.first.longitude;
    var maxLon = minLon;
    for (final h in widget.hospitals) {
      minLat = h.latitude < minLat ? h.latitude : minLat;
      maxLat = h.latitude > maxLat ? h.latitude : maxLat;
      minLon = h.longitude < minLon ? h.longitude : minLon;
      maxLon = h.longitude > maxLon ? h.longitude : maxLon;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );
    await _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 64),
    );
  }
}

/// Moves the camera only after meaningful movement and a quiet interval.
LatLng? nearbyCareCameraTarget({
  required LocationResult? previous,
  required LocationResult position,
  required Duration elapsed,
}) {
  if (previous != null &&
      (elapsed < const Duration(seconds: 8) ||
          distanceBetweenKm(
                previous.latitude!,
                previous.longitude!,
                position.latitude!,
                position.longitude!,
              ) <
              0.25)) {
    return null;
  }
  return LatLng(position.latitude!, position.longitude!);
}
