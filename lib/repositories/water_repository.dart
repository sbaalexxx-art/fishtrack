import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';

class WaterRepository {
  const WaterRepository();

  Future<List<Station>> getStations() async {
    final response = await Supabase.instance.client
        .from('stations')
        .select()
        .order('name');

    return response.map<Station>((json) {
      WaterTrend trend;

      switch (json['trend']) {
        case 'rising':
          trend = WaterTrend.rising;
          break;

        case 'falling':
          trend = WaterTrend.falling;
          break;

        default:
          trend = WaterTrend.stable;
      }

      return Station(
        id: json['id'].toString(),
        name: json['name'],
        river: json['river'],
        level: (json['level'] as num).toDouble(),
        trend: trend,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        lastUpdate: DateTime.parse(json['last_update']),
      );
    }).toList();
  }
}
