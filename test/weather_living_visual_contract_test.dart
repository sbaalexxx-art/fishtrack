import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Weather Hub removes duplicated 24h and current-detail surfaces', () {
    final source = File('lib/screens/weather_page.dart').readAsStringSync();

    expect('WeatherInteractiveSeriesChart('.allMatches(source), hasLength(1));
    expect('class _WeatherMetricRail'.allMatches(source), hasLength(1));
    expect('class _SectionPanel'.allMatches(source), hasLength(1));

    expect(source, isNot(contains('class _HourlyWeatherOverview')));
    expect(source, isNot(contains('class _WeatherMetricsGrid')));
    expect(source, isNot(contains('class _SectionSelector')));
    expect(source, isNot(contains('class _HourlyRail')));
    expect(source, isNot(contains('Acum în detaliu')));
    expect(source, isNot(contains('Temperature and precipitation')));
    expect(source, isNot(contains('EVOLUȚIE REALĂ')));
  });

  test('Weather living identity is shared between Home and Hub', () {
    final home = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();
    final hub = File('lib/screens/weather_page.dart').readAsStringSync();
    final visuals = File(
      'lib/widgets/weather/weather_visuals.dart',
    ).readAsStringSync();

    expect(home, contains('WeatherAtmosphereBackdrop('));
    expect(hub, contains('WeatherAtmosphereBackdrop('));
    expect(home, contains('weatherAtmosphereGradient('));
    expect(hub, contains('weatherAtmosphereGradient('));
    expect(visuals, contains('class WeatherAtmosphereBackdrop'));
  });

  test('only factual Weather metrics are selectable graph controls', () {
    final source = File('lib/screens/weather_page.dart').readAsStringSync();

    for (final section in <String>[
      'WeatherPageSection.temperature',
      'WeatherPageSection.wind',
      'WeatherPageSection.pressure',
      'WeatherPageSection.humidity',
      'WeatherPageSection.precipitation',
    ]) {
      expect(source, contains('section: $section'));
    }

    expect(source, contains('button: true'));
    expect(source, contains('selected: selected'));
    expect(source, contains('onTap: onTap'));
  });

  test('Final Weather composition is dense and truthful over 24h', () {
    final source = File('lib/screens/weather_page.dart').readAsStringSync();

    expect(source, contains('BoxConstraints(minHeight: 166)'));
    final heroStart = source.indexOf('class _AtmosphericHero');
    final heroEnd = source.indexOf('class _WindCompass');
    final hero = source.substring(heroStart, heroEnd);
    expect('Expanded('.allMatches(hero), hasLength(3));
    expect(source, contains('height: 42'));
    expect(source, contains('height: 112'));
    expect(source, contains('BoxConstraints(maxWidth: 132)'));
    expect(source, contains('BoxConstraints(maxWidth: 205)'));
    expect(source, contains('fit: BoxFit.scaleDown'));
    expect(source, contains('class _TimeAxis24h'));
    expect(source, contains('!hour.time.isBefore(cutoff)'));
    expect(source, contains('.take(24)'));
    expect(source, isNot(contains('class _HourlyRail')));
    expect(source, isNot(contains('EVOLUȚIE REALĂ')));
  });

  test(
    'Final atmosphere uses organic cloud silhouettes rather than bubble primitives',
    () {
      final visuals = File(
        'lib/widgets/weather/weather_visuals.dart',
      ).readAsStringSync();

      expect(visuals, contains('final cloud = Path()'));
      expect(visuals, contains('canvas.drawPath(cloud, cloudPaint)'));
      expect(
        visuals,
        isNot(contains('final rect = Rect.fromLTWH(x, y, w, h);')),
      );
    },
  );
}
