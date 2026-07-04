import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';

class WaterRepository {
  const WaterRepository();

  Future<List<Station>> getStations() async {
    final client = Supabase.instance.client;
    final stationRows = await client
        .from('stations')
        .select()
        .order('name')
        .timeout(const Duration(seconds: 12));
    final levelRows = await client
        .from('water_levels')
        .select('station_id, value, timestamp, trend')
        .order('timestamp', ascending: false)
        .timeout(const Duration(seconds: 12));

    final latestLevels = <String, Map<String, dynamic>>{};
    for (final row in levelRows) {
      final stationId = row['station_id']?.toString();
      if (stationId != null && !latestLevels.containsKey(stationId)) {
        latestLevels[stationId] = row;
      }
    }

    return stationRows
        .map((row) {
          final data = Map<String, dynamic>.from(row);
          final latest = latestLevels[data['id']?.toString()];
          if (latest != null) {
            data['level'] = latest['value'];
            data['last_update'] = latest['timestamp'];
            data['trend'] = latest['trend'];
          }
          return Station.tryFromJson(data);
        })
        .whereType<Station>()
        .toList(growable: false);
  }
}
