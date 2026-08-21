import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/water_asset.dart';

class HydroCanonicalMapSite {
  const HydroCanonicalMapSite({
    required this.siteKey,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.pinEligible,
    required this.hydropowerVerified,
    required this.dispatchAvailable,
    this.riverName,
    this.countryCode,
    this.basinName,
    this.anchorType,
    this.plantId,
    this.damId,
    this.reservoirId,
    this.waterBodyId,
  });

  factory HydroCanonicalMapSite.fromJson(Map<String, dynamic> json) =>
      HydroCanonicalMapSite(
        siteKey: json['site_key']?.toString() ?? '',
        displayName: json['display_name']?.toString() ?? '',
        riverName: _text(json['river_name']),
        countryCode: _text(json['country_code'])?.toUpperCase(),
        basinName: _text(json['basin_name']),
        latitude: _double(json['latitude']) ?? double.nan,
        longitude: _double(json['longitude']) ?? double.nan,
        anchorType: _text(json['anchor_type']),
        pinEligible: json['pin_eligible'] == true,
        hydropowerVerified: json['hydropower_verified'] == true,
        dispatchAvailable: json['dispatch_available'] == true,
        plantId: _text(json['plant_id']),
        damId: _text(json['dam_id']),
        reservoirId: _text(json['reservoir_id']),
        waterBodyId: _text(json['water_body_id']),
      );

  final String siteKey;
  final String displayName;
  final String? riverName;
  final String? countryCode;
  final String? basinName;
  final double latitude;
  final double longitude;
  final String? anchorType;
  final bool pinEligible;
  final bool hydropowerVerified;
  final bool dispatchAvailable;
  final String? plantId;
  final String? damId;
  final String? reservoirId;
  final String? waterBodyId;

  bool get isVerifiedPin =>
      pinEligible &&
      hydropowerVerified &&
      plantId?.isNotEmpty == true &&
      latitude.isFinite &&
      longitude.isFinite;

  WaterMapPin toWaterMapPin() => WaterMapPin(
    entityType: 'hydro_plant',
    entityId: plantId!,
    canonicalKey: siteKey,
    name: displayName,
    riverName: riverName,
    countryCode: countryCode,
    latitude: latitude,
    longitude: longitude,
    waterBodyId: waterBodyId,
    operationState: 'UNKNOWN',
    evidenceClass: 'UNKNOWN',
    stateSource: 'canonical_hydro_map',
    priority: dispatchAvailable ? 100 : 90,
    hasOperationalData: false,
    statePayload: <String, Object?>{
      if (damId != null) 'dam_id': damId,
      if (reservoirId != null) 'reservoir_id': reservoirId,
      if (anchorType != null) 'anchor_type': anchorType,
      'hydropower_verified': hydropowerVerified,
      'dispatch_available': dispatchAvailable,
    },
  );
}

class HydroMapDispatchSnapshot {
  const HydroMapDispatchSnapshot({
    required this.plantId,
    required this.name,
    required this.availabilityStatus,
    required this.confidence,
    required this.evidenceClass,
    required this.observedState,
    required this.observedFreshness,
    required this.observedReportCount,
    this.damId,
    this.reservoirId,
    this.windowStart,
    this.windowEnd,
    this.windowProbability,
    this.peakProbability,
    this.updatedAt,
    this.observedConfidence,
  });

  factory HydroMapDispatchSnapshot.fromJson(Map<String, dynamic> json) =>
      HydroMapDispatchSnapshot(
        plantId: json['plant_id']?.toString() ?? '',
        damId: _text(json['dam_id']),
        reservoirId: _text(json['reservoir_id']),
        name: json['name']?.toString() ?? '',
        availabilityStatus:
            json['availability_status']?.toString() ?? 'UNAVAILABLE',
        windowStart: _dateTime(json['window_start']),
        windowEnd: _dateTime(json['window_end']),
        windowProbability: _double(json['window_probability']),
        peakProbability: _double(json['peak_probability']),
        confidence: json['confidence']?.toString() ?? 'unknown',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        updatedAt: _dateTime(json['updated_at']),
        observedState: json['observed_state']?.toString() ?? 'unknown',
        observedConfidence: _double(json['observed_confidence']),
        observedFreshness:
            json['observed_freshness']?.toString() ?? 'unavailable',
        observedReportCount: _int(json['observed_report_count']) ?? 0,
      );

  final String plantId;
  final String? damId;
  final String? reservoirId;
  final String name;
  final String availabilityStatus;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double? windowProbability;
  final double? peakProbability;
  final String confidence;
  final String evidenceClass;
  final DateTime? updatedAt;
  final String observedState;
  final double? observedConfidence;
  final String observedFreshness;
  final int observedReportCount;

  bool get isAvailable =>
      availabilityStatus == 'AVAILABLE' &&
      windowStart != null &&
      windowEnd != null &&
      windowProbability != null;
}

class HydroMapCanonicalService {
  const HydroMapCanonicalService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<HydroCanonicalMapSite>> getVerifiedSites({
    String countryCode = 'RO',
  }) => _guard(() async {
    final response = await _supabase.rpc(
      'get_hydro_map_sites_v1',
      params: <String, Object?>{
        'p_country_code': countryCode.trim().toUpperCase(),
        'p_include_unresolved': false,
        'p_limit': 250,
      },
    );
    if (response is! List) return const <HydroCanonicalMapSite>[];
    return response
        .whereType<Map>()
        .map(
          (row) =>
              HydroCanonicalMapSite.fromJson(Map<String, dynamic>.from(row)),
        )
        .where((site) => site.isVerifiedPin)
        .toList(growable: false);
  });

  Future<List<WaterMapPin>> getVerifiedPins({
    String countryCode = 'RO',
  }) async => (await getVerifiedSites(
    countryCode: countryCode,
  )).map((site) => site.toWaterMapPin()).toList(growable: false);

  Future<HydroMapDispatchSnapshot?> getDispatchSnapshot(String plantId) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_hydro_map_dispatch_overlay_v1',
        );
        if (response is! List) return null;
        for (final row in response.whereType<Map>()) {
          final snapshot = HydroMapDispatchSnapshot.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (snapshot.plantId == plantId) return snapshot;
        }
        return null;
      });

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const HydroMapCanonicalException('No internet connection.');
    } on TimeoutException {
      throw const HydroMapCanonicalException(
        'Hydro Map request timed out. Please retry.',
      );
    } on PostgrestException catch (error) {
      throw HydroMapCanonicalException(
        error.message.trim().isEmpty
            ? 'Hydro Map is unavailable. Please retry.'
            : error.message,
      );
    }
  }
}

class HydroMapCanonicalException implements Exception {
  const HydroMapCanonicalException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _dateTime(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '');
