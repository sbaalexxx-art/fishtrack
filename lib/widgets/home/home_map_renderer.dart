import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/map/map_theme_style.dart';
import '../../services/community_service.dart';
import 'home_map.dart';

class HomeMapRenderer extends StatefulWidget {
  const HomeMapRenderer({
    super.key,
    required this.reports,
    required this.initialCamera,
    this.onMapTap,
    this.onReportTap,
    this.currentLocation,
    this.explorationCenter,
    this.onMapReady,
    this.onMapboxMapCreated,
    this.baseLayer = MapBaseLayer.satellite,
    this.overlays = const {MapOverlay.communityReports},
    this.recentCatches = const [],
  });

  final List<CommunityPost> reports;
  final LatLng initialCamera;
  final VoidCallback? onMapTap;
  final ValueChanged<CommunityPost>? onReportTap;
  final LatLng? currentLocation;
  final LatLng? explorationCenter;
  final VoidCallback? onMapReady;
  final ValueChanged<mapbox.MapboxMap>? onMapboxMapCreated;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;
  final List<CommunityPost> recentCatches;

  @override
  State<HomeMapRenderer> createState() => _HomeMapRendererState();
}

class _HomeMapRendererState extends State<HomeMapRenderer>
    with AutomaticKeepAliveClientMixin<HomeMapRenderer> {
  static const _mapWidgetKey = ValueKey<String>('aifishmap-home-mapbox');
  static const _reportMarkerImageSize = 144;
  static const _reportMarkerIconScale = .72;
  static const _importantReportMarkerIconScale = .82;
  static const _reportMarkerStyleImagePrefix = 'fluvi-home-report-';
  static const _reportMarkerPixelRatio = 3.0;
  static const _mapTapInteractionId = 'fluvi-home-open-full-map';

  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _reportAnnotationManager;
  mapbox.CircleAnnotationManager? _locationContextAnnotationManager;
  dynamic _reportTapEvents;
  Future<void> _annotationSyncQueue = Future<void>.value();
  int _annotationSyncRevision = 0;
  int _styleRevision = 0;
  bool _isStyleLoaded = false;
  final Map<ReportCategory?, Uint8List> _reportMarkerImageCache = {};
  final Set<String> _registeredReportStyleImageIds = {};

  @override
  void didUpdateWidget(covariant HomeMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!listEquals(oldWidget.reports, widget.reports) ||
        !setEquals(oldWidget.overlays, widget.overlays) ||
        oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.explorationCenter != widget.explorationCenter) {
      _scheduleAnnotationSync();
    }

    if (oldWidget.baseLayer != widget.baseLayer) {
      _reloadResolvedStyle();
    }
  }

  String _resolvedStyleUri() => switch (widget.baseLayer) {
    MapBaseLayer.satellite => MapThemeStyle.satellite,
    MapBaseLayer.standard || MapBaseLayer.fishingMode => MapThemeStyle.standard,
  };

  void _reloadResolvedStyle() {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    unawaited(mapboxMap.loadStyleURI(_resolvedStyleUri()));
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
      previousMap.removeInteraction(_mapTapInteractionId);
      unawaited(_releaseAnnotationManagers(previousMap));
    }
    _mapboxMap = mapboxMap;
    _isStyleLoaded = false;
    _styleRevision++;
    _annotationSyncRevision++;
    _registeredReportStyleImageIds.clear();

    try {
      await mapboxMap.scaleBar.updateSettings(
        mapbox.ScaleBarSettings(enabled: false),
      );
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(
          enabled: true,
          position: mapbox.OrnamentPosition.TOP_LEFT,
          marginLeft: 12,
          marginTop: 12,
          opacity: .82,
          fadeWhenFacingNorth: true,
          clickable: true,
        ),
      );
    } on Exception {
      // The Home map remains usable if an ornament update is unavailable.
    }

    if (!mounted || !identical(_mapboxMap, mapboxMap)) return;

    if (widget.onMapTap != null) {
      mapboxMap.addInteraction(
        mapbox.TapInteraction.onMap((gestureContext) {
          unawaited(_handleMapTap(gestureContext));
        }, stopPropagation: false),
        interactionID: _mapTapInteractionId,
      );
    }
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
    if (_reportAnnotationManager != null &&
        _locationContextAnnotationManager != null) {
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

      _locationContextAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      if (!_isCurrentMap(mapboxMap)) {
        await _releaseAnnotationManagers(mapboxMap);
        return;
      }
      _scheduleAnnotationSync();
    } on Exception {
      await _releaseAnnotationManagers(mapboxMap);
    }
  }

  Future<void> _releaseAnnotationManagers(mapbox.MapboxMap mapboxMap) async {
    final reportManager = _reportAnnotationManager;
    final locationContextManager = _locationContextAnnotationManager;
    final reportTapEvents = _reportTapEvents;

    _reportAnnotationManager = null;
    _locationContextAnnotationManager = null;
    _reportTapEvents = null;

    if (reportTapEvents != null) {
      try {
        await reportTapEvents.cancel();
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
    if (locationContextManager != null) {
      try {
        await mapboxMap.annotations.removeAnnotationManager(
          locationContextManager,
        );
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
      await _syncLocationContextAnnotations(mapboxMap, revision);
    } on Exception {
      // Location context can fail without affecting the other map layers.
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

  Future<void> _syncLocationContextAnnotations(
    mapbox.MapboxMap mapboxMap,
    int revision,
  ) async {
    final manager = _locationContextAnnotationManager;
    if (manager == null || !_canSyncAnnotations(mapboxMap, revision)) return;

    final options = _locationContextAnnotationOptions();
    await manager.deleteAll();
    if (!_canSyncAnnotations(mapboxMap, revision) ||
        !identical(_locationContextAnnotationManager, manager)) {
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

  List<mapbox.CircleAnnotationOptions> _locationContextAnnotationOptions() {
    final options = <mapbox.CircleAnnotationOptions>[];
    final currentLocation = widget.currentLocation;
    if (currentLocation != null) {
      options.add(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(
              currentLocation.longitude,
              currentLocation.latitude,
            ),
          ),
          circleRadius: 8,
          circleColor: _mapboxColor(const Color(0xFF67D04B)),
          circleOpacity: 1,
          circleStrokeColor: _mapboxColor(Colors.white),
          circleStrokeWidth: 3,
          circleSortKey: 60,
          customData: const <String, Object>{'type': 'current_location'},
        ),
      );
    }

    final explorationCenter = widget.explorationCenter;
    if (explorationCenter != null) {
      options.add(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(
              explorationCenter.longitude,
              explorationCenter.latitude,
            ),
          ),
          circleRadius: 10,
          circleColor: _mapboxColor(const Color(0xFF12D8D6)),
          circleOpacity: 1,
          circleStrokeColor: _mapboxColor(Colors.white),
          circleStrokeWidth: 3,
          circleSortKey: 70,
          customData: const <String, Object>{'type': 'exploration_target'},
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

  Future<void> _handleMapTap(
    mapbox.MapContentGestureContext gestureContext,
  ) async {
    final mapboxMap = _mapboxMap;
    final onMapTap = widget.onMapTap;
    if (mapboxMap == null || onMapTap == null || !mounted) return;

    final annotationLayerIds = <String>[
      if (_reportAnnotationManager case final manager?) manager.id,
    ];

    if (annotationLayerIds.isNotEmpty) {
      try {
        final features = await mapboxMap.queryRenderedFeatures(
          mapbox.RenderedQueryGeometry.fromScreenCoordinate(
            gestureContext.touchPosition,
          ),
          mapbox.RenderedQueryOptions(layerIds: annotationLayerIds),
        );
        if (features.any((feature) => feature != null)) return;
      } on Exception {
        // Preserve annotation routing if native hit-testing is unavailable.
        return;
      }
    }

    if (mounted && identical(_mapboxMap, mapboxMap)) onMapTap();
  }

  static int _mapboxColor(Color color) {
    return ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
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
      mapboxMap.removeInteraction(_mapTapInteractionId);
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
      child: ColoredBox(
        color: const Color(0xFF101820),
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              mapbox.MapWidget(
                key: _mapWidgetKey,
                textureView: true,
                styleUri: _resolvedStyleUri(),
                viewport: mapbox.CameraViewportState(
                  center: mapbox.Point(
                    coordinates: mapbox.Position(
                      widget.initialCamera.longitude,
                      widget.initialCamera.latitude,
                    ),
                  ),
                  zoom: 12.5,
                ),
                gestureRecognizers: _buildGestureRecognizers(),
                onMapCreated: _handleMapCreated,
                onStyleLoadedListener: _handleStyleLoaded,
              ),
            ],
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
