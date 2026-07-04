import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';
import '../../screens/station_details_page.dart';
import '../../services/location_service.dart';
import '../../services/water_service.dart';
import '../home/home_map.dart';
import '../home/map_preview.dart';

class HomePremiumMap extends StatefulWidget {
  const HomePremiumMap({super.key, this.onTap, this.child});

  final VoidCallback? onTap;
  final Widget? child;

  @override
  State<HomePremiumMap> createState() => _HomePremiumMapState();
}

class _HomePremiumMapState extends State<HomePremiumMap> {
  final WaterService _waterService = WaterService();
  final LocationService _locationService = const LocationService();
  final MapController _mapController = MapController();
  late Future<List<Station>> _stationsFuture;
  LatLng? _currentLocation;
  LocationFailureReason? _locationFailure;
  bool _isLocating = false;
  bool _isMapReady = false;
  bool _pendingRecenter = false;

  @override
  void initState() {
    super.initState();
    _stationsFuture = _waterService.getStations();
    if (widget.child == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _stationsFuture = _waterService.getStations();
    });
  }

  void _openStation(Station station) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailsPage(station: station),
      ),
    );
  }

  Future<void> _locateUser({bool recenter = false}) async {
    if (_isLocating) {
      return;
    }

    final knownLocation = _currentLocation;
    if (knownLocation != null && recenter) {
      _recenter(knownLocation);
      return;
    }

    setState(() {
      _isLocating = true;
      _locationFailure = null;
      _pendingRecenter = recenter;
    });

    try {
      final position = await _locationService.determinePosition();
      if (!mounted) {
        return;
      }

      final location = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = location;
        _locationFailure = null;
      });

      if (_pendingRecenter) {
        _recenter(location);
      }
    } on LocationFailure catch (failure) {
      if (mounted) {
        setState(() {
          _locationFailure = failure.reason;
          _pendingRecenter = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _recenter(LatLng location) {
    if (!_isMapReady) {
      _pendingRecenter = true;
      return;
    }

    _mapController.move(location, 13.5);
    _pendingRecenter = false;
  }

  void _onMapReady() {
    _isMapReady = true;
    final location = _currentLocation;
    if (_pendingRecenter && location != null) {
      _recenter(location);
    }
  }

  void _handleLocationAction() {
    final location = _currentLocation;
    if (location != null) {
      _recenter(location);
      return;
    }

    _locateUser(recenter: true);
  }

  String get _locationLabel {
    if (_isLocating) {
      return 'Locating...';
    }

    return switch (_locationFailure) {
      LocationFailureReason.serviceDisabled => 'Location is off',
      LocationFailureReason.permissionDenied => 'Permission denied',
      LocationFailureReason.permissionDeniedForever => 'Enable in settings',
      LocationFailureReason.unavailable => 'Location unavailable',
      null => 'Current Location',
    };
  }

  Widget _buildMapContent() {
    final customChild = widget.child;
    if (customChild != null) {
      return customChild;
    }

    return FutureBuilder<List<Station>>(
      future: _stationsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return HomeMap(
            stations: snapshot.data!,
            onStationTap: _openStation,
            mapController: _mapController,
            currentLocation: _currentLocation,
            onMapReady: _onMapReady,
          );
        }

        if (snapshot.hasError) {
          return ColoredBox(
            color: const Color(0xFF16212B),
            child: Center(
              child: IconButton(
                tooltip: 'Retry loading stations',
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
            ),
          );
        }

        return const ColoredBox(
          color: Color(0xFF16212B),
          child: Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF67D04B),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = 28.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .42),
            blurRadius: 30,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: const Color(0xFF2B7FFF).withValues(alpha: .08),
            blurRadius: 22,
            spreadRadius: -10,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final searchWidth = (constraints.maxWidth - 58).clamp(210.0, 560.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                MapPreview(onTap: widget.onTap, child: _buildMapContent()),

                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .09),
                      ),
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, .38, 1],
                        colors: [
                          Colors.black.withValues(alpha: .10),
                          Colors.transparent,
                          Colors.black.withValues(alpha: .38),
                        ],
                      ),
                    ),
                  ),
                ),

                // SEARCH
                Positioned(
                  left: 8,
                  top: 14,
                  child: _GlassSurface(
                    borderRadius: 22,
                    blur: 22,
                    child: SizedBox(
                      width: searchWidth,
                      height: 36,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 15),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 19,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Search for lake, river, spot...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: .1,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // FLOATING BUTTONS
                Positioned(
                  right: 14,
                  top: 76,
                  child: Column(
                    children: [
                      _FloatingButton(
                        Icons.my_location_rounded,
                        onTap: _handleLocationAction,
                        isLoading: _isLocating,
                      ),
                      const SizedBox(height: 10),
                      const _FloatingButton(Icons.layers_rounded),
                      const SizedBox(height: 10),
                      const _FloatingButton(Icons.filter_alt_rounded),
                    ],
                  ),
                ),

                // LOCATION
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleLocationAction,
                    child: _GlassSurface(
                      borderRadius: 18,
                      blur: 20,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLocating)
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF67D04B),
                                ),
                              )
                            else
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFF67D04B),
                                size: 17,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              _locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                letterSpacing: .1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // LIVE
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF67D04B),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF67D04B).withValues(alpha: .30),
                          blurRadius: 14,
                          spreadRadius: -3,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sensors_rounded,
                          size: 14,
                          color: Colors.black,
                        ),
                        SizedBox(width: 5),
                        Text(
                          "LIVE",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: .5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    required this.borderRadius,
    required this.blur,
  });

  final Widget child;
  final double borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF101720).withValues(alpha: .58),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: .13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FloatingButton extends StatelessWidget {
  const _FloatingButton(this.icon, {this.onTap, this.isLoading = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 17,
      blur: 22,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Center(
              child: isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      icon,
                      color: Colors.white.withValues(alpha: .92),
                      size: 22,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
