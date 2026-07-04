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
    final storagePath =
        '${userId ?? 'anonymous'}/${DateTime.now().microsecondsSinceEpoch}$extension';

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
      if (userId != null) data['user_id'] = userId;
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
    final catches = [
      Catch(
        id: '1',
        stationId: '1',
        species: 'Crap',
        weight: 6.4,
        length: 72,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Catch(
        id: '2',
        stationId: '1',
        species: 'Șalău',
        weight: 3.1,
        length: 61,
        date: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Catch(
        id: '3',
        stationId: '2',
        species: 'Somn',
        weight: 18.7,
        length: 145,
        date: DateTime.now().subtract(const Duration(days: 3)),
      ),
      Catch(
        id: '4',
        stationId: '2',
        species: 'Avat',
        weight: 2.6,
        length: 58,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Catch(
        id: '5',
        stationId: '3',
        species: 'Crap',
        weight: 8.2,
        length: 79,
        date: DateTime.now().subtract(const Duration(days: 4)),
      ),
      Catch(
        id: '6',
        stationId: '3',
        species: 'Știucă',
        weight: 5.8,
        length: 92,
        date: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];

    return catches
        .where((catchItem) => catchItem.stationId == stationId)
        .toList();
  }
}
