import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Weather route resolves to the living canonical WeatherPage', () {
    final router = File(
      'lib/features/figma_complete/presentation/figma_destination_router.dart',
    ).readAsStringSync();

    expect(router, contains("import '../../../screens/weather_page.dart';"));
    expect(router, contains('AppDestination.weather => WeatherPage('));
    expect(
      router,
      contains(
        'initialWeather: arguments is WeatherHomeResult ? arguments : null',
      ),
    );
    expect(
      router,
      isNot(contains('AppDestination.weather => FigmaWeatherHubPage(')),
    );
  });

  test('Weather cards expose only real interactive detail contracts', () {
    final page = File('lib/screens/weather_page.dart').readAsStringSync();

    expect(page, contains('Scrollable.ensureVisible('));
    expect(page, contains("key: const ValueKey('weather-alerts-action')"));
    expect(page, contains('section: WeatherPageSection.wind'));
    expect(page, contains('section: WeatherPageSection.pressure'));
    expect(page, contains('section: WeatherPageSection.humidity'));
    expect(page, contains('section: WeatherPageSection.precipitation'));
    expect(page, contains('section: WeatherPageSection.temperature'));
    expect(page, contains('button: true'));
    expect(page, contains('onTap: onTap'));
    expect(page, contains('selected: selected'));
    expect(page, contains('URMĂTOARELE 7 ZILE'));
  });

  test('stale Figma Weather runtime-source contract is removed', () {
    final integration = File(
      'test/ui_complete_integration_test.dart',
    ).readAsStringSync();

    expect(
      integration,
      contains(
        'Water and Fluvi keep injected runtime source while Weather is GPS-owned',
      ),
    );
    expect(
      integration,
      isNot(
        contains('Water, Weather and Fluvi retain one injected runtime source'),
      ),
    );
    expect(integration, contains('expect(weather, isA<WeatherPage>());'));
  });

  test('batch3 route contracts use GPS-owned WeatherPage', () {
    final batch3 = File(
      'test/batch3_priority_utilities_integration_test.dart',
    ).readAsStringSync();

    expect(batch3, contains('isA<WeatherPage>()'));
    expect(batch3, contains('Home passes its already-loaded Weather snapshot'));
    expect(
      batch3,
      contains('Later refreshes remain GPS-first inside WeatherPage.'),
    );
    expect(
      batch3,
      contains(
        'Selected water/station context is intentionally separate '
        'from the',
      ),
    );
    expect(
      batch3,
      isNot(
        contains(
          'priority destination router carries station and runtime source',
        ),
      ),
    );
  });
}
