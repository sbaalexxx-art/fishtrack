import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/services/map_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = MapSearchService();
  final stations = [
    Station(
      id: '1',
      name: 'Moldova Veche',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.72,
      longitude: 21.62,
      lastUpdate: DateTime(2026),
    ),
    Station(
      id: '2',
      name: 'Brăila',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 45.27,
      longitude: 27.97,
      lastUpdate: DateTime(2026),
    ),
  ];

  test('station search is case insensitive', () {
    expect(
      service.searchStations('MOLDOVA', stations).single.name,
      'Moldova Veche',
    );
  });

  test('station search ignores Romanian diacritics', () {
    expect(service.searchStations('braila', stations).single.name, 'Brăila');
  });

  test('station search returns an empty list for no match', () {
    expect(service.searchStations('Isaccea', stations), isEmpty);
  });
}
