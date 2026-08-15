import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/context/selected_context.dart';
import '../models/fishing_session.dart';

class FishingJournalRepository {
  const FishingJournalRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  Future<List<FishingSession>> getSessions({int limit = 50}) => _guard(() async {
    final user = _requireUser();
    final rows = await _supabase
        .from('fishing_sessions')
        .select('id,title,started_at,ended_at,notes,latitude,longitude,place_name,station_id,water_id,water_name,country_code,region')
        .eq('user_id', user.id)
        .order('started_at', ascending: false)
        .limit(limit < 1 ? 1 : (limit > 100 ? 100 : limit));
    return rows
        .whereType<Map>()
        .map((row) => FishingSession.fromJson(Map<String, dynamic>.from(row)))
        .where((session) => session.id.isNotEmpty)
        .toList(growable: false);
  });

  Future<FishingSession?> getOpenSession() => _guard(() async {
    final user = _requireUser();
    final rows = await _supabase
        .from('fishing_sessions')
        .select('id,title,started_at,ended_at,notes,latitude,longitude,place_name,station_id,water_id,water_name,country_code,region')
        .eq('user_id', user.id)
        .isFilter('ended_at', null)
        .order('started_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return FishingSession.fromJson(Map<String, dynamic>.from(rows.first));
  });

  Future<FishingSession> startSession({
    SelectedContext? context,
    String? title,
    String? notes,
  }) => _guard(() async {
    final user = _requireUser();
    final existing = await getOpenSession();
    if (existing != null) {
      throw const FishingJournalException('Ai deja o partidă activă. Încheie-o înainte de a începe alta.');
    }
    final row = await _supabase
        .from('fishing_sessions')
        .insert({
          'user_id': user.id,
          'title': _clean(title),
          'notes': _clean(notes),
          'latitude': context?.latitude,
          'longitude': context?.longitude,
          'place_name': context?.primaryLabel,
          'station_id': context?.stationId,
          'water_id': context?.waterId,
          'water_name': context?.waterName ?? context?.riverName,
          'country_code': context?.countryCode,
          'region': context?.region,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id,title,started_at,ended_at,notes,latitude,longitude,place_name,station_id,water_id,water_name,country_code,region')
        .single();
    return FishingSession.fromJson(Map<String, dynamic>.from(row));
  });

  Future<FishingSession> endSession(String id, {String? notes}) => _guard(() async {
    final user = _requireUser();
    final payload = <String, Object?>{
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (notes != null) payload['notes'] = _clean(notes);
    final row = await _supabase
        .from('fishing_sessions')
        .update(payload)
        .eq('id', id)
        .eq('user_id', user.id)
        .isFilter('ended_at', null)
        .select('id,title,started_at,ended_at,notes,latitude,longitude,place_name,station_id,water_id,water_name,country_code,region')
        .maybeSingle();
    if (row == null) {
      throw const FishingJournalException('Partida nu mai este activă sau nu a putut fi găsită.');
    }
    return FishingSession.fromJson(Map<String, dynamic>.from(row));
  });

  Future<void> updateNotes(String id, String notes) => _guard(() async {
    final user = _requireUser();
    await _supabase
        .from('fishing_sessions')
        .update({
          'notes': _clean(notes),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', user.id);
  });

  User _requireUser() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const FishingJournalException('Autentificarea este necesară pentru jurnal.');
    }
    return user;
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on FishingJournalException {
      rethrow;
    } on SocketException {
      throw const FishingJournalException('Nu există conexiune la internet.');
    } on TimeoutException {
      throw const FishingJournalException('Cererea a expirat. Încearcă din nou.');
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const FishingJournalException('Ai deja o partidă activă.');
      }
      throw const FishingJournalException('Jurnalul nu este disponibil momentan.');
    }
  }
}

class FishingJournalException implements Exception {
  const FishingJournalException(this.message);
  final String message;
}
