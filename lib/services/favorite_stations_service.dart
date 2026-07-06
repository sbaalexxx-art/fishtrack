import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoriteStationsService {
  const FavoriteStationsService({SupabaseClient? client}) : _client = client;

  static final ValueNotifier<int> revision = ValueNotifier(0);

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  Future<Set<String>> getFavoriteIds() => _guard(() async {
    final user = _requireUser();
    final response = await _supabase
        .from('favorites')
        .select('station_id')
        .eq('user_id', user.id);
    return response
        .whereType<Map>()
        .map((row) => row['station_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  });

  Future<bool> isFavorite(String stationId) async =>
      (await getFavoriteIds()).contains(stationId);

  Future<bool> setFavorite(String stationId, {required bool favorite}) =>
      _guard(() async {
        final user = _requireUser();
        if (favorite) {
          await _supabase
              .from('favorites')
              .upsert(
                {'user_id': user.id, 'station_id': stationId},
                onConflict: 'user_id,station_id',
                ignoreDuplicates: true,
              );
        } else {
          await _supabase
              .from('favorites')
              .delete()
              .eq('user_id', user.id)
              .eq('station_id', stationId);
        }
        revision.value++;
        return favorite;
      });

  User _requireUser() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const FavoriteException(
        'Please sign in to save favourite stations.',
      );
    }
    return user;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on FavoriteException {
      rethrow;
    } on SocketException {
      throw const FavoriteException('No internet connection.');
    } on TimeoutException {
      throw const FavoriteException('The request timed out. Please retry.');
    } on PostgrestException {
      throw const FavoriteException(
        'Favourite stations are unavailable. Please retry.',
      );
    }
  }
}

class FavoriteException implements Exception {
  const FavoriteException(this.message);
  final String message;
}
