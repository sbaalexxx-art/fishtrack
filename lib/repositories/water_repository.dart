import '../core/network/api_client.dart';
import '../models/station.dart';

class WaterRepository {
  const WaterRepository();

  final ApiClient _api = const ApiClient();

  Future<List<Station>> getStations() async {
    // În Sprint 4 aici vom apela API-ul AFDJ.
    // Momentan păstrăm date locale.

    // ignore: unused_local_variable
    final client = _api;

    return [
      Station(
        id: '1',
        name: 'Giurgiu',
        river: 'Dunărea',
        level: 336,
        trend: WaterTrend.rising,
        latitude: 43.9037,
        longitude: 25.9699,
        lastUpdate: DateTime.now(),
      ),
      Station(
        id: '2',
        name: 'Cernavodă',
        river: 'Dunărea',
        level: 289,
        trend: WaterTrend.stable,
        latitude: 44.3388,
        longitude: 28.0328,
        lastUpdate: DateTime.now(),
      ),
      Station(
        id: '3',
        name: 'Tulcea',
        river: 'Dunărea',
        level: 412,
        trend: WaterTrend.falling,
        latitude: 45.1716,
        longitude: 28.7914,
        lastUpdate: DateTime.now(),
      ),
    ];
  }
}
