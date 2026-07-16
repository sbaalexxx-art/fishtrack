import 'package:fishtrack/screens/weather_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeatherPageSectionSelection', () {
    test('defaults to temperature without an initial section', () {
      expect(weatherPageInitialSection(null), WeatherPageSection.temperature);
    });

    for (final section in WeatherPageSection.values) {
      test('keeps $section as the initial section', () {
        expect(weatherPageInitialSection(section), section);
      });
    }

    test('changes the selected contextual section in place', () {
      final selection = WeatherPageSectionSelection(
        WeatherPageSection.temperature,
      );

      expect(selection.select(WeatherPageSection.wind), isTrue);
      expect(selection.selected, WeatherPageSection.wind);
      expect(selection.select(WeatherPageSection.wind), isFalse);
    });
  });

  group('moon phase presentation', () {
    test('normalizes invalid and out-of-range illumination safely', () {
      expect(normalizedMoonIllumination(double.nan), 0);
      expect(normalizedMoonIllumination(-10), 0);
      expect(normalizedMoonIllumination(150), 1);
    });

    test('distinguishes waxing and waning phase names', () {
      expect(moonPhaseIsWaxing('Waxing Crescent'), isTrue);
      expect(moonPhaseIsWaxing('Waning Gibbous'), isFalse);
      expect(moonPhaseIsWaxing('Last Quarter'), isFalse);
    });
  });
}
