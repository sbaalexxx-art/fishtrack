import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catch.dart';
import '../services/diagnostics_service.dart';

class CatchSubmissionException implements Exception {
  const CatchSubmissionException(this.message);

  final String message;
}

class CatchRepository {
  const CatchRepository({SupabaseClient? client}) : _client = client;

  static const _bucket = 'catch-images';
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<void> createCatch({
    required String imagePath,
    required String species,
    required double? weightKg,
    required double? lengthCm,
    required String notes,
    required double? latitude,
    required double? longitude,
    required String? placeName,
    required String waterType,
    required String locationPrivacy,
    required String? stationId,
    String? speciesScientific,
    String speciesSource = 'manual',
    double? speciesConfidence,
    String? speciesModelVersion,
    bool speciesUserConfirmed = true,
    List<Map<String, Object?>> speciesCandidates =
        const <Map<String, Object?>>[],
  }) async {
    final submitStopwatch = Stopwatch()..start();
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.community,
      operation: 'catch_submit',
      message: 'started',
      metadata: <String, Object?>{
        'species_source': speciesSource,
        'has_station': stationId != null,
        'privacy': locationPrivacy,
      },
    );
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw const CatchSubmissionException(
        'The selected image is no longer available.',
      );
    }

    final fileName = imagePath.split(RegExp(r'[/\\]')).last;
    final extension = fileName.contains('.')
        ? '.${fileName.split('.').last.toLowerCase()}'
        : '.jpg';
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw const CatchSubmissionException('Your session has expired.');
    }
    final storagePath =
        '$userId/${DateTime.now().microsecondsSinceEpoch}$extension';

    try {
      await _supabase.storage
          .from(_bucket)
          .upload(storagePath, imageFile)
          .timeout(const Duration(seconds: 45));
    } on SocketException catch (error, stackTrace) {
      _logFailure('catch image upload', error, stackTrace);
      throw const CatchSubmissionException(
        'No internet connection. Your catch was not uploaded.',
      );
    } on TimeoutException catch (error, stackTrace) {
      _logFailure('catch image upload', error, stackTrace);
      throw const CatchSubmissionException(
        'The upload timed out. Check your connection and try again.',
      );
    } on StorageException catch (error, stackTrace) {
      _logFailure('catch image upload', error, stackTrace);
      throw const CatchSubmissionException(
        'The image could not be uploaded. Please try again.',
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('catch image upload', error, stackTrace);
      throw const CatchSubmissionException(
        'The image could not be uploaded. Please try again.',
      );
    }

    try {
      final data = <String, Object?>{
        'station_id': stationId,
        'species': species.trim(),
        'species_scientific': speciesScientific?.trim(),
        'species_source': speciesSource,
        'species_confidence': speciesConfidence,
        'species_model_version': speciesModelVersion,
        'species_user_confirmed': speciesUserConfirmed,
        'species_candidates': speciesCandidates,
        'weight': weightKg,
        'length': lengthCm,
        'notes': notes.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'place_name': placeName,
        'water_type': waterType,
        'location_privacy': locationPrivacy,
        'image': _supabase.storage.from(_bucket).getPublicUrl(storagePath),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      data['user_id'] = userId;
      await _supabase
          .from('catches')
          .insert(data)
          .timeout(const Duration(seconds: 20));
      submitStopwatch.stop();
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.community,
        operation: 'catch_submit',
        message: 'completed',
        duration: submitStopwatch.elapsed,
        metadata: <String, Object?>{
          'species_source': speciesSource,
          'has_station': stationId != null,
        },
      );
    } on SocketException catch (error, stackTrace) {
      _logFailure('catch database insert', error, stackTrace);
      await _removeImage(storagePath);
      throw const CatchSubmissionException(
        'No internet connection. Your catch was not saved.',
      );
    } on TimeoutException catch (error, stackTrace) {
      _logFailure('catch database insert', error, stackTrace);
      await _removeImage(storagePath);
      throw const CatchSubmissionException(
        'Saving timed out. Check your connection and try again.',
      );
    } on PostgrestException catch (error, stackTrace) {
      _logFailure('catch database insert', error, stackTrace);
      await _removeImage(storagePath);
      throw const CatchSubmissionException(
        'The catch could not be saved. Please try again.',
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('catch database insert', error, stackTrace);
      await _removeImage(storagePath);
      throw const CatchSubmissionException(
        'The catch could not be saved. Please try again.',
      );
    }
  }

  Future<void> _removeImage(String path) async {
    try {
      await _supabase.storage.from(_bucket).remove([path]);
    } on Exception {
      // Cleanup is best-effort; preserve the original save failure.
    }
  }

  Future<List<Catch>> getCatchesForStation(String stationId) async {
    try {
      final response = await _supabase
          .rpc(
            'get_public_catches_for_station_v2',
            params: <String, Object?>{'p_station_id': stationId, 'p_limit': 20},
          )
          .timeout(const Duration(seconds: 12));

      return response
          .map((row) {
            final id = row['id']?.toString();
            final species = row['species']?.toString().trim();
            final weight = _number(row['weight']);
            final length = _number(row['length']);
            final date = DateTime.tryParse(row['timestamp']?.toString() ?? '');
            if (id == null ||
                id.isEmpty ||
                species == null ||
                species.isEmpty ||
                date == null) {
              return null;
            }
            return Catch(
              id: id,
              stationId: row['station_id']?.toString() ?? stationId,
              species: species,
              speciesScientific: row['species_scientific']?.toString(),
              speciesSource: row['species_source']?.toString() ?? 'manual',
              speciesConfidence: _number(row['species_confidence']),
              speciesModelVersion: row['species_model_version']?.toString(),
              speciesUserConfirmed: row['species_user_confirmed'] != false,
              weight: weight,
              length: length,
              date: date.toLocal(),
            );
          })
          .whereType<Catch>()
          .toList(growable: false);
    } on Exception catch (error, stackTrace) {
      _logFailure('load station catches', error, stackTrace);
      return const <Catch>[];
    }
  }

  Future<List<Catch>> getMyCatches() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const <Catch>[];
    try {
      final response = await _supabase
          .from('catches')
          .select(
            'id, station_id, species, species_scientific, species_source, species_confidence, species_model_version, species_user_confirmed, weight, length, timestamp',
          )
          .eq('user_id', userId)
          .order('timestamp', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 12));
      return response
          .map((row) => _catchFromRow(row))
          .whereType<Catch>()
          .toList(growable: false);
    } on Exception catch (error, stackTrace) {
      _logFailure('load user catches', error, stackTrace);
      rethrow;
    }
  }

  static Catch? _catchFromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final species = row['species']?.toString().trim();
    final date = DateTime.tryParse(row['timestamp']?.toString() ?? '');
    if (id == null ||
        id.isEmpty ||
        species == null ||
        species.isEmpty ||
        date == null) {
      return null;
    }
    return Catch(
      id: id,
      stationId: row['station_id']?.toString() ?? '',
      species: species,
      speciesScientific: row['species_scientific']?.toString(),
      speciesSource: row['species_source']?.toString() ?? 'manual',
      speciesConfidence: _number(row['species_confidence']),
      speciesModelVersion: row['species_model_version']?.toString(),
      speciesUserConfirmed: row['species_user_confirmed'] != false,
      weight: _number(row['weight']),
      length: _number(row['length']),
      date: date.toLocal(),
    );
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static void _logFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    DiagnosticsService.instance.recordError(
      category: DiagnosticCategory.community,
      operation: operation.replaceAll(' ', '_'),
      error: error,
      stackTrace: stackTrace,
    );
    developer.log(
      '$operation failed',
      name: 'AIFishMap.Catches',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
