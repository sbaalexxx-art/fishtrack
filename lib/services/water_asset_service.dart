import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/water_asset.dart';
import '../models/water_river.dart';

class WaterAssetService {
  const WaterAssetService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const Duration _mapPinsCacheTtl = Duration(minutes: 3);
  static const int _mapPinsCacheMaxEntries = 32;

  static final Map<
    String,
    ({DateTime createdAt, List<WaterMapPin> pins})
  >
  _mapPinsCache = <
    String,
    ({DateTime createdAt, List<WaterMapPin> pins})
  >{};

  static final Map<String, Future<List<WaterMapPin>>> _mapPinsInFlight =
      <String, Future<List<WaterMapPin>>>{};

  Future<List<WaterHubRiverGroup>> getHubRivers({String countryCode = 'RO'}) =>
      _guardPublic(() async {
        final response = await _supabase.rpc(
          'get_water_hub_major_rivers_v1',
          params: {'p_country_code': countryCode.trim().toUpperCase()},
        );
        if (response is! List) return const <WaterHubRiverGroup>[];
        return response
            .whereType<Map>()
            .map(
              (row) =>
                  WaterHubRiverGroup.fromJson(Map<String, dynamic>.from(row)),
            )
            .where(
              (group) =>
                  group.groupKey.isNotEmpty &&
                  group.displayName.isNotEmpty &&
                  group.riverKeys.isNotEmpty &&
                  group.waterBodyIds.isNotEmpty,
            )
            .toList(growable: false);
      });

  Future<List<WaterHydropowerComplex>> getHubHydropowerComplexes({
    String countryCode = 'RO',
    int limit = 150,
  }) => _guardPublic(() async {
    final response = await _supabase.rpc(
      'get_water_hub_hydropower_complexes_v1',
      params: {
        'p_country_code': countryCode.trim().toUpperCase(),
        'p_limit': limit.clamp(1, 250),
      },
    );
    if (response is! List) return const <WaterHydropowerComplex>[];
    return response
        .whereType<Map>()
        .map(
          (row) =>
              WaterHydropowerComplex.fromJson(Map<String, dynamic>.from(row)),
        )
        .where(
          (complex) =>
              complex.reservoirId.isNotEmpty &&
              complex.reservoirName.isNotEmpty &&
              complex.latitude.isFinite &&
              complex.longitude.isFinite,
        )
        .toList(growable: false);
  });

