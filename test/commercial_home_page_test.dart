import 'dart:async';
import 'dart:io';

import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/theme/app_theme.dart';
import 'package:fishtrack/core/theme/fluviai_commercial_tokens.dart';

import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_destination_router.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/navigation/app_navigator.dart';
import 'package:fishtrack/core/navigation/water_entry.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'commercial-home-test-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    AppNavigator.resetForTesting();
  });

  test('canonical Home contains no mini-map runtime', () {
    final source = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('HomePremiumMap(')));
    expect(source, isNot(contains('DraggableAskFluviControl(')));
    expect(source, contains("ValueKey<String>('home-continuous-canvas')"));
    expect(source, contains("ValueKey('home-ask-fluvi')"));
    expect(source, contains('canonicalFluviContextProvider'));
  });

  test('Home Water chart reuses the canonical real-observation renderer', () {
    final home = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();
    final chart = File(
      'lib/widgets/home_premium/water_level_card.dart',
    ).readAsStringSync();

    expect(home, contains('realWaterHistorySeries('));
    expect(home, contains('HomeWaterHistoryLineChart('));
    expect(chart, contains('realWaterHistorySegments(readings)'));
    expect(chart, contains('LineChartBarData('));
    expect(chart, contains('isCurved: segment.length >= 3'));
    expect(chart, contains('preventCurveOverShooting: true'));
    expect(chart, contains('final reading = readingByX[spot.x]!'));
    expect(chart, contains("'\\n\$source'"));
  });

  testWidgets('approved Home renders the continuous hierarchy at 390px', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    expect(find.byKey(const ValueKey('canonical-home')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('commercial-home-context-header')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-menu-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-continuous-canvas')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('commercial-home-map')), findsNothing);
    expect(find.byKey(const ValueKey('commercial-water-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('commercial-weather-card')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('commercial-score-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-fluviscore-ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-fluviscore-value')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-fluviscore-confidence')),
      findsOneWidget,
    );
    expect(find.text('/ 100'), findsOneWidget);
    expect(find.text('Încredere: 75%'), findsOneWidget);
    expect(find.text('75%'), findsNothing);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('home-fluviscore-confidence')))
          .dy,
      greaterThan(tester.getTopLeft(find.text('Condiții bune')).dy),
    );
    final progress = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byKey(const ValueKey('home-fluviscore-ring')),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(
      (progress.valueColor! as AlwaysStoppedAnimation<Color>).value,
      FluviAICommercialTokens.fluviScoreActive,
    );
    expect(
      find.byKey(const ValueKey('commercial-community-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('commercial-reports-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-catch-catch-local')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-ask-fluvi')), findsOneWidget);
    expect(find.text('Capturi recente'), findsOneWidget);
    expect(find.text('Rapoarte live'), findsOneWidget);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      (scroll.padding! as EdgeInsets).bottom,
      FluviAICommercialTokens.bottomNavigationVisualHeight + 16,
    );

    expect(find.byKey(const ValueKey('home-more-menu-action')), findsNothing);
    expect(find.text('Drobeta-Turnu Severin'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('home-water-station-name')),
      findsOneWidget,
    );
    final canonicalWaterCard = find.byKey(
      const ValueKey('commercial-water-card'),
    );
    expect(
      find.descendant(
        of: canonicalWaterCard,
        matching: find.textContaining(RegExp('Dunărea', caseSensitive: false)),
      ),
      findsOneWidget,
    );
    expect(find.text('690 cm'), findsOneWidget);
    expect(find.text('22°'), findsOneWidget);
    expect(find.text('Vreme acum'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-weather-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-water-status')), findsOneWidget);
    expect(find.text('11 km/h · SV'), findsOneWidget);
    expect(find.text('1015 hPa'), findsOneWidget);
    expect(find.text('Parțial înnorat'), findsOneWidget);
    expect(find.text('Waxing crescent'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('home-weather-precipitation')),
          )
          .data,
      '18%',
    );
    expect(
      find.byKey(const ValueKey('home-weather-hourly-strip')),
      findsOneWidget,
    );
    expect(find.text('78'), findsOneWidget);
    expect(find.text('/ 100'), findsOneWidget);
    expect(find.text('Condiții bune'), findsOneWidget);
    expect(find.text('Încredere: 75%'), findsOneWidget);
    expect(find.text('Acces blocat'), findsOneWidget);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-continuous-canvas')))
          .width,
      358,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('390x844 Home exposes core decision modules without scrolling', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final water = tester.getRect(
      find.byKey(const ValueKey('commercial-water-card')),
    );
    expect(scrollable.position.pixels, 0);
    expect(water.top, lessThan(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home score and selector respect Reduce Motion', (tester) async {
    _configurePhone(tester, const Size(390, 844));
    final source = _FakeCommercialHomeDataSource(_snapshot());
    await tester.pumpWidget(_testApp(dataSource: source, reduceMotion: true));
    await _settleHome(tester);

    final scoreAnimationFinder = find.byKey(
      const ValueKey('home-fluviscore-progress-78'),
    );
    final scoreAnimation = tester.widget<TweenAnimationBuilder<double>>(
      scoreAnimationFinder,
    );
    expect(scoreAnimation.duration, Duration.zero);

    final selectorAnimations = find.descendant(
      of: find.byKey(const ValueKey('home-water-selector')),
      matching: find.byType(AnimatedContainer),
    );
    expect(selectorAnimations, findsNWidgets(3));
    for (final element in selectorAnimations.evaluate()) {
      expect((element.widget as AnimatedContainer).duration, Duration.zero);
    }

    final scoreElement = tester.element(scoreAnimationFinder);
    await tester.pumpWidget(_testApp(dataSource: source, reduceMotion: true));
    await _settleHome(tester);
    expect(tester.element(scoreAnimationFinder), same(scoreElement));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home field metadata remains outdoor-readable', (tester) async {
    _configurePhone(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    final context = tester.element(
      find.byKey(const ValueKey<String>('canonical-home')),
    );
    final palette = FluviAIThemeColors.of(context);
    final provenance = tester.widget<Text>(
      find.byKey(const ValueKey('home-water-provenance')),
    );
    final gusts = tester.widget<Text>(
      find.byKey(const ValueKey('home-weather-gusts')),
    );
    expect(provenance.style!.fontSize, 10.5);
    expect(provenance.style!.color, palette.textSecondary);
    expect(gusts.style!.fontSize, 10);
    expect(gusts.style!.color, palette.textSecondary);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home burger opens the canonical drawer and GPS stays a preview',
    (tester) async {
      _configurePhone(tester, const Size(390, 844));

      var selectedTab = -1;
      await tester.pumpWidget(
        _testApp(
          dataSource: _FakeCommercialHomeDataSource(_snapshot()),
          onNavigate: (index) => selectedTab = index,
        ),
      );
      await _settleHome(tester);

      await tester.tap(
        find.byKey(const ValueKey('commercial-home-context-header')),
      );
      await tester.pump();
      expect(selectedTab, -1);

      await tester.tap(find.byKey(const ValueKey('home-menu-button')));
      await tester.pumpAndSettle();
      expect(selectedTab, -1);
      expect(find.byKey(const ValueKey('home-more-drawer')), findsOneWidget);
      for (var index = 0; index < 5; index++) {
        expect(find.byKey(ValueKey('burger-family-$index')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('more-water')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home notifications uses the canonical destination', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    await tester.tap(find.byKey(const ValueKey('canonical-home-alerts')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(AppNavigator.destinationKey(AppDestination.notifications)),
      findsOneWidget,
    );
  });

  testWidgets('Commercial Home manual refresh remains a forced reload', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final source = _RecordingCommercialHomeDataSource(_snapshot());

    await tester.pumpWidget(_testApp(dataSource: source));
    await tester.pumpAndSettle();
    expect(source.forceRefreshes, [false]);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(source.forceRefreshes, [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote station selection does not replace Home GPS header', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final source = _MutableCommercialHomeDataSource(_snapshot());
    addTearDown(source.dispose);

    await tester.pumpWidget(_testApp(dataSource: source));
    await _settleHome(tester);
    expect(find.text('Drobeta-Turnu Severin'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('home-water-station-name')),
      findsOneWidget,
    );

    final now = DateTime.now().toUtc();
    final station = Station(
      id: 'bazias',
      name: 'Baziaș',
      river: 'Timiș',
      level: 121,
      trend: WaterTrend.stable,
      latitude: 44.816,
      longitude: 21.39,
      lastUpdate: now,
      hasWaterLevel: true,
      hasKnownTrend: true,
      waterLevelSource: 'AFDJ',
    );
    source.select(
      CommercialHomeSnapshot(
        station: station,
        water: null,
        weather: null,
        score: null,
        communityPosts: const [],
        loadedAt: now,
        currentLocation: source.current.currentLocation,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drobeta-Turnu Severin'), findsOneWidget);
    final remoteGpsHeader = find.byKey(
      const ValueKey('commercial-home-context-header'),
    );
    expect(
      find.descendant(
        of: remoteGpsHeader,
        matching: find.textContaining(RegExp('Timiș', caseSensitive: false)),
      ),
      findsNothing,
    );
    final remoteWaterCard = find.byKey(const ValueKey('commercial-water-card'));
    expect(
      find.descendant(
        of: remoteWaterCard,
        matching: find.textContaining(RegExp('Timiș', caseSensitive: false)),
      ),
      findsOneWidget,
    );
    final context = tester.element(find.byType(CommercialHomePage));
    final container = ProviderScope.containerOf(context, listen: false);
    expect(container.read(selectedContextProvider)?.stationId, 'bazias');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home presents truthful 24h water delta and polished compact weather',
    (tester) async {
      _configurePhone(tester, const Size(390, 844));

      await tester.pumpWidget(
        _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
      );
      await _settleHome(tester);

      expect(find.text('−12 cm / 24h'), findsOneWidget);
      expect(find.text('În scădere'), findsOneWidget);
      expect(
        find.text('Dunărea · AFDJ · LIVE · actualizat acum 42 min'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-water-selector')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-water-history-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-water-history-window')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-weather-temperature')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-weather-wind')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-weather-moon')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-weather-pressure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-weather-precipitation')),
        findsOneWidget,
      );
      expect(find.text('11 km/h · SV'), findsOneWidget);
      expect(find.text('1015 hPa'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('home-weather-precipitation')),
            )
            .data,
        '18%',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('Water selector request opens the requested canonical Hub section', () {
    const request = WaterHubRequest(initialSection: WaterHubSection.dams);
    final page = FigmaDestinationRouter.page(
      AppDestination.water,
      arguments: request,
    );

    expect(page, isA<FigmaWaterHubPage>());
    expect((page as FigmaWaterHubPage).initialSection, WaterHubSection.dams);
    final home = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();
    expect(home, contains('onSelectSection(WaterHubSection.dams)'));
  });

  testWidgets('Water selector is one flat 44dp segmented control', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    final selectorFinder = find.byKey(const ValueKey('home-water-selector'));
    final selector = tester.widget<Container>(selectorFinder);
    final decoration = selector.decoration! as BoxDecoration;
    expect(tester.getSize(selectorFinder).height, 44);
    expect(selector.clipBehavior, Clip.antiAlias);
    expect(decoration.border, isNotNull);
    expect(
      find.descendant(of: selectorFinder, matching: find.byType(InkWell)),
      findsNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Water history copy reports the actual visible interval', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final source = _FakeCommercialHomeDataSource(_snapshot());

    await tester.pumpWidget(_testApp(dataSource: source));
    await _settleHome(tester);
    expect(find.text('24h · 2 măsurători'), findsOneWidget);

    await tester.pumpWidget(
      _testApp(dataSource: source, accessTier: FluviAccessTier.premium),
    );
    await _settleHome(tester);
    expect(find.text('24h · 2 măsurători'), findsOneWidget);
  });

  test('Capturi keeps distinct truthful public runtime items', () {
    final now = DateTime.now().toUtc();
    CommunityPost catchPost(
      String id,
      String imageUrl, {
      bool suspicious = false,
      bool speciesUserConfirmed = true,
    }) => CommunityPost(
      id: id,
      userId: 'public-user',
      type: CommunityPostType.catchPost,
      title: 'Șalău',
      body: 'Captură publică',
      createdAt: now,
      authorName: 'Pescar',
      imageUrl: imageUrl,
      isSuspicious: suspicious,
      speciesUserConfirmed: speciesUserConfirmed,
    );

    final result = selectDistinctHomeCatches([
      catchPost('a', 'https://images.example/a.webp'),
      catchPost('b', 'https://images.example/a.webp'),
      catchPost('c', 'https://images.example/c.webp'),
      catchPost('d', 'https://images.example/d.webp', suspicious: true),
      catchPost(
        'e',
        'https://images.example/e.webp',
        speciesUserConfirmed: false,
      ),
    ]);

    expect(result.map((item) => item.id), ['a', 'c', 'e']);
  });

  test('Weather selects only upcoming canonical hourly observations', () {
    final now = DateTime(2026, 8, 22, 18);
    WeatherForecastHour hour(DateTime time) => WeatherForecastHour(
      time: time,
      temperature: 18,
      feelsLike: 18,
      humidity: 60,
      precipitationProbability: 10,
      cloudCover: 20,
      windSpeed: 7,
      windGusts: 11,
      windDirectionDegrees: 270,
      condition: 'Clear',
    );

    final selected = selectUpcomingHomeWeatherHours([
      hour(now.subtract(const Duration(hours: 2))),
      hour(now.add(const Duration(hours: 3))),
      hour(now.add(const Duration(hours: 1))),
      hour(now.add(const Duration(hours: 2))),
      hour(now.add(const Duration(hours: 4))),
      hour(now.add(const Duration(hours: 5))),
    ], now: now);

    expect(selected, hasLength(4));
    expect(selected.first.time, now.add(const Duration(hours: 1)));
    expect(selected.last.time, now.add(const Duration(hours: 4)));
  });

  testWidgets('Weather keeps critical Samsung-width values complete', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    for (final key in const [
      'home-weather-wind',
      'home-weather-pressure',
      'home-weather-precipitation',
    ]) {
      final text = tester.widget<Text>(find.byKey(ValueKey<String>(key)));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    }
    expect(find.text('11 km/h · SV'), findsOneWidget);
    expect(find.text('1015 hPa'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('home-weather-precipitation')),
          )
          .data,
      '18%',
    );
    expect(find.text('Parțial înnorat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Capturi is a responsive swipe carousel with canonical routing', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final now = DateTime.now();
    final catches = List<CommunityPost>.generate(
      5,
      (index) => CommunityPost(
        id: 'carousel-$index',
        userId: 'angler-$index',
        type: CommunityPostType.catchPost,
        title: 'Șalău ${index + 1}',
        body: 'Captură publică',
        createdAt: now.subtract(Duration(minutes: index * 10)),
        authorName: 'Pescar',
        imageUrl: 'https://images.example/catch-$index.webp',
        weight: 2 + index.toDouble(),
        latitude: 44.63,
        longitude: 22.66,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        dataSource: _FakeCommercialHomeDataSource(_snapshotWithPosts(catches)),
      ),
    );
    await _settleHome(tester);

    final strip = find.byKey(const ValueKey('home-catches-strip'));
    await tester.ensureVisible(strip);
    await tester.pump();
    final list = tester.widget<ListView>(strip);
    expect(list.scrollDirection, Axis.horizontal);
    expect(
      tester.getSize(find.byKey(const ValueKey('home-catch-slot-0'))).width,
      inInclusiveRange(145, 165),
    );
    final firstImage = find.byKey(
      const ValueKey('home-catch-image-carousel-0'),
    );
    expect(firstImage, findsOneWidget);
    expect(
      tester.getSize(firstImage),
      tester.getSize(find.byKey(const ValueKey('home-catch-carousel-0'))),
    );
    final catchTitle = tester.widget<Text>(
      find.byKey(const ValueKey('home-catch-title-carousel-0')),
    );
    final catchMetadata = tester.widget<Text>(
      find.byKey(const ValueKey('home-catch-metadata-carousel-0')),
    );
    expect(catchTitle.style!.fontSize, 14);
    expect(catchMetadata.style!.fontSize, 11.5);
    await tester.drag(strip, const Offset(-170, 0));
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: strip, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.pixels, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('home-catch-carousel-2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(AppNavigator.destinationKey(AppDestination.catchDetail)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reports height collapses when empty and expands for live rows', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(
        dataSource: _FakeCommercialHomeDataSource(_snapshotWithPosts(const [])),
      ),
    );
    await _settleHome(tester);
    final emptyCard = find.byKey(const ValueKey('commercial-reports-card'));
    await tester.ensureVisible(emptyCard);
    await tester.pump();
    final emptyHeight = tester.getSize(emptyCard).height;
    expect(emptyHeight, lessThanOrEqualTo(96));
    expect(find.byKey(const ValueKey('home-reports-empty')), findsOneWidget);

    final now = DateTime.now();
    final reports = List<CommunityPost>.generate(
      2,
      (index) => CommunityPost(
        id: 'live-report-$index',
        userId: 'reporter-$index',
        type: CommunityPostType.report,
        title: 'Raport local',
        body: 'Observație reală',
        createdAt: now.subtract(Duration(minutes: index * 5)),
        authorName: 'Pescar',
        reportCategory: ReportCategory.goodFishing,
        latitude: 44.63,
        longitude: 22.66,
        expiresAt: now.add(const Duration(hours: 2)),
        stillValidCount: 2,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _testApp(
        dataSource: _FakeCommercialHomeDataSource(_snapshotWithPosts(reports)),
      ),
    );
    await _settleHome(tester);
    final liveCard = find.byKey(const ValueKey('commercial-reports-card'));
    await tester.ensureVisible(liveCard);
    await tester.pump();
    expect(tester.getSize(liveCard).height, greaterThan(emptyHeight));
    expect(
      find.byKey(const ValueKey('home-report-live-report-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('integrated Ask Fluvi opens with canonical Home context', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);
    final homeContext = tester.element(find.byType(CommercialHomePage));
    final container = ProviderScope.containerOf(homeContext, listen: false);
    final expectedContext = container.read(canonicalFluviContextProvider);
    final ask = find.byKey(const ValueKey('home-ask-fluvi'));
    await tester.ensureVisible(ask);
    await tester.pump();
    await tester.tap(ask);
    await tester.pumpAndSettle();

    final route = find.byKey(
      AppNavigator.destinationKey(AppDestination.askFluvi),
    );
    expect(route, findsOneWidget);
    final page = tester.widget<FigmaAskFluviPage>(
      find.descendant(of: route, matching: find.byType(FigmaAskFluviPage)),
    );
    expect(identical(page.initialContext, expectedContext), isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Home uses the canonical ${brightness.name} palette', (
      tester,
    ) async {
      _configurePhone(tester, const Size(390, 844));
      await tester.pumpWidget(
        _testApp(
          dataSource: _FakeCommercialHomeDataSource(_snapshot()),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
        ),
      );
      await _settleHome(tester);

      final context = tester.element(
        find.byKey(const ValueKey<String>('canonical-home')),
      );
      final expected = brightness == Brightness.dark
          ? FluviAIThemeColors.dark
          : FluviAIThemeColors.light;
      expect(Theme.of(context).brightness, brightness);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        expected.background,
      );
      expect(find.byKey(const ValueKey('home-water-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-ask-fluvi')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home Auto follows OS brightness without mixed theme state', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      _testApp(
        dataSource: _FakeCommercialHomeDataSource(_snapshot()),
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
      ),
    );
    await _settleHome(tester);
    var context = tester.element(
      find.byKey(const ValueKey<String>('canonical-home')),
    );
    expect(Theme.of(context).brightness, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    context = tester.element(
      find.byKey(const ValueKey<String>('canonical-home')),
    );
    expect(Theme.of(context).brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home caps the continuous canvas cleanly at 430px width', (
    tester,
  ) async {
    _configurePhone(tester, const Size(430, 932));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-continuous-canvas')))
          .width,
      398,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home remains usable in compact landscape', (tester) async {
    _configurePhone(tester, const Size(844, 390));
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-continuous-canvas')))
          .width,
      398,
    );
    expect(find.byKey(const ValueKey('home-menu-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('commercial-water-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long physical GPS labels stay one-line ellipsized', (
    tester,
  ) async {
    _configurePhone(tester, const Size(320, 700));
    final baseline = _snapshot();
    final longLocation = CommercialHomeSnapshot(
      station: baseline.station,
      water: baseline.water,
      weather: baseline.weather,
      score: baseline.score,
      communityPosts: baseline.communityPosts,
      loadedAt: baseline.loadedAt,
      currentLocation: CurrentDeviceLocation(
        latitude: baseline.currentLocation!.latitude,
        longitude: baseline.currentLocation!.longitude,
        accuracyMeters: 8,
        observedAt: baseline.loadedAt,
        label:
            'Patchway, South Gloucestershire, United Kingdom, very long locality',
      ),
    );
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(longLocation)),
    );
    await _settleHome(tester);

    final header = find.byKey(const ValueKey('commercial-home-context-header'));
    final label = tester.widget<Text>(
      find.descendant(of: header, matching: find.textContaining('Patchway')),
    );
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid GPS without a locality never falls back to Zona ta', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final baseline = _snapshot();
    final gpsOnly = CommercialHomeSnapshot(
      station: baseline.station,
      water: baseline.water,
      weather: baseline.weather,
      score: baseline.score,
      communityPosts: baseline.communityPosts,
      loadedAt: baseline.loadedAt,
      currentLocation: CurrentDeviceLocation(
        latitude: baseline.currentLocation!.latitude,
        longitude: baseline.currentLocation!.longitude,
        accuracyMeters: 8,
        observedAt: baseline.loadedAt,
      ),
    );
    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(gpsOnly)),
    );
    await _settleHome(tester);

    expect(find.text('Locație GPS'), findsOneWidget);
    expect(find.text('Zona ta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home never presents a sparse five-day delta as a daily delta', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final baseline = _snapshot();
    final water = baseline.water!;
    final sparse = CommercialHomeSnapshot(
      station: baseline.station,
      water: WaterUiResult(
        latestReading: water.latestReading,
        previousReading: water.previousReading,
        history: water.history,
        source: water.source,
        sourceName: 'afdj',
        measurementTimestamp: water.measurementTimestamp,
        dataAge: const Duration(days: 10),
        isStale: true,
        status: water.status,
        safeDiagnosticMessage: water.safeDiagnosticMessage,
        deltaCm: -6,
        comparisonDuration: const Duration(days: 5),
        trend: water.trend,
        hasEnoughHistory: true,
      ),
      weather: baseline.weather,
      score: baseline.score,
      communityPosts: baseline.communityPosts,
      loadedAt: baseline.loadedAt,
      currentLocation: baseline.currentLocation,
    );

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(sparse)),
    );
    await _settleHome(tester);

    expect(find.text('Trend în scădere'), findsOneWidget);
    expect(find.text('Date insuficiente pentru Δ24h'), findsOneWidget);
    expect(find.textContaining('/ 5d'), findsNothing);
    expect(
      find.text('Dunărea · AFDJ · VECHI · actualizat acum 10 zile'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-water-status')), findsOneWidget);
    expect(find.text('STALE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continuous Home reflows safely at 360px and textScale 1.3', (
    tester,
  ) async {
    _configurePhone(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-continuous-canvas')))
          .width,
      328,
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('commercial-reports-card')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continuous Home remains scrollable without overflow at 200% text',
    (tester) async {
      _configurePhone(tester, const Size(390, 844));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
      );
      await _settleHome(tester);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('commercial-reports-card')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('continuous Home narrow-width fallback has no layout overflow', (
    tester,
  ) async {
    _configurePhone(tester, const Size(320, 700));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-continuous-canvas')))
          .width,
      288,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continuous Home never fabricates live values when data is absent',
    (tester) async {
      _configurePhone(tester, const Size(390, 844));

      await tester.pumpWidget(
        _testApp(
          dataSource: _FakeCommercialHomeDataSource(
            CommercialHomeSnapshot(
              station: null,
              water: null,
              weather: null,
              score: null,
              communityPosts: const [],
              loadedAt: DateTime.now(),
            ),
          ),
        ),
      );
      await _settleHome(tester);

      expect(find.text('214'), findsNothing);
      expect(find.text('18°'), findsNothing);
      expect(find.text('76'), findsNothing);
      expect(find.text('Niciun raport activ în apropiere'), findsOneWidget);
      expect(
        find.text('Nicio captură publică în această zonă'),
        findsOneWidget,
      );
      expect(find.text('—'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Home header shows GPS locality only', (tester) async {
    _configurePhone(tester, const Size(390, 844));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    final gpsHeader = find.byKey(
      const ValueKey('commercial-home-context-header'),
    );
    expect(gpsHeader, findsOneWidget);
    expect(
      find.descendant(
        of: gpsHeader,
        matching: find.text('Drobeta-Turnu Severin'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: gpsHeader, matching: find.textContaining('Dunărea')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('canonical-home-alerts')), findsOneWidget);
    expect(find.byKey(const ValueKey('commercial-water-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _configurePhone(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settleHome(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Widget _testApp({
  required CommercialHomeDataSource dataSource,
  ValueChanged<int>? onNavigate,
  FluviAccessTier accessTier = FluviAccessTier.free,
  ThemeData? theme,
  ThemeData? darkTheme,
  ThemeMode? themeMode,
  bool reduceMotion = false,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: theme ?? ThemeData(splashFactory: NoSplash.splashFactory),
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: const Locale('ro'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: CommercialHomePage(
        onNavigate: onNavigate ?? (_) {},
        dataSource: dataSource,
        accessTier: accessTier,
        mapOverride: const ColoredBox(color: Color(0xFF12343E)),
      ),
    ),
  );
}

CommercialHomeSnapshot _snapshot() {
  final now = DateTime.now().toUtc();
  final station = Station(
    id: 'drobeta_turnu_severin',
    name: 'Drobeta-Turnu Severin',
    river: 'Dunărea',
    level: 690,
    trend: WaterTrend.falling,
    latitude: 44.625,
    longitude: 22.656,
    lastUpdate: now.subtract(const Duration(minutes: 42)),
    hasWaterLevel: true,
    hasKnownTrend: true,
    waterLevelSource: 'AFDJ',
  );
  final current = WaterLevel(
    stationId: station.id,
    value: 690,
    timestamp: now.subtract(const Duration(minutes: 42)),
    trend: WaterTrend.falling,
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    hasKnownTrend: true,
  );
  final previous = WaterLevel(
    stationId: station.id,
    value: 702,
    timestamp: now.subtract(const Duration(hours: 24)),
    trend: WaterTrend.falling,
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    hasKnownTrend: true,
  );
  final water = WaterUiResult(
    latestReading: current,
    previousReading: previous,
    history: [previous, current],
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    measurementTimestamp: current.timestamp,
    dataAge: const Duration(minutes: 42),
    isStale: false,
    status: WaterUiStatus.availableHistory,
    safeDiagnosticMessage: null,
    deltaCm: -12,
    comparisonDuration: const Duration(hours: 24),
    trend: WaterTrend.falling,
    hasEnoughHistory: true,
  );
  final weatherData = WeatherData(
    temperature: 22,
    feelsLike: 21,
    condition: 'Partly cloudy',
    humidity: 64,
    windSpeed: 11,
    windGusts: 19,
    windDirectionDegrees: 245,
    precipitationProbability: 18,
    cloudCover: 37,
    pressure: 1015,
    observedAt: now,
    forecast: const [],
    hourlyForecast: List<WeatherForecastHour>.generate(
      4,
      (index) => WeatherForecastHour(
        time: now.add(Duration(hours: index + 1)),
        temperature: 21 - index.toDouble(),
        feelsLike: 20 - index.toDouble(),
        humidity: 65,
        precipitationProbability: 18 + index.toDouble(),
        cloudCover: 40,
        windSpeed: 10,
        windGusts: 16,
        windDirectionDegrees: 245,
        pressure: 1015,
        condition: index == 0 ? 'Partly cloudy' : 'Cloudy',
        isDay: true,
      ),
    ),
    moonPhase: 'Waxing crescent',
    fishingActivity: FishingActivity.good,
  );
  final weather = WeatherHomeResult(
    data: weatherData,
    latitude: station.latitude,
    longitude: station.longitude,
    locationSource: WeatherLocationSource.stationFallback,
    status: WeatherHomeStatus.available,
    dataTimestamp: now,
    dataAge: Duration.zero,
    isStale: false,
    safeDiagnosticMessage: null,
  );
  final score = FishingScoreResult(
    score: 78,
    rating: FishingScoreRating.good,
    recommendation: 'Condiții bune',
    explanation: 'Semnalele principale sunt favorabile.',
    positiveFactors: const ['Presiune stabilă'],
    negativeFactors: const ['Vânt moderat'],
    missingFactors: const [],
    bestTime: '18:30–20:30',
    confidence: 75,
    moonPhase: 'Waxing crescent',
    goldenHour: '18:30–20:30',
  );
  final community = CommunityPost(
    id: 'catch-local',
    userId: 'user-1',
    type: CommunityPostType.catchPost,
    title: 'Activitate mai redusă',
    body: 'Observație locală',
    createdAt: now.subtract(const Duration(minutes: 50)),
    authorName: 'Pescar local',
    latitude: 44.63,
    longitude: 22.66,
  );
  final report = CommunityPost(
    id: 'report-local',
    userId: 'user-2',
    type: CommunityPostType.report,
    title: 'Acces dificil',
    body: 'Accesul este îngreunat temporar.',
    createdAt: now.subtract(const Duration(minutes: 24)),
    authorName: 'Pescar local',
    reportCategory: ReportCategory.accessBlocked,
    latitude: 44.632,
    longitude: 22.662,
    expiresAt: now.add(const Duration(hours: 6)),
    stillValidCount: 4,
  );

  return CommercialHomeSnapshot(
    station: station,
    water: water,
    weather: weather,
    score: score,
    communityPosts: [community, report],
    loadedAt: now,
    currentLocation: CurrentDeviceLocation(
      latitude: station.latitude,
      longitude: station.longitude,
      accuracyMeters: 8,
      observedAt: now,
      label: 'Drobeta-Turnu Severin',
    ),
  );
}

CommercialHomeSnapshot _snapshotWithPosts(List<CommunityPost> posts) {
  final source = _snapshot();
  return CommercialHomeSnapshot(
    station: source.station,
    water: source.water,
    weather: source.weather,
    score: source.score,
    communityPosts: posts,
    loadedAt: source.loadedAt,
    selectionMode: source.selectionMode,
    currentLocation: source.currentLocation,
    environmentalContext: source.environmentalContext,
    resolvedContext: source.resolvedContext,
    waterStatus: source.waterStatus,
    weatherStatus: source.weatherStatus,
    scoreStatus: source.scoreStatus,
    communityStatus: source.communityStatus,
  );
}

class _FakeCommercialHomeDataSource implements CommercialHomeDataSource {
  const _FakeCommercialHomeDataSource(this.snapshot);

  final CommercialHomeSnapshot snapshot;

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      snapshot;
}

class _RecordingCommercialHomeDataSource implements CommercialHomeDataSource {
  _RecordingCommercialHomeDataSource(this.snapshot);

  final CommercialHomeSnapshot snapshot;
  final List<bool> forceRefreshes = [];

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async {
    forceRefreshes.add(forceRefresh);
    return snapshot;
  }
}

class _MutableCommercialHomeDataSource implements CommercialHomeDataSource {
  _MutableCommercialHomeDataSource(this._snapshot);

  CommercialHomeSnapshot _snapshot;
  CommercialHomeSnapshot get current => _snapshot;
  final StreamController<Station> _selections =
      StreamController<Station>.broadcast();

  @override
  Stream<Station> get stationSelections => _selections.stream;

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      _snapshot;

  void select(CommercialHomeSnapshot snapshot) {
    _snapshot = snapshot;
    _selections.add(snapshot.station!);
  }

  Future<void> dispose() => _selections.close();
}
