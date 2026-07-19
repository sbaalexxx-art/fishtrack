import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../models/station.dart';
import '../../services/community_service.dart';
import 'home_map.dart';

class HomeMapRenderer extends StatefulWidget {
  const HomeMapRenderer({
    super.key,
    required this.reports,
    this.stations = const [],
    this.onReportTap,
    this.onStationTap,
    this.currentLocation,
    this.onMapReady,
    this.onMapboxMapCreated,
    this.baseLayer = MapBaseLayer.standard,
    this.overlays = const {
      MapOverlay.waterStations,
      MapOverlay.communityReports,
    },
    this.favoriteStationIds = const {},
    this.recentCatches = const [],
  });

  final List<CommunityPost> reports;
  final List<Station> stations;
  final ValueChanged<CommunityPost>? onReportTap;
  final ValueChanged<Station>? onStationTap;
  final LatLng? currentLocation;
  final VoidCallback? onMapReady;
  final ValueChanged<mapbox.MapboxMap>? onMapboxMapCreated;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;
  final Set<String> favoriteStationIds;
  final List<CommunityPost> recentCatches;

  @override
  State<HomeMapRenderer> createState() => _HomeMapRendererState();
}

class _HomeMapRendererState extends State<HomeMapRenderer>
    with AutomaticKeepAliveClientMixin<HomeMapRenderer> {
  static const _satelliteStreetsStyle =
      'mapbox://styles/mapbox/satellite-streets-v12';

  static const _fallbackCamera = LatLng(44.8148, 21.3895);

  static const _mapWidgetKey = ValueKey<String>('aifishmap-home-mapbox');
  static const _reportMarkerImageSize = 144;
  static const _reportMarkerIconScale = .72;
  static const _importantReportMarkerIconScale = .82;
  static const _reportMarkerStyleImagePrefix = 'fluvi-home-report-';
  static const _reportMarkerPixelRatio = 3.0;

  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _reportAnnotationManager;
  mapbox.CircleAnnotationManager? _stationAnnotationManager;
  dynamic _reportTapEvents;
  dynamic _stationTapEvents;
  Future<void> _annotationSyncQueue = Future<void>.value();
  int _annotationSyncRevision = 0;
  int _styleRevision = 0;
  bool _isStyleLoaded = false;
  final Map<ReportCategory?, Uint8List> _reportMarkerImageCache = {};
  final Set<String> _registeredReportStyleImageIds = {};

  late final mapbox.CameraOptions _initialCameraOptions;

  bool _didApplyLocationCamera = false;

  @override
  void initState() {
    super.initState();

    final initialCenter = widget.currentLocation ?? _fallbackCamera;

    _initialCameraOptions = _cameraFor(initialCenter, zoom: 12.5);

    _didApplyLocationCamera = widget.currentLocation != null;
  }

  @override
  void didUpdateWidget(covariant HomeMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!listEquals(oldWidget.reports, widget.reports) ||
        !listEquals(oldWidget.stations, widget.stations) ||
        !setEquals(oldWidget.overlays, widget.overlays) ||
        !setEquals(oldWidget.favoriteStationIds, widget.favoriteStationIds)) {
      _scheduleAnnotationSync();
    }

    final location = widget.currentLocation;

    if (location == null || _didApplyLocationCamera) {
      return;
    }

    _didApplyLocationCamera = true;

    _setCamera(location, zoom: 12.5);
  }

  Set<Factory<OneSequenceGestureRecognizer>> _buildGestureRecognizers() {
    return {
      Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
      Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
    };
  }

  Future<void> _handleMapCreated(mapbox.MapboxMap mapboxMap) async {
    final previousMap = _mapboxMap;
    if (previousMap != null && !identical(previousMap, mapboxMap)) {
      unawaited(_releaseAnnotationManagers(previousMap));
    }
    _mapboxMap = mapboxMap;
    _isStyleLoaded = false;
    _styleRevision++;
    _annotationSyncRevision++;
    _registeredReportStyleImageIds.clear();

    final location = widget.currentLocation;

    if (location != null && !_didApplyLocationCamera) {
      _didApplyLocationCamera = true;

      _setCamera(location, zoom: 12.5);
    }

    try {
      await mapboxMap.scaleBar.updateSettings(
        mapbox.ScaleBarSettings(enabled: false),
      );
    } on Exception {
      // The Home map remains usable if an ornament update is unavailable.
    }

    if (!mounted || !identical(_mapboxMap, mapboxMap)) return;

    widget.onMapboxMapCreated?.call(mapboxMap);
    widget.onMapReady?.call();
  }

  void _handleStyleLoaded(mapbox.StyleLoadedEventData _) {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !mounted) return;

    _isStyleLoaded = true;
    final styleRevision = ++_styleRevision;
    _annotationSyncRevision++;
    _registeredReportStyleImageIds.clear();
    _annotationSyncQueue = _annotationSyncQueue
        .then<void>(
          (_) => _restoreAnnotationsAfterStyleLoad(mapboxMap, styleRevision),
        )
        .catchError((Object _, StackTrace _) {
          // A style restoration error must not make the base map unusable.
        });
  }

  Future<void> _restoreAnnotationsAfterStyleLoad(
    mapbox.MapboxMap mapboxMap,
    int styleRevision,
  ) async {
    if (!_canUseStyle(mapboxMap, styleRevision)) return;

    await _releaseAnnotationManagers(mapboxMap);
    if (!_canUseStyle(mapboxMap, styleRevision)) return;

    await _bindAnnotationManagers(mapboxMap);
  }

  Future<void> _bindAnnotationManagers(mapbox.MapboxMap mapboxMap) async {
    if (!_isStyleLoaded || !_isCurrentMap(mapboxMap)) return;
    if (_reportAnnotationManager != null && _stationAnnotationManager != null) {
      _scheduleAnnotationSync();
      return;
    }

    try {
      _reportAnnotationManager = await mapboxMap.annotations
          .createPointAnnotationManager();
      if (!_isCurrentMap(mapboxMap)) {
        await _releaseAnnotationManagers(mapboxMap);
        return;
      }
      _reportTapEvents = _reportAnnotationManager?.tapEvents(
        onTap: _handleReportAnnotationTap,
      );

      _stationAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      if (!_isCurrentMap(mapboxMap)) {
        await _releaseAnnotationManagers(mapboxMap);
        return;
      }
      _stationTapEvents = _stationAnnotationManager?.tapEvents(
        onTap: _handleStationAnnotationTap,
      );
      _scheduleAnnotationSync();
    } on Exception {
      await _releaseAnnotationManagers(mapboxMap);
    }
  }

  Future<void> _releaseAnnotationManagers(mapbox.MapboxMap mapboxMap) async {
    final reportManager = _reportAnnotationManager;
    final stationManager = _stationAnnotationManager;
    final reportTapEvents = _reportTapEvents;
    final stationTapEvents = _stationTapEvents;

    _reportAnnotationManager = null;
    _stationAnnotationManager = null;
    _reportTapEvents = null;
    _stationTapEvents = null;

    for (final tapEvents in [reportTapEvents, stationTapEvents]) {
      if (tapEvents == null) continue;
      try {
        await tapEvents.cancel();
      } on Exception {
        // The native event stream may already be closed with the map.
      }
    }

    if (reportManager != null) {
      try {
        await mapboxMap.annotations.removeAnnotationManager(reportManager);
      } on Exception {
        // The native manager may already be released with the map or style.
      }
    }
    if (stationManager != null) {
      try {
        await mapboxMap.annotations.removeAnnotationManager(stationManager);
      } on Exception {
        // The native manager may already be released with the map or style.
      }
    }
  }

  void _scheduleAnnotationSync() {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final revision = ++_annotationSyncRevision;
    _annotationSyncQueue = _annotationSyncQueue
        .then<void>((_) => _syncAnnotations(mapboxMap, revision))
        .catchError((Object _, StackTrace _) {
          // Annotation errors must not make the base map unusable.
        });
  }

  Future<void> _syncAnnotations(
    mapbox.MapboxMap mapboxMap,
    int revision,
  ) async {
    if (!_canSyncAnnotations(mapboxMap, revision)) return;

    try {
      await _syncReportAnnotations(mapboxMap, revision);
    } on Exception {
      // Reports can fail independently without affecting other map layers.
    }
    if (!_canSyncAnnotations(mapboxMap, revision)) return;

    try {
      await _syncStationAnnotations(mapboxMap, revision);
    } on Exception {
      // Stations can fail independently without affecting the base map.
    }
  }

  Future<void> _syncReportAnnotations(
    mapbox.MapboxMap mapboxMap,
    int revision,
  ) async {
    final manager = _reportAnnotationManager;
    if (manager == null || !_canSyncAnnotations(mapboxMap, revision)) return;

    final options = await _reportAnnotationOptions(mapboxMap, revision);
    if (!_canSyncAnnotations(mapboxMap, revision) ||
        !identical(_reportAnnotationManager, manager)) {
      return;
    }
    await manager.deleteAll();
    if (!_canSyncAnnotations(mapboxMap, revision) ||
        !identical(_reportAnnotationManager, manager)) {
      return;
    }
    if (options.isNotEmpty) await manager.createMulti(options);
  }

  Future<void> _syncStationAnnotations(
    mapbox.MapboxMap mapboxMap,
    int revision,
  ) async {
    final manager = _stationAnnotationManager;
    if (manager == null || !_canSyncAnnotations(mapboxMap, revision)) return;

    final options = _stationAnnotationOptions();
    await manager.deleteAll();
    if (!_canSyncAnnotations(mapboxMap, revision) ||
        !identical(_stationAnnotationManager, manager)) {
      return;
    }
    if (options.isNotEmpty) await manager.createMulti(options);
  }

  Future<List<mapbox.PointAnnotationOptions>> _reportAnnotationOptions(
    mapbox.MapboxMap mapboxMap,
    int revision,
  ) async {
    if (!widget.overlays.contains(MapOverlay.communityReports)) {
      return const <mapbox.PointAnnotationOptions>[];
    }

    final seen = <String>{};
    final options = <mapbox.PointAnnotationOptions>[];
    for (final report in widget.reports) {
      final latitude = report.latitude;
      final longitude = report.longitude;
      if (!_isValidCoordinate(latitude, longitude) || !seen.add(report.id)) {
        continue;
      }
      final style = _reportMarkerStyle(report.reportCategory);
      final imageId = await _ensureReportStyleImage(
        mapboxMap,
        revision,
        report.reportCategory,
      );
      if (imageId == null) continue;
      options.add(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(longitude!, latitude!),
          ),
          iconAnchor: mapbox.IconAnchor.CENTER,
          iconImage: imageId,
          iconSize: style.isImportant
              ? _importantReportMarkerIconScale
              : _reportMarkerIconScale,
          symbolSortKey: style.isImportant ? 35 : 30,
          customData: <String, Object>{
            'type': 'community_report',
            'reportId': report.id,
          },
        ),
      );
    }
    return options;
  }

  Future<String?> _ensureReportStyleImage(
    mapbox.MapboxMap mapboxMap,
    int revision,
    ReportCategory? category,
  ) async {
    final styleCategory = category == ReportCategory.other ? null : category;
    final imageId = _reportStyleImageId(styleCategory);
    if (_registeredReportStyleImageIds.contains(imageId)) return imageId;

    final image = await _reportMarkerImage(styleCategory);
    if (image == null || !_canSyncAnnotations(mapboxMap, revision)) {
      return null;
    }

    try {
      await mapboxMap.style.addStyleImage(
        imageId,
        _reportMarkerPixelRatio,
        mapbox.MbxImage(
          width: _reportMarkerImageSize,
          height: _reportMarkerImageSize,
          data: image,
        ),
        false,
        const [],
        const [],
        null,
      );
      if (!_canSyncAnnotations(mapboxMap, revision)) return null;
      _registeredReportStyleImageIds.add(imageId);
      return imageId;
    } on Exception {
      if (styleCategory != null) {
        return _ensureReportStyleImage(mapboxMap, revision, null);
      }
      return null;
    }
  }

  String _reportStyleImageId(ReportCategory? category) =>
      '$_reportMarkerStyleImagePrefix${category?.name ?? 'other'}';

  Future<Uint8List?> _reportMarkerImage(ReportCategory? category) async {
    final cached = _reportMarkerImageCache[category];
    if (cached != null) return cached;

    try {
      final image = await _renderReportMarker(_reportMarkerStyle(category));
      _reportMarkerImageCache[category] = image;
      return image;
    } catch (_) {
      if (category != null) {
        final fallback = await _reportMarkerImage(null);
        if (fallback != null) _reportMarkerImageCache[category] = fallback;
        return fallback;
      }

      try {
        final fallback = await _renderReportMarker(
          _reportMarkerStyle(null),
          includeIcon: false,
        );
        _reportMarkerImageCache[null] = fallback;
        return fallback;
      } catch (_) {
        return null;
      }
    }
  }

  Future<Uint8List> _renderReportMarker(
    _ReportMarkerStyle style, {
    bool includeIcon = true,
  }) async {
    const size = _reportMarkerImageSize;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final outerRadius = style.isImportant ? 58.0 : 55.0;
    final fillRadius = style.isImportant ? 49.0 : 47.0;
    final markerPath = ui.Path()
      ..addOval(ui.Rect.fromCircle(center: center, radius: outerRadius));

    canvas.drawShadow(
      markerPath,
      Colors.black.withValues(alpha: .58),
      style.isImportant ? 14 : 11,
      true,
    );
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()..color = Colors.white.withValues(alpha: .98),
    );
    canvas.drawCircle(center, fillRadius, Paint()..color = style.color);
    canvas.drawCircle(
      center.translate(0, -5),
      fillRadius - 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: .16),
    );

    if (includeIcon) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(style.icon.codePoint),
          style: TextStyle(
            color: Colors.white,
            fontSize: style.isImportant ? 62 : 58,
            fontFamily: style.icon.fontFamily,
            package: style.icon.fontPackage,
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        center - Offset(iconPainter.width / 2, iconPainter.height / 2),
      );
      iconPainter.dispose();
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(size, size);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Unable to encode the report marker image.');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  _ReportMarkerStyle _reportMarkerStyle(ReportCategory? category) {
    return switch (category) {
      ReportCategory.fishActivity => const _ReportMarkerStyle(
        Icons.phishing_rounded,
        Color(0xFF1976D2),
      ),
      ReportCategory.waterClarity => const _ReportMarkerStyle(
        Icons.visibility_rounded,
        Color(0xFF0097A7),
      ),
      ReportCategory.floatingGrass => const _ReportMarkerStyle(
        Icons.grass_rounded,
        Color(0xFF00897B),
      ),
      ReportCategory.highWater => const _ReportMarkerStyle(
        Icons.arrow_upward_rounded,
        Color(0xFF1565C0),
      ),
      ReportCategory.lowWater => const _ReportMarkerStyle(
        Icons.arrow_downward_rounded,
        Color(0xFF0288D1),
      ),
      ReportCategory.strongCurrent => const _ReportMarkerStyle(
        Icons.waves_rounded,
        Color(0xFF0069C0),
      ),
      ReportCategory.noCurrent => const _ReportMarkerStyle(
        Icons.horizontal_rule_rounded,
        Color(0xFF4A90A4),
      ),
      ReportCategory.boats => const _ReportMarkerStyle(
        Icons.directions_boat_filled_rounded,
        Color(0xFF0277BD),
      ),
      ReportCategory.goodFishing => const _ReportMarkerStyle(
        Icons.check_circle_rounded,
        Color(0xFF2E7D32),
      ),
      ReportCategory.parkingAvailable => const _ReportMarkerStyle(
        Icons.local_parking_rounded,
        Color(0xFF43A047),
      ),
      ReportCategory.poaching => const _ReportMarkerStyle(
        Icons.warning_amber_rounded,
        Color(0xFFD32F2F),
        isImportant: true,
      ),
      ReportCategory.theftWarning => const _ReportMarkerStyle(
        Icons.shield_rounded,
        Color(0xFFE64A19),
        isImportant: true,
      ),
      ReportCategory.accessBlocked => const _ReportMarkerStyle(
        Icons.block_rounded,
        Color(0xFFC62828),
        isImportant: true,
      ),
      ReportCategory.poorFishing => const _ReportMarkerStyle(
        Icons.report_problem_rounded,
        Color(0xFFEF6C00),
      ),
      ReportCategory.other || null => const _ReportMarkerStyle(
        Icons.info_outline_rounded,
        Color(0xFF546E7A),
      ),
    };
  }

  List<mapbox.CircleAnnotationOptions> _stationAnnotationOptions() {
    final seen = <String>{};
    final options = <mapbox.CircleAnnotationOptions>[];
    for (final station in widget.stations) {
      if (!_isValidCoordinate(station.latitude, station.longitude) ||
          !seen.add(station.id)) {
        continue;
      }
      final isFavorite = widget.favoriteStationIds.contains(station.id);
      options.add(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(station.longitude, station.latitude),
          ),
          circleRadius: isFavorite ? 7.5 : 6.5,
          circleColor: _mapboxColor(
            isFavorite ? const Color(0xFFFFD166) : const Color(0xFF20B8D8),
          ),
          circleOpacity: 1,
          circleStrokeColor: _mapboxColor(
            isFavorite ? Colors.white : const Color(0xFF06141D),
          ),
          circleStrokeWidth: isFavorite ? 3 : 2.2,
          circleSortKey: isFavorite ? 40 : 20,
          customData: <String, Object>{
            'type': 'water_station',
            'stationId': station.id,
          },
        ),
      );
    }
    return options;
  }

  bool _canSyncAnnotations(mapbox.MapboxMap mapboxMap, int revision) =>
      mounted &&
      identical(_mapboxMap, mapboxMap) &&
      _isStyleLoaded &&
      revision == _annotationSyncRevision;

  bool _canUseStyle(mapbox.MapboxMap mapboxMap, int styleRevision) =>
      mounted &&
      identical(_mapboxMap, mapboxMap) &&
      _isStyleLoaded &&
      styleRevision == _styleRevision;

  bool _isCurrentMap(mapbox.MapboxMap mapboxMap) =>
      mounted && identical(_mapboxMap, mapboxMap);

  static bool _isValidCoordinate(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  void _handleReportAnnotationTap(mapbox.PointAnnotation annotation) {
    final reportId = annotation.customData?['reportId']?.toString();
    if (reportId == null || !mounted) return;

    CommunityPost? report;
    for (final item in widget.reports) {
      if (item.id == reportId) {
        report = item;
        break;
      }
    }
    if (report != null) widget.onReportTap?.call(report);
  }

  void _handleStationAnnotationTap(mapbox.CircleAnnotation annotation) {
    final stationId = annotation.customData?['stationId']?.toString();
    if (stationId == null || !mounted) return;

    Station? station;
    for (final item in widget.stations) {
      if (item.id == stationId) {
        station = item;
        break;
      }
    }
    if (station != null) widget.onStationTap?.call(station);
  }

  static int _mapboxColor(Color color) {
    return ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
  }

  mapbox.CameraOptions _cameraFor(LatLng target, {required double zoom}) {
    return mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(target.longitude, target.latitude),
      ),
      zoom: zoom,
    );
  }

  void _setCamera(LatLng target, {required double zoom}) {
    final mapboxMap = _mapboxMap;

    if (mapboxMap == null) {
      return;
    }

    mapboxMap.setCamera(_cameraFor(target, zoom: zoom));
  }

  @override
  void dispose() {
    _annotationSyncRevision++;
    _styleRevision++;
    _isStyleLoaded = false;
    _registeredReportStyleImageIds.clear();
    _reportMarkerImageCache.clear();
    final mapboxMap = _mapboxMap;
    _mapboxMap = null;
    if (mapboxMap != null) {
      unawaited(_releaseAnnotationManagers(mapboxMap));
    }
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: const Color(0xFF101820),
          child: SizedBox.expand(
            child: mapbox.MapWidget(
              key: _mapWidgetKey,
              textureView: true,
              styleUri: _satelliteStreetsStyle,
              // ignore: deprecated_member_use
              cameraOptions: _initialCameraOptions,
              gestureRecognizers: _buildGestureRecognizers(),
              onMapCreated: _handleMapCreated,
              onStyleLoadedListener: _handleStyleLoaded,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportMarkerStyle {
  const _ReportMarkerStyle(this.icon, this.color, {this.isImportant = false});

  final IconData icon;
  final Color color;
  final bool isImportant;
}
