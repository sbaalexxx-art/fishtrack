import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class HydroDispatchAlertService {
  const HydroDispatchAlertService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<void> enableDefaultAlerts(String plantId) async {
    final normalized = plantId.trim();
    if (normalized.isEmpty) {
      throw const HydroDispatchAlertException(
        'Hydro plant identity is missing.',
      );
    }

    try {
      await _supabase
          .rpc(
            'upsert_hydro_dispatch_alert_rule_v1',
            params: <String, Object?>{
              'p_plant_id': normalized,
              'p_probability_threshold': 0.70,
              'p_min_probability_delta': 0.08,
              'p_window_lead_minutes': 90,
              'p_cooldown_minutes': 90,
              'p_notify_probability': true,
              'p_notify_window_approaching': true,
              'p_notify_observed_activity': true,
              'p_enabled': true,
              // Favorite state has its own explicit control in the Hydro panel.
              'p_save_favorite': false,
            },
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const HydroDispatchAlertException('No internet connection.');
    } on TimeoutException {
      throw const HydroDispatchAlertException(
        'Hydro alert request timed out. Please retry.',
      );
    } on PostgrestException catch (error) {
      throw HydroDispatchAlertException(
        error.message.trim().isEmpty
            ? 'Hydro alerts are unavailable. Please retry.'
            : error.message,
      );
    }
  }
}

class HydroDispatchAlertException implements Exception {
  const HydroDispatchAlertException(this.message);

  final String message;

  @override
  String toString() => message;
}
