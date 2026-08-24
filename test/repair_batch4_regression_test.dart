import 'dart:io';

import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/widgets/fluviai/draggable_ask_fluvi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  group('Home Water semantics', () {
    test('combines a real daily delta with its trend', () {
      final result = resolveHomeWaterSemanticPresentation(
        dailyDelta: 12,
        trend: WaterTrend.rising,
        isRomanian: true,
      );
      expect(result.primary, '+12 cm / 24h · În creștere');
      expect(result.secondary, isNull);
    });

    test('keeps a known trend when daily delta is unavailable', () {
      final result = resolveHomeWaterSemanticPresentation(
        dailyDelta: null,
        trend: WaterTrend.rising,
        isRomanian: true,
      );
      expect(result.primary, 'Trend în creștere');
      expect(result.secondary, 'Date insuficiente pentru Δ24h');
    });

    test('reports both unavailable facts truthfully', () {
      final result = resolveHomeWaterSemanticPresentation(
        dailyDelta: null,
        trend: null,
        isRomanian: true,
      );
      expect(result.primary, 'Trend indisponibil');
      expect(result.secondary, 'Date insuficiente pentru Δ24h');
    });

    test('does not label a non-daily delta as 24 hours', () {
      final result = resolveHomeWaterSemanticPresentation(
        dailyDelta: null,
        trend: WaterTrend.falling,
        isRomanian: false,
      );
      expect(result.primary, 'Trend falling');
      expect(result.secondary, 'Insufficient data for Δ24h');
    });
  });

  test('Romanian local report categories never expose raw Other', () {
    expect(
      localizedHomeReportCategory(ReportCategory.other, isRomanian: true),
      'Altă observație',
    );
  });

  group('Water freshness truth', () {
    test('distinguishes live, cache, stale, error, and unavailable', () {
      expect(
        resolveWaterFreshnessDisplayState(_water()),
        WaterFreshnessDisplayState.live,
      );
      expect(
        resolveWaterFreshnessDisplayState(
          _water(status: WaterUiStatus.providerError, providerError: true),
        ),
        WaterFreshnessDisplayState.cache,
      );
      expect(
        resolveWaterFreshnessDisplayState(_water(isStale: true)),
        WaterFreshnessDisplayState.stale,
      );
      expect(
        resolveWaterFreshnessDisplayState(
          _water(
            hasReading: false,
            status: WaterUiStatus.providerError,
            providerError: true,
          ),
        ),
        WaterFreshnessDisplayState.error,
      );
      expect(
        resolveWaterFreshnessDisplayState(null),
        WaterFreshnessDisplayState.unavailable,
      );
    });
  });

  test('official Water chart keeps real observations in one visual series', () {
    final base = DateTime.utc(2026, 8, 8, 12);
    final segments = officialWaterChartSegments([
      _reading(base.subtract(const Duration(hours: 50)), 100),
      _reading(base.subtract(const Duration(hours: 49)), 101),
      _reading(base.subtract(const Duration(hours: 2)), 110),
      _reading(base.subtract(const Duration(hours: 1)), 111),
    ]);
    expect(segments.map((segment) => segment.length), [4]);
  });

  testWidgets('Water Details renders curved real series and touch metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final base = DateTime.utc(2026, 8, 8, 12);
    final history = [
      _reading(base.subtract(const Duration(hours: 14)), 100),
      _reading(base.subtract(const Duration(hours: 13)), 102),
      _reading(base.subtract(const Duration(hours: 12)), 101),
      _reading(base.subtract(const Duration(hours: 3)), 108),
      _reading(base.subtract(const Duration(hours: 2)), 109),
      _reading(base.subtract(const Duration(hours: 1)), 111),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: WaterHistorySheet(
            history: history,
            accessTier: FluviAccessTier.premium,
          ),
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.titlesData.show, isFalse);
    expect(chart.data.gridData.show, isFalse);
    expect(chart.data.lineTouchData.enabled, isTrue);
    expect(chart.data.lineBarsData, hasLength(1));
    expect(
      chart.data.lineBarsData.every(
        (bar) => bar.isCurved && bar.curveSmoothness == .18,
      ),
      isTrue,
    );
    expect(
      chart.data.lineBarsData.expand((bar) => bar.spots).map((spot) => spot.x),
      history.map(
        (reading) => reading.timestamp.millisecondsSinceEpoch.toDouble(),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'Home uses integrated contextual Ask while Full Map stays draggable',
    () {
      final home = File(
        'lib/features/commercial_home/presentation/commercial_home_page.dart',
      ).readAsStringSync();
      final map = File('lib/screens/map_page.dart').readAsStringSync();
      final settings = File(
        'lib/features/figma_complete/presentation/figma_account_pages.dart',
      ).readAsStringSync();
      expect(home, contains("ValueKey('home-ask-fluvi')"));
      expect(home, contains('canonicalFluviContextProvider'));
      expect(home, contains('AppDestination.askFluvi'));
      expect(home, isNot(contains('AskFluviPlacementScope.home')));
      expect(home, isNot(contains('DraggableAskFluviControl(')));
      expect(map, contains('AskFluviPlacementScope.fullMap'));
      expect(map, contains("ValueKey('map-ask-fluvi')"));
      expect(settings, contains('AskFluviPlacementStore.resetAll()'));
    },
  );

  group('Ask Fluvi placement', () {
    test('clamps, avoids obstacles, snaps, and normalizes safely', () {
      const geometry = AskFluviPlacementGeometry(
        workspace: Rect.fromLTWH(10, 10, 280, 280),
        controlSize: Size(40, 40),
        obstacles: [Rect.fromLTWH(10, 100, 100, 80)],
      );
      final clamped = geometry.constrain(const Offset(-100, -100));
      expect(clamped, const Offset(10, 10));

      final avoided = geometry.constrain(const Offset(30, 120));
      expect(
        (avoided & const Size(40, 40)).overlaps(geometry.obstacles.first),
        isFalse,
      );

      final snapped = geometry.snap(const Offset(220, 200));
      expect(snapped.dx, 250);
      final normalized = geometry.normalize(snapped);
      expect(normalized.dx, 1);
      expect(normalized.dy, inInclusiveRange(0, 1));
    });

    test('persists independently and reset removes both surfaces', () async {
      await AskFluviPlacementStore.save(
        AskFluviPlacementScope.home,
        Orientation.portrait,
        const Offset(.2, .7),
      );
      await AskFluviPlacementStore.save(
        AskFluviPlacementScope.fullMap,
        Orientation.portrait,
        const Offset(.8, .3),
      );
      expect(
        await AskFluviPlacementStore.load(
          AskFluviPlacementScope.home,
          Orientation.portrait,
        ),
        const Offset(.2, .7),
      );
      await AskFluviPlacementStore.resetAll();
      expect(
        await AskFluviPlacementStore.load(
          AskFluviPlacementScope.home,
          Orientation.portrait,
        ),
        isNull,
      );
      expect(
        await AskFluviPlacementStore.load(
          AskFluviPlacementScope.fullMap,
          Orientation.portrait,
        ),
        isNull,
      );
    });

    testWidgets('tap opens and long-press drag snaps to a safe edge', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: DraggableAskFluviControl(
                controlKey: const ValueKey('test-ask-fluvi'),
                scope: AskFluviPlacementScope.home,
                controlSize: const Size(40, 40),
                defaultNormalizedPosition: const Offset(0, 0),
                workspaceBuilder: (_) => const Rect.fromLTWH(10, 10, 280, 280),
                obstaclesBuilder: (_) => const [
                  Rect.fromLTWH(10, 100, 100, 80),
                ],
                semanticLabel: 'Ask Fluvi',
                onTap: () => taps++,
                child: const ColoredBox(color: Colors.teal),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('test-ask-fluvi')));
      await tester.pump();
      expect(taps, 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('test-ask-fluvi'))),
      );
      await tester.pump(const Duration(milliseconds: 620));
      await gesture.moveBy(const Offset(210, 170));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.byKey(const ValueKey('test-ask-fluvi')));
      expect(taps, 1);
      expect(rect.left, 250);
      expect(rect.left, greaterThanOrEqualTo(10));
      expect(rect.right, lessThanOrEqualTo(290));
      expect(tester.takeException(), isNull);
    });
  });
}

WaterLevel _reading(DateTime timestamp, double value) => WaterLevel(
  stationId: 'station',
  value: value,
  timestamp: timestamp,
  trend: WaterTrend.stable,
  source: WaterLevelSource.afdj,
  sourceName: 'AFDJ',
  hasKnownTrend: true,
);

WaterUiResult _water({
  bool hasReading = true,
  bool isStale = false,
  WaterUiStatus status = WaterUiStatus.availableHistory,
  bool providerError = false,
}) {
  final reading = hasReading ? _reading(DateTime.utc(2026, 8, 8), 123) : null;
  return WaterUiResult(
    latestReading: reading,
    history: reading == null ? const [] : [reading],
    source: reading?.source,
    sourceName: reading?.sourceName,
    measurementTimestamp: reading?.timestamp,
    dataAge: reading == null ? null : const Duration(hours: 1),
    isStale: isStale,
    status: status,
    safeDiagnosticMessage: null,
    providerError: providerError,
  );
}
