import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

enum HydroPublicFeatureType { river, reservoir, dam }

class HydroPublicFeatureSelection {
  const HydroPublicFeatureSelection({
    required this.type,
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final HydroPublicFeatureType type;
  final String displayName;
  final double latitude;
  final double longitude;
}

class HydroOverlayPreferences {
  const HydroOverlayPreferences({
    this.enabled = true,
    this.rivers = true,
    this.reservoirs = true,
    this.dams = true,
  });

  final bool enabled;
  final bool rivers;
  final bool reservoirs;
  final bool dams;

  HydroOverlayPreferences copyWith({
    bool? enabled,
    bool? rivers,
    bool? reservoirs,
    bool? dams,
  }) => HydroOverlayPreferences(
    enabled: enabled ?? this.enabled,
    rivers: rivers ?? this.rivers,
    reservoirs: reservoirs ?? this.reservoirs,
    dams: dams ?? this.dams,
  );
}

/// Public cartography for the Romania Hydro country pack.
///
/// Only public presentation properties are used here. Canonical identifiers,
/// topology, measurements, evidence and operational state stay in Supabase and
/// are resolved through the existing mobile contracts after a selection.
class HydroRoMapboxOverlay {
  HydroRoMapboxOverlay._();

  static const String tilesetUri = 'mapbox://sba85.fluviai-hydro-ro';
  static const String sourceId = 'fluviai-hydro-ro-source';

  static const String reservoirLayerId = 'fluviai-hydro-ro-reservoirs';
  static const String reservoirOutlineLayerId =
      'fluviai-hydro-ro-reservoir-outlines';
  static const String reservoirSelectedLayerId =
      'fluviai-hydro-ro-reservoir-selected';
  static const String reservoirSelectedOutlineLayerId =
      'fluviai-hydro-ro-reservoir-selected-outline';
  static const String riverCasingLayerId =
      'fluviai-hydro-ro-rivers-network-casing';
  static const String riverLayerId = 'fluviai-hydro-ro-rivers-network';
  static const String majorRiverCasingLayerId =
      'fluviai-hydro-ro-rivers-major-casing';
  static const String majorRiverLayerId = 'fluviai-hydro-ro-rivers-major';
  static const String danubeCasingLayerId = 'fluviai-hydro-ro-danube-casing';
  static const String danubeLayerId = 'fluviai-hydro-ro-danube';
  static const String riverSelectedCasingLayerId =
      'fluviai-hydro-ro-river-selected-casing';
  static const String riverSelectedLayerId = 'fluviai-hydro-ro-river-selected';
  static const String riverLabelLayerId = 'fluviai-hydro-ro-river-labels-local';
  static const String majorRiverLabelLayerId =
      'fluviai-hydro-ro-river-labels-major';
  static const String danubeLabelLayerId =
      'fluviai-hydro-ro-river-label-danube';
  // Legacy public-vector dam layer ids are retained for safe style cleanup.
  // RC2.2C-1D no longer renders/query-selects these generic diamond layers.
  static const String damLayerId = 'fluviai-hydro-ro-dams';
  static const String damSelectedLayerId = 'fluviai-hydro-ro-dam-selected';

  static const List<String> layerIds = <String>[
    reservoirLayerId,
    reservoirOutlineLayerId,
    reservoirSelectedLayerId,
    reservoirSelectedOutlineLayerId,
    riverCasingLayerId,
    riverLayerId,
    majorRiverCasingLayerId,
    majorRiverLayerId,
    danubeCasingLayerId,
    danubeLayerId,
    riverSelectedCasingLayerId,
    riverSelectedLayerId,
    riverLabelLayerId,
    majorRiverLabelLayerId,
    danubeLabelLayerId,
    damLayerId,
    damSelectedLayerId,
  ];

  static const List<String> _majorRiverNames = <String>[
    'mureș',
    'mures',
    'olt',
    'siret',
    'prut',
    'someș',
    'somes',
    'jiu',
    'argeș',
    'arges',
    'ialomița',
    'ialomita',
    'timiș',
    'timis',
    'bega',
    'cerna',
    'bistrița',
    'bistrita',
    'târnava',
    'tarnava',
    'crișul repede',
    'crisul repede',
    'crișul negru',
    'crisul negru',
    'crișul alb',
    'crisul alb',
  ];

  static const List<String> _nationalRiverLabelNames = <String>[
    'mureș',
    'mures',
    'olt',
    'siret',
    'prut',
    'someș',
    'somes',
    'jiu',
    'argeș',
    'arges',
    'ialomița',
    'ialomita',
  ];

  static const List<String> _danubeNames = <String>[
    'dunărea',
    'dunarea',
    'dunăre',
    'dunare',
    'danube',
    'dunav',
  ];

  static bool isDanubeName(String value) =>
      _danubeNames.contains(value.trim().toLowerCase());

  static bool isMajorRiverName(String value) {
    final normalized = value.trim().toLowerCase();
    return isDanubeName(normalized) || _majorRiverNames.contains(normalized);
  }

  static double riverMinimumZoom(String value) {
    if (isDanubeName(value)) return 4.4;
    if (isMajorRiverName(value)) return 5.6;
    return 8.2;
  }

  static List<Object> get _danubeFilter => <Object>[
    'in',
    <Object>[
      'downcase',
      <Object>[
        'coalesce',
        <Object>['get', 'display_name'],
        '',
      ],
    ],
    <Object>['literal', _danubeNames],
  ];

  static List<Object> get _majorRiverFilter => <Object>[
    'in',
    <Object>[
      'downcase',
      <Object>[
        'coalesce',
        <Object>['get', 'display_name'],
        '',
      ],
    ],
    <Object>['literal', _majorRiverNames],
  ];

  static List<Object> get _nationalRiverLabelFilter => <Object>[
    'in',
    <Object>[
      'downcase',
      <Object>[
        'coalesce',
        <Object>['get', 'display_name'],
        '',
      ],
    ],
    <Object>['literal', _nationalRiverLabelNames],
  ];

  static List<Object> get _secondaryRiverFilter => <Object>[
    'all',
    <Object>['!', _majorRiverFilter],
    <Object>['!', _danubeFilter],
  ];

  static List<Object> _selectionFilter(String? displayName) => <Object>[
    '==',
    <Object>['get', 'display_name'],
    displayName ?? '__fluviai_no_selection__',
  ];

  static Future<void> bind(
    mapbox.MapboxMap mapboxMap, {
    HydroOverlayPreferences preferences = const HydroOverlayPreferences(),
    HydroPublicFeatureSelection? selection,
    bool satelliteBasemap = false,
  }) async {
    final style = mapboxMap.style;

    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(mapbox.VectorSource(id: sourceId, url: tilesetUri));
    }

    await _addIfMissing(
      style,
      mapbox.FillLayer(
        id: reservoirLayerId,
        sourceId: sourceId,
        sourceLayer: 'reservoirs',
        minZoom: 4.7,
        slot: 'middle',
        fillColor: 0xFF0B82A4,
        fillOpacity: satelliteBasemap ? .62 : .46,
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: reservoirOutlineLayerId,
        sourceId: sourceId,
        sourceLayer: 'reservoirs',
        minZoom: 5.0,
        slot: 'middle',
        lineColor: satelliteBasemap ? 0xFF8CF4F4 : 0xFF087F9B,
        lineOpacity: satelliteBasemap ? .80 : .64,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          5.2,
          .42,
          7.5,
          .72,
          9.0,
          1.05,
          13.0,
          1.65,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.FillLayer(
        id: reservoirSelectedLayerId,
        sourceId: sourceId,
        sourceLayer: 'reservoirs',
        minZoom: 4.7,
        slot: 'top',
        filter: _selectionFilter(
          selection?.type == HydroPublicFeatureType.reservoir
              ? selection?.displayName
              : null,
        ),
        fillColor: 0xFF37DAD5,
        fillOpacity: satelliteBasemap ? .42 : .30,
        fillOutlineColor: 0xFFBFFFFB,
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: reservoirSelectedOutlineLayerId,
        sourceId: sourceId,
        sourceLayer: 'reservoirs',
        minZoom: 4.7,
        slot: 'top',
        filter: _selectionFilter(
          selection?.type == HydroPublicFeatureType.reservoir
              ? selection?.displayName
              : null,
        ),
        lineColor: 0xFFD8FFFC,
        lineOpacity: .96,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          5.4,
          1.8,
          9.0,
          2.8,
          13.0,
          4.0,
        ],
      ),
    );

    await _addRiverLayers(style);
    await _addLabelLayers(style);

    // Dam geometry remains available in the public Hydro source, but dam
    // symbols are rendered only from canonical runtime WaterAsset annotations.
    // This prevents duplicate generic orange diamonds over reservoir polygons
    // and keeps dam taps tied to canonical Supabase identity.

    await applyConfiguration(
      mapboxMap,
      preferences: preferences,
      selection: selection,
      satelliteBasemap: satelliteBasemap,
    );
  }

  static Future<void> _addRiverLayers(mapbox.StyleManager style) async {
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: riverCasingLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 7.4,
        slot: 'middle',
        filter: _secondaryRiverFilter,
        lineColor: 0xFF06141D,
        lineOpacity: .34,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          7.4,
          .42,
          7.8,
          1.10,
          12.0,
          2.25,
          16.0,
          3.8,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: riverLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 7.4,
        slot: 'middle',
        filter: _secondaryRiverFilter,
        lineColor: 0xFF68BED2,
        lineOpacity: .28,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          7.4,
          .18,
          7.8,
          .50,
          12.0,
          1.0,
          16.0,
          1.75,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: majorRiverCasingLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 4.75,
        slot: 'middle',
        filter: _majorRiverFilter,
        lineColor: 0xFF061820,
        lineOpacity: .84,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          4.75,
          2.35,
          6.2,
          2.75,
          9.0,
          3.6,
          13.0,
          5.4,
          16.0,
          7.6,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: majorRiverLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 4.75,
        slot: 'middle',
        filter: _majorRiverFilter,
        lineColor: 0xFF35C7EA,
        lineOpacity: .92,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          4.75,
          1.28,
          6.2,
          1.55,
          9.0,
          2.1,
          13.0,
          3.35,
          16.0,
          5.0,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: danubeCasingLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 4.0,
        slot: 'middle',
        filter: _danubeFilter,
        lineColor: 0xFF031018,
        lineOpacity: .94,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          4.0,
          4.35,
          5.6,
          5.05,
          8.0,
          7.1,
          12.0,
          10.4,
          16.0,
          15.2,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: danubeLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 4.0,
        slot: 'middle',
        filter: _danubeFilter,
        lineColor: 0xFF3DC7F0,
        lineOpacity: .96,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          4.0,
          2.90,
          5.6,
          3.35,
          8.0,
          4.65,
          12.0,
          7.35,
          16.0,
          11.2,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: riverSelectedCasingLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 4.0,
        slot: 'top',
        filter: _selectionFilter(null),
        lineColor: 0xFFFFFFFF,
        lineOpacity: .92,
        lineBlur: 1.2,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          4.0,
          6.0,
          10.0,
          9.0,
          16.0,
          15.0,
        ],
      ),
    );
    await _addIfMissing(
      style,
      mapbox.LineLayer(
        id: riverSelectedLayerId,
        sourceId: sourceId,
        sourceLayer: 'rivers',
        minZoom: 4.0,
        slot: 'top',
        filter: _selectionFilter(null),
        lineColor: 0xFF37F0E6,
        lineOpacity: 1,
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
        lineWidthExpression: const <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          4.0,
          3.4,
          10.0,
          5.4,
          16.0,
          9.0,
        ],
      ),
    );
  }

  static Future<void> _addLabelLayers(mapbox.StyleManager style) async {
    mapbox.SymbolLayer label({
      required String id,
      required double minZoom,
      required int color,
      required double minimumSize,
      required double maximumSize,
      required double sortKey,
      List<Object>? filter,
      double spacing = 280,
      double opacity = .86,
      double? forceVisibleZoom,
    }) => mapbox.SymbolLayer(
      id: id,
      sourceId: sourceId,
      sourceLayer: 'rivers',
      minZoom: minZoom,
      filter: filter,
      symbolPlacement: mapbox.SymbolPlacement.LINE,
      symbolSpacing: spacing,
      symbolSortKey: sortKey,
      textFieldExpression: const <Object>[
        'to-string',
        <Object>['get', 'display_name'],
      ],
      textSizeExpression: <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['zoom'],
        minZoom,
        minimumSize,
        14.0,
        maximumSize,
      ],
      textColor: color,
      textOpacity: opacity,
      textHaloColor: 0xFF071217,
      textHaloWidth: 1.6,
      textHaloBlur: .35,
      textLetterSpacing: .04,
      textMaxAngle: 32,
      textKeepUpright: true,
      textAllowOverlapExpression: forceVisibleZoom == null
          ? null
          : <Object>[
              'step',
              <Object>['zoom'],
              false,
              forceVisibleZoom,
              true,
            ],
      textAllowOverlap: forceVisibleZoom == null ? false : null,
      textIgnorePlacement: false,
      textRotationAlignment: mapbox.TextRotationAlignment.MAP,
    );

    await _addIfMissing(
      style,
      label(
        id: riverLabelLayerId,
        minZoom: 9.6,
        color: 0xFF9AEFF3,
        minimumSize: 10.0,
        maximumSize: 12.0,
        sortKey: 20,
        filter: _secondaryRiverFilter,
        spacing: 420,
        opacity: .72,
      ),
    );
    await _addIfMissing(
      style,
      label(
        id: majorRiverLabelLayerId,
        minZoom: 4.85,
        color: 0xFFD5FDFF,
        minimumSize: 12.0,
        maximumSize: 15.2,
        sortKey: 4,
        filter: _nationalRiverLabelFilter,
        spacing: 520,
        forceVisibleZoom: 5.30,
      ),
    );
    await _addIfMissing(
      style,
      label(
        id: danubeLabelLayerId,
        minZoom: 4.15,
        color: 0xFFFFFFFF,
        minimumSize: 14.0,
        maximumSize: 17.8,
        sortKey: 0,
        filter: _danubeFilter,
        spacing: 620,
        opacity: .98,
        forceVisibleZoom: 4.80,
      ),
    );
  }

  static Future<void> _addIfMissing(
    mapbox.StyleManager style,
    mapbox.Layer layer,
  ) async {
    if (!await style.styleLayerExists(layer.id)) await style.addLayer(layer);
  }

  static Future<void> applyConfiguration(
    mapbox.MapboxMap mapboxMap, {
    required HydroOverlayPreferences preferences,
    HydroPublicFeatureSelection? selection,
    bool satelliteBasemap = false,
  }) async {
    final style = mapboxMap.style;
    final riversVisible = preferences.enabled && preferences.rivers;
    final reservoirsVisible = preferences.enabled && preferences.reservoirs;
    final damsVisible = preferences.enabled && preferences.dams;

    await _setLayersVisible(style, <String>[
      riverCasingLayerId,
      riverLayerId,
      majorRiverCasingLayerId,
      majorRiverLayerId,
      danubeCasingLayerId,
      danubeLayerId,
      riverLabelLayerId,
      majorRiverLabelLayerId,
      danubeLabelLayerId,
    ], riversVisible);
    await _setLayersVisible(style, <String>[
      reservoirLayerId,
      reservoirOutlineLayerId,
    ], reservoirsVisible);

    final riverSelected =
        riversVisible && selection?.type == HydroPublicFeatureType.river;
    final reservoirSelected =
        reservoirsVisible &&
        selection?.type == HydroPublicFeatureType.reservoir;
    final damSelected =
        damsVisible && selection?.type == HydroPublicFeatureType.dam;

    await _setLayersVisible(style, <String>[
      riverSelectedCasingLayerId,
      riverSelectedLayerId,
    ], riverSelected);
    await _setLayersVisible(style, <String>[
      reservoirSelectedLayerId,
      reservoirSelectedOutlineLayerId,
    ], reservoirSelected);

    if (riverSelected) {
      final filter = _selectionFilter(selection?.displayName);
      await style.setStyleLayerProperty(
        riverSelectedCasingLayerId,
        'filter',
        filter,
      );
      await style.setStyleLayerProperty(riverSelectedLayerId, 'filter', filter);
    }
    if (reservoirSelected) {
      final filter = _selectionFilter(selection?.displayName);
      await style.setStyleLayerProperty(
        reservoirSelectedLayerId,
        'filter',
        filter,
      );
      await style.setStyleLayerProperty(
        reservoirSelectedOutlineLayerId,
        'filter',
        filter,
      );
      await style.setStyleLayerProperty(
        reservoirSelectedLayerId,
        'fill-opacity',
        satelliteBasemap ? .42 : .30,
      );
    }

    final focused = riverSelected || reservoirSelected || damSelected;
    if (await style.styleLayerExists(riverCasingLayerId)) {
      await style.setStyleLayerProperty(
        riverCasingLayerId,
        'line-opacity',
        focused ? .20 : .42,
      );
    }
    if (await style.styleLayerExists(riverLayerId)) {
      await style.setStyleLayerProperty(
        riverLayerId,
        'line-opacity',
        focused ? .18 : .34,
      );
    }
    if (await style.styleLayerExists(majorRiverCasingLayerId)) {
      await style.setStyleLayerProperty(
        majorRiverCasingLayerId,
        'line-opacity',
        focused ? .40 : .86,
      );
    }
    if (await style.styleLayerExists(majorRiverLayerId)) {
      await style.setStyleLayerProperty(
        majorRiverLayerId,
        'line-opacity',
        focused ? .42 : .94,
      );
    }
    if (await style.styleLayerExists(danubeCasingLayerId)) {
      await style.setStyleLayerProperty(
        danubeCasingLayerId,
        'line-opacity',
        focused ? .50 : .95,
      );
    }
    if (await style.styleLayerExists(danubeLayerId)) {
      await style.setStyleLayerProperty(
        danubeLayerId,
        'line-opacity',
        focused ? .54 : .98,
      );
    }
    if (await style.styleLayerExists(reservoirLayerId)) {
      await style.setStyleLayerProperty(
        reservoirLayerId,
        'fill-opacity',
        focused ? .20 : (satelliteBasemap ? .62 : .46),
      );
    }
    if (await style.styleLayerExists(reservoirOutlineLayerId)) {
      await style.setStyleLayerProperty(
        reservoirOutlineLayerId,
        'line-color',
        satelliteBasemap ? 0xFF8CF4F4 : 0xFF087F9B,
      );
      await style.setStyleLayerProperty(
        reservoirOutlineLayerId,
        'line-opacity',
        focused ? .30 : (satelliteBasemap ? .80 : .64),
      );
    }
    await _applyLabelPalette(style, satelliteBasemap, focused: focused);
  }

  static Future<void> _applyLabelPalette(
    mapbox.StyleManager style,
    bool satelliteBasemap, {
    required bool focused,
  }) async {
    final textColor = satelliteBasemap ? 0xFFD8FCFF : 0xFF096A82;
    final danubeTextColor = satelliteBasemap ? 0xFFFFFFFF : 0xFF07546D;
    final haloColor = satelliteBasemap ? 0xFF071217 : 0xFFF4FBFC;
    for (final id in <String>[riverLabelLayerId, majorRiverLabelLayerId]) {
      if (!await style.styleLayerExists(id)) continue;
      await style.setStyleLayerProperty(id, 'text-color', textColor);
      await style.setStyleLayerProperty(id, 'text-halo-color', haloColor);
      await style.setStyleLayerProperty(
        id,
        'text-opacity',
        focused ? .44 : (id == riverLabelLayerId ? .72 : .88),
      );
    }
    if (await style.styleLayerExists(danubeLabelLayerId)) {
      await style.setStyleLayerProperty(
        danubeLabelLayerId,
        'text-color',
        danubeTextColor,
      );
      await style.setStyleLayerProperty(
        danubeLabelLayerId,
        'text-halo-color',
        haloColor,
      );
      await style.setStyleLayerProperty(
        danubeLabelLayerId,
        'text-opacity',
        focused ? .58 : .96,
      );
    }
  }

  static Future<void> _setLayersVisible(
    mapbox.StyleManager style,
    Iterable<String> ids,
    bool visible,
  ) async {
    for (final id in ids) {
      if (await style.styleLayerExists(id)) {
        await style.setStyleLayerProperty(
          id,
          'visibility',
          visible ? 'visible' : 'none',
        );
      }
    }
  }

  static Future<HydroPublicFeatureSelection?> queryFeature(
    mapbox.MapboxMap mapboxMap,
    mapbox.MapContentGestureContext gesture, {
    required HydroOverlayPreferences preferences,
  }) async {
    if (!preferences.enabled) return null;
    final camera = await mapboxMap.getCameraState();
    final tolerance = camera.zoom < 7
        ? 24.0
        : camera.zoom < 11
        ? 18.0
        : 13.0;
    final touch = gesture.touchPosition;
    final geometry = mapbox.RenderedQueryGeometry.fromScreenBox(
      mapbox.ScreenBox(
        min: mapbox.ScreenCoordinate(
          x: touch.x - tolerance,
          y: touch.y - tolerance,
        ),
        max: mapbox.ScreenCoordinate(
          x: touch.x + tolerance,
          y: touch.y + tolerance,
        ),
      ),
    );
    final queryLayers = <String>[
      if (preferences.reservoirs) reservoirSelectedLayerId,
      if (preferences.reservoirs) reservoirLayerId,
      if (preferences.rivers) riverSelectedLayerId,
      if (preferences.rivers) danubeLayerId,
      if (preferences.rivers) majorRiverLayerId,
      if (preferences.rivers) riverLayerId,
    ];
    final features = await mapboxMap.queryRenderedFeatures(
      geometry,
      mapbox.RenderedQueryOptions(layerIds: queryLayers, filter: null),
    );
    for (final result in features) {
      final queried = result?.queriedFeature;
      if (queried == null || queried.source != sourceId) continue;
      final rawProperties = queried.feature['properties'];
      if (rawProperties is! Map) continue;
      final properties = Map<Object?, Object?>.from(rawProperties);
      final name = properties['display_name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      final type = switch (queried.sourceLayer) {
        'reservoirs' => HydroPublicFeatureType.reservoir,
        'dams' => HydroPublicFeatureType.dam,
        _ => HydroPublicFeatureType.river,
      };
      return HydroPublicFeatureSelection(
        type: type,
        displayName: name,
        latitude: gesture.point.coordinates.lat.toDouble(),
        longitude: gesture.point.coordinates.lng.toDouble(),
      );
    }
    return null;
  }
}
