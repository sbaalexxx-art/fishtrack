import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';
import '../models/water_level.dart';

abstract interface class OfficialWaterDataSource {
  WaterLevelSource get source;

  Future<List<WaterLevel>> getHistory(String stationId, {int limit = 30});
}

class WaterRepository implements OfficialWaterDataSource {
  const WaterRepository();

  static const officialAfdjStationOrder = <String>[
    'Bazias',
    'Moldova Veche',
    'Drencova',
    'Orsova',
    'Drobeta Turnu Severin',
    'Gruia',
    'Cetate',
    'Calafat',
    'Rast',
    'Bechet',
    'Corabia',
    'Turnu Magurele',
    'Zimnicea',
    'Giurgiu',
    'Oltenita',
    'Calarasi',
    'Cernavoda',
    'Harsova',
    'Braila',
    'Galati',
    'Isaccea',
    'Tulcea',
    'Sulina',
  ];

  // Metadata-only fallbacks for official AFDJ stations missing from the
  // current Supabase seed. Coordinates are published by AFDJ; levels remain
  // unavailable until a real reading exists.
  static final _missingSeedStations = <String, Station>{
    _normalizedName('Drencova'): Station(
      id: 'afdj-drencova',
      name: 'Drencova',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.6377707,
      longitude: 21.9723364,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    _normalizedName('Gruia'): Station(
      id: 'afdj-gruia',
      name: 'Gruia',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.2665732,
      longitude: 22.7046852,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    _normalizedName('Cetate'): Station(
      id: 'afdj-cetate',
      name: 'Cetate',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.1114259,
      longitude: 23.0475514,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    _normalizedName('Rast'): Station(
      id: 'afdj-rast',
      name: 'Rast',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 43.8851672,
      longitude: 23.2813472,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
  };

  @override
  WaterLevelSource get source => WaterLevelSource.manualFallback;

  Future<List<Station>> getStations() async {
    final client = Supabase.instance.client;
    final stationRows = await client
        .from('stations')
        .select()
        .timeout(const Duration(seconds: 12));
    List<Map<String, dynamic>> levelRows = const [];
    try {
      levelRows = await client
          .from('water_levels')
          .select('station_id, value, timestamp, trend')
          .order('timestamp', ascending: false)
          .timeout(const Duration(seconds: 12));
    } on PostgrestException catch (error) {
      if (!_isUnavailableTable(error)) rethrow;
    }

    final latestLevels = <String, Map<String, dynamic>>{};
    for (final row in levelRows) {
      final stationId = row['station_id']?.toString();
      if (stationId != null && !latestLevels.containsKey(stationId)) {
        latestLevels[stationId] = row;
      }
    }

    final stationsByName = stationRows
        .map((row) {
          final data = Map<String, dynamic>.from(row);
          final latest = latestLevels[data['id']?.toString()];
          if (latest != null) {
            data['level'] = latest['value'];
            data['last_update'] = latest['timestamp'];
            data['trend'] = latest['trend'];
            data['has_water_level'] = true;
          } else {
            data['has_water_level'] = false;
          }
          return Station.tryFromJson(data);
        })
        .whereType<Station>()
        .fold<Map<String, Station>>({}, (stations, station) {
          stations[_normalizedName(station.name)] = station;
          return stations;
        });

    return officialAfdjStationOrder
        .map((name) {
          final key = _normalizedName(name);
          return stationsByName[key] ?? _missingSeedStations[key];
        })
        .whereType<Station>()
        .toList(growable: false);
  }

  @override
  Future<List<WaterLevel>> getHistory(
    String stationId, {
    int limit = 30,
  }) async {
    try {
      final rows = await Supabase.instance.client
          .from('water_levels')
          .select('station_id, value, timestamp, trend')
          .eq('station_id', stationId)
          .order('timestamp', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 12));
      return rows
          .map(
            (row) => WaterLevel.tryFromJson(
              row,
              fallbackStationId: stationId,
              source: source,
            ),
          )
          .whereType<WaterLevel>()
          .toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isUnavailableTable(error)) return const [];
      rethrow;
    }
  }

  static bool _isUnavailableTable(PostgrestException error) =>
      error.code == '42P01' || error.code == 'PGRST205';

  static String _normalizedName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[ăâáàä]'), 'a')
      .replaceAll(RegExp('[îíìï]'), 'i')
      .replaceAll(RegExp('[șş]'), 's')
      .replaceAll(RegExp('[țţ]'), 't')
      .replaceAll(RegExp('[^a-z0-9]'), '');
}
