import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saved_item.dart';

class SavedItemsService {
  const SavedItemsService({SupabaseClient? client}) : _client = client;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  /// `hydropower` was used by the recovered Flutter UI before the backend
  /// contract was finalized. Keep it as a client compatibility alias while
  /// persisting only the canonical database type.
  static String canonicalItemType(String type) {
    final normalized = type.trim();
    return normalized == 'hydropower' ? 'hydropower_plant' : normalized;
  }

  Future<List<SavedItem>> getItems({String? type}) => _guard(() async {
    final user = _requireUser();
    final canonicalType = type == null ? null : canonicalItemType(type);
    var query = _supabase
        .from('saved_items')
        .select(
          'id,item_type,reference_id,title,subtitle,latitude,longitude,metadata,created_at',
        )
        .eq('user_id', user.id);
    final response = canonicalType == null || canonicalType.isEmpty
        ? await query.order('created_at', ascending: false)
        : await query
              .eq('item_type', canonicalType)
              .order('created_at', ascending: false);
    return response
        .whereType<Map>()
        .map((row) => SavedItem.fromJson(Map<String, dynamic>.from(row)))
        .where((item) => item.id.isNotEmpty && item.referenceId.isNotEmpty)
        .toList(growable: false);
  });

  Future<bool> isSaved({required String type, required String referenceId}) =>
      _guard(() async {
        final user = _requireUser();
        final rows = await _supabase
            .from('saved_items')
            .select('id')
            .eq('user_id', user.id)
            .eq('item_type', canonicalItemType(type))
            .eq('reference_id', referenceId)
            .limit(1);
        return rows.isNotEmpty;
      });

  Future<void> save({
    required String type,
    required String referenceId,
    required String title,
    String? subtitle,
    double? latitude,
    double? longitude,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => _guard(() async {
    final user = _requireUser();
    await _supabase.from('saved_items').upsert({
      'user_id': user.id,
      'item_type': canonicalItemType(type),
      'reference_id': referenceId,
      'title': title.trim(),
      'subtitle': subtitle?.trim().isEmpty == true ? null : subtitle?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,item_type,reference_id');
    revision.value++;
  });

  Future<void> remove({required String type, required String referenceId}) =>
      _guard(() async {
        final user = _requireUser();
        await _supabase
            .from('saved_items')
            .delete()
            .eq('user_id', user.id)
            .eq('item_type', canonicalItemType(type))
            .eq('reference_id', referenceId);
        revision.value++;
      });

  User _requireUser() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const SavedItemsException('Please sign in to save this item.');
    }
    return user;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on SavedItemsException {
      rethrow;
    } on SocketException {
      throw const SavedItemsException('No internet connection.');
    } on TimeoutException {
      throw const SavedItemsException('The request timed out. Please retry.');
    } on PostgrestException {
      throw const SavedItemsException(
        'Saved items are unavailable. Please retry.',
      );
    }
  }
}

class SavedItemsException implements Exception {
  const SavedItemsException(this.message);
  final String message;
}
