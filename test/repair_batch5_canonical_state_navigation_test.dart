import 'dart:io';

import 'package:fishtrack/core/context/environmental_context.dart';
import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/theme/fluviai_commercial_tokens.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_community_pages.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/notification_preferences_service.dart';
import 'package:fishtrack/widgets/navigation/fluviai_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'canonical contexts keep device, search, water, and station identity separate',
    () {
      final now = DateTime.utc(2026, 8, 9);
      final device = EnvironmentalContext(
        source: EnvironmentalContextSource.deviceGps,
        latitude: 51.5,
        longitude: -0.1,
        observedAt: now,
        locality: 'London',
        countryCode: 'GB',
      );
      final searched = EnvironmentalContext(
        source: EnvironmentalContextSource.searchedPlace,
        latitude: 44.4,
        longitude: 26.1,
        observedAt: now,
        displayLabel: 'Bucharest',
      );
      final water = const SelectedContext(
        waterId: 'danube',
        waterName: 'Danube',
        latitude: 44.8,
        longitude: 21.4,
      ).environmentalContext!;

      expect(device.contextKey, isNot(searched.contextKey));
      expect(water.source, EnvironmentalContextSource.selectedWater);
      expect(water.waterId, 'danube');
      expect(water.stationId, isNull);
    },
  );

  test(
    'monitoring station preserves station identity and never becomes a water id',
    () {
      final station = Station(
        id: 'station-42',
        name: 'Gauge 42',
        river: 'Danube',
        level: 120,
        trend: WaterTrend.stable,
        latitude: 44.8,
        longitude: 21.4,
        lastUpdate: DateTime.utc(2026, 8, 9),
      );
      final selected = SelectedContext.fromStation(station);

      expect(selected.stationId, station.id);
      expect(selected.stationName, station.name);
      expect(selected.waterId, isNull);
      expect(selected.waterName, station.river);
      expect(
        selected.environmentalContext!.source,
        EnvironmentalContextSource.selectedStation,
      );
    },
  );

  test('community radius and My Reports ownership are enforced', () {
    final now = DateTime.now();
    CommunityPost post(String id, String user, double? lat, double? lng) =>
        CommunityPost(
          id: id,
          userId: user,
          type: CommunityPostType.report,
          title: id,
          body: id,
          createdAt: now,
          authorName: user,
          latitude: lat,
          longitude: lng,
          expiresAt: now.add(const Duration(hours: 1)),
        );
    final posts = [
      post('near-mine', 'me', 51.51, -0.11),
      post('far-mine', 'me', 53.48, -2.24),
      post('near-other', 'other', 51.50, -0.12),
      post('unknown', 'me', null, null),
    ];
    final local = LocalContentContext(
      latitude: 51.5,
      longitude: -0.1,
      radiusKm: 100,
      observedAt: now,
    );

    expect(
      filterCommunityPostsWithinLocalContext(posts, local).map((p) => p.id),
      containsAll(<String>['near-mine', 'near-other']),
    );
    expect(
      filterCommunityPostsWithinLocalContext(posts, local).map((p) => p.id),
      isNot(contains('far-mine')),
    );
    expect(
      filterReportsForUser(posts, 'me').map((p) => p.id),
      isNot(contains('near-other')),
    );
  });

  test('notification preferences survive service memory reset', () async {
    SharedPreferences.setMockInitialValues(const {});
    final service = NotificationPreferencesService();
    const saved = NotificationPreferences(
      enabledCategories: {NotificationCategory.waterAlerts},
      quietHoursEnabled: true,
      quietStartMinutes: 123,
      quietEndMinutes: 456,
      groupingEnabled: false,
      cooldown: Duration(minutes: 30),
    );
    await service.saveForUser('user-a', saved);
    NotificationPreferencesService.clearMemoryForTesting();

    final restored = await NotificationPreferencesService().loadForUser(
      'user-a',
    );
    expect(restored.enabledCategories, {NotificationCategory.waterAlerts});
    expect(restored.quietHoursEnabled, isTrue);
    expect(restored.quietStartMinutes, 123);
    expect(restored.groupingEnabled, isFalse);
  });

  testWidgets('Samsung bottom inset is outside the fixed painted nav surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            bottomNavigationBar: FluviAIBottomNavigationBar(
              selectedIndex: 0,
              onSelect: _noopIndex,
              onAdd: _noop,
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('main-bottom-navigation')))
          .height,
      FluviAICommercialTokens.bottomNavigationVisualHeight,
    );
    expect(
      tester.getSize(find.byType(FluviAIBottomNavigationBar)).height,
      FluviAICommercialTokens.bottomNavigationVisualHeight + 34,
    );
  });

  test(
    'source guards preserve canonical map, progressive Home, and no sessions',
    () {
      final navigator = File(
        'lib/core/navigation/app_navigator.dart',
      ).readAsStringSync();
      final homeData = File(
        'lib/features/commercial_home/data/commercial_home_data_source.dart',
      ).readAsStringSync();
      final environment = File(
        'lib/features/figma_complete/presentation/figma_environment_pages.dart',
      ).readAsStringSync();
      final search = File(
        'lib/features/figma_complete/presentation/figma_misc_pages.dart',
      ).readAsStringSync();
      final favorites = File(
        'lib/features/figma_complete/presentation/figma_account_pages.dart',
      ).readAsStringSync();
      final productionDart = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(navigator, contains('AppDestination.contextualMap'));
      expect(search, contains('AppDestination.contextualMap'));
      expect(environment, contains('AppDestination.contextualMap'));
      expect(favorites, contains('AppDestination.contextualMap'));
      expect(homeData, contains('Future.wait<void>'));
      expect(homeData, contains('await loadScore()'));
      expect(homeData, contains('CommercialHomeDomainStatus.error'));
      expect(environment, contains('initialStation'));
      expect(productionDart, isNot(contains('AppDestination.newSession')));
      expect(productionDart, isNot(contains('homeRuntimeProvider')));
      expect(productionDart, isNot(contains('Start Travel')));
      expect(productionDart, isNot(contains('Start Fishing')));
    },
  );
}

void _noopIndex(int _) {}
void _noop() {}