  Future<List<WaterAssetRef>> searchAssets(String query, {int limit = 50}) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'search_water_assets_v2',
          params: {'p_query': query.trim(), 'p_limit': limit},
        );
        if (response is! List) return const <WaterAssetRef>[];
        return response
            .whereType<Map>()
            .map(
              (row) => WaterAssetRef.fromJson(Map<String, dynamic>.from(row)),
            )
            .where((asset) => asset.id.isNotEmpty && asset.name.isNotEmpty)
            .toList(growable: false);
      });

  Future<List<WaterRiverRef>> searchRivers(String query, {int limit = 50}) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'search_water_rivers_v2',
          params: {'p_query': query.trim(), 'p_limit': limit},
        );
        if (response is! List) return const <WaterRiverRef>[];
        return response
            .whereType<Map>()
            .map(
              (row) => WaterRiverRef.fromJson(Map<String, dynamic>.from(row)),
            )
            .where((river) => river.key.isNotEmpty && river.name.isNotEmpty)
            .toList(growable: false);
      });

  /// Searches canonical CHE entities through existing Water relationships.
  ///
  /// Hydropower plants are not part of `search_water_assets_v2`. River, asset,
  /// and nearby map-pin water-body ids are therefore resolved first and passed
  /// to `get_hydropower_plant_states_v2` without adding a parallel data source.
  Future<List<WaterMapPin>> searchHydropower(
    String query, {
    int limit = 50,
    double? anchorLatitude,
    double? anchorLongitude,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <WaterMapPin>[];
    final terms = normalized
        .split(RegExp(r'[^a-z0-9ăâîșț]+'))
        .where((term) => term.isNotEmpty)
        .where(
          (term) =>
              term != 'che' &&
              term != 'hidrocentrala' &&
              term != 'hidrocentrală' &&
              term != 'hydropower',
        )
        .toList(growable: false);
    if (terms.isEmpty) return const <WaterMapPin>[];
    final relationLookups = await Future.wait(
      terms
          .take(3)
          .map(
            (term) async => (
              rivers: await searchRivers(term, limit: 12),
              assets: await searchAssets(term, limit: 12),
            ),
          ),
    );
    final waterBodyIds = <String>{
      for (final lookup in relationLookups)
        for (final river in lookup.rivers)
          if (river.waterBodyId?.isNotEmpty == true) river.waterBodyId!,
      for (final lookup in relationLookups)
        for (final asset in lookup.assets)
          if (asset.waterBodyId?.isNotEmpty == true) asset.waterBodyId!,
    };
    final waterBodyNames = <String, String>{
      for (final lookup in relationLookups)
        for (final river in lookup.rivers)
          if (river.waterBodyId?.isNotEmpty == true)
            river.waterBodyId!: river.name,
      for (final lookup in relationLookups)
        for (final asset in lookup.assets)
          if (asset.waterBodyId?.isNotEmpty == true &&
              asset.riverName?.isNotEmpty == true)
            asset.waterBodyId!: asset.riverName!,
    };
    if (anchorLatitude != null && anchorLongitude != null) {
      final nearbyPins = await getMapPins(
        latitude: anchorLatitude,
        longitude: anchorLongitude,
        zoom: 13,
        radiusKm: 80,
        limit: 750,
      );
      waterBodyIds.addAll(
        nearbyPins
            .map((pin) => pin.waterBodyId)
            .whereType<String>()
            .where((waterBodyId) => waterBodyId.isNotEmpty),
      );
      for (final pin in nearbyPins) {
        final waterBodyId = pin.waterBodyId;
        final riverName = pin.riverName;
        if (waterBodyId?.isNotEmpty == true && riverName?.isNotEmpty == true) {
          waterBodyNames.putIfAbsent(waterBodyId!, () => riverName!);
        }
      }
    }
    if (waterBodyIds.isEmpty) return const <WaterMapPin>[];
    final states = (await Future.wait(
      waterBodyIds
          .take(12)
          .map(
            (waterBodyId) => getHydropowerPlantStates(waterBodyId: waterBodyId),
          ),
    )).expand((items) => items).toList(growable: false);
    final pins = states
        .where(
          (state) =>
              state.plantId.isNotEmpty &&
              state.name.isNotEmpty &&
              state.latitude != null &&
              state.longitude != null &&
              state.latitude!.isFinite &&
              state.longitude!.isFinite,
        )
        .map(
          (state) => waterMapPinFromHydropowerState(
            state,
            riverName: waterBodyNames[state.waterBodyId],
          ),
        )
        .toList(growable: false);
    final matches =
        pins
            .where((pin) => pin.isHydropower)
            .where((pin) => pin.countryCode == null || pin.countryCode == 'RO')
            .where((pin) {
              if (terms.isEmpty) return true;
              final haystack =
                  '${pin.name} ${pin.riverName ?? ''} ${pin.canonicalKey}'
                      .toLowerCase();
              return terms.every(haystack.contains);
            })
            .toList(growable: false)
          ..sort((left, right) {
            final leftExact = left.name.toLowerCase() == normalized ? 0 : 1;
            final rightExact = right.name.toLowerCase() == normalized ? 0 : 1;
            final exactOrder = leftExact.compareTo(rightExact);
            if (exactOrder != 0) return exactOrder;
            final priorityOrder = right.priority.compareTo(left.priority);
            if (priorityOrder != 0) return priorityOrder;
            return left.name.compareTo(right.name);
          });
    return List<WaterMapPin>.unmodifiable(matches.take(limit));
  }

  Future<WaterRiverDetail> getRiverDetail(WaterRiverRef river) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_water_river_detail_v2',
          params: {'p_river_key': river.key},
        );
        if (response is! Map) {
          throw const WaterAssetException(
            'Detaliile râului nu sunt disponibile.',
          );
        }
        return WaterRiverDetail.fromJson(Map<String, dynamic>.from(response));
      });

  Future<WaterEntityState> getRiverState(WaterRiverRef river) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_water_river_state_v2',
          params: {'p_river_key': river.key},
        );
        if (response is! Map) {
          throw const WaterAssetException('Starea râului nu este disponibilă.');
        }
        return WaterEntityState.fromJson(Map<String, dynamic>.from(response));
      });

  Future<List<WaterAssetRef>> getNearby({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    int limit = 250,
  }) => _guard(() async {
    final response = await _supabase.rpc(
      'get_water_assets_nearby_v3',
      params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_radius_km': radiusKm,
        'p_limit': limit,
      },
    );
    if (response is! List) return const <WaterAssetRef>[];
    return response
        .whereType<Map>()
        .map((row) => WaterAssetRef.fromJson(Map<String, dynamic>.from(row)))
        .where(
          (asset) =>
              asset.id.isNotEmpty &&
              asset.name.isNotEmpty &&
              asset.latitude.isFinite &&
              asset.longitude.isFinite,
        )
        .toList(growable: false);
  });

  Future<List<WaterMapPin>> getMapPins({
    required double latitude,
    required double longitude,
    required double zoom,
    double radiusKm = 100,
    int limit = 750,
  }) => _guard(() async {
    final cacheKey = _mapPinsRequestKey(
      latitude: latitude,
      longitude: longitude,
      zoom: zoom,
      radiusKm: radiusKm,
      limit: limit,
    );

    final now = DateTime.now();
    final cached = _mapPinsCache[cacheKey];
    if (cached != null) {
      if (now.difference(cached.createdAt) < _mapPinsCacheTtl) {
        return cached.pins;
      }
      _mapPinsCache.remove(cacheKey);
    }

    final inFlight = _mapPinsInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final request = (() async {
      final response = await _supabase.rpc(
        'get_water_map_pins_v3',
        params: {
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_radius_km': radiusKm,
          'p_zoom': zoom,
          'p_limit': limit,
        },
      );

      if (response is! List) return const <WaterMapPin>[];

      return response
          .whereType<Map>()
          .map((row) => WaterMapPin.fromJson(Map<String, dynamic>.from(row)))
          .where(
            (pin) =>
                pin.entityId.isNotEmpty &&
                pin.name.isNotEmpty &&
                pin.latitude.isFinite &&
                pin.longitude.isFinite,
          )
          .toList(growable: false);
    })();

    _mapPinsInFlight[cacheKey] = request;

    try {
      final pins = await request;
      final completedAt = DateTime.now();
      _mapPinsCache[cacheKey] = (createdAt: completedAt, pins: pins);
      _pruneMapPinsCache(completedAt);
      return pins;
    } finally {
      if (identical(_mapPinsInFlight[cacheKey], request)) {
        _mapPinsInFlight.remove(cacheKey);
      }
    }
  });

  String _mapPinsRequestKey({
    required double latitude,
    required double longitude,
    required double zoom,
    required double radiusKm,
    required int limit,
  }) {
    final latitudeCell = (latitude * 100).round();
    final longitudeCell = (longitude * 100).round();
    final zoomCell = (zoom * 10).round();
    final radiusCell = (radiusKm * 10).round();

    return '${identityHashCode(_supabase)}:$latitudeCell:$longitudeCell:'
        '$zoomCell:$radiusCell:$limit';
  }

  void _pruneMapPinsCache(DateTime now) {
    _mapPinsCache.removeWhere(
      (_, entry) => now.difference(entry.createdAt) >= _mapPinsCacheTtl,
    );

    if (_mapPinsCache.length <= _mapPinsCacheMaxEntries) return;

    final entries = _mapPinsCache.entries.toList(growable: false)
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

    final overflow = _mapPinsCache.length - _mapPinsCacheMaxEntries;
    for (var index = 0; index < overflow; index++) {
      _mapPinsCache.remove(entries[index].key);
    }
  }

  Future<List<HydropowerPlantState>> getHydropowerPlantStates({
    String? waterBodyId,
    String? plantId,
  }) => _guard(() async {
    final response = await _supabase.rpc(
      'get_hydropower_plant_states_v2',
      params: {'p_water_body_id': waterBodyId, 'p_plant_id': plantId},
    );
    if (response is! List) return const <HydropowerPlantState>[];
    return response
        .whereType<Map>()
        .map(
          (row) =>
              HydropowerPlantState.fromJson(Map<String, dynamic>.from(row)),
        )
        .where((state) => state.plantId.isNotEmpty && state.name.isNotEmpty)
        .toList(growable: false);
  });

  Future<HydropowerPlantState?> getHydropowerPlantState(String plantId) async {
    final states = await getHydropowerPlantStates(plantId: plantId);
    return states.isEmpty ? null : states.first;
  }

  Future<WaterAssetDetail> getDetail(WaterAssetRef asset) => _guard(() async {
    final function = asset.type == WaterAssetType.dam
        ? 'get_dam_detail_v1'
        : 'get_reservoir_detail_v1';
    final param = asset.type == WaterAssetType.dam
        ? 'p_dam_id'
        : 'p_reservoir_id';
    final response = await _supabase.rpc(function, params: {param: asset.id});
    if (response is! Map) {
      throw const WaterAssetException('Detaliile Water nu sunt disponibile.');
    }
    return WaterAssetDetail.fromJson(
      Map<String, dynamic>.from(response),
      type: asset.type,
    );
  });

  Future<WaterEntityState> getState(WaterAssetRef asset) => _guard(() async {
    final response = await _supabase.rpc(
      'get_water_entity_state_v1',
      params: {'p_entity_type': asset.entityType, 'p_entity_id': asset.id},
    );
    if (response is! Map) {
      throw const WaterAssetException('Starea Water nu este disponibilă.');
    }
    return WaterEntityState.fromJson(Map<String, dynamic>.from(response));
  });

  Future<T> _guardPublic<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on WaterAssetException {
      rethrow;
    } on SocketException {
      throw const WaterAssetException('Nu există conexiune la internet.');
    } on TimeoutException {
      throw const WaterAssetException('Cererea a expirat. Încearcă din nou.');
    } on PostgrestException {
      throw const WaterAssetException(
        'Catalogul Water nu este disponibil momentan.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      if (_supabase.auth.currentUser == null) {
        throw const WaterAssetException('Autentificarea este necesară.');
      }
      return await operation().timeout(const Duration(seconds: 20));
    } on WaterAssetException {
      rethrow;
    } on SocketException {
      throw const WaterAssetException('Nu există conexiune la internet.');
    } on TimeoutException {
      throw const WaterAssetException('Cererea Water a expirat. Reîncearcă.');
    } on PostgrestException {
      throw const WaterAssetException(
        'Datele Water nu sunt disponibile momentan.',
      );
    }
  }
}

WaterMapPin waterMapPinFromHydropowerState(
  HydropowerPlantState state, {
  String? riverName,
}) => WaterMapPin(
  entityType: 'hydro_plant',
  entityId: state.plantId,
  canonicalKey: state.canonicalKey,
  name: state.name,
  riverName: riverName,
  countryCode: state.countryCode,
  latitude: state.latitude!,
  longitude: state.longitude!,
  waterBodyId: state.waterBodyId,
  operationState: state.operationState,
  evidenceClass: state.evidenceClass,
  stateSource: state.evidenceSource,
  confidence: state.confidence,
  freshnessStatus: state.freshnessStatus,
  hasOperationalData:
      state.evidenceClass.toUpperCase() != 'UNKNOWN' &&
      state.evidenceValue != null,
  communityReportCount: state.communityReportCount,
  statePayload: <String, Object?>{
    'operator_name': state.operatorName,
    'operator_unit': state.operatorUnit,
    'sector_name': state.sectorName,
    'plant_kind': state.plantKind,
    'installed_power_mw': state.installedPowerMw,
    'dam_id': state.damId,
    'reservoir_id': state.reservoirId,
  },
);

class WaterAssetException implements Exception {
  const WaterAssetException(this.message);
  final String message;
}
