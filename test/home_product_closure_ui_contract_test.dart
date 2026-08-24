import 'dart:io';

import 'package:fishtrack/core/utility/fluviai_utility_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('global theme consumers do not force obsolete Night roots', () {
    final drawer = source('lib/widgets/home_premium/side_menu.dart');
    final notifications = source(
      'lib/features/figma_complete/presentation/figma_account_pages.dart',
    );
    final environment = source(
      'lib/features/figma_complete/presentation/figma_environment_pages.dart',
    );
    final fluviStart = environment.indexOf('class FigmaFluviHubPage');
    final fluviEnd = environment.indexOf('class FigmaAskFluviPage');
    final fluvi = environment.substring(fluviStart, fluviEnd);

    expect(drawer, contains('FluviAIThemeColors.of(context)'));
    expect(drawer, isNot(contains('static const _background')));
    expect(drawer, isNot(contains('backgroundColor: _background')));
    expect(
      notifications,
      contains('final colors = FluviAIThemeColors.of(context)'),
    );
    expect(fluvi, contains('final colors = FluviAIThemeColors.of(context)'));
    expect(fluvi, isNot(contains('scaffoldColor:')));
    expect(fluvi, isNot(contains('Color(0xFF05080A)')));
  });

  test(
    'Home is cardless by default where the product contract requires it',
    () {
      final home = source(
        'lib/features/commercial_home/presentation/commercial_home_page.dart',
      );
      final waterStart = home.indexOf('class _BentoWaterCard');
      final waterEnd = home.indexOf('class _HomeWaterSegment');
      final water = home.substring(waterStart, waterEnd);

      expect(home, contains("ValueKey('home-living-weather-atmosphere')"));
      expect(home, contains('WeatherAtmosphereBackdrop('));
      expect(home, contains('homeWeatherAtmosphereGradient('));
      expect(water, contains("ValueKey('home-water-cardless-content')"));
      expect(water, isNot(contains('DecoratedBox(')));
      expect(water, contains('realWaterHistorySeries('));
      expect(water, contains('HomeWaterHistoryLineChart('));
    },
  );

  test('Home typography and Catch imagery keep one truthful language', () {
    final home = source(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    );
    final catchStart = home.indexOf('class _HomeCatchTile');
    final catchEnd = home.indexOf('class _CatchImageFallback');
    final catchTile = home.substring(catchStart, catchEnd);

    expect(home, isNot(contains('monoFontFamily')));
    expect(catchTile, contains('StackFit.expand'));
    expect(catchTile, contains("'home-catch-image-\${post.id}'"));
    expect(catchTile, contains('fontSize: 14'));
    expect(catchTile, contains('fontSize: 11.5'));
    expect(home, isNot(contains('post.speciesUserConfirmed')));
    expect(home, contains('!post.isSuspicious'));
  });

  test('Notifications are a flat stream without per-row card surfaces', () {
    final account = source(
      'lib/features/figma_complete/presentation/figma_account_pages.dart',
    );
    final start = account.indexOf('class FigmaNotificationCenterPage');
    final end = account.indexOf('class FigmaRegulationsPage');
    final notifications = account.substring(start, end);

    expect(notifications, contains("ValueKey('notification-row-\${item.id}')"));
    expect(notifications, contains("ValueKey('notification-row-divider')"));
    expect(notifications, isNot(contains('FigmaSurface(')));
    expect(notifications, contains('_service.markAsRead(notification.id)'));
    expect(notifications, contains('AppDestination.contextualMap'));
    expect(notifications, contains('AppDestination.water'));
  });

  test('Fluvi keeps one score surface and flat explanatory factor rows', () {
    final environment = source(
      'lib/features/figma_complete/presentation/figma_environment_pages.dart',
    );
    final factorStart = environment.indexOf('class _ScoreFactorCard');
    final factorEnd = environment.indexOf('class FigmaWaterHubPage');
    final factor = environment.substring(factorStart, factorEnd);
    final fluviStart = environment.indexOf('class FigmaFluviHubPage');
    final fluviEnd = environment.indexOf('class FigmaAskFluviPage');
    final fluvi = environment.substring(fluviStart, fluviEnd);

    expect(factor, isNot(contains('_ReviewPanel(')));
    expect(fluvi, contains("ValueKey('fluvi-score-functional-surface')"));
    expect(
      fluvi,
      contains("isRomanian ? 'DE CE ACEST SCOR' : 'WHY THIS SCORE'"),
    );
    expect(fluvi, contains("isRomanian ? 'EXPLICABIL' : 'EXPLAINABLE'"));
    expect(fluvi, contains("isRomanian ? 'Hartă completă' : 'Full map'"));
    expect(fluvi, contains('maxLines: 2'));
  });

  test('handset orientation and P0 Map resource contracts stay explicit', () {
    final main = source('lib/main.dart');
    final manifest = source('android/app/src/main/AndroidManifest.xml');
    final ios = source('ios/Runner/Info.plist');
    final keep = source('android/app/src/main/res/raw/fluviai_mapbox_keep.xml');

    expect(main, contains('SystemChrome.setPreferredOrientations'));
    expect(main, contains('DeviceOrientation.portraitUp'));
    expect(manifest, contains('android:screenOrientation="portrait"'));
    expect(ios, contains('UIInterfaceOrientationPortrait'));
    expect(keep, contains('tools:keep="@string/mapbox_access_token"'));
  });

  test('canonical Utilities inventory remains complete', () {
    expect(FluviUtilityRegistry.definitions, hasLength(34));
    expect(
      FluviUtilityRegistry.definitions.map((item) => item.id).toSet(),
      hasLength(34),
    );
  });
}
