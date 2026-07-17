import 'dart:async';

import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/core/water/water_history_analysis.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/repositories/weather_repository.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/services/weather_service.dart';
import 'package:fishtrack/screens/water_level_page.dart'
    show
        WaterLevelPage,
        WaterDetailsPeriod,
        WaterDetailsSummary,
        waterDetailsTrendColor,
        waterDetailsSelectionForHandoff,
        waterDetailsRefreshLabel,
        waterDetailsPeriodLabel;
import 'package:fishtrack/widgets/home_premium/water_level_card.dart'
    show
        WaterLevelCardPremium,
        formatWaterCardDelta,
        isApproximatelyDailyWaterComparison,
        shouldShowWaterHistoryChart,
        shouldShowWaterLiveBadge,
        waterCardTrendColor;
import 'package:fishtrack/widgets/home_premium/home_premium_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    WaterService.clearCache();
    WeatherService.clearCache();
    WaterService.resetStationSelectionForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('Water card formats real deltas without inventing zero', () {
    expect(formatWaterCardDelta(41, 'cm'), '+41 cm');
    expect(formatWaterCardDelta(-12, 'cm'), '-12 cm');
    expect(formatWaterCardDelta(0, 'cm'), '0 cm');
    expect(formatWaterCardDelta(null, 'cm'), '—');
    expect(formatWaterCardDelta(.4, 'cm'), '+0.4 cm');
  });

  testWidgets('Water Details refresh and period labels are localized cleanly', (
    tester,
  ) async {
    Future<void> pumpLabel(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(
              '${waterDetailsRefreshLabel(context)}|${waterDetailsPeriodLabel(context, WaterDetailsPeriod.sevenDays)}',
            ),
          ),
        ),
      );
    }

    await pumpLabel(const Locale('ro'));
    expect(find.text('Actualizare\u2026|7 zile'), findsOneWidget);

    await pumpLabel(const Locale('en'));
    expect(find.text('Updating\u2026|7 days'), findsOneWidget);
  });

  test(
    'Water comparison label policy distinguishes daily and last readings',
    () {
      expect(
        isApproximatelyDailyWaterComparison(const Duration(hours: 24)),
        isTrue,
      );
      expect(
        isApproximatelyDailyWaterComparison(const Duration(hours: 6)),
        isFalse,
      );
    },
  );

  test(
    'Station weather keeps delayed A and B coordinate requests isolated',
    () async {
      final stationA = _homeStation('station-a', 'Station A', 44.81, 21.38);
      final stationB = _homeStation('station-b', 'Station B', 45.17, 28.81);
      final repository = _ControlledWeatherRepository();
      final service = WeatherService(repository: repository);

      final weatherA = service.getWeatherForStation(stationA);
      final weatherB = service.getWeatherForStation(stationB);

      expect(repository.requests, [(44.81, 21.38), (45.17, 28.81)]);

      repository.complete(45.17, 28.81, _weather(22));
      expect((await weatherB).temperature, 22);
      repository.complete(44.81, 21.38, _weather(11));
      expect((await weatherA).temperature, 11);
    },
  );

  test('Station weather rejects 0/0 without a provider request', () async {
    final repository = _ControlledWeatherRepository();
    final service = WeatherService(repository: repository);
    final station = _homeStation('missing-coordinates', 'Missing', 0, 0);

    await expectLater(
      service.getWeatherForStation(station),
      throwsA(isA<WeatherServiceException>()),
    );
    expect(repository.requests, isEmpty);
  });

  test('Water card maps each real trend to its official color', () {
    expect(waterCardTrendColor(WaterTrend.rising), const Color(0xFF2196F3));
    expect(waterCardTrendColor(WaterTrend.stable), const Color(0xFF43A047));
    expect(waterCardTrendColor(WaterTrend.falling), const Color(0xFFE53935));
    expect(waterCardTrendColor(null), const Color(0xFF9AA7B2));
  });

  test('Water card does not draw a chart without two real points', () {
    final reading = _reading(
      stationId: 'station-a',
      value: 500,
      timestamp: DateTime.utc(2026, 7, 16),
      source: WaterLevelSource.danubeFis,
    );

    expect(shouldShowWaterHistoryChart(const <WaterLevel>[]), isFalse);
    expect(shouldShowWaterHistoryChart([reading]), isFalse);
    expect(shouldShowWaterHistoryChart([reading, reading]), isTrue);
  });

  test('insufficient Home history never becomes zero and stable', () {
    final reading = _reading(
      stationId: 'bazias',
      value: 537,
      timestamp: DateTime.utc(2026, 7, 17, 9),
      source: WaterLevelSource.danubeFis,
    );
    final previous = _reading(
      stationId: 'bazias',
      value: 531,
      timestamp: DateTime.utc(2026, 7, 16, 9),
      source: WaterLevelSource.danubeFis,
    );

    expect(realWaterSeriesDelta(const <WaterLevel>[]), isNull);
    expect(realWaterSeriesDelta([reading]), isNull);
    expect(waterTrendFromRealDelta(realWaterSeriesDelta([reading])), isNull);
    expect(realWaterSeriesDelta([previous, reading]), 6);
    expect(
      waterTrendFromRealDelta(realWaterSeriesDelta([previous, reading])),
      WaterTrend.rising,
    );
  });

  test(
    'Water details periods filter and summarize only real history locally',
    () {
      final latest = DateTime.utc(2026, 7, 16, 12);
      final history = [
        _reading(
          value: 480,
          timestamp: latest.subtract(const Duration(days: 31)),
          source: WaterLevelSource.danubeFis,
        ),
        _reading(
          value: 500,
          timestamp: latest.subtract(const Duration(days: 13)),
          source: WaterLevelSource.danubeFis,
        ),
        _reading(
          value: 512,
          timestamp: latest.subtract(const Duration(days: 2)),
          source: WaterLevelSource.danubeFis,
        ),
        _reading(
          value: 520,
          timestamp: latest,
          source: WaterLevelSource.danubeFis,
        ),
      ];

      final sevenDays = WaterDetailsSummary.fromHistory(
        history,
        WaterDetailsPeriod.sevenDays,
      );
      final fourteenDays = WaterDetailsSummary.fromHistory(
        history,
        WaterDetailsPeriod.fourteenDays,
      );
      final thirtyDays = WaterDetailsSummary.fromHistory(
        history,
        WaterDetailsPeriod.thirtyDays,
      );

      expect(sevenDays.readings.map((reading) => reading.value), [512, 520]);
      expect(sevenDays.minimum, 512);
      expect(sevenDays.maximum, 520);
      expect(sevenDays.change, 8);
      expect(sevenDays.coverage, const Duration(days: 2));
      expect(fourteenDays.readings.map((reading) => reading.value), [
        500,
        512,
        520,
      ]);
      expect(thirtyDays.readings.map((reading) => reading.value), [
        500,
        512,
        520,
      ]);
      expect(fourteenDays.change, 20);
      expect(thirtyDays.change, 20);
    },
  );

  test('period trend delta and colors come only from real endpoints', () {
    final now = DateTime.utc(2026, 7, 16, 12);
    WaterDetailsSummary summary(double first, double last) =>
        WaterDetailsSummary.fromHistory(
          [
            _reading(
              stationId: 'orsova',
              value: first,
              timestamp: now.subtract(const Duration(days: 2)),
              source: WaterLevelSource.danubeFis,
            ),
            _reading(
              stationId: 'orsova',
              value: last,
              timestamp: now,
              source: WaterLevelSource.danubeFis,
            ),
          ],
          WaterDetailsPeriod.sevenDays,
          stationId: 'orsova',
        );

    final falling = summary(540, 533);
    final rising = summary(533, 540);
    final stable = summary(537, 537);
    expect(falling.change, -7);
    expect(falling.trend, WaterTrend.falling);
    expect(waterDetailsTrendColor(falling.trend), const Color(0xFFE53935));
    expect(rising.change, 7);
    expect(rising.trend, WaterTrend.rising);
    expect(waterDetailsTrendColor(rising.trend), const Color(0xFF2196F3));
    expect(stable.change, 0);
    expect(stable.trend, WaterTrend.stable);
    expect(waterDetailsTrendColor(stable.trend), const Color(0xFF43A047));
  });

  test('one real observation is visible but never produces a chart line', () {
    final summary = WaterDetailsSummary.fromHistory(
      [
        _reading(
          stationId: 'moldovaveche',
          value: 690,
          timestamp: DateTime.utc(2026, 7, 16),
          source: WaterLevelSource.danubeFis,
        ),
      ],
      WaterDetailsPeriod.sevenDays,
      stationId: 'moldova_veche',
    );

    expect(summary.readings.single.value, 690);
    expect(summary.hasChart, isFalse);
    expect(summary.change, isNull);
    expect(summary.trend, isNull);
  });

  test('missing observations never become zero deltas', () {
    expect(
      realWaterIntervalDelta(
        const <WaterLevel>[],
        const Duration(hours: 24),
        stationId: 'orsova',
      ),
      isNull,
    );
    final summary = WaterDetailsSummary.fromHistory(
      const <WaterLevel>[],
      WaterDetailsPeriod.thirtyDays,
      stationId: 'orsova',
    );
    expect(summary.change, isNull);
    expect(summary.minimum, isNull);
    expect(summary.maximum, isNull);
  });

  test('24h 48h and 7 day comparisons use nearby real observations', () {
    final latest = DateTime.utc(2026, 7, 16, 12);
    final history = [
      _reading(
        stationId: 'orsova',
        value: 550,
        timestamp: latest.subtract(const Duration(days: 7)),
        source: WaterLevelSource.danubeFis,
      ),
      _reading(
        stationId: 'orsova',
        value: 544,
        timestamp: latest.subtract(const Duration(hours: 48)),
        source: WaterLevelSource.danubeFis,
      ),
      _reading(
        stationId: 'orsova',
        value: 540,
        timestamp: latest.subtract(const Duration(hours: 24)),
        source: WaterLevelSource.danubeFis,
      ),
      _reading(
        stationId: 'orsova',
        value: 537,
        timestamp: latest,
        source: WaterLevelSource.danubeFis,
      ),
    ];

    expect(
      realWaterIntervalDelta(
        history,
        const Duration(hours: 24),
        stationId: 'orsova',
      )?.deltaCm,
      -3,
    );
    expect(
      realWaterIntervalDelta(
        history,
        const Duration(hours: 48),
        stationId: 'orsova',
      )?.deltaCm,
      -7,
    );
    expect(
      realWaterIntervalDelta(
        history,
        const Duration(days: 7),
        stationId: 'orsova',
      )?.deltaCm,
      -13,
    );
  });

  test('station A history is excluded from station B series', () {
    final now = DateTime.utc(2026, 7, 16);
    final mixed = [
      _reading(
        stationId: 'moldovaveche',
        value: 690,
        timestamp: now,
        source: WaterLevelSource.danubeFis,
      ),
      _reading(
        stationId: 'orsova',
        value: 310,
        timestamp: now.subtract(const Duration(days: 1)),
        source: WaterLevelSource.danubeFis,
      ),
      _reading(
        stationId: 'orsova',
        value: 303,
        timestamp: now,
        source: WaterLevelSource.danubeFis,
      ),
    ];
    final orsova = WaterDetailsSummary.fromHistory(
      mixed,
      WaterDetailsPeriod.sevenDays,
      stationId: 'orsova',
    );
    final moldova = WaterDetailsSummary.fromHistory(
      mixed,
      WaterDetailsPeriod.sevenDays,
      stationId: 'moldova_veche',
    );

    expect(orsova.readings.map((reading) => reading.value), [310, 303]);
    expect(orsova.change, -7);
    expect(moldova.readings.map((reading) => reading.value), [690]);
    expect(moldova.change, isNull);
  });

  test('period switching performs local filtering without a fetch', () {
    var fetchCount = 0;
    final history = [
      _reading(
        value: 500,
        timestamp: DateTime.utc(2026, 7, 1),
        source: WaterLevelSource.danubeFis,
      ),
      _reading(
        value: 510,
        timestamp: DateTime.utc(2026, 7, 16),
        source: WaterLevelSource.danubeFis,
      ),
    ];
    for (final period in WaterDetailsPeriod.values) {
      WaterDetailsSummary.fromHistory(history, period);
    }

    expect(fetchCount, 0);
  });

  test(
    'automatic candidates choose the nearest eligible canonical station',
    () {
      final candidates = WaterService.rankHomeCandidates(
        [
          _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
          _homeStation('afdj-tulcea', 'Tulcea', 45.1786, 28.8059),
          _homeStation('afdj-galati', 'Galati', 45.4353, 28.0080),
        ],
        latitude: 45.17,
        longitude: 28.81,
      );

      expect(candidates.first.id, 'afdj-tulcea');
    },
  );

  test('automatic fallback does not pin Bazias merely because it is first', () {
    final candidates = WaterService.rankHomeCandidates([
      _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
      _homeStation('afdj-moldova-veche', 'Moldova Veche', 44.7383, 21.6333),
    ]);

    expect(candidates.first.id, 'afdj-moldova-veche');
  });

  test('Water station selector exposes exactly 23 canonical stations', () {
    expect(WaterService.canonicalStationNames, [
      'Baziaș',
      'Moldova Veche',
      'Drencova',
      'Orșova',
      'Drobeta Turnu Severin',
      'Gruia',
      'Cetate',
      'Calafat',
      'Rast',
      'Bechet',
      'Corabia',
      'Turnu Măgurele',
      'Zimnicea',
      'Giurgiu',
      'Oltenița',
      'Călărași',
      'Cernavodă',
      'Hârșova',
      'Brăila',
      'Galați',
      'Isaccea',
      'Tulcea',
      'Sulina',
    ]);
    expect(WaterService.canonicalStationNames, hasLength(23));
    expect(
      WaterService.canonicalStationNames.any(
        (name) => name.toLowerCase().contains('periprava'),
      ),
      isFalse,
    );
  });

  test('Water station search is local and ignores Romanian diacritics', () {
    expect(WaterService.filterCanonicalStationNames('orsova'), ['Orșova']);
    expect(WaterService.filterCanonicalStationNames('Orșova'), ['Orșova']);
    expect(WaterService.filterCanonicalStationNames('calarasi'), ['Călărași']);
    expect(WaterService.filterCanonicalStationNames('Călărași'), ['Călărași']);
  });

  testWidgets(
    'real Water route exposes burger and pins Calafat from existing selector',
    (tester) async {
      final stations = _canonicalMenuStations();
      final service = WaterService(
        repository: _MenuWaterRepository(stations),
        locationService: _FixedLocationService(_position(44.2665, 22.7046)),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ro'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-home-water-route'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WaterLevelPage(waterService: service),
                    ),
                  ),
                  child: const Text('Open Water'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-home-water-route')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.byKey(const Key('water-station-menu-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      await tester.tap(find.byKey(const Key('water-station-menu-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Automat / Locația mea'), findsOneWidget);
      expect(find.text('Baziaș'), findsOneWidget);
      expect(find.byKey(const Key('water-station-search')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('water-station-search')),
        'Calafat',
      );
      await tester.pump();
      expect(find.byKey(const Key('water-station-calafat')), findsOneWidget);

      await tester.tap(find.byKey(const Key('water-station-calafat')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Automat / Locația mea'), findsNothing);
      expect(service.selectionMode, WaterStationSelectionMode.pinned);
      expect(service.selectedStation?.name, 'Calafat');
    },
  );

  test('manual Gruia and Moldova Veche selections remain pinned', () async {
    final stations = _canonicalMenuStations();
    final repository = _MenuWaterRepository(stations);
    final service = WaterService(
      repository: repository,
      locationService: _FixedLocationService(_position(44.2665, 22.7046)),
    );
    final gruia = WaterService.canonicalStationNamed(stations, 'Gruia')!;
    final moldova = WaterService.canonicalStationNamed(
      stations,
      'Moldova Veche',
    )!;

    service.selectStation(gruia);
    var selection = await service.resolveHomeStationSelection();
    expect(selection.mode, WaterStationSelectionMode.pinned);
    expect(selection.station?.name, 'Gruia');
    expect(selection.station?.id, isNot('bazias'));

    service.selectStation(moldova);
    selection = await service.resolveHomeStationSelection();
    expect(selection.mode, WaterStationSelectionMode.pinned);
    expect(selection.station?.name, 'Moldova Veche');
    expect(selection.station?.id, 'moldova_veche');
  });

  test('returning to Automatic reactivates geolocation near Gruia', () async {
    final stations = _canonicalMenuStations();
    final service = WaterService(
      repository: _MenuWaterRepository(stations),
      locationService: _FixedLocationService(_position(44.2665, 22.7046)),
    );
    service.selectStation(
      WaterService.canonicalStationNamed(stations, 'Moldova Veche')!,
    );
    expect(service.selectionMode, WaterStationSelectionMode.pinned);

    await service.setAutomatic();
    final selection = await service.resolveHomeStationSelection();

    expect(selection.mode, WaterStationSelectionMode.automatic);
    expect(selection.station?.name, 'Gruia');
    expect(selection.canonicalStations, hasLength(23));
  });

  test('manual station keeps name level history and source coherent', () async {
    final stations = _canonicalMenuStations();
    final repository = _MenuWaterRepository(stations);
    final service = WaterService(
      repository: repository,
      locationService: _FixedLocationService(_position(44.2665, 22.7046)),
    );
    final moldova = WaterService.canonicalStationNamed(
      stations,
      'Moldova Veche',
    )!;
    service.selectStation(moldova);

    final selection = await service.resolveHomeStationSelection();
    final result = await service.getWaterUiResult(selection.station!);

    expect(selection.station?.name, 'Moldova Veche');
    expect(selection.station?.level, moldova.level);
    expect(result.latestReading?.stationId, moldova.id);
    expect(
      result.history.every((reading) => reading.stationId == moldova.id),
      isTrue,
    );
    expect(result.source, WaterLevelSource.danubeHis);
    expect(
      result.history.every(
        (reading) => reading.source == WaterLevelSource.danubeHis,
      ),
      isTrue,
    );
  });

  test(
    'Water Details keeps Baziaș, Isaccea and Gruia station data coherent',
    () async {
      final stations = _canonicalMenuStations();
      final service = WaterService(repository: _MenuWaterRepository(stations));
      for (final name in const ['Baziaș', 'Isaccea', 'Gruia']) {
        final station = WaterService.canonicalStationNamed(stations, name)!;
        final result = await service.getWaterUiResult(station);

        expect(result.latestReading?.stationId, station.id);
        expect(
          result.history.every((reading) => reading.stationId == station.id),
          isTrue,
        );
        expect(result.latestReading?.value, station.level);
      }
    },
  );

  test('automatic selection never falls back to stations.first', () async {
    final stations = _canonicalMenuStations();
    expect(stations.first.name, 'Baziaș');
    final service = WaterService(
      repository: _MenuWaterRepository(stations),
      locationService: const _FailingLocationService(),
    );

    final selection = await service.resolveHomeStationSelection();

    expect(selection.mode, WaterStationSelectionMode.automatic);
    expect(selection.station, isNull);
  });

  test('Water details preserves the exact station handed off by Home', () {
    final bazias = _homeStation('bazias', 'Baziaș', 44.8176, 21.3892);
    final moldova = _homeStation(
      'moldova_veche',
      'Moldova Veche',
      44.723,
      21.634,
    );
    final orsova = _homeStation('orsova', 'Orșova', 44.725, 22.396);
    final resolved = WaterHomeStationSelection(
      mode: WaterStationSelectionMode.automatic,
      station: bazias,
      candidates: [bazias, moldova, orsova],
    );

    expect(
      waterDetailsSelectionForHandoff(resolved, moldova).station?.id,
      'moldova_veche',
    );
    expect(
      waterDetailsSelectionForHandoff(resolved, orsova).station?.id,
      'orsova',
    );
  });

  test('automatic candidates exclude invalid and noncanonical stations', () {
    final candidates = WaterService.rankHomeCandidates([
      _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
      _homeStation('afdj-chilia', 'Chilia Veche', 45.4167, 29.3),
      _homeStation(
        'afdj-tulcea',
        'Tulcea',
        45.1786,
        28.8059,
        hasReading: false,
      ),
    ]);

    expect(candidates.map((station) => station.id), ['afdj-bazias']);
  });

  test('automatic candidates are capped at five stations', () {
    final candidates = WaterService.rankHomeCandidates([
      _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
      _homeStation('afdj-moldova', 'Moldova Veche', 44.7383, 21.6333),
      _homeStation('afdj-drencova', 'Drencova', 44.6377, 21.9723),
      _homeStation('afdj-orsova', 'Orsova', 44.725, 22.396),
      _homeStation('afdj-drobeta', 'Drobeta Turnu Severin', 44.631, 22.656),
      _homeStation('afdj-gruia', 'Gruia', 44.2665, 22.7046),
    ]);

    expect(candidates, hasLength(5));
  });

  test(
    'manual selection persists pinned mode and automatic clears it',
    () async {
      final service = WaterService();
      final station = _homeStation('afdj-tulcea', 'Tulcea', 45.1786, 28.8059);

      service.selectStation(station);
      await Future<void>.delayed(Duration.zero);
      final preferences = await SharedPreferences.getInstance();
      expect(service.selectionMode, WaterStationSelectionMode.pinned);
      expect(
        preferences.getString('water_home_station_selection_mode'),
        'pinned',
      );
      expect(preferences.getString('water_home_pinned_station_id'), station.id);

      await service.setAutomatic();
      expect(service.selectionMode, WaterStationSelectionMode.automatic);
      expect(
        preferences.getString('water_home_station_selection_mode'),
        'automatic',
      );
      expect(preferences.containsKey('water_home_pinned_station_id'), isFalse);
    },
  );

  test('station metadata preserves missing dynamic Water fields', () {
    final station = Station.tryFromJson({
      'id': 'afdj-drencova',
      'name': 'Drencova',
      'river': 'Dunărea',
      'latitude': 44.6377707,
      'longitude': 21.9723364,
      'level': null,
      'trend': null,
      'last_update': null,
    });

    expect(station, isNotNull);
    expect(station!.persistedLevel, isNull);
    expect(station.persistedTrend, isNull);
    expect(station.persistedLastUpdate, isNull);
    expect(station.level.isNaN, isTrue);
    expect(station.hasWaterLevel, isFalse);
    expect(station.hasKnownTrend, isFalse);
    expect(station.trendText, 'Unknown');
    expect(station.lastUpdate.millisecondsSinceEpoch, 0);
  });

  test('complete station metadata remains compatible', () {
    final observedAt = DateTime.utc(2026, 7, 16, 9, 30);
    final station = Station.tryFromJson({
      'id': 'afdj-tulcea',
      'name': 'Tulcea',
      'river': 'Dunărea',
      'latitude': 45.1786,
      'longitude': 28.8059,
      'level': 214,
      'trend': 'falling',
      'last_update': observedAt.toIso8601String(),
      'has_water_level': true,
      'has_known_trend': true,
    });

    expect(station, isNotNull);
    expect(station!.persistedLevel, 214);
    expect(station.persistedTrend, WaterTrend.falling);
    expect(station.persistedLastUpdate, observedAt);
    expect(station.level, 214);
    expect(station.trend, WaterTrend.falling);
    expect(station.lastUpdate, observedAt);
    expect(station.hasWaterLevel, isTrue);
    expect(station.hasKnownTrend, isTrue);
  });

  test(
    'daily snapshots keep real chronological readings once per day',
    () async {
      final reader = _FakeSnapshotReader([
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-14',
          level: 500,
          measuredAt: DateTime.utc(2026, 7, 14, 8),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-15',
          level: 505,
          measuredAt: DateTime.utc(2026, 7, 15, 8),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-15',
          level: 512,
          measuredAt: DateTime.utc(2026, 7, 15, 12),
        ),
        _snapshotRow(
          stationId: 'station-b',
          observationDate: '2026-07-16',
          level: 999,
          measuredAt: DateTime.utc(2026, 7, 16),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-16',
          level: null,
          measuredAt: DateTime.utc(2026, 7, 16),
        ),
      ]);
      final result = await WaterRepository(
        snapshotReader: reader,
      ).getSnapshotHistoryResult('station-a', limit: 30);

      expect(reader.stationIds, ['station-a']);
      expect(reader.limits, [30]);
      expect(result.status, WaterHistoryResultStatus.success);
      expect(result.readings.map((reading) => reading.value), [500, 512]);
      expect(result.readings.last.trend, WaterTrend.rising);
      expect(result.readings.last.hasKnownTrend, isTrue);
      expect(
        result.readings.every((reading) => reading.stationId == 'station-a'),
        isTrue,
      );
    },
  );

  test(
    'daily snapshot history caps the requested series at thirty points',
    () async {
      final rows = List.generate(
        35,
        (index) => _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-06-${(index + 1).toString().padLeft(2, '0')}',
          level: index.toDouble(),
          measuredAt: DateTime.utc(2026, 6, index + 1),
        ),
      );
      final result = await WaterRepository(
        snapshotReader: _FakeSnapshotReader(rows),
      ).getSnapshotHistoryResult('station-a', limit: 99);

      expect(result.readings, hasLength(30));
      expect(result.readings.first.value, 5);
      expect(result.readings.last.value, 34);
    },
  );

  test('snapshot history exposes a positive delta and real interval', () async {
    final result = await WaterService(
      repository: _StaticHistoryRepository(
        _history([
          _reading(
            stationId: 'station-a',
            value: 500,
            timestamp: DateTime.utc(2026, 7, 10),
            source: WaterLevelSource.danubeFis,
          ),
          _reading(
            stationId: 'station-a',
            value: 512,
            timestamp: DateTime.utc(2026, 7, 13),
            source: WaterLevelSource.danubeFis,
          ),
        ]),
      ),
    ).getWaterUiResult(_stationWithoutReading());

    expect(result.deltaCm, 12);
    expect(result.trend, WaterTrend.rising);
    expect(result.comparisonDuration, const Duration(days: 3));
    expect(result.hasEnoughHistory, isTrue);
  });

  test(
    'snapshot history exposes negative and stable deltas without invention',
    () async {
      final falling = await WaterService(
        repository: _StaticHistoryRepository(
          _history([
            _reading(
              stationId: 'bazias',
              value: 520,
              timestamp: DateTime.utc(2026, 7, 10),
              source: WaterLevelSource.danubeFis,
            ),
            _reading(
              stationId: 'bazias',
              value: 508,
              timestamp: DateTime.utc(2026, 7, 11),
              source: WaterLevelSource.danubeFis,
            ),
          ]),
        ),
      ).getWaterUiResult(_stationWithoutReading());
      final stable = await WaterService(
        repository: _StaticHistoryRepository(
          _history([
            _reading(
              stationId: 'bazias',
              value: 508,
              timestamp: DateTime.utc(2026, 7, 10),
              source: WaterLevelSource.danubeFis,
            ),
            _reading(
              stationId: 'bazias',
              value: 508,
              timestamp: DateTime.utc(2026, 7, 11),
              source: WaterLevelSource.danubeFis,
            ),
          ]),
        ),
      ).getWaterUiResult(_stationWithoutReading());

      expect(falling.deltaCm, -12);
      expect(falling.trend, WaterTrend.falling);
      expect(stable.deltaCm, 0);
      expect(stable.trend, WaterTrend.stable);
    },
  );

  test('one snapshot leaves delta and trend unavailable', () async {
    final result = await WaterService(
      repository: _StaticHistoryRepository(
        _history([
          _reading(
            stationId: 'bazias',
            value: 508,
            timestamp: DateTime.utc(2026, 7, 11),
            source: WaterLevelSource.danubeFis,
          ),
        ]),
      ),
    ).getWaterUiResult(_stationWithoutReading());

    expect(result.deltaCm, isNull);
    expect(result.trend, isNull);
    expect(result.comparisonDuration, isNull);
    expect(result.hasEnoughHistory, isFalse);
  });

  test('a newer live reading is not replaced by an older snapshot', () async {
    final now = _now();
    final live = _reading(
      stationId: 'bazias',
      value: 530,
      timestamp: now.subtract(const Duration(minutes: 5)),
      source: WaterLevelSource.danubeFis,
    );
    final result = await WaterService(
      repository: _StaticHistoryRepository(
        _history([
          _reading(
            stationId: 'bazias',
            value: 500,
            timestamp: now.subtract(const Duration(days: 2)),
            source: WaterLevelSource.danubeFis,
          ),
        ]),
      ),
    ).getWaterUiResult(_stationFrom(live));

    expect(result.latestReading?.value, 530);
    expect(result.latestReading?.timestamp, live.timestamp);
  });

  test(
    'FIS current value is emitted before delayed canonical result',
    () async {
      final repository = _ControlledWaterRepository();
      final station = _stationFrom(
        _reading(
          value: 536,
          timestamp: _now().subtract(const Duration(minutes: 5)),
          source: WaterLevelSource.danubeFis,
        ),
      );
      final iterator = StreamIterator(
        WaterService(
          repository: repository,
        ).getProgressiveWaterUiResults(station),
      );

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.value, 536);
      expect(iterator.current.source, WaterLevelSource.danubeFis);
      expect(repository.historyRequestCount, 1);
      expect(repository.isCanonicalCompleted, isFalse);

      repository.complete(
        const WaterHistoryResult(
          status: WaterHistoryResultStatus.unavailable,
          readings: <WaterLevel>[],
          source: null,
          hadProviderError: false,
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.value, 536);
      expect(iterator.current.history, hasLength(1));
      expect(iterator.current.history.single.value, 536);
      expect(await iterator.moveNext(), isFalse);
    },
  );

  test('fresh AFDJ reconciles after the FIS fast result', () async {
    final now = _now();
    final repository = _ControlledWaterRepository();
    final iterator = StreamIterator(
      WaterService(repository: repository).getProgressiveWaterUiResults(
        _stationFrom(
          _reading(
            value: 536,
            timestamp: now.subtract(const Duration(minutes: 5)),
            source: WaterLevelSource.danubeFis,
          ),
        ),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    final fastResult = iterator.current;
    expect(fastResult.source, WaterLevelSource.danubeFis);

    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
          trend: WaterTrend.falling,
          hasKnownTrend: true,
        ),
      ]),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.latestReading?.value, 535);
    expect(iterator.current.source, WaterLevelSource.afdj);
    expect(await iterator.moveNext(), isFalse);
  });

  test('AFDJ provider error keeps the real FIS result visible', () async {
    final repository = _ControlledWaterRepository();
    final iterator = StreamIterator(
      WaterService(repository: repository).getProgressiveWaterUiResults(
        _stationFrom(
          _reading(
            value: 536,
            timestamp: _now().subtract(const Duration(minutes: 5)),
            source: WaterLevelSource.danubeFis,
          ),
        ),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    final fastResult = iterator.current;
    expect(fastResult.source, WaterLevelSource.danubeFis);

    repository.complete(
      const WaterHistoryResult(
        status: WaterHistoryResultStatus.providerError,
        readings: <WaterLevel>[],
        source: null,
        hadProviderError: true,
        safeDiagnosticMessage: 'Provider request failed: AFDJ',
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.latestReading?.value, 536);
    expect(iterator.current.source, WaterLevelSource.danubeFis);
    expect(iterator.current.status, WaterUiStatus.insufficientHistory);
    expect(await iterator.moveNext(), isFalse);
  });

  test('slow HIS history does not block the FIS current level', () async {
    final now = _now();
    final repository = _ControlledWaterRepository();
    final iterator = StreamIterator(
      WaterService(repository: repository).getProgressiveWaterUiResults(
        _stationFrom(
          _reading(
            value: 536,
            timestamp: now.subtract(const Duration(minutes: 10)),
            source: WaterLevelSource.danubeFis,
          ),
        ),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.source, WaterLevelSource.danubeFis);
    expect(repository.isCanonicalCompleted, isFalse);

    repository.complete(
      _result([
        _reading(
          value: 540,
          timestamp: now.subtract(const Duration(minutes: 2)),
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.source, WaterLevelSource.danubeHis);
    expect(await iterator.moveNext(), isFalse);
  });

  test('a timestamp over five minutes in the future is rejected', () async {
    final futureReading = _reading(
      value: 999,
      timestamp: _now().add(const Duration(minutes: 6)),
      source: WaterLevelSource.danubeFis,
    );
    final repository = _ControlledWaterRepository()
      ..complete(_result([futureReading]));
    final iterator = StreamIterator(
      WaterService(
        repository: repository,
      ).getProgressiveWaterUiResults(_stationFrom(futureReading)),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.latestReading, isNull);
    expect(iterator.current.status, WaterUiStatus.unavailable);
    expect(await iterator.moveNext(), isFalse);
  });

  test(
    'one historical point keeps trend unknown and history insufficient',
    () async {
      final reading = _reading(
        value: 536,
        timestamp: _now().subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      );
      final repository = _ControlledWaterRepository()
        ..complete(_result([reading]));
      final iterator = StreamIterator(
        WaterService(
          repository: repository,
        ).getProgressiveWaterUiResults(_stationFrom(reading)),
      );

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.hasKnownTrend, isFalse);
      expect(iterator.current.history, isEmpty);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.hasKnownTrend, isFalse);
      expect(iterator.current.history, hasLength(1));
      expect(iterator.current.status, WaterUiStatus.insufficientHistory);
      expect(await iterator.moveNext(), isFalse);
    },
  );

  test(
    'simultaneous progressive requests keep canonical deduplication',
    () async {
      final now = _now();
      final station = _stationFrom(
        _reading(
          value: 536,
          timestamp: now.subtract(const Duration(minutes: 5)),
          source: WaterLevelSource.danubeFis,
        ),
      );
      final repository = _ControlledWaterRepository();
      final service = WaterService(repository: repository);
      final first = StreamIterator(
        service.getProgressiveWaterUiResults(station),
      );
      final second = StreamIterator(
        service.getProgressiveWaterUiResults(station),
      );

      expect(await first.moveNext(), isTrue);
      expect(await second.moveNext(), isTrue);
      expect(repository.historyRequestCount, 1);

      repository.complete(
        _result([
          _reading(
            value: 535,
            timestamp: now.subtract(const Duration(hours: 1)),
            source: WaterLevelSource.afdj,
          ),
        ]),
      );
      expect(await first.moveNext(), isTrue);
      expect(await second.moveNext(), isTrue);
      expect(first.current.source, WaterLevelSource.afdj);
      expect(second.current.source, WaterLevelSource.afdj);
      expect(await first.moveNext(), isFalse);
      expect(await second.moveNext(), isFalse);
    },
  );

  test('simultaneous forced refreshes share one in-flight request', () async {
    final now = _now();
    final station = _stationFrom(
      _reading(
        value: 536,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _ControlledWaterRepository();
    final service = WaterService(repository: repository);
    final first = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );
    final second = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );

    expect(await first.moveNext(), isTrue);
    expect(await second.moveNext(), isTrue);
    expect(repository.historyRequestCount, 1);

    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    expect(await first.moveNext(), isTrue);
    expect(await second.moveNext(), isTrue);
    expect(first.current.source, WaterLevelSource.afdj);
    expect(second.current.source, WaterLevelSource.afdj);
    expect(await first.moveNext(), isFalse);
    expect(await second.moveNext(), isFalse);
  });

  test('forced refresh reuses an active normal request', () async {
    final now = _now();
    final station = _stationFrom(
      _reading(
        value: 536,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _ControlledWaterRepository();
    final service = WaterService(repository: repository);
    final normal = StreamIterator(
      service.getProgressiveWaterUiResults(station),
    );
    final forced = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );

    expect(await normal.moveNext(), isTrue);
    expect(await forced.moveNext(), isTrue);
    expect(repository.historyRequestCount, 1);

    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    expect(await normal.moveNext(), isTrue);
    expect(await forced.moveNext(), isTrue);
    expect(await normal.moveNext(), isFalse);
    expect(await forced.moveNext(), isFalse);
  });

  test('forced refresh after completion bypasses the finished cache', () async {
    final now = _now();
    final station = _stationFrom(
      _reading(
        value: 536,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _ControlledWaterRepository();
    final service = WaterService(repository: repository);
    final first = StreamIterator(service.getProgressiveWaterUiResults(station));

    expect(await first.moveNext(), isTrue);
    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    expect(await first.moveNext(), isTrue);
    expect(await first.moveNext(), isFalse);
    expect(repository.historyRequestCount, 1);

    final forced = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );
    expect(await forced.moveNext(), isTrue);
    expect(repository.historyRequestCount, 2);
    expect(await forced.moveNext(), isTrue);
    expect(forced.current.source, WaterLevelSource.afdj);
    expect(await forced.moveNext(), isFalse);
  });

  test(
    'forced refresh emits the same-station cache before the provider result',
    () async {
      final now = _now();
      final station = _stationWithoutReading();
      final repository = _SequencedWaterRepository();
      final service = WaterService(repository: repository);
      final initial = service.getWaterUiResult(station);
      repository.complete(
        0,
        _result([
          _reading(
            value: 535,
            timestamp: now.subtract(const Duration(minutes: 5)),
            source: WaterLevelSource.afdj,
          ),
        ]),
      );
      await initial;

      final refresh = StreamIterator(
        service.getProgressiveWaterUiResults(station, forceRefresh: true),
      );
      expect(await refresh.moveNext(), isTrue);
      expect(refresh.current.latestReading?.value, 535);
      expect(refresh.current.latestReading?.stationId, station.id);

      repository.complete(
        1,
        const WaterHistoryResult(
          status: WaterHistoryResultStatus.providerError,
          readings: <WaterLevel>[],
          source: null,
          hadProviderError: true,
        ),
      );
      expect(await refresh.moveNext(), isTrue);
      expect(refresh.current.latestReading?.value, 535);
      expect(refresh.current.status, WaterUiStatus.providerError);
      expect(await refresh.moveNext(), isFalse);
    },
  );

  testWidgets(
    'Home cold start uses one compact no-data state after loading finishes',
    (tester) async {
      final location = _ControlledLocationService();
      final service = WaterService(
        repository: _MenuWaterRepository(const <Station>[]),
        locationService: location,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ro'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: SizedBox(
                height: 150,
                child: WaterLevelCardPremium(
                  layout: HomePremiumLayout.of(context),
                  waterService: service,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(
        find.text('Se \u00eencarc\u0103 nivelul apei\u2026'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('water-home-no-data-message')), findsNothing);

      location.fail();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('water-home-no-data-message')),
        findsOneWidget,
      );
      expect(find.textContaining('F\u0103r\u0103 surs\u0103'), findsNothing);
      expect(find.textContaining('Se a\u0219teapt\u0103 date'), findsNothing);
    },
  );

  testWidgets(
    'Home Water remains RenderFlex-safe at narrow portrait and landscape sizes',
    (tester) async {
      final stations = _canonicalMenuStations();
      final drobeta = WaterService.canonicalStationNamed(
        stations,
        'Drobeta Turnu Severin',
      )!;
      final service = WaterService(
        repository: _MenuWaterRepository(stations),
        locationService: _FixedLocationService(
          _position(drobeta.latitude, drobeta.longitude),
        ),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> pumpHome(Size size) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ro'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: SizedBox(
                  height: size.height >= size.width ? 136 : 128,
                  child: WaterLevelCardPremium(
                    layout: HomePremiumLayout.of(context),
                    waterService: service,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
      }

      await pumpHome(const Size(320, 700));
      expect(tester.takeException(), isNull);

      await pumpHome(const Size(700, 320));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Water Details keeps long station and period controls visible when narrow',
    (tester) async {
      final stations = _canonicalMenuStations();
      final drobeta = WaterService.canonicalStationNamed(
        stations,
        'Drobeta Turnu Severin',
      )!;
      final service = WaterService(
        repository: _MenuWaterRepository(stations),
        locationService: _FixedLocationService(
          _position(drobeta.latitude, drobeta.longitude),
        ),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> pumpDetails(Size size, Locale locale) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: WaterLevelPage(
              initialStation: drobeta,
              waterService: service,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 700));
      }

      await pumpDetails(const Size(320, 700), const Locale('ro'));
      expect(find.text('7 zile'), findsAtLeastNWidgets(1));
      expect(find.text('14 zile'), findsAtLeastNWidgets(1));
      expect(find.text('30 zile'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('water-details-primary-delta')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('water-details-absolute-level')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('water-details-period-trend-badge')),
        findsOneWidget,
      );
      expect(find.textContaining('7 zile ·'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpDetails(const Size(700, 320), const Locale('en'));
      expect(find.text('7 zile'), findsAtLeastNWidgets(1));
      expect(find.text('14 zile'), findsAtLeastNWidgets(1));
      expect(find.text('30 zile'), findsAtLeastNWidgets(1));
      expect(find.textContaining('7 days ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('provider error is emitted with the last-known-good reading', () async {
    final now = _now();
    final station = _stationWithoutReading();
    final repository = _SequencedWaterRepository();
    final service = WaterService(repository: repository);
    final initialFuture = service.getWaterUiResult(station, limit: 71);
    repository.complete(
      0,
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(minutes: 5)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    final initial = await initialFuture;
    expect(initial.latestReading?.value, 535);

    final progressive = StreamIterator(
      service.getProgressiveWaterUiResults(station, limit: 72),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.status, isNot(WaterUiStatus.providerError));

    repository.complete(
      1,
      const WaterHistoryResult(
        status: WaterHistoryResultStatus.providerError,
        readings: <WaterLevel>[],
        source: null,
        hadProviderError: true,
        safeDiagnosticMessage: 'Provider request failed: AFDJ',
      ),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.status, WaterUiStatus.providerError);
    expect(progressive.current.latestReading?.value, 535);
    expect(progressive.current.source, WaterLevelSource.afdj);
    expect(await progressive.moveNext(), isFalse);
  });

  test('same measurement emits changed status source and trend', () async {
    final now = _now();
    final station = _stationWithoutReading();
    final repository = _SequencedWaterRepository();
    final service = WaterService(repository: repository);
    final timestamp = now.subtract(const Duration(minutes: 5));
    final initialFuture = service.getWaterUiResult(station, limit: 70);
    repository.complete(
      0,
      _result([
        _reading(
          value: 536,
          timestamp: timestamp,
          source: WaterLevelSource.danubeFis,
        ),
      ]),
    );
    final initial = await initialFuture;
    expect(initial.source, WaterLevelSource.danubeFis);
    expect(initial.latestReading?.hasKnownTrend, isFalse);

    final progressive = StreamIterator(
      service.getProgressiveWaterUiResults(station, limit: 72),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.source, WaterLevelSource.danubeFis);

    repository.complete(
      1,
      _result([
        _reading(
          value: 530,
          timestamp: timestamp.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.danubeHis,
        ),
        _reading(
          value: 536,
          timestamp: timestamp,
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.source, WaterLevelSource.danubeHis);
    expect(progressive.current.status, WaterUiStatus.availableHistory);
    expect(progressive.current.latestReading?.trend, WaterTrend.rising);
    expect(progressive.current.latestReading?.hasKnownTrend, isTrue);
    expect(await progressive.moveNext(), isFalse);
  });

  test('delayed station A result remains isolated from station B', () async {
    final now = _now();
    final stationA = _stationFrom(
      _reading(
        stationId: 'station-a',
        value: 100,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final stationB = _stationFrom(
      _reading(
        stationId: 'station-b',
        value: 200,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _PerStationWaterRepository();
    final service = WaterService(repository: repository);
    final first = StreamIterator(
      service.getProgressiveWaterUiResults(stationA),
    );
    final second = StreamIterator(
      service.getProgressiveWaterUiResults(stationB),
    );

    expect(await first.moveNext(), isTrue);
    expect(await second.moveNext(), isTrue);
    repository.complete(
      'station-b',
      _result([
        _reading(
          stationId: 'station-b',
          value: 201,
          timestamp: now.subtract(const Duration(minutes: 1)),
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await second.moveNext(), isTrue);
    expect(second.current.latestReading?.stationId, 'station-b');

    repository.complete(
      'station-a',
      _result([
        _reading(
          stationId: 'station-a',
          value: 101,
          timestamp: now.subtract(const Duration(minutes: 1)),
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await first.moveNext(), isTrue);
    expect(first.current.latestReading?.stationId, 'station-a');
    expect(await first.moveNext(), isFalse);
    expect(await second.moveNext(), isFalse);
  });

  test(
    'fresh reading with confirmed online connectivity permits live badge',
    () {
      expect(
        shouldShowWaterLiveBadge(
          hasRealReading: true,
          isStale: false,
          status: WaterUiStatus.insufficientHistory,
          connectivityKnown: true,
          isDefinitelyOffline: false,
        ),
        isTrue,
      );
    },
  );

  test('fresh reading in airplane mode hides live badge', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: true,
      ),
      isFalse,
    );
  });

  test('unknown connectivity hides live badge', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: false,
        isDefinitelyOffline: false,
      ),
      isFalse,
    );
  });

  test('live badge returns when connectivity recovers', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: true,
      ),
      isFalse,
    );
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: false,
      ),
      isTrue,
    );
  });

  test('provider error hides live badge despite confirmed connectivity', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.providerError,
        connectivityKnown: true,
        isDefinitelyOffline: false,
      ),
      isFalse,
    );
  });

  test('stale reading hides live badge despite confirmed connectivity', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: true,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: false,
      ),
      isFalse,
    );
  });

  test('offline badge policy preserves the cached water result', () {
    final cachedResult = WaterUiResult(
      latestReading: _reading(
        value: 536,
        timestamp: _now().subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
      history: const <WaterLevel>[],
      source: WaterLevelSource.danubeFis,
      sourceName: 'DanubeFIS',
      measurementTimestamp: _now().subtract(const Duration(minutes: 5)),
      dataAge: const Duration(minutes: 5),
      isStale: false,
      status: WaterUiStatus.insufficientHistory,
      safeDiagnosticMessage: null,
    );

    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: cachedResult.latestReading != null,
        isStale: cachedResult.isStale,
        status: cachedResult.status,
        connectivityKnown: true,
        isDefinitelyOffline: true,
      ),
      isFalse,
    );
    expect(cachedResult.latestReading?.value, 536);
  });
}

class _ControlledWaterRepository extends WaterRepository {
  final Completer<WaterHistoryResult> _canonical = Completer();
  int historyRequestCount = 0;

  bool get isCanonicalCompleted => _canonical.isCompleted;

  void complete(WaterHistoryResult result) => _canonical.complete(result);

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) {
    historyRequestCount++;
    return _canonical.future;
  }
}

class _SequencedWaterRepository extends WaterRepository {
  final List<Completer<WaterHistoryResult>> _requests = [];

  void complete(int index, WaterHistoryResult result) {
    _requests[index].complete(result);
  }

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) {
    final request = Completer<WaterHistoryResult>();
    _requests.add(request);
    return request.future;
  }
}

class _PerStationWaterRepository extends WaterRepository {
  final Map<String, Completer<WaterHistoryResult>> _requests = {};

  void complete(String stationId, WaterHistoryResult result) {
    _requests[stationId]!.complete(result);
  }

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) {
    final request = Completer<WaterHistoryResult>();
    _requests[stationId] = request;
    return request.future;
  }
}

class _MenuWaterRepository extends WaterRepository {
  _MenuWaterRepository(this.stations);

  final List<Station> stations;

  @override
  Future<List<Station>> getStations() async => stations;

  @override
  Future<List<Station>> getFastStations() async => stations;

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) async {
    final station = stations.singleWhere((value) => value.id == stationId);
    final source = station.name == 'Moldova Veche'
        ? WaterLevelSource.danubeHis
        : WaterLevelSource.afdj;
    final readings = [
      _reading(
        stationId: station.id,
        value: station.level - 2,
        timestamp: station.lastUpdate.subtract(const Duration(days: 1)),
        source: source,
      ),
      _reading(
        stationId: station.id,
        value: station.level,
        timestamp: station.lastUpdate,
        source: source,
      ),
    ];
    return WaterHistoryResult(
      status: WaterHistoryResultStatus.success,
      readings: readings,
      source: source,
      hadProviderError: false,
    );
  }
}

class _FixedLocationService extends LocationService {
  const _FixedLocationService(this.position);

  final Position position;

  @override
  Future<Position> determinePosition() async => position;
}

class _FailingLocationService extends LocationService {
  const _FailingLocationService();

  @override
  Future<Position> determinePosition() async =>
      throw const LocationFailure(LocationFailureReason.unavailable);
}

class _ControlledLocationService extends LocationService {
  final Completer<Position> _position = Completer<Position>();

  void fail() => _position.completeError(
    const LocationFailure(LocationFailureReason.unavailable),
  );

  @override
  Future<Position> determinePosition() => _position.future;
}

class _ControlledWeatherRepository extends WeatherRepository {
  final requests = <(double, double)>[];
  final _responses = <String, Completer<WeatherData>>{};

  @override
  Future<WeatherData> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) {
    requests.add((latitude, longitude));
    return _responses
        .putIfAbsent(
          _weatherKey(latitude, longitude),
          Completer<WeatherData>.new,
        )
        .future;
  }

  void complete(double latitude, double longitude, WeatherData weather) {
    _responses[_weatherKey(latitude, longitude)]!.complete(weather);
  }
}

class _StaticHistoryRepository extends WaterRepository {
  _StaticHistoryRepository(this.result);

  final WaterHistoryResult result;

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) async => result;
}

class _FakeSnapshotReader implements DailyWaterSnapshotReader {
  _FakeSnapshotReader(this.rows);

  final List<Map<String, Object?>> rows;
  final List<String> stationIds = <String>[];
  final List<int> limits = <int>[];

  @override
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  }) async {
    stationIds.add(stationId);
    limits.add(limit);
    return rows;
  }
}

