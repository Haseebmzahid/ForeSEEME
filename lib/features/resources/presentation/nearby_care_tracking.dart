import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/hospital.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/location_result.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/nearby_hospitals_result.dart';
import 'package:fyp_foreseeme/features/resources/presentation/nearby_hospitals_providers.dart';

/// Shares the directory's exact filtering with the map as its distances change.
class NearbyCareMapArguments {
  const NearbyCareMapArguments(this.initial, this.filter);
  final NearbyHospitalsResult initial;
  final List<Hospital> Function(List<Hospital>) filter;
}

/// Owns the GPS subscription for the visible directory or map route.
class NearbyCareTracking extends ConsumerStatefulWidget {
  const NearbyCareTracking({
    super.key,
    required this.initial,
    required this.builder,
  });

  final NearbyHospitalsResult initial;
  final Widget Function(
    NearbyHospitalsResult result,
    LocationStatus? loss,
    bool lookupDelayed,
  )
  builder;

  @override
  ConsumerState<NearbyCareTracking> createState() =>
      _NearbyCareTrackingState();
}

class _NearbyCareTrackingState extends ConsumerState<NearbyCareTracking>
    with WidgetsBindingObserver {
  StreamSubscription<LocationResult>? _subscription;
  Future<void>? _cancelling;
  int _generation = 0;
  bool _starting = false;
  bool _lookingUp = false;
  bool _lookupDelayed = false;
  bool _routeActive = false;
  LocationStatus? _loss;
  late bool _foreground;
  late NearbyHospitalsResult _result;
  late LocationResult? _searchOrigin;
  final _sinceLookup = Stopwatch();

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _foreground =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    _setInitial();
  }

  void _setInitial() {
    _result = widget.initial;
    _searchOrigin = widget.initial.devicePosition;
    _sinceLookup
      ..reset()
      ..start();
    _loss = null;
    _lookupDelayed = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = ModalRoute.isCurrentOf(context) ?? true;
    _syncTracking();
  }

  @override
  void didUpdateWidget(NearbyCareTracking oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.initial, oldWidget.initial)) {
      _stop();
      _setInitial();
      _syncTracking();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTracking();
  }

  void _syncTracking() {
    if (!_routeActive || !_foreground) {
      _stop();
    } else if (_searchOrigin != null &&
        _loss == null &&
        _subscription == null &&
        !_starting) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    final generation = _generation;
    _starting = true;
    await _cancelling;
    if (!mounted || generation != _generation) return;
    _starting = false;
    _subscription = ref
        .read(locationServiceProvider)
        .watchLocation()
        .listen(
          (fix) => _onFix(fix, generation),
          onError: (Object error, StackTrace stack) =>
              _locationLost(LocationStatus.noFix, generation),
          onDone: () => _locationLost(LocationStatus.noFix, generation),
        );
  }

  void _stop() {
    _generation++;
    _starting = false;
    _lookingUp = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) _cancelling = subscription.cancel();
  }

  void _locationLost(LocationStatus status, int generation) {
    if (!mounted || generation != _generation) return;
    _stop();
    setState(() => _loss = status);
  }

  void _onFix(LocationResult fix, int generation) {
    if (!mounted || generation != _generation) return;
    if (fix.status != LocationStatus.granted) {
      _locationLost(fix.status, generation);
      return;
    }
    if (!fix.hasValidFix) return;

    final previous = _result.devicePosition!;
    final distance = _distance(previous, fix);
    if (distance >= 0.05) {
      setState(() => _result = _atPosition(_result, fix));
    }
    if (!_lookingUp &&
        _sinceLookup.elapsed >= const Duration(minutes: 1) &&
        _distance(_searchOrigin!, fix) >= 1) {
      unawaited(_searchAt(fix, generation));
    }
  }

  Future<void> _searchAt(LocationResult fix, int generation) async {
    _lookingUp = true;
    _sinceLookup.reset();
    try {
      final refreshed = await ref
          .read(placesRepositoryProvider)
          .nearbyHospitals(
            latitude: fix.latitude!,
            longitude: fix.longitude!,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _searchOrigin = fix;
        _result = _atPosition(refreshed, _result.devicePosition!);
        _lookupDelayed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _lookupDelayed = true);
      }
    } finally {
      if (generation == _generation) _lookingUp = false;
    }
  }

  double _distance(LocationResult a, LocationResult b) => distanceBetweenKm(
    a.latitude!,
    a.longitude!,
    b.latitude!,
    b.longitude!,
  );

  NearbyHospitalsResult _atPosition(
    NearbyHospitalsResult result,
    LocationResult fix,
  ) => result.measuredFrom(
    fix.latitude!,
    fix.longitude!,
    devicePosition: fix,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_result, _loss, _lookupDelayed);
}
