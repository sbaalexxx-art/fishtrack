import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class HydroDispatchFieldGeofence {
  const HydroDispatchFieldGeofence({
    required this.eligible,
    required this.reason,
    required this.plantId,
    required this.plantName,
    required this.targetDistanceKm,
    required this.confirmationRadiusKm,
    required this.ambiguityMarginKm,
    required this.nearestPlantId,
    required this.nearestPlantName,
    required this.nearestDistanceKm,
    required this.nearestGapKm,
    this.secondNearestPlantId,
    this.secondNearestPlantName,
    this.secondNearestDistanceKm,
  });

  factory HydroDispatchFieldGeofence.fromJson(
    Map<String, dynamic> json,
  ) => HydroDispatchFieldGeofence(
    eligible: json['eligible'] == true,
    reason: json['reason']?.toString() ?? 'unknown',
    plantId: json['plant_id']?.toString() ?? '',
    plantName: json['plant_name']?.toString() ?? '',
    targetDistanceKm: _double(json['target_distance_km']) ?? double.infinity,
    confirmationRadiusKm: _double(json['confirmation_radius_km']) ?? 5.0,
    ambiguityMarginKm: _double(json['ambiguity_margin_km']) ?? .75,
    nearestPlantId: json['nearest_plant_id']?.toString() ?? '',
    nearestPlantName: json['nearest_plant_name']?.toString() ?? '',
    nearestDistanceKm: _double(json['nearest_distance_km']) ?? double.infinity,
    secondNearestPlantId: _text(json['second_nearest_plant_id']),
    secondNearestPlantName: _text(json['second_nearest_plant_name']),
    secondNearestDistanceKm: _double(json['second_nearest_distance_km']),
    nearestGapKm: _double(json['nearest_gap_km']) ?? double.infinity,
  );

  final bool eligible;
  final String reason;
  final String plantId;
  final String plantName;
  final double targetDistanceKm;
  final double confirmationRadiusKm;
  final double ambiguityMarginKm;
  final String nearestPlantId;
  final String nearestPlantName;
  final double nearestDistanceKm;
  final String? secondNearestPlantId;
  final String? secondNearestPlantName;
  final double? secondNearestDistanceKm;
  final double nearestGapKm;

  bool get isNearestPlant => nearestPlantId == plantId;
  bool get isAmbiguous => reason == 'ambiguous_between_plants';
}

class HydroDispatchGeofenceService {
  const HydroDispatchGeofenceService({SupabaseClient? client})
    : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<HydroDispatchFieldGeofence> check({
    required String plantId,
    required double latitude,
    required double longitude,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const HydroDispatchGeofenceException('Authentication is required.');
    }
    try {
      final response = await _supabase
          .rpc(
            'get_hydro_dispatch_field_geofence_v1',
            params: <String, Object?>{
              'p_plant_id': plantId,
              'p_latitude': latitude,
              'p_longitude': longitude,
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response is! Map) {
        throw const HydroDispatchGeofenceException(
          'Hydro field location could not be verified.',
        );
      }
      return HydroDispatchFieldGeofence.fromJson(
        Map<String, dynamic>.from(response),
      );
    } on HydroDispatchGeofenceException {
      rethrow;
    } on SocketException {
      throw const HydroDispatchGeofenceException(
        'No internet connection. Field confirmation is unavailable.',
      );
    } on TimeoutException {
      throw const HydroDispatchGeofenceException(
        'Hydro field location verification timed out.',
      );
    } on PostgrestException catch (error) {
      throw HydroDispatchGeofenceException(
        error.message.trim().isEmpty
            ? 'Hydro field location could not be verified.'
            : error.message,
      );
    }
  }
}

class HydroDispatchGeofenceException implements Exception {
  const HydroDispatchGeofenceException(this.message);

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
