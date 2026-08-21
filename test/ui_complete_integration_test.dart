import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/utility/fluviai_utility_registry.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_destination_router.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/screens/weather_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complete UI inventory keeps every protected utility', () {
    const expectedIds = <String>{
      'water.overview',
      'water.hydro-pulse',
      'water.stations',
      'water.reservoirs',
      'water.hydropower',
      'map.full',
      'map.search',
      'map.access',
      'weather.forecast',
      'weather.solunar',
      'fluvi.score',
      'fluvi.insight',
      'fluvi.ask',
      'fluvi.vision',
      'community.feed',
      'reports.add',
      'reports.mine',
      'catches.add',
      'catches.mine',
      'journal.sessions',
      'journal.bite-effort',
      'favorites.my-waters',
      'alerts.center',
      'rules.can-fish-now',
      'rules.permits',
      'safety.ready-to-fish',
      'safety.check-in',
      'safety.fish-welfare',
      'safety.biosecurity',
      'account.profile',
      'account.settings',
      'account.premium',
      'account.support',
      'account.legal',
    };

    final actual = FluviUtilityRegistry.definitions
        .map((utility) => utility.id)
        .toSet();
    expect(actual, expectedIds);
    expect(
      FluviUtilityRegistry.definitions.map((utility) => utility.family).toSet(),
      FluviUtilityFamily.values.toSet(),
    );
  });

  test('every destination has one stable unique route definition', () {
    expect(
      AppDestinationRegistry.definitions.keys.toSet(),
      AppDestination.values.toSet(),
    );
    final paths = AppDestinationRegistry.definitions.values
        .map((definition) => definition.path)
        .toList(growable: false);
    expect(paths.toSet(), hasLength(paths.length));
    for (final definition in AppDestinationRegistry.definitions.values) {
      expect(definition.path, startsWith('/'));
      expect(definition.titleRo.trim(), isNotEmpty);
      expect(definition.titleEn.trim(), isNotEmpty);
    }
  });

  test('every non-shell destination builds an executable production page', () {
    final station = _station();
    const source = _FailingDataSource();
    const shellDestinations = <AppDestination>{
      AppDestination.home,
      AppDestination.map,
      AppDestination.activity,
      AppDestination.utilities,
    };

    for (final destination in AppDestination.values) {
      final page = FigmaDestinationRouter.page(
        destination,
        arguments: _argumentsFor(destination, station),
        dataSource: source,
      );
      if (shellDestinations.contains(destination)) {
        expect(page, isA<SizedBox>());
      } else {
        expect(
          page,
          isNot(isA<SizedBox>()),
          reason: '${destination.name} must resolve to a production page',
        );
      }
    }
  });

  test(
    'Water and Fluvi keep injected runtime source while Weather is GPS-owned',
    () {
      final station = _station();
      const source = _FailingDataSource();

      final water =
          FigmaDestinationRouter.page(
                AppDestination.water,
                arguments: station,
                dataSource: source,
              )
              as FigmaWaterHubPage;
      final weather = FigmaDestinationRouter.page(
        AppDestination.weather,
        arguments: station,
        dataSource: source,
      );
      final fluvi =
          FigmaDestinationRouter.page(
                AppDestination.fluvi,
                arguments: station,
                dataSource: source,
              )
              as FigmaFluviHubPage;

      expect(identical(water.dataSource, source), isTrue);
      expect(weather, isA<WeatherPage>());
      expect(identical(fluvi.dataSource, source), isTrue);
      expect(water.initialStation?.id, station.id);
      expect(fluvi.initialStation?.id, station.id);
    },
  );
}

Object? _argumentsFor(AppDestination destination, Station station) =>
    switch (destination) {
      AppDestination.water ||
      AppDestination.station ||
      AppDestination.weather ||
      AppDestination.fluvi ||
      AppDestination.newAlert => station,
      AppDestination.reportConfirmed => true,
      AppDestination.catchDetail => 'catch-smoke',
      AppDestination.favoriteCollection => 'collection-smoke',
      AppDestination.river => 'river-smoke',
      AppDestination.reservoir => 'reservoir-smoke',
      AppDestination.hydropower => 'hydropower-smoke',
      _ => null,
    };

Station _station() => Station(
  id: 'ui-complete-station',
  name: 'Baziaș',
  river: 'Dunărea',
  level: double.nan,
  trend: WaterTrend.stable,
  latitude: 44.8167,
  longitude: 21.3944,
  lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  hasWaterLevel: false,
  hasKnownTrend: false,
  waterLevelSource: 'UI test context',
);

class _FailingDataSource implements CommercialHomeDataSource {
  const _FailingDataSource();

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) =>
      Future<CommercialHomeSnapshot>.error(StateError('offline-test'));
}