WaterHistoryResult _history(List<WaterLevel> readings) => WaterHistoryResult(
  status: readings.length >= 2
      ? WaterHistoryResultStatus.success
      : WaterHistoryResultStatus.insufficientHistory,
  readings: readings,
  source: readings.isEmpty ? null : readings.last.source,
  hadProviderError: false,
);

Map<String, Object?> _snapshotRow({
  required String stationId,
  required String observationDate,
  required Object? level,
  required DateTime measuredAt,
  String source = 'DanubeFIS',
  String quality = 'valid',
}) => {
  'station_id': stationId,
  'observation_date': observationDate,
  'level_cm': level,
  'level_source': source,
  'level_measured_at': measuredAt.toIso8601String(),
  'quality': quality,
};

WaterHistoryResult _result(List<WaterLevel> readings) => WaterHistoryResult(
  status: readings.length >= 2
      ? WaterHistoryResultStatus.success
      : readings.isEmpty
      ? WaterHistoryResultStatus.unavailable
      : WaterHistoryResultStatus.insufficientHistory,
  readings: readings,
  source: readings.isEmpty ? null : readings.last.source,
  hadProviderError: false,
);

DateTime _now() => DateTime.now().toUtc();

WaterLevel _reading({
  String stationId = 'bazias',
  required double value,
  required DateTime timestamp,
  required WaterLevelSource source,
  WaterTrend trend = WaterTrend.stable,
  bool hasKnownTrend = false,
}) => WaterLevel(
  stationId: stationId,
  value: value,
  timestamp: timestamp,
  trend: trend,
  source: source,
  sourceName: source.name,
  hasKnownTrend: hasKnownTrend,
);

