import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Weather advanced living product maturity contract', () {
    test('Open-Meteo retains the real fishing-useful weather variables', () {
      final source = File(
        'lib/repositories/weather_repository.dart',
      ).readAsStringSync();

      for (final token in <String>[
        "'forecast_days': '7'",
        "'pressure_msl'",
        "'weather_code'",
        "'precipitation'",
        "'visibility'",
        "'dew_point_2m'",
        "'uv_index'",
        "'is_day'",
        "'precipitation_probability_max'",
        "'precipitation_sum'",
        "'uv_index_max'",
      ]) {
        expect(source, contains(token), reason: token);
      }
      expect(source, contains('forecast.length < 7'));
    });

    test(
      'weather models keep optional metrics truthful without fake defaults',
      () {
        final source = File('lib/models/weather.dart').readAsStringSync();

        for (final token in <String>[
          'final double? precipitation;',
          'final double? visibility;',
          'final double? dewPoint;',
          'final double? uvIndex;',
          'final bool? isDay;',
          'final double? precipitationProbabilityMax;',
          'final double? precipitationSum;',
          'final double? uvIndexMax;',
        ]) {
          expect(source, contains(token), reason: token);
        }
      },
    );

    test('Weather Hub uses one compact living 24h analysis flow', () {
      final source = File('lib/screens/weather_page.dart').readAsStringSync();

      expect(source, contains('class _AtmosphericHero'));
      expect(source, contains('WeatherAtmosphereBackdrop('));
      expect(source, contains('class _WindCompass'));
      expect(source, contains('class _WeatherMetricRail'));
      expect(source, contains('WeatherInteractiveSeriesChart('));
      expect(source, contains('class _SevenDayForecast'));
      expect(source, contains('class _FishingWeatherSummary'));
      expect(source, contains('class _SolunarPanel'));

      expect(source, isNot(contains('class _HourlyWeatherOverview')));
      expect(source, isNot(contains('class _WeatherMetricsGrid')));
      expect(source, isNot(contains('class _SectionSelector')));
      expect(source, isNot(contains('Acum în detaliu')));
      expect(source, isNot(contains('Încredere · 100%')));

      expect(source, contains('weather.visibility'));
      expect(source, contains('weather.dewPoint'));
      expect(source, contains('weather.uvIndex'));
      expect(source, contains("secondaryFacts.join(' · ')"));
      expect(source, contains('day.precipitationProbabilityMax'));
      expect(source, contains('Interpretare meteo deterministă'));
      expect(source, contains('class _TimeAxis24h'));
      expect(source, isNot(contains('class _HourlyRail')));
    });

    test('Home Weather is a living Bento card without geometry redesign', () {
      final source = File(
        'lib/features/commercial_home/presentation/commercial_home_page.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('commercial-weather-card')"));
      expect(source, contains('class _BentoWeatherCard'));
      expect(source, contains('weatherAtmosphereGradient('));
      expect(source, contains('WeatherAtmosphereBackdrop('));
      expect(source, contains('weatherVisualIcon('));
      expect(source, contains("data.windSpeed.round()} km/h"));
      expect(source, contains('fit: BoxFit.scaleDown'));
      expect(source, contains('snapshot?.weather'));
      expect(source, contains('onOpenWeather'));
    });

    test('living visuals are finite and chart supports direct inspection', () {
      final source = File(
        'lib/widgets/weather/weather_visuals.dart',
      ).readAsStringSync();

      expect(source, contains('class WeatherAtmosphereBackdrop'));
      expect(source, contains('TweenAnimationBuilder<double>'));
      expect(source, contains('Duration(milliseconds: 650)'));
      expect(source, contains('class WeatherInteractiveSeriesChart'));
      expect(source, contains('onTapDown:'));
      expect(source, contains('onHorizontalDragUpdate:'));
      expect(source, contains('selectedIndex'));
      expect(source, isNot(contains('repeat(')));
    });

    test(
      'existing Weather alerts and astronomy foundations remain present',
      () {
        expect(
          File('lib/services/alert_rule_repository.dart').existsSync(),
          isTrue,
        );
        expect(
          File('lib/services/astronomy_service.dart').existsSync(),
          isTrue,
        );
        expect(File('test/astronomy_service_test.dart').existsSync(), isTrue);
        expect(
          File('test/weather_page_section_test.dart').existsSync(),
          isTrue,
        );
      },
    );
  });
}
