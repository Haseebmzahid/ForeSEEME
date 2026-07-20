import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fyp_foreseeme/core/maps/dark_map_style.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/widgets/app_motion.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/presentation/services/hospital_actions.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/hospital_detail_sheet.dart';

/// Full-screen map of the nearby hospitals ("View on map") — visually and
/// interactionally the same family as the Geospatial Risk Map: dark map
/// style in dark mode, a persistent bottom-anchored detail sheet driven by
/// marker **selection** (not a bare InfoWindow), reached with the same
/// [AppMotion.sheetTransition]. Self-sufficient via the shared launcher
/// (Call/Directions), so callers only need to hand it the hospital list.
class HospitalsMapScreen extends ConsumerStatefulWidget {
  final List<Hospital> hospitals;

  const HospitalsMapScreen({super.key, required this.hospitals});

  @override
  ConsumerState<HospitalsMapScreen> createState() =>
      _HospitalsMapScreenState();
}

class _HospitalsMapScreenState extends ConsumerState<HospitalsMapScreen> {
  GoogleMapController? _controller;
  String? _selectedHospitalId;

  LatLng get _center {
    final h = widget.hospitals.first; // nearest (list is distance-sorted)
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

  Set<Marker> get _markers => {
    for (final h in widget.hospitals)
      Marker(
        markerId: MarkerId(h.id),
        position: LatLng(h.latitude, h.longitude),
        infoWindow: InfoWindow(
          title: h.name,
          snippet: '${h.distanceKm.toStringAsFixed(1)} km away',
        ),
        onTap: () => _selectHospital(h),
      ),
  };

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text('Hospitals map', style: context.fsmText.titleLarge),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 12),
              style: palette.isDark ? kDarkMapStyle : null,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onTap: (_) => setState(() => _selectedHospitalId = null),
              onMapCreated: (c) {
                _controller = c;
                _fitToMarkers();
              },
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
                      onDirections: () => openHospitalDirections(ref, selected),
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
    await _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
  }
}
