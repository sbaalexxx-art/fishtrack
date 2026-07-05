import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catch.dart';

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
    required double weight,
    required double length,
    required String notes,
    required double latitude,
    required double longitude,
    required String stationId,
  }) async {
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
    } on SocketException {
      throw const CatchSubmissionException(
        'No internet connection. Your catch was not uploaded.',
      );
    } on TimeoutException {
      throw const CatchSubmissionException(
        'The upload timed out. Check your connection and try again.',
      );
    } on StorageException catch (error) {
      throw CatchSubmissionException('Image upload failed: ${error.message}');
    } on Exception {
      throw const CatchSubmissionException(
        'The image could not be uploaded. Please try again.',
      );
    }

    try {
      final data = <String, Object?>{
        'station_id': stationId,
        'species': species.trim(),
        'weight': weight,
        'length': length,
        'notes': notes.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'image': _supabase.storage.from(_bucket).getPublicUrl(storagePath),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      data['user_id'] = userId;
      await _supabase
          .from('catches')
          .insert(data)
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      await _removeImage(storagePath);
      throw const CatchSubmissionException(
        'No internet connection. Your catch was not saved.',
      );
    } on TimeoutException {
      await _removeImage(storagePath);
      throw const CatchSubmissionException(
        'Saving timed out. Check your connection and try again.',
      );
    } on Exception {
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
              weight == null ||
              length == null ||
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
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
