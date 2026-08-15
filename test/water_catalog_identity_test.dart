import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mobile Water catalog accepts a large backend-driven result set',
    () async {
      final rows = List<Map<String, dynamic>>.generate(1000, (index) {
        final observedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );
        return <String, dynamic>{
          'station_id': 'water-$index',
          'station_name': 'Water entity $index',
          'river_name': 'River ${index % 40}',
          'latitude': 43.0 + (index % 400) / 1000,
          'longitude': 20.0 + (index % 600) / 1000,
          'display_order': index,
          'level_cm': 100 + index,
          'observed_at': observedAt.toIso8601String(),
          'source_key': 'AFDJ',
          'source_name': 'AFDJ',
          'quality_status': 'validated',
        };
      });
      final repository = WaterRepository(
        mobileContractReader: _Reader(rows),
        snapshotReader: const _Snapshots(),
      );

      final stations = await repository.getStations();

      expect(stations, hasLength(1000));
      expect(stations.first.id, 'water-0');
      expect(stations.last.id, 'water-999');
      expect(stations.map((station) => station.id).toSet(), hasLength(1000));
    },
  );

  test(
    'station identity does not depend on punctuation in the display name',
    () {
      final station = _station(
        id: 'drobeta_turnu_severin',
        name: 'Drobeta-Turnu Severin',
      );

      expect(
        WaterService.canonicalStationNamed(<Station>[
          station,
        ], 'Drobeta Turnu Severin')?.id,
        'drobeta_turnu_severin',
      );
      expect(
        WaterService.filterStations(<Station>[
          station,
        ], 'drobeta turnu').single.id,
        'drobeta_turnu_severin',
      );
    },
  );

  test('catalog ordering and deduplication use stable IDs', () {
    final first = _station(id: 'entity-a', name: 'Same name');
    final duplicate = _station(id: 'entity-a', name: 'Renamed label');
    final second = _station(id: 'entity-b', name: 'Same name');

    final ordered = WaterService.orderCanonicalStations(<Station>[
      first,
      duplicate,
      second,
    ]);

    expect(ordered.map((station) => station.id), <String>[
      'entity-a',
      'entity-b',
    ]);
    expect(ordered.first.name, 'Same name');
  });
}

class _Reader implements WaterMobileContractReader {
  const _Reader(this.rows);

  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Map<String, dynamic>>> readLatestStations({
    String? stationId,
  }) async => rows;

  @override
  Future<List<Map<String, dynamic>>> readStationHistory(
    String stationId, {
    required int days,
  }) async => const <Map<String, dynamic>>[];
}

class _Snapshots implements DailyWaterSnapshotReader {
  const _Snapshots();

  @override
  Future<List<Map<String, Object?>>> readRecentStationTrends(
    Iterable<String> stationIds, {
    required DateTime notBefore,
  }) async => const <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  }) async => const <Map<String, Object?>>[];
}

Station _station({required String id, required String name}) => Station(
  id: id,
  name: name,
  river: 'Dunărea',
  level: 300,
  trend: WaterTrend.stable,
  latitude: 44.6,
  longitude: 22.6,
  lastUpdate: DateTime.utc(2026, 7, 30),
  hasWaterLevel: true,
);
