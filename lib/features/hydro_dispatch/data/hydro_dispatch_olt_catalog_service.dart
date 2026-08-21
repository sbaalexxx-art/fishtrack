import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/hydro_dispatch_service.dart';

class HydroDispatchOltCatalogException implements Exception {
  const HydroDispatchOltCatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HydroDispatchOltCatalogService {
  const HydroDispatchOltCatalogService({SupabaseClient? client})
      : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<HydroDispatchDayForecast>> loadTodayTomorrow() async {
    try {
      if (_supabase.auth.currentUser == null) {
        throw const HydroDispatchOltCatalogException(
          'Autentificarea este necesară pentru Hydro PRO.',
        );
      }

      final response = await _supabase
          .rpc('get_hydro_dispatch_olt_today_tomorrow_v3')
          .timeout(const Duration(seconds: 20));
      if (response is! List) return const <HydroDispatchDayForecast>[];

      final rows = response
          .whereType<Map>()
          .map(
            (row) => HydroDispatchDayForecast.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .where((row) => row.plantId.isNotEmpty && row.plantName.isNotEmpty)
          .toList(growable: false)
        ..sort((left, right) {
          final order = left.nodeOrder.compareTo(right.nodeOrder);
          if (order != 0) return order;
          return left.dayOffset.compareTo(right.dayOffset);
        });

      return List<HydroDispatchDayForecast>.unmodifiable(rows);
    } on HydroDispatchOltCatalogException {
      rethrow;
    } on TimeoutException {
      throw const HydroDispatchOltCatalogException(
        'Datele Hydro răspund prea lent. Reîncearcă.',
      );
    } on SocketException {
      throw const HydroDispatchOltCatalogException(
        'Nu există conexiune la internet.',
      );
    } on PostgrestException {
      throw const HydroDispatchOltCatalogException(
        'Datele Hydro nu sunt disponibile momentan.',
      );
    }
  }
}