Station _stationFrom(WaterLevel reading) => Station(
  id: reading.stationId,
  name: 'Bazias',
  river: 'Dunarea',
  level: reading.value,
  trend: reading.trend,
  latitude: 44.8167,
  longitude: 21.3833,
  lastUpdate: reading.timestamp,
  hasWaterLevel: true,
  waterLevelUnit: reading.unit,
  waterLevelSource: reading.source.name,
  hasKnownTrend: reading.hasKnownTrend,
);

Station _stationWithoutReading() => Station(
  id: 'bazias',
  name: 'Bazias',
  river: 'Dunarea',
  level: 0,
  trend: WaterTrend.stable,
  latitude: 44.8167,
  longitude: 21.3833,
  lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  hasWaterLevel: false,
);

Station _homeStation(
  String id,
  String name,
  double latitude,
  double longitude, {
  bool hasReading = true,
}) => Station(
  id: id,
  name: name,
  river: 'Dunarea',
  level: hasReading ? 300 : 0,
  trend: WaterTrend.stable,
  latitude: latitude,
  longitude: longitude,
  lastUpdate: DateTime.utc(2026, 7, 16),
  hasWaterLevel: hasReading,
  waterLevelSource: 'DanubeFIS',
);

List<Station> _canonicalMenuStations() => WaterService.canonicalStationNames
    .asMap()
    .entries
    .map((entry) {
      final name = entry.value;
      final (latitude, longitude) = switch (name) {
        'Baziaș' => (44.8167, 21.3833),
        'Moldova Veche' => (44.7383, 21.6333),
        'Gruia' => (44.2665, 22.7046),
        _ => (46.0 + entry.key / 1000, 28.0 + entry.key / 1000),
      };
      final id = switch (name) {
        'Baziaș' => 'bazias',
        'Moldova Veche' => 'moldova_veche',
        'Gruia' => 'gruia',
        _ => 'canonical-${entry.key}',
      };
      final source = name == 'Moldova Veche'
          ? WaterLevelSource.danubeHis
          : WaterLevelSource.afdj;
      return Station(
        id: id,
        name: name,
        river: 'Dunărea',
        level: 300 + entry.key.toDouble(),
        trend: WaterTrend.stable,
        latitude: latitude,
        longitude: longitude,
        lastUpdate: DateTime.utc(2026, 7, 17, 9),
        hasWaterLevel: true,
        waterLevelUnit: 'cm',
        waterLevelSource: source.name,
        hasKnownTrend: true,
      );
    })
    .toList(growable: false);

Position _position(double latitude, double longitude) => Position(
  longitude: longitude,
  latitude: latitude,
  timestamp: DateTime.utc(2026, 7, 17, 9),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 1,
);

String _weatherKey(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(3)}:${longitude.toStringAsFixed(3)}';

WeatherData _weather(double temperature) => WeatherData(
  temperature: temperature,
  condition: 'Clear sky',
  humidity: 50,
  windSpeed: 10,
  windGusts: 15,
  windDirectionDegrees: 180,
  precipitationProbability: 0,
  cloudCover: 0,
  observedAt: DateTime.utc(2026, 7, 17),
  forecast: const <WeatherForecastDay>[],
  hourlyForecast: const <WeatherForecastHour>[],
  moonPhase: 'Full moon',
  fishingActivity: FishingActivity.good,
);
