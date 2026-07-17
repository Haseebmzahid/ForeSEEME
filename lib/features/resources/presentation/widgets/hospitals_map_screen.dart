import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';

/// Full-screen map of the nearby hospitals ("View on map"). Each hospital is a
/// marker whose info window opens Google Maps directions on tap. The device
/// location blue-dot is shown when location permission is granted.
///
/// Reused from the list screen via `Navigator.push`; kept self-contained so the
/// list widget tests never instantiate the native map view.
class HospitalsMapScreen extends StatefulWidget {
  final List<Hospital> hospitals;
  final void Function(Hospital) onDirections;

  const HospitalsMapScreen({
    super.key,
    required this.hospitals,
    required this.onDirections,
  });

  @override
  State<HospitalsMapScreen> createState() => _HospitalsMapScreenState();
}

class _HospitalsMapScreenState extends State<HospitalsMapScreen> {
  GoogleMapController? _controller;

  LatLng get _center {
    final h = widget.hospitals.first; // nearest (list is distance-sorted)
    return LatLng(h.latitude, h.longitude);
  }

  Set<Marker> get _markers => {
    for (final h in widget.hospitals)
      Marker(
        markerId: MarkerId(h.id),
        position: LatLng(h.latitude, h.longitude),
        infoWindow: InfoWindow(
          title: h.name,
          snippet: '${h.distanceKm.toStringAsFixed(1)} km · Tap for directions',
          onTap: () => widget.onDirections(h),
        ),
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
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Hospitals map', style: context.fsmText.titleLarge),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _center, zoom: 12),
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
        onMapCreated: (c) {
          _controller = c;
          _fitToMarkers();
        },
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
