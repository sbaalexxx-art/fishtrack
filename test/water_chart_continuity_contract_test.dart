import 'package:flutter_test/flutter_test.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';

WaterLevel _reading(DateTime timestamp, double value) => WaterLevel(
  stationId: 'bazias',
  value: value,
  unit: 'cm',
  timestamp: timestamp,
  trend: WaterTrend.stable,
  source: WaterLevelSource.afdj,
  sourceName: 'AFDJ',
);

void main() {
  test(
    'official Water chart renders one continuous spline from real samples',
    () {
      final base = DateTime.utc(2026, 8, 17);
      final points = <WaterLevel>[
        _reading(base.subtract(const Duration(days: 29)), 538),
        _reading(base.subtract(const Duration(days: 20)), 542),
        _reading(base.subtract(const Duration(days: 8)), 547),
        _reading(base, 544),
      ];

      final segments = officialWaterChartSegments(points);
      expect(segments, hasLength(1));
      expect(segments.single, points);
    },
  );
}
