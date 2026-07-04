import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';

class WaterRepository {
  const WaterRepository();

  Future<List<Station>> getStations() async {
    final response = await Supabase.instance.client
        .from('stations')
        .select()
        .order('name')
        .timeout(const Duration(seconds: 12));

    return response.map(Station.tryFromJson).whereType<Station>().toList();
  }
}
