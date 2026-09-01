import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catch.dart';
import '../services/media_processing_service.dart';

class CatchSubmissionException implements Exception {
  const CatchSubmissionException(this.message);

  final String message;
}

class CatchRepository {
  const CatchRepository({
    SupabaseClient? client,
    MediaProcessingService mediaProcessor = const MediaProcessingService(),
  }) : _client = client,
       _mediaProcessor = mediaProcessor;

  static const _bucket = 'catch-images';
  final SupabaseClient? _client;
  final MediaProcessingService _mediaProcessor;

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
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw const CatchSubmissionException('Your session has expired.');
    }

    late final ProcessedMedia media;
    try {
      media = await _mediaProcessor.processFile(
        path: imagePath,
        purpose: MediaPurpose.catchPhoto,
      );
    } on MediaProcessingException catch (error, stackTrace) {
      _logFailure('catch image processing', error, stackTrace);
      throw CatchSubmissionException(error.message);
    } on Exception catch (error, stackTrace) {
      _logFailure('catch image processing', error, stackTrace);
      throw const CatchSubmissionException(
        'The image could not be processed. Please try again.',
      );
    }

    final storagePath =
        '$userId/${DateTime.now().microsecondsSinceEpoch}${ProcessedMedia.extension}';

    try {
      await _supabase.storage
          .from(_bucket)
          .uploadBinary(
            storagePath,
            media.bytes,
            fileOptions: FileOptions(
              cacheControl: '31536000',
              contentType: ProcessedMedia.contentType,
              upsert: false,
              metadata: {
                'sha256': media.sha256Hex,
                'original_bytes': media.originalBytes,
                'processed_bytes': media.outputBytes,
                'dimension_limit': media.dimensionLimit,
                'quality': media.quality,
                'exif_preserved': false,
              },
            ),
          )
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
        'weight': weightKg,
        'length': lengthCm,
        'notes': notes.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'place_name': placeName,
        'water_type': waterType,
        'location_privacy': locationPrivacy,
        'image': _supabase.storage.from(_bucket).getPublicUrl(storagePath),
        'image_sha256': media.sha256Hex,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      data['user_id'] = userId;
      await _supabase
          .from('catches')
          .insert(data)
          .timeout(const Duration(seconds: 20));
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
      if (error.code == '23505') {
        throw const CatchSubmissionException(
          'This photo is already saved as one of your catches.',
        );
      }
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
          .from('catches')
          .select('id, station_id, species, weight, length, timestamp')
          .eq('station_id', stationId)
          .order('timestamp', ascending: false)
          .limit(20)
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

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static void _logFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      '$operation failed',
      name: 'AIFishMap.Catches',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
