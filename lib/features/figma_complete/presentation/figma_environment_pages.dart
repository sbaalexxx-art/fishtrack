import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/context/current_location.dart';
import '../../../core/context/selected_context.dart';
import '../../../core/runtime/app_runtime.dart';
import '../../../core/map/map_runtime_provenance.dart';
import '../../../core/map/pending_map_camera.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/map_entry.dart';
import '../../../core/navigation/water_entry.dart';
import '../../../core/water/water_history_analysis.dart';
import '../../../models/station.dart';
import '../../../models/water_asset.dart';
import '../../../models/water_river.dart';
import '../../../models/water_level.dart';
import '../../../models/weather.dart';
import '../../../l10n/l10n.dart';
import '../../../services/water_service.dart';
import '../../../services/water_asset_service.dart';
import '../../../services/saved_items_service.dart';
import '../../../services/location_service.dart';
import '../../../services/fluvi_deterministic_answer_service.dart';
import '../../../services/weather_alert_rule_repository.dart';
import '../../commercial_home/data/commercial_home_data_source.dart';
import 'figma_foundation.dart';
import 'figma_runtime_data.dart';

String _number(double? value, {int decimals = 0}) =>
    value == null || !value.isFinite ? '—' : value.toStringAsFixed(decimals);

enum WaterFreshnessDisplayState { live, cache, stale, error, unavailable }

WaterFreshnessDisplayState resolveWaterFreshnessDisplayState(
  WaterUiResult? result,
) {
  if (result?.latestReading == null) {
    return result?.providerError == true ||
            result?.status == WaterUiStatus.providerError
        ? WaterFreshnessDisplayState.error
        : WaterFreshnessDisplayState.unavailable;
  }
  if (result!.isStale) return WaterFreshnessDisplayState.stale;
  if (result.providerError || result.status == WaterUiStatus.providerError) {
    return WaterFreshnessDisplayState.cache;
  }
  return WaterFreshnessDisplayState.live;
}

String waterFreshnessDisplayLabel(
  WaterFreshnessDisplayState state, {
  required bool isRomanian,
}) => switch (state) {
  WaterFreshnessDisplayState.live => isRomanian ? 'ACTUAL' : 'LIVE',
  WaterFreshnessDisplayState.cache => 'CACHE',
  WaterFreshnessDisplayState.stale => isRomanian ? 'VECHI' : 'STALE',
  WaterFreshnessDisplayState.error => isRomanian ? 'EROARE' : 'ERROR',
  WaterFreshnessDisplayState.unavailable =>
    isRomanian ? 'FĂRĂ DATE' : 'UNAVAILABLE',
};

Color _waterFreshnessDisplayColor(WaterFreshnessDisplayState state) =>
    switch (state) {
      WaterFreshnessDisplayState.live => const Color(0xFF38BDF8),
      WaterFreshnessDisplayState.cache => FigmaFluviTokens.amber,
      WaterFreshnessDisplayState.stale ||
      WaterFreshnessDisplayState.error => FigmaFluviTokens.red,
      WaterFreshnessDisplayState.unavailable => FigmaFluviTokens.textMuted,
    };

String _stationContext(CommercialHomeSnapshot? snapshot, Station? preferred) {
  final station = preferred ?? snapshot?.station;
  if (station == null) {
    return 'Locația ta';
  }
  final river = station.river.trim();
  return river.isEmpty ? station.name : '$river · ${station.name}';
}

String _officialContext(CommercialHomeSnapshot? snapshot, Station? preferred) {
  final station = preferred ?? snapshot?.station;
  final river = station?.river.trim();
  final label = river != null && river.isNotEmpty ? river : station?.name;
  return label == null || label.trim().isEmpty
      ? 'DATE OFICIALE'
      : 'DATE OFICIALE · ${label.toUpperCase()}';
}

@immutable
class WaterOfficialObservationState {
  const WaterOfficialObservationState({
    required this.currentReading,
    required this.deltaCm,
    required this.trend,
  });

  final WaterLevel? currentReading;
  final double? deltaCm;
  final WaterTrend? trend;
}

WaterOfficialObservationState resolveWaterOfficialObservationState(
  WaterUiResult? result,
) {
  final canonical = result?.effectiveCanonicalTrend;
  final comparison = result?.comparisonDuration;
  final dailyDelta =
      result?.deltaCm != null &&
          comparison != null &&
          comparison.inHours >= 18 &&
          comparison.inHours <= 30
      ? result!.deltaCm
      : null;
  return WaterOfficialObservationState(
    currentReading: result?.latestReading,
    // This UI labels the value /24h, therefore a sparse arbitrary-interval
    // delta is deliberately not presented as a daily change.
    deltaCm: dailyDelta,
    trend: result?.trend ?? canonical?.trend.displayTrend,
  );
}

Color _trendColor(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => const Color(0xFF38BDF8),
  WaterTrend.falling => FigmaFluviTokens.red,
  WaterTrend.stable => FigmaFluviTokens.green,
  null => FigmaFluviTokens.textMuted,
};

String _trendLabel(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => 'Crește lent',
  WaterTrend.falling => 'Scade lent',
  WaterTrend.stable => 'Stabil',
  null => 'Trend indisponibil',
};

String _signedDelta(double value) {
  final rounded = value.round();
  final sign = rounded > 0
      ? '+'
      : rounded < 0
      ? '−'
      : '';
  return '$sign${rounded.abs()} cm / 24h';
}

String _relativeAge(Duration? age) {
  if (age == null) {
    return 'actualizare indisponibilă';
  }
  final safe = age.isNegative ? Duration.zero : age;
  if (safe.inDays > 0) {
    return 'acum ${safe.inDays} ${safe.inDays == 1 ? 'zi' : 'zile'}';
  }
  if (safe.inHours > 0) {
    return 'acum ${safe.inHours} h';
  }
  if (safe.inMinutes > 0) {
    return 'acum ${safe.inMinutes} min';
  }
  return 'acum';
}

String _sourceLabel(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) {
    return 'Sursă indisponibilă';
  }
  return RegExp(r'^[A-Za-z0-9_-]{2,10}$').hasMatch(value)
      ? value.toUpperCase()
      : value;
}

String _windDirectionRo(String direction) => direction.replaceAll('W', 'V');

String _localizedWeatherCondition(BuildContext context, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty ||
      Localizations.localeOf(context).languageCode.toLowerCase() != 'ro') {
    return value;
  }
  return switch (value.toLowerCase()) {
    'clear sky' || 'clear' => 'Senin',
    'mainly clear' => 'Mai mult senin',
    'partly cloudy' => 'Parțial noros',
    'overcast' => 'Cer acoperit',
    'fog' || 'mist' => 'Ceață',
    'drizzle' => 'Burniță',
    'rain' || 'light rain' => 'Ploaie',
    'snow' || 'snowfall' => 'Ninsoare',
    'thunderstorm' => 'Furtună',
    _ => value,
  };
}

String _localizedScoreText(BuildContext context, String raw) {
  if (Localizations.localeOf(context).languageCode.toLowerCase() != 'ro') {
    return raw;
  }
  return switch (raw.trim().toLowerCase()) {
    'fair' => 'Moderat',
    'good' => 'Bun',
    'poor' => 'Slab',
    'stable water trend' => 'Tendință stabilă a apei',
    'water reading is outdated' => 'Citirea apei este veche',
    'unfavourable humidity' => 'Umiditate nefavorabilă',
    'very bright, clear conditions' => 'Lumină puternică și cer senin',
    'moderate sw wind' => 'Vânt moderat din SV',
    'moderate west wind' => 'Vânt moderat din vest',
    _ => raw,
  };
}

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16;

double _responsivePanelHeight(
  BuildContext context,
  double normalHeight,
  double heightAt200Percent,
) {
  final scale = _textScale(context);
  if (scale <= 1) {
    return normalHeight;
  }

  final progress = (scale - 1).clamp(0.0, 1.0);
  final calibrated =
      normalHeight + (heightAt200Percent - normalHeight) * progress;

  // Large accessibility text does more than scale glyphs: it also creates
  // extra wrapped lines. Preserve the exact 1.0x Figma height, but grow card
  // capacity faster than glyph scale once accessibility scaling is active.
  final wrapCapacity = normalHeight * (1 + 2.0 * (scale - 1).clamp(0.0, 1.0));

  final bounded = calibrated > wrapCapacity ? calibrated : wrapCapacity;
  if (scale <= 2) {
    return bounded;
  }

  // Continue growing beyond 200% rather than freezing a fixed-height card.
  return bounded + normalHeight * (scale - 2);
}

IconData _conditionIcon(String? condition) {
  final value = condition?.toLowerCase() ?? '';
  if (value.contains('storm') ||
      value.contains('thunder') ||
      value.contains('furt')) {
    return Icons.thunderstorm_rounded;
  }
  if (value.contains('rain') ||
      value.contains('drizzle') ||
      value.contains('ploa')) {
    return Icons.water_drop_rounded;
  }
  if (value.contains('snow') || value.contains('ninso')) {
    return Icons.ac_unit_rounded;
  }
  if (value.contains('fog') ||
      value.contains('mist') ||
      value.contains('cea')) {
    return Icons.cloud_queue_rounded;
  }
  if (value.contains('cloud') ||
      value.contains('overcast') ||
      value.contains('nor')) {
    return Icons.cloud_rounded;
  }
  return Icons.wb_sunny_rounded;
}

class _ContextHubAction {
  const _ContextHubAction({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.secondary = true,
  });

  final String keyName;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool secondary;
}

class _ContextHubActionGrid extends StatelessWidget {
  const _ContextHubActionGrid({required this.actions});

  final List<_ContextHubAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = _textScale(context);
        final columns = textScale >= 1.5 || constraints.maxWidth < 520
            ? 1
            : actions.length > 3
            ? 3
            : actions.length;
        final gap = 10.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: itemWidth,
                child: FigmaPrimaryButton(
                  key: ValueKey<String>(action.keyName),
                  label: action.label,
                  icon: action.icon,
                  secondary: action.secondary,
                  onPressed: action.onPressed,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(14),
    this.accent,
    this.background = const Color(0xFF0C151A),
    this.radius = 18,
  });

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final Color background;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent ?? const Color(0xFF253841)),
      ),
      child: child,
    );
  }
}

class _MonoLabel extends StatelessWidget {
  const _MonoLabel(this.text, {this.color = FigmaFluviTokens.textSecondary});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: 'IBM Plex Mono',
      color: color,
      fontSize: 9,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: .25,
    ),
  );
}

class _TinyStatusPill extends StatelessWidget {
  const _TinyStatusPill({required this.label, required this.color, this.width});

  final String label;
  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'IBM Plex Mono',
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _WaterSegmentBar extends StatelessWidget {
  const _WaterSegmentBar({required this.onStations, required this.onAlerts});

  final VoidCallback onStations;
  final VoidCallback onAlerts;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    Widget segment(String label, {bool selected = false, VoidCallback? onTap}) {
      return _SegmentLabel(
        label,
        selected: selected,
        onTap: onTap,
        semanticLabel: onTap == null ? null : 'Deschide $label',
      );
    }

    final children = <Widget>[
      segment('Rezumat'),
      segment('Tendință', selected: true),
      segment('Stații', onTap: onStations),
      segment('Alerte', onTap: onAlerts),
    ];

    return _ReviewPanel(
      height: largeText ? 50 : 42,
      padding: const EdgeInsets.all(4),
      radius: 14,
      background: const Color(0xFF091318),
      child: largeText
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  for (final child in children)
                    SizedBox(width: 112, child: child),
                ],
              ),
            )
          : Row(
              children: [for (final child in children) Expanded(child: child)],
            ),
    );
  }
}

enum _WaterHubCategory { automatic, danube, rivers, hydropower, favorites }

class _WaterContextBar extends StatelessWidget {
  const _WaterContextBar({required this.selected, required this.onSelected});

  final _WaterHubCategory selected;
  final ValueChanged<_WaterHubCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    const entries = <(_WaterHubCategory, String)>[
      (_WaterHubCategory.automatic, 'Automat'),
      (_WaterHubCategory.danube, 'Dunăre'),
      (_WaterHubCategory.rivers, 'Râuri'),
      (_WaterHubCategory.hydropower, 'Baraje hidro'),
      (_WaterHubCategory.favorites, 'Favorite'),
    ];
    return _ReviewPanel(
      height: 48,
      padding: const EdgeInsets.all(4),
      radius: 14,
      background: const Color(0xFF0B1820),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: entry.$1 == _WaterHubCategory.hydropower ? 112 : 82,
                  child: _SegmentLabel(
                    entry.$2,
                    selected: selected == entry.$1,
                    onTap: () => onSelected(entry.$1),
                    semanticLabel: 'Water ${entry.$2}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(
    this.label, {
    this.selected = false,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 34,
      alignment: Alignment.center,
      decoration: selected
          ? BoxDecoration(
              color: const Color(0xFF113B3A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FigmaFluviTokens.cyan),
            )
          : null,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? FigmaFluviTokens.cyan
              : FigmaFluviTokens.textSecondary,
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    if (onTap == null) {
      return child;
    }
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

List<List<WaterLevel>> officialWaterChartSegments(List<WaterLevel> history) {
  final points = history.where((item) => item.value.isFinite).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (points.isEmpty) return const <List<WaterLevel>>[];

  // Product chart contract: render one continuous observational spline across
  // the real measurements returned for the entitlement window. No synthetic
  // WaterLevel samples are inserted here; timestamps, statistics and tooltips
  // remain tied exclusively to measured observations. Temporal gaps continue
  // to be visible through the real x-axis spacing rather than by fabricating
  // intermediate daily points.
  return <List<WaterLevel>>[List<WaterLevel>.unmodifiable(points)];
}

class _OfficialWaterChart extends StatelessWidget {
  const _OfficialWaterChart({required this.history});

  final List<WaterLevel> history;

  @override
  Widget build(BuildContext context) {
    final segments = officialWaterChartSegments(history);
    final points = segments
        .expand((segment) => segment)
        .toList(growable: false);
    if (points.length < 2) return const SizedBox.shrink();

    var minimum = points.first.value;
    var maximum = points.first.value;
    for (final point in points.skip(1)) {
      if (point.value < minimum) minimum = point.value;
      if (point.value > maximum) maximum = point.value;
    }
    final range = maximum - minimum;
    final padding = range.abs() < .01 ? 1.0 : range * .18;
    final firstTime = points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final lastTime = points.last.timestamp.millisecondsSinceEpoch.toDouble();
    final chartTrend = waterTrendFromRealDelta(realWaterSeriesDelta(points));
    final color = _trendColor(chartTrend);

    WaterLevel readingForX(double x) => points.reduce((nearest, candidate) {
      final nearestDistance = (nearest.timestamp.millisecondsSinceEpoch - x)
          .abs();
      final candidateDistance = (candidate.timestamp.millisecondsSinceEpoch - x)
          .abs();
      return candidateDistance < nearestDistance ? candidate : nearest;
    });

    return Padding(
      key: const ValueKey('batch-b-water-official-chart'),
      padding: const EdgeInsets.fromLTRB(2, 6, 6, 4),
      child: LineChart(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        LineChartData(
          minX: firstTime,
          maxX: firstTime == lastTime ? lastTime + 1 : lastTime,
          minY: minimum - padding,
          maxY: maximum + padding,
          clipData: const FlClipData.all(),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchSpotThreshold: 22,
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              tooltipBorderRadius: BorderRadius.circular(11),
              tooltipBorder: BorderSide(color: color.withValues(alpha: .38)),
              getTooltipColor: (_) => const Color(0xF507131C),
              getTooltipItems: (spots) => spots
                  .map((spot) {
                    final reading = readingForX(spot.x);
                    final value = reading.value == reading.value.roundToDouble()
                        ? reading.value.toStringAsFixed(0)
                        : reading.value.toStringAsFixed(1);
                    final local = reading.timestamp.toLocal();
                    final stamp =
                        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                    return LineTooltipItem(
                      '$value ${reading.unit}\n$stamp',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          lineBarsData: [
            for (final segment in segments)
              LineChartBarData(
                spots: segment
                    .map(
                      (point) => FlSpot(
                        point.timestamp.millisecondsSinceEpoch.toDouble(),
                        point.value,
                      ),
                    )
                    .toList(growable: false),
                isCurved: segment.length >= 3,
                curveSmoothness: .18,
                preventCurveOverShooting: true,
                color: color,
                barWidth: segment.length >= 2 ? 2.8 : 0,
                isStrokeCapRound: true,
                isStrokeJoinRound: true,
                belowBarData: BarAreaData(
                  show: segment.length >= 2,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: .20),
                      color.withValues(alpha: .01),
                    ],
                  ),
                ),
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) {
                    if (spot.x == lastTime || points.length <= 18) return true;
                    final index = points.indexWhere(
                      (point) =>
                          point.timestamp.millisecondsSinceEpoch.toDouble() ==
                          spot.x,
                    );
                    final stride = (points.length / 12).ceil();
                    return index >= 0 && index % stride == 0;
                  },
                  getDotPainter: (spot, _, _, _) {
                    final latest = spot.x == lastTime;
                    return FlDotCirclePainter(
                      radius: latest ? 4.4 : 2.4,
                      color: color,
                      strokeColor: latest
                          ? Colors.white
                          : const Color(0xFF071217),
                      strokeWidth: latest ? 1.4 : 1,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonoLabel(label),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: FigmaFluviTokens.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip({required this.hours});

  final List<WeatherForecastHour> hours;

  @override
  Widget build(BuildContext context) {
    final visible = hours.take(4).toList(growable: false);
    if (visible.isEmpty) {
      return const Center(
        child: Text(
          'Prognoza orară nu este disponibilă.',
          style: TextStyle(color: FigmaFluviTokens.textMuted, fontSize: 11),
        ),
      );
    }
    return Row(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: _HourlyCell(hour: visible[index], now: index == 0),
          ),
        ],
      ],
    );
  }
}

class _HourlyCell extends StatelessWidget {
  const _HourlyCell({required this.hour, required this.now});

  final WeatherForecastHour hour;
  final bool now;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        now ? 'Acum' : hour.time.hour.toString().padLeft(2, '0'),
        style: const TextStyle(
          color: FigmaFluviTokens.textSecondary,
          fontSize: 10,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${hour.temperature.round()}°',
        style: const TextStyle(
          color: FigmaFluviTokens.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${_windDirectionRo(hour.windDirectionLabel)} ${hour.windSpeed.round()}',
        style: const TextStyle(
          color: FigmaFluviTokens.cyan,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _FishingDecisionCard extends StatelessWidget {
  const _FishingDecisionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => _ReviewPanel(
    height: _responsivePanelHeight(context, 74, 128),
    radius: 16,
    background: const Color(0xFF0D171C),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        SizedBox(width: 30, child: Icon(icon, color: color, size: 21)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FigmaFluviTokens.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: FigmaFluviTokens.cyan),
      ],
    ),
  );
}

class _SolunarDatum extends StatelessWidget {
  const _SolunarDatum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 82, maxWidth: 140),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MonoLabel(label),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: FigmaFluviTokens.white,
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ScoreFactor {
  const _ScoreFactor({
    required this.label,
    required this.detail,
    required this.color,
    required this.pill,
  });

  final String label;
  final String detail;
  final Color color;
  final String pill;
}

class _ScoreFactorCard extends StatelessWidget {
  const _ScoreFactorCard({required this.factor});

  final _ScoreFactor factor;

  @override
  Widget build(BuildContext context) => _ReviewPanel(
    height: _responsivePanelHeight(context, 72, 128),
    radius: 16,
    background: const Color(0xFF0B1115),
    padding: const EdgeInsets.symmetric(horizontal: 13),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: factor.color.withValues(alpha: .08),
            border: Border.all(color: factor.color),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.circle, size: 6, color: factor.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                factor.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                factor.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FigmaFluviTokens.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _TinyStatusPill(label: factor.pill, color: factor.color, width: 82),
      ],
    ),
  );
}

class FigmaWaterHubPage extends StatefulWidget {
  const FigmaWaterHubPage({
    super.key,
    this.initialStation,
    this.dataSource,
    this.entryMode = WaterHubEntryMode.overview,
  });

  final Station? initialStation;
  final CommercialHomeDataSource? dataSource;
  final WaterHubEntryMode entryMode;

  @override
  State<FigmaWaterHubPage> createState() => _FigmaWaterHubPageState();
}

class _FigmaWaterHubPageState extends State<FigmaWaterHubPage> {
  final WaterService _waterService = WaterService();
  final WaterAssetService _waterAssetService = const WaterAssetService();
  _WaterHubCategory _category = _WaterHubCategory.automatic;
  Station? _selectedStation;
  WaterHubRiverGroup? _selectedRiver;
  WaterHydropowerComplex? _selectedHydropower;

  Station? get _activeStation => _selectedStation ?? widget.initialStation;

  @override
  void initState() {
    super.initState();
    if (widget.entryMode == WaterHubEntryMode.selectStation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openStationSelector();
      });
    }
  }

  void _publishStation(Station station, {bool persistSelection = false}) {
    logMapRuntime(
      persistSelection ? 'water.select-station' : 'water.publish-selection',
      station: station,
    );
    final container = ProviderScope.containerOf(context);
    final selected = container.read(selectedContextProvider);
    if (selected?.stationId == station.id &&
        selected?.latitude == station.latitude &&
        selected?.longitude == station.longitude) {
      if (persistSelection) _waterService.selectStation(station);
      return;
    }
    final notifier = container.read(selectedContextProvider.notifier);
    if (persistSelection) {
      notifier.selectStation(station);
    } else {
      notifier.publishStation(station);
    }
  }

  Future<void> _openAlert(Station? station) async {
    if (station != null) {
      _publishStation(station);
    }
    await AppNavigator.open<void>(
      context,
      AppDestination.newAlert,
      arguments: station,
    );
  }

  Future<void> _openStationSelector() async {
    final selected = await showModalBottomSheet<Station>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: FigmaFluviTokens.surface,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FigmaFluviTokens.textMuted,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Schimbă apa',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Station>>(
                future: _waterService.getStations(),
                builder: (context, state) {
                  if (state.connectionState == ConnectionState.waiting &&
                      !state.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final stations = state.data ?? const <Station>[];
                  if (stations.isEmpty) {
                    return const FigmaTruthfulEmpty(
                      icon: Icons.water_drop_outlined,
                      title: 'Nicio apă disponibilă',
                      message: 'Catalogul Water nu a returnat stații.',
                    );
                  }
                  return ListView.separated(
                    key: const ValueKey('water-station-selector-list'),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: stations.length,
                    separatorBuilder: (_, _) => const FigmaDivider(),
                    itemBuilder: (context, index) {
                      final station = stations[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.waves_rounded,
                          color: FigmaFluviTokens.cyan,
                        ),
                        title: Text(station.name),
                        subtitle: Text(
                          station.river.isEmpty
                              ? station.waterBodyType.name
                              : station.river,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(sheetContext, station),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    _publishStation(selected, persistSelection: true);
    if (widget.entryMode == WaterHubEntryMode.selectStation) {
      Navigator.of(context).pop(selected);
      return;
    }
    setState(() {
      _category = _WaterHubCategory.danube;
      _selectedStation = selected;
      _selectedRiver = null;
      _selectedHydropower = null;
    });
  }

  Future<void> _selectCategory(_WaterHubCategory category) async {
    if (category == _WaterHubCategory.automatic) {
      await _waterService.setAutomatic();
      if (!mounted) return;
      ProviderScope.containerOf(
        context,
      ).read(selectedContextProvider.notifier).clearWaterContext();
      setState(() {
        _category = category;
        _selectedStation = null;
        _selectedRiver = null;
        _selectedHydropower = null;
      });
      return;
    }
    if (category == _WaterHubCategory.danube) {
      if (mounted) setState(() => _category = category);
      await _openStationSelector();
      return;
    }
    if (category == _WaterHubCategory.rivers) {
      await _openRiverSelector();
      return;
    }
    if (category == _WaterHubCategory.hydropower) {
      await _openHydropowerSelector();
      return;
    }
    if (!mounted) return;
    setState(() => _category = category);
    await AppNavigator.open<void>(context, AppDestination.favorites);
  }

  Future<void> _openRiverSelector() async {
    final selected = await showModalBottomSheet<WaterHubRiverGroup>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: FigmaFluviTokens.surface,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .82,
        child: FutureBuilder<List<WaterHubRiverGroup>>(
          future: _waterAssetService.getHubRivers(),
          builder: (context, state) {
            final rows = state.data ?? const <WaterHubRiverGroup>[];
            if (state.connectionState == ConnectionState.waiting &&
                rows.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Râuri',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const FigmaDivider(),
                    itemBuilder: (_, index) {
                      final river = rows[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.water_rounded,
                          color: FigmaFluviTokens.cyan,
                        ),
                        title: Text(river.displayName),
                        subtitle: Text(
                          '${river.damCount} baraje · ${river.reservoirCount} acumulări',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(sheetContext, river),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final ref = WaterRiverRef(
      key: selected.riverKeys.first,
      name: selected.displayName,
      countryCode: 'RO',
      damCount: selected.damCount,
      reservoirCount: selected.reservoirCount,
      basinNames: const <String>[],
      counties: const <String>[],
      waterBodyId: selected.waterBodyIds.first,
      canonicalWaterBody: true,
    );
    ProviderScope.containerOf(context)
        .read(selectedContextProvider.notifier)
        .select(SelectedContext.fromRiver(ref));
    setState(() {
      _category = _WaterHubCategory.rivers;
      _selectedRiver = selected;
      _selectedHydropower = null;
    });
  }

  Future<void> _openHydropowerSelector() async {
    final selected = await showModalBottomSheet<WaterHydropowerComplex>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: FigmaFluviTokens.surface,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .86,
        child: FutureBuilder<List<WaterHydropowerComplex>>(
          future: _waterAssetService.getHubHydropowerComplexes(),
          builder: (context, state) {
            final rows = state.data ?? const <WaterHydropowerComplex>[];
            if (state.connectionState == ConnectionState.waiting &&
                rows.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Baraje hidro',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const FigmaDivider(),
                    itemBuilder: (_, index) {
                      final item = rows[index];
                      final contextLine = [item.riverName, item.county]
                          .whereType<String>()
                          .where((e) => e.trim().isNotEmpty)
                          .join(' · ');
                      return ListTile(
                        leading: const Icon(
                          Icons.account_balance_rounded,
                          color: FigmaFluviTokens.cyan,
                        ),
                        title: Text(item.displayName),
                        subtitle: Text(
                          contextLine.isEmpty
                              ? 'Complex hidroenergetic'
                              : contextLine,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(sheetContext, item),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (!mounted || selected == null) return;
    ProviderScope.containerOf(context)
        .read(selectedContextProvider.notifier)
        .select(SelectedContext.fromHydropowerComplex(selected));
    setState(() {
      _category = _WaterHubCategory.hydropower;
      _selectedHydropower = selected;
      _selectedRiver = null;
    });
  }

  Widget _canonicalContextPanel() {
    final river = _selectedRiver;
    final hydro = _selectedHydropower;
    if (river == null && hydro == null) return const SizedBox.shrink();
    final title = river?.displayName ?? hydro!.displayName;
    final subtitle = river != null
        ? '${river.damCount} baraje · ${river.reservoirCount} acumulări canonice'
        : [
            hydro!.riverName,
            hydro.reservoirName,
            hydro.plantName,
          ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' · ');
    final status = river != null
        ? 'Context canonic Water'
        : hydro!.hasOperationalData
        ? 'Date operaționale disponibile'
        : 'Date operaționale indisponibile';
    return _ReviewPanel(
      height: 154,
      radius: 20,
      background: const Color(0xFF0C1D25),
      accent: FigmaFluviTokens.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MonoLabel(
            'CONTEXT WATER SELECTAT',
            color: FigmaFluviTokens.cyan,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: FigmaFluviTokens.textSecondary,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            status,
            style: const TextStyle(
              fontFamily: 'IBM Plex Mono',
              color: FigmaFluviTokens.textSecondary,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistory(List<WaterLevel> history) {
    final accessTier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(fluviAccessTierProvider);
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: FigmaFluviTokens.surface,
      builder: (sheetContext) =>
          WaterHistorySheet(history: history, accessTier: accessTier),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-water-hub'),
      title: 'Inteligență Hidrologică',
      subtitle:
          _selectedRiver?.displayName ??
          _selectedHydropower?.displayName ??
          _officialContext(null, _activeStation),
      subtitleColor: const Color(0xFF38BDF8),
      action: FigmaRoundButton(
        key: const ValueKey('water-create-alert'),
        icon: Icons.notifications_none_rounded,
        tooltip: 'Creează alertă',
        onPressed: () => _openAlert(_activeStation),
      ),
      scaffoldColor: const Color(0xFF05080B),
      background: const BoxDecoration(color: Color(0xFF05080B)),
      padding: EdgeInsets.zero,
      child: FigmaRuntimeSnapshotBuilder(
        key: ValueKey('water-runtime-${_activeStation?.id ?? 'selected'}'),
        station: _activeStation,
        dataSource: widget.dataSource,
        builder: (context, snapshot, refresh) {
          final water = snapshot?.water;
          final officialObservation = resolveWaterOfficialObservationState(
            water,
          );
          final reading = officialObservation.currentReading;
          final station = _activeStation ?? snapshot?.station;
          final delta = officialObservation.deltaCm;
          final trend = officialObservation.trend;
          final trendColor = _trendColor(trend);
          final history = water?.history ?? const <WaterLevel>[];
          final accessTier = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(fluviAccessTierProvider);
          final historyRange = accessTier == FluviAccessTier.premium
              ? WaterHistoryRange.thirtyDays
              : WaterHistoryRange.sevenDays;
          final visibleHistory = realWaterHistoryForRange(
            history,
            historyRange,
            stationId: station?.id,
          );
          final historyDays = historyRange.duration.inDays;
          final source = _sourceLabel(water?.sourceName ?? reading?.sourceName);
          final freshness = _relativeAge(water?.dataAge);
          final freshnessState = resolveWaterFreshnessDisplayState(water);
          final currentStatus = waterFreshnessDisplayLabel(
            freshnessState,
            isRomanian: true,
          );
          final currentStatusColor = _waterFreshnessDisplayColor(
            freshnessState,
          );
          if (_selectedRiver != null || _selectedHydropower != null) {
            return RefreshIndicator(
              onRefresh: () async {
                if (_selectedRiver != null) {
                  await _waterAssetService.getHubRivers();
                } else {
                  await _waterAssetService.getHubHydropowerComplexes();
                }
              },
              child: ListView(
                key: const ValueKey('figma-water-canonical-context-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  _WaterContextBar(
                    selected: _category,
                    onSelected: _selectCategory,
                  ),
                  const SizedBox(height: 10),
                  _WaterSegmentBar(
                    onStations: _openStationSelector,
                    onAlerts: () =>
                        AppNavigator.open<void>(context, AppDestination.alerts),
                  ),
                  const SizedBox(height: 14),
                  _canonicalContextPanel(),
                  const SizedBox(height: 14),
                  _ReviewPanel(
                    height: 118,
                    radius: 18,
                    background: const Color(0xFF0A171D),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MonoLabel(
                          'ADEVĂR OPERAȚIONAL',
                          color: FigmaFluviTokens.cyan,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Valorile hidrologice apar numai când există o sursă reală asociată acestui context.',
                          style: TextStyle(
                            color: FigmaFluviTokens.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        Spacer(),
                        Text(
                          'Fără telemetrie validă: UNKNOWN — nu estimăm și nu reutilizăm datele altei stații.',
                          style: TextStyle(
                            fontFamily: 'IBM Plex Mono',
                            color: FigmaFluviTokens.textMuted,
                            fontSize: 8.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => AppNavigator.open<void>(
                            context,
                            AppDestination.contextualMap,
                          ),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Hartă'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => AppNavigator.open<void>(
                            context,
                            AppDestination.addReport,
                          ),
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('Raport'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => AppNavigator.open<void>(
                            context,
                            AppDestination.community,
                          ),
                          icon: const Icon(Icons.groups_outlined),
                          label: const Text('Puls'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              key: const ValueKey('figma-water-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _TinyStatusPill(
                    label: currentStatus,
                    color: currentStatusColor,
                    width: 92,
                  ),
                ),
                const SizedBox(height: 10),
                _ReviewPanel(
                  height: _responsivePanelHeight(context, 133, 230),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _MonoLabel(
                        'ULTIMA OBSERVAȚIE OFICIALĂ',
                        color: Color(0xFF38BDF8),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text(
                            _number(reading?.value),
                            style: const TextStyle(
                              color: FigmaFluviTokens.white,
                              fontSize: 48,
                              height: .92,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1.4,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 5),
                            child: Text(
                              'cm',
                              style: TextStyle(
                                color: FigmaFluviTokens.textSecondary,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 20,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (delta != null)
                            Text(
                              _signedDelta(delta),
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            _trendLabel(trend),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: FigmaFluviTokens.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$source · ${station?.name ?? 'stație'} · actualizat $freshness',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'IBM Plex Mono',
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _WaterContextBar(
                  selected: _category,
                  onSelected: _selectCategory,
                ),
                const SizedBox(height: 10),
                _WaterSegmentBar(
                  onStations: _openStationSelector,
                  onAlerts: () =>
                      AppNavigator.open<void>(context, AppDestination.alerts),
                ),
                if (_selectedRiver != null || _selectedHydropower != null) ...[
                  const SizedBox(height: 14),
                  _canonicalContextPanel(),
                ],
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  label: 'Deschide opțiunile de istoric apă',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    key: const ValueKey('water-history-open'),
                    onTap: () => _openHistory(history),
                    child: _ReviewPanel(
                      height: _responsivePanelHeight(context, 270, 360),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            runAlignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              const _MonoLabel(
                                'DOAR OBSERVAȚII OFICIALE',
                                color: Color(0xFF38BDF8),
                              ),
                              _MonoLabel('${visibleHistory.length} observații'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tendință nivel · $historyDays zile',
                            style: TextStyle(
                              color: FigmaFluviTokens.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: visibleHistory.length >= 2
                                ? _OfficialWaterChart(history: visibleHistory)
                                : const FigmaTruthfulEmpty(
                                    icon: Icons.show_chart_rounded,
                                    title: 'Istoric insuficient',
                                    message:
                                        'Nu sunt suficiente observații oficiale pentru grafic.',
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            runAlignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              _MonoLabel('−$historyDays Z'),
                              _MonoLabel('−${(historyDays / 2).round()} Z'),
                              const _MonoLabel('ACUM'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Perioadele fără date nu sunt estimate.',
                            style: TextStyle(
                              fontFamily: 'IBM Plex Mono',
                              color: FigmaFluviTokens.textSecondary,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ReviewPanel(
                  height: _responsivePanelHeight(context, 78, 150),
                  radius: 16,
                  background: const Color(0xFF101C22),
                  child: Row(
                    children: [
                      const Expanded(
                        child: _WaterMetricBlock(label: 'DEBIT', value: '—'),
                      ),
                      Expanded(
                        child: _WaterMetricBlock(
                          label: 'TEMP. APĂ',
                          value: reading?.waterTemperatureC == null
                              ? '—'
                              : '${reading!.waterTemperatureC!.toStringAsFixed(0)}°C',
                        ),
                      ),
                      const Expanded(
                        child: _WaterMetricBlock(
                          label: 'ACTUALIZAT',
                          value: 'date live',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  button: true,
                  label: 'Deschide Pulsul Râului',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => AppNavigator.open<void>(
                      context,
                      AppDestination.community,
                    ),
                    child: _ReviewPanel(
                      height: _responsivePanelHeight(context, 70, 140),
                      radius: 16,
                      accent: FigmaFluviTokens.cyan,
                      background: const Color(0xFF0A1519),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MonoLabel(
                                  'SEMNAL COMUNITAR · SURSĂ SEPARATĂ',
                                  color: FigmaFluviTokens.cyan,
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Deschide Pulsul Râului',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: FigmaFluviTokens.white,
                                    fontSize: 15,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: FigmaFluviTokens.cyan,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ContextHubActionGrid(
                  actions: [
                    _ContextHubAction(
                      keyName: 'batch3-water-open-map',
                      label: 'Vezi pe hartă',
                      icon: Icons.map_outlined,
                      onPressed: station == null
                          ? null
                          : () {
                              _publishStation(station);
                              AppNavigator.open<void>(
                                context,
                                AppDestination.contextualMap,
                                arguments: ContextualMapEntry.forStation(
                                  source: 'water',
                                  station: station,
                                ),
                              );
                            },
                    ),
                    _ContextHubAction(
                      keyName: 'batch3-water-add-alert',
                      label: 'Adaugă alertă',
                      icon: Icons.add_alert_rounded,
                      secondary: false,
                      onPressed: () => _openAlert(station),
                    ),
                    _ContextHubAction(
                      keyName: 'batch3-water-open-weather',
                      label: 'Vreme și solunar',
                      icon: Icons.cloud_outlined,
                      onPressed: () => AppNavigator.open<void>(
                        context,
                        AppDestination.weather,
                        arguments: station,
                      ),
                    ),
                    _ContextHubAction(
                      keyName: 'batch3-water-open-fluvi',
                      label: 'FluviScore',
                      icon: Icons.auto_awesome_rounded,
                      onPressed: () => AppNavigator.open<void>(
                        context,
                        AppDestination.fluvi,
                        arguments: station,
                      ),
                    ),
                  ],
                ),
                if (water?.safeDiagnosticMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    water!.safeDiagnosticMessage!,
                    textAlign: TextAlign.center,
                    style: figmaBody(size: 10),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class WaterHistorySheet extends StatelessWidget {
  const WaterHistorySheet({
    super.key,
    required this.history,
    required this.accessTier,
  });

  final List<WaterLevel> history;
  final FluviAccessTier accessTier;

  @override
  Widget build(BuildContext context) {
    final range = accessTier == FluviAccessTier.premium
        ? WaterHistoryRange.thirtyDays
        : WaterHistoryRange.sevenDays;
    final filtered = realWaterHistoryForRange(history, range);
    final days = range.duration.inDays;
    return SingleChildScrollView(
      key: const ValueKey('water-history-scroll'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FigmaFluviTokens.textMuted,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Istoric apă',
              style: TextStyle(
                color: FigmaFluviTokens.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              accessTier == FluviAccessTier.premium
                  ? 'Istoric Pro · ultimele 30 zile'
                  : 'Istoric Free · ultimele 7 zile',
              style: figmaBody(size: 11),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _TinyStatusPill(
                  label: '$days ZILE',
                  color: accessTier == FluviAccessTier.premium
                      ? FigmaFluviTokens.amber
                      : const Color(0xFF38BDF8),
                  width: 86,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${filtered.length} observații reale',
                    key: const ValueKey('water-history-observation-count'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: figmaBody(size: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: filtered.length >= 2
                  ? _OfficialWaterChart(history: filtered)
                  : const FigmaTruthfulEmpty(
                      icon: Icons.show_chart_rounded,
                      title: 'Istoric insuficient',
                      message: 'Sunt necesare cel puțin două observații reale.',
                    ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Perioadele fără date nu sunt estimate. Graficul folosește numai observații oficiale reale.',
              style: TextStyle(
                fontFamily: 'IBM Plex Mono',
                color: FigmaFluviTokens.textSecondary,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterMetricBlock extends StatelessWidget {
  const _WaterMetricBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _MonoLabel(label),
      const SizedBox(height: 6),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: FigmaFluviTokens.white,
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class FigmaStationPage extends StatelessWidget {
  const FigmaStationPage({super.key, this.station});

  final Station? station;

  @override
  Widget build(BuildContext context) =>
      FigmaWaterHubPage(initialStation: station);
}

class FigmaWeatherHubPage extends StatelessWidget {
  const FigmaWeatherHubPage({super.key, this.initialStation, this.dataSource});

  final Station? initialStation;
  final CommercialHomeDataSource? dataSource;

  Future<void> _openWeatherAlert(BuildContext context) async {
    WeatherAlertTarget target;
    final station = initialStation;
    if (station != null) {
      target = WeatherAlertTarget.fromStation(station);
    } else {
      try {
        final position = await const LocationService().determinePosition();
        target = WeatherAlertTarget.fromCoordinates(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } on Exception {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Locația reală nu este disponibilă. Activează locația pentru a crea alerta meteo.',
            ),
          ),
        );
        return;
      }
    }
    if (!context.mounted) return;
    await AppNavigator.open<void>(
      context,
      AppDestination.newAlert,
      arguments: target,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-weather-hub'),
      title: 'Vreme & Solunar',
      subtitle: _stationContext(null, initialStation),
      action: FigmaRoundButton(
        key: const ValueKey('weather-open-alerts'),
        icon: Icons.notifications_none_rounded,
        tooltip: 'Alerte meteo',
        onPressed: () => _openWeatherAlert(context),
      ),
      scaffoldColor: const Color(0xFF05080B),
      background: const BoxDecoration(color: Color(0xFF05080B)),
      padding: EdgeInsets.zero,
      child: FigmaRuntimeSnapshotBuilder(
        station: initialStation,
        dataSource: dataSource,
        builder: (context, snapshot, refresh) {
          final result = snapshot?.weather;
          final data = result?.data;
          final station = initialStation ?? snapshot?.station;
          final hours = data?.hourlyForecast ?? const <WeatherForecastHour>[];
          final score = snapshot?.score;
          final bestTime = score?.hasEnoughData == true ? score!.bestTime : '—';
          final confidence = score?.hasEnoughData == true
              ? '${score!.confidence}%'
              : 'indisponibilă';
          final windRisk = data == null
              ? 'Vânt indisponibil'
              : data.windGusts >= 28
              ? 'Vânt dificil · rafale ${data.windGusts.round()} km/h'
              : 'Vânt ${data.windSpeed.round()} km/h acum';
          final windDetail = data == null
              ? 'Nu există date meteo live.'
              : '${_windDirectionRo(data.windDirectionLabel)} · rafale ${data.windGusts.round()} km/h';
          final pressureTitle = data?.pressure == null
              ? 'Presiune indisponibilă'
              : 'Presiune ${data!.pressure!.round()} hPa';
          final pressureDetail = data?.pressure == null
              ? 'Sursa meteo nu a returnat presiunea.'
              : 'Valoare curentă · fără trend inventat';
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              key: const ValueKey('figma-weather-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                _ReviewPanel(
                  height: _responsivePanelHeight(context, 209, 372),
                  radius: 20,
                  background: const Color(0xFF0D171C),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _MonoLabel('CONDIȚII ACTUALE'),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 2,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (data != null)
                                        Icon(
                                          _conditionIcon(data.condition),
                                          color: FigmaFluviTokens.cyan,
                                          size: 28,
                                        ),
                                      Text(
                                        data == null
                                            ? '—'
                                            : '${data.temperature.round()}°',
                                        style: const TextStyle(
                                          color: FigmaFluviTokens.white,
                                          fontSize: 54,
                                          height: .95,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    data == null
                                        ? 'Date meteo indisponibile'
                                        : _localizedWeatherCondition(
                                            context,
                                            data.condition,
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: FigmaFluviTokens.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 136,
                              child: _ReviewPanel(
                                height: _responsivePanelHeight(
                                  context,
                                  98,
                                  160,
                                ),
                                padding: const EdgeInsets.all(13),
                                radius: 16,
                                accent: FigmaFluviTokens.cyan,
                                background: const Color(0xFF103F42),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _MonoLabel(
                                      'INTERVAL OPTIM',
                                      color: FigmaFluviTokens.cyan,
                                    ),
                                    const Spacer(),
                                    Text(
                                      bestTime,
                                      maxLines: 2,
                                      softWrap: true,
                                      style: const TextStyle(
                                        color: FigmaFluviTokens.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Încredere · $confidence',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: FigmaFluviTokens.textSecondary,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _WeatherMetric(
                              icon: Icons.north_east_rounded,
                              label: 'VÂNT',
                              value: data == null
                                  ? '—'
                                  : '${data.windSpeed.round()} km/h',
                              color: FigmaFluviTokens.amber,
                            ),
                          ),
                          Expanded(
                            child: _WeatherMetric(
                              icon: Icons.water_drop_outlined,
                              label: 'PLOAIE',
                              value: data == null
                                  ? '—'
                                  : '${data.precipitationProbability.round()}%',
                              color: const Color(0xFF2DB9F2),
                            ),
                          ),
                          Expanded(
                            child: _WeatherMetric(
                              icon: Icons.adjust_rounded,
                              label: 'PRESIUNE',
                              value: data?.pressure == null
                                  ? '—'
                                  : '${data!.pressure!.round()} hPa',
                              color: FigmaFluviTokens.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _MonoLabel('URMĂTOARELE 12 ORE'),
                const SizedBox(height: 12),
                _ReviewPanel(
                  height: _responsivePanelHeight(context, 108, 190),
                  radius: 18,
                  background: const Color(0xFF0D171C),
                  child: _HourlyStrip(hours: hours),
                ),
                const SizedBox(height: 22),
                const _MonoLabel('DECIZIE PESCUIT'),
                const SizedBox(height: 12),
                _FishingDecisionCard(
                  icon: Icons.north_east_rounded,
                  color: FigmaFluviTokens.amber,
                  title: windRisk,
                  subtitle: windDetail,
                ),
                const SizedBox(height: 10),
                _FishingDecisionCard(
                  icon: Icons.adjust_rounded,
                  color: FigmaFluviTokens.green,
                  title: pressureTitle,
                  subtitle: pressureDetail,
                ),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: const ValueKey('batch3-weather-solunar-section'),
                  child: _ReviewPanel(
                    height: _responsivePanelHeight(context, 82, 150),
                    radius: 18,
                    background: const Color(0xFF101D23),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Prognoză extinsă',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: FigmaFluviTokens.white,
                                  fontSize: 15,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '72h vânt · ploaie · presiune · răsărit · solunar',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: FigmaFluviTokens.textSecondary,
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.timeline_rounded,
                          color: FigmaFluviTokens.cyan,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ReviewPanel(
                  radius: 16,
                  background: const Color(0xFF0D171C),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _SolunarDatum(
                        label: 'RĂSĂRIT',
                        value: data?.sunrise == null
                            ? '—'
                            : '${data!.sunrise!.hour.toString().padLeft(2, '0')}:${data.sunrise!.minute.toString().padLeft(2, '0')}',
                      ),
                      _SolunarDatum(
                        label: 'APUS',
                        value: data?.sunset == null
                            ? '—'
                            : '${data!.sunset!.hour.toString().padLeft(2, '0')}:${data.sunset!.minute.toString().padLeft(2, '0')}',
                      ),
                      _SolunarDatum(
                        label: 'LUNĂ',
                        value: data?.moonPhase ?? '—',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: const ValueKey('batch3-weather-actions'),
                  child: _ContextHubActionGrid(
                    actions: [
                      _ContextHubAction(
                        keyName: 'batch3-weather-open-water',
                        label: 'Inteligență hidrologică',
                        icon: Icons.water_rounded,
                        onPressed: () => AppNavigator.open<void>(
                          context,
                          AppDestination.water,
                          arguments: station,
                        ),
                      ),
                      _ContextHubAction(
                        keyName: 'batch3-weather-open-map',
                        label: 'Hartă completă',
                        icon: Icons.map_outlined,
                        onPressed: station == null
                            ? null
                            : () => AppNavigator.open<void>(
                                context,
                                AppDestination.contextualMap,
                                arguments: ContextualMapEntry.forStation(
                                  source: 'weather',
                                  station: station,
                                ),
                              ),
                      ),
                      _ContextHubAction(
                        keyName: 'batch3-weather-open-fluvi',
                        label: 'FluviScore',
                        icon: Icons.auto_awesome_rounded,
                        secondary: false,
                        onPressed: () => AppNavigator.open<void>(
                          context,
                          AppDestination.fluvi,
                          arguments: station,
                        ),
                      ),
                    ],
                  ),
                ),
                if (result?.safeDiagnosticMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    result!.safeDiagnosticMessage!,
                    textAlign: TextAlign.center,
                    style: figmaBody(size: 10),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class FigmaFluviHubPage extends StatelessWidget {
  const FigmaFluviHubPage({
    super.key,
    this.initialStation,
    this.initialContext,
    this.dataSource,
  });

  final Station? initialStation;
  final FluviResolvedContext? initialContext;
  final CommercialHomeDataSource? dataSource;

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-fluvi-hub'),
      eyebrow: context.l10n.fluviIntelligence,
      title: 'FluviScore',
      subtitle: _stationContext(null, initialStation),
      action: const _TinyStatusPill(
        label: 'EXPLICABIL',
        color: FigmaFluviTokens.cyan,
        width: 88,
      ),
      scaffoldColor: const Color(0xFF05080A),
      background: const BoxDecoration(color: Color(0xFF05080A)),
      padding: EdgeInsets.zero,
      child: FigmaRuntimeSnapshotBuilder(
        station: initialStation,
        resolvedContext: initialContext,
        dataSource: dataSource,
        builder: (context, snapshot, refresh) {
          final score = snapshot?.score;
          final station = initialStation ?? snapshot?.station;
          final hasScore = score?.hasEnoughData == true;
          final scoreValue = hasScore ? score!.score!.round().toString() : '—';
          final confidence = hasScore ? score!.confidence : 0;
          final recommendation = hasScore
              ? _localizedScoreText(context, score!.recommendation)
              : 'Nu sunt suficiente date';
          final positive = score?.positiveFactors ?? const <String>[];
          final negative = score?.negativeFactors ?? const <String>[];
          final missing = score?.missingFactors ?? const <String>[];
          final factors = <_ScoreFactor>[
            for (final item in positive.take(2))
              _ScoreFactor(
                label: _localizedScoreText(context, item),
                detail: 'Semnal real favorabil',
                color: FigmaFluviTokens.green,
                pill: 'POZITIV',
              ),
            for (final item in negative.take(2))
              _ScoreFactor(
                label: _localizedScoreText(context, item),
                detail: 'Semnal real nefavorabil',
                color: FigmaFluviTokens.amber,
                pill: 'RISC',
              ),
            for (final item in missing.take(2))
              _ScoreFactor(
                label: _localizedScoreText(context, item),
                detail: 'Intrare lipsă · scorul nu este completat artificial',
                color: FigmaFluviTokens.red,
                pill: 'DATE PUȚINE',
              ),
          ].take(4).toList(growable: false);
          final confidenceColor = confidence >= 75
              ? FigmaFluviTokens.green
              : confidence >= 45
              ? FigmaFluviTokens.amber
              : FigmaFluviTokens.red;

          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              key: const ValueKey('figma-fluvi-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Wrap(
                  key: const ValueKey('fluvi-intelligence-switcher'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FigmaPill(
                      label: context.l10n.fluviScoreView,
                      icon: Icons.insights_rounded,
                      active: true,
                    ),
                    FigmaPill(
                      label: context.l10n.askFluviView,
                      icon: Icons.auto_awesome_rounded,
                      onTap: () => AppNavigator.open(
                        context,
                        AppDestination.askFluvi,
                        arguments: snapshot?.resolvedContext ?? initialContext,
                        dataSource: dataSource,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ReviewPanel(
                  height: _responsivePanelHeight(context, 167, 300),
                  radius: 20,
                  background: const Color(0xFF0B1115),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: _MonoLabel('CONDIȚII DE PESCUIT ACUM'),
                          ),
                          _TinyStatusPill(
                            label: hasScore
                                ? 'ÎNCREDERE $confidence%'
                                : 'DATE PUȚINE',
                            color: confidenceColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (MediaQuery.textScalerOf(context).scale(1) < 1.5)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              scoreValue,
                              style: const TextStyle(
                                color: FigmaFluviTokens.white,
                                fontSize: 54,
                                height: .95,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 6, bottom: 5),
                              child: Text(
                                '/100',
                                style: TextStyle(
                                  color: FigmaFluviTokens.cyan,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(
                              scoreValue,
                              style: const TextStyle(
                                color: FigmaFluviTokens.white,
                                fontSize: 54,
                                height: .95,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 5),
                              child: Text(
                                '/100',
                                style: TextStyle(
                                  color: FigmaFluviTokens.cyan,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const Spacer(),
                      Text(
                        recommendation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasScore
                              ? FigmaFluviTokens.green
                              : FigmaFluviTokens.textSecondary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        hasScore
                            ? 'Scor calculat din intrările disponibile acum.'
                            : 'Fluvi nu inventează scorul când lipsesc intrările.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _MonoLabel('DE CE ACEST SCOR'),
                const SizedBox(height: 10),
                if (factors.isEmpty)
                  const _ReviewPanel(
                    height: 88,
                    child: Center(
                      child: Text(
                        'Nu există încă factori explicabili disponibili.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                else
                  for (var index = 0; index < factors.length; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    _ScoreFactorCard(factor: factors[index]),
                  ],
                const SizedBox(height: 16),
                _ReviewPanel(
                  height: _responsivePanelHeight(context, 82, 150),
                  radius: 16,
                  background: const Color(0xFF070E11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Proveniența scorului',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Scor determinist · limită 0–100\nModelul IA nu calculează scorul numeric.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ContextHubActionGrid(
                  actions: [
                    _ContextHubAction(
                      keyName: 'batch3-fluvi-open-water',
                      label: 'Inteligență hidrologică',
                      icon: Icons.water_rounded,
                      onPressed: () => AppNavigator.open<void>(
                        context,
                        AppDestination.water,
                        arguments: station,
                      ),
                    ),
                    _ContextHubAction(
                      keyName: 'batch3-fluvi-open-weather',
                      label: 'Vreme și solunar',
                      icon: Icons.cloud_outlined,
                      onPressed: () => AppNavigator.open<void>(
                        context,
                        AppDestination.weather,
                        arguments: station,
                      ),
                    ),
                    _ContextHubAction(
                      keyName: 'batch3-fluvi-open-map',
                      label: 'Hartă completă',
                      icon: Icons.map_outlined,
                      onPressed: station == null
                          ? null
                          : () => AppNavigator.open<void>(
                              context,
                              AppDestination.contextualMap,
                              arguments: ContextualMapEntry.forStation(
                                source: 'fluvi-score',
                                station: station,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class FigmaAskFluviPage extends ConsumerStatefulWidget {
  const FigmaAskFluviPage({super.key, this.dataSource, this.initialContext});

  final CommercialHomeDataSource? dataSource;
  final FluviResolvedContext? initialContext;

  @override
  ConsumerState<FigmaAskFluviPage> createState() => _FigmaAskFluviPageState();
}

class _FigmaAskFluviPageState extends ConsumerState<FigmaAskFluviPage> {
  final _controller = TextEditingController();
  final _answerService = const FluviDeterministicAnswerService();
  late final CommercialHomeDataSource _dataSource;
  FluviAnswer? _answer;
  bool _loading = false;
  String? _error;
  String? _answerContextKey;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? LiveCommercialHomeDataSource();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  FluviResolvedContext? _effectiveContext() =>
      widget.initialContext ?? ref.read(canonicalFluviContextProvider);

  Future<CommercialHomeSnapshot> _loadCanonicalSnapshot(
    FluviResolvedContext? resolvedContext,
  ) async {
    final contextAwareSource =
        _dataSource is ContextAwareCommercialHomeDataSource
        ? _dataSource as ContextAwareCommercialHomeDataSource
        : null;
    if (resolvedContext != null && contextAwareSource != null) {
      return contextAwareSource.loadForContext(resolvedContext);
    }
    if (_dataSource
        case final CurrentLocationAwareCommercialHomeDataSource
            locationAwareSource) {
      final languageCode = Localizations.localeOf(context).languageCode;

      await ref
          .read(appRuntimeProvider.notifier)
          .start(languageCode: languageCode);

      final locationState = ref.read(currentLocationProvider);
      final location = locationState.location;

      if (locationState.hasUsableLocation && location != null) {
        return locationAwareSource.loadForCurrentLocation(location);
      }
    }

    // No second GPS acquisition is allowed here.
    return _dataSource.load();
  }

  Future<void> _submit() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    final resolvedContext = _effectiveContext();
    final contextKey = resolvedContext?.contextKey ?? 'unavailable';
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
      _answerContextKey = contextKey;
    });
    try {
      final snapshot = await _loadCanonicalSnapshot(resolvedContext);
      final answer = _answerService.answer(
        question: question,
        snapshot: snapshot,
      );
      final currentKey = _effectiveContext()?.contextKey ?? 'unavailable';
      if (!mounted ||
          generation != _requestGeneration ||
          currentKey != contextKey) {
        return;
      }
      setState(() {
        _answer = answer;
        _loading = false;
      });
    } on Exception {
      final currentKey = _effectiveContext()?.contextKey ?? 'unavailable';
      if (!mounted ||
          generation != _requestGeneration ||
          currentKey != contextKey) {
        return;
      }
      setState(() {
        _loading = false;
        _error =
            'Contextul real nu a putut fi încărcat. Verifică locația/conexiunea și încearcă din nou.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<FluviResolvedContext?>(canonicalFluviContextProvider, (
      previous,
      next,
    ) {
      if (widget.initialContext != null ||
          previous?.contextKey == next?.contextKey) {
        return;
      }
      _requestGeneration++;
      if (!mounted) return;
      setState(() {
        _answer = null;
        _error = null;
        _loading = false;
        _answerContextKey = null;
      });
    });
    final resolvedContext =
        widget.initialContext ?? ref.watch(canonicalFluviContextProvider);
    final answer = _answer;
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-ask-fluvi'),
      subtitle: resolvedContext?.primaryLabel ?? 'Context curent indisponibil',
      title: 'Întreabă Fluvi',
      eyebrow: 'CONTEXT REAL',
      child: ListView(
        children: [
          FigmaSurface(
            accent: FigmaFluviTokens.violet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: FigmaFluviTokens.violet,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'Fluvi',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Întreabă despre apă, vreme, condițiile de pescuit sau activitatea din zonă. Fluvi răspunde acum determinist din datele reale ale aplicației; modelul AI avansat va folosi același context și același fallback.',
                  style: figmaBody(size: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 7,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'Ex.: Cum influențează scăderea apei partida de mâine?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FigmaPrimaryButton(
            label: _loading ? 'Analizez datele…' : 'Trimite întrebarea',
            icon: Icons.send_rounded,
            onPressed: _loading ? null : _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 18),
            FigmaTruthfulEmpty(
              icon: Icons.cloud_off_rounded,
              title: 'Context indisponibil',
              message: _error!,
              actionLabel: 'Reîncearcă',
              onAction: _submit,
            ),
          ],
          if (answer != null &&
              _answerContextKey ==
                  (resolvedContext?.contextKey ?? 'unavailable')) ...[
            const SizedBox(height: 18),
            FigmaSurface(
              accent: answer.hasEnoughData
                  ? FigmaFluviTokens.cyan
                  : FigmaFluviTokens.amber,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          answer.hasEnoughData
                              ? 'Răspuns Fluvi'
                              : 'Date insuficiente',
                          style: const TextStyle(
                            color: FigmaFluviTokens.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _TinyStatusPill(
                        label: 'ÎNCREDERE ${answer.confidence}%',
                        color: answer.confidence >= 70
                            ? FigmaFluviTokens.green
                            : answer.confidence >= 40
                            ? FigmaFluviTokens.amber
                            : FigmaFluviTokens.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(answer.text, style: figmaBody(size: 12)),
                  if (answer.sources.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Surse: ${answer.sources.join(' · ')}',
                      style: figmaBody(
                        color: FigmaFluviTokens.textSecondary,
                        size: 9,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Motor determinist · fără valori inventate · model AI avansat neactivat încă',
                    style: figmaBody(
                      color: FigmaFluviTokens.textMuted,
                      size: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class FigmaRiverPage extends ConsumerStatefulWidget {
  const FigmaRiverPage({
    super.key,
    this.river,
    this.service = const WaterAssetService(),
    this.savedItemsService = const SavedItemsService(),
  });

  final WaterRiverRef? river;
  final WaterAssetService service;
  final SavedItemsService savedItemsService;

  @override
  ConsumerState<FigmaRiverPage> createState() => _FigmaRiverPageState();
}

class _FigmaRiverPageState extends ConsumerState<FigmaRiverPage> {
  Future<_WaterRiverPageData>? _future;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final river = widget.river;
    if (river == null) return;
    _future = _load(river);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(selectedContextProvider.notifier)
          .select(
            SelectedContext(
              countryCode: river.countryCode,
              waterId: river.waterBodyId,
              waterName: river.name,
              riverName: river.name,
              riverKey: river.key,
              source: river.provenanceSource,
            ),
          );
    });
    _loadSaved(river);
  }

  Future<_WaterRiverPageData> _load(WaterRiverRef river) async {
    final parts = await Future.wait<Object>([
      widget.service.getRiverDetail(river),
      widget.service.getRiverState(river),
    ]);
    return _WaterRiverPageData(
      detail: parts[0] as WaterRiverDetail,
      state: parts[1] as WaterEntityState,
    );
  }

  Future<void> _loadSaved(WaterRiverRef river) async {
    try {
      final saved = await widget.savedItemsService.isSaved(
        type: 'river',
        referenceId: river.key,
      );
      if (mounted) setState(() => _saved = saved);
    } on Exception {
      // The detail remains useful even when favorite state is unavailable.
    }
  }

  void _addRiverAlert(WaterRiverRef river) {
    AppNavigator.open<void>(context, AppDestination.newAlert, arguments: river);
  }

  Future<void> _toggleSaved(WaterRiverRef river) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_saved) {
        await widget.savedItemsService.remove(
          type: 'river',
          referenceId: river.key,
        );
      } else {
        await widget.savedItemsService.save(
          type: 'river',
          referenceId: river.key,
          title: river.name,
          subtitle: [
            if (river.basinNames.isNotEmpty) river.basinNames.first,
            '${river.damCount} baraje · ${river.reservoirCount} acumulări',
          ].join(' · '),
          metadata: <String, Object?>{
            'source': river.provenanceSource,
            'river_key': river.key,
            'water_body_id': river.waterBodyId,
            'canonical_key': river.canonicalKey,
            'basin_code': river.basinCode,
            'canonical_water_body': river.canonicalWaterBody,
            'map_geometry_available': river.mapGeometryAvailable,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        _saved = !_saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _saved
                ? 'Râul a fost adăugat în Apele mele.'
                : 'Râul a fost eliminat din Apele mele.',
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apele mele nu sunt disponibile momentan.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final river = widget.river;
    if (river == null) {
      return const FigmaCanonicalScaffold(
        key: ValueKey('figma-river-detail'),
        title: 'Râu',
        eyebrow: 'WATER',
        child: FigmaTruthfulEmpty(
          icon: Icons.waves_rounded,
          title: 'Niciun râu selectat',
          message: 'Selectează un râu real din Căutare sau Water.',
        ),
      );
    }
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-river-detail'),
      title: river.name,
      eyebrow: 'RÂU',
      child: FutureBuilder<_WaterRiverPageData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Column(
              children: [
                const FigmaTruthfulEmpty(
                  icon: Icons.sync_problem_rounded,
                  title: 'Datele râului nu sunt disponibile',
                  message:
                      'Catalogul Water nu a putut fi încărcat. Contextul selectat rămâne păstrat.',
                ),
                const SizedBox(height: 14),
                FigmaPrimaryButton(
                  label: 'Reîncearcă',
                  icon: Icons.refresh_rounded,
                  onPressed: () => setState(() => _future = _load(river)),
                ),
              ],
            );
          }
          final data = snapshot.data!;
          return ListView(
            children: [
              _identity(data.detail),
              const SizedBox(height: 12),
              _state(data.state),
              const SizedBox(height: 12),
              _geometryNotice(data.detail.ref),
              if (data.detail.stations.isNotEmpty) ...[
                const SizedBox(height: 12),
                _linkedList('Stații hidrometrice', data.detail.stations),
              ],
              if (data.detail.dams.isNotEmpty) ...[
                const SizedBox(height: 12),
                _linkedList('Baraje', data.detail.dams),
              ],
              if (data.detail.reservoirs.isNotEmpty) ...[
                const SizedBox(height: 12),
                _linkedList('Lacuri de acumulare', data.detail.reservoirs),
              ],
              const SizedBox(height: 14),
              FigmaPrimaryButton(
                label: 'Raportează starea apei',
                icon: Icons.add_alert_rounded,
                onPressed: () =>
                    AppNavigator.open<void>(context, AppDestination.addReport),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FigmaPrimaryButton(
                      label: 'Alertă',
                      icon: Icons.notifications_active_outlined,
                      secondary: true,
                      onPressed: () => _addRiverAlert(river),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FigmaPrimaryButton(
                      label: _saving ? '...' : (_saved ? 'Salvat' : 'Salvează'),
                      icon: _saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      secondary: true,
                      onPressed: _saving ? null : () => _toggleSaved(river),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _identity(WaterRiverDetail detail) => FigmaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.waves_rounded,
              color: FigmaFluviTokens.cyan,
              size: 25,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.ref.name,
                    style: const TextStyle(
                      color: FigmaFluviTokens.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (detail.ref.basinNames.isNotEmpty)
                        detail.ref.basinNames.take(2).join(', '),
                      if (detail.ref.basinCode?.isNotEmpty == true)
                        detail.ref.basinCode!,
                      '${detail.ref.damCount} baraje',
                      '${detail.ref.reservoirCount} acumulări',
                    ].join(' · '),
                    style: figmaBody(size: 9.5),
                  ),
                ],
              ),
            ),
            const _TinyStatusPill(label: 'ANAR', color: FigmaFluviTokens.cyan),
          ],
        ),
        if (detail.ref.counties.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Județe: ${detail.ref.counties.take(5).join(', ')}${detail.ref.counties.length > 5 ? '…' : ''}',
            style: figmaBody(color: FigmaFluviTokens.textSecondary, size: 9),
          ),
        ],
      ],
    ),
  );

  Widget _state(WaterEntityState state) {
    final trend = state.officialTrend != 'unknown'
        ? state.officialTrend
        : state.communityTrend;
    final label = switch (trend) {
      'rising' => 'Crește',
      'falling' => 'Scade',
      'stable' => 'Stabil',
      _ => 'Necunoscut',
    };
    final color = switch (trend) {
      'rising' => const Color(0xFF2F8CFF),
      'falling' => FigmaFluviTokens.red,
      'stable' => FigmaFluviTokens.green,
      _ => FigmaFluviTokens.textMuted,
    };
    final source = switch (state.source) {
      'official' => 'OFICIAL',
      'official_plus_community' => 'OFICIAL + COMUNITATE',
      'community_observed' => 'OBSERVAT',
      _ => 'FĂRĂ STARE RECENTĂ',
    };
    final flow = switch (state.flowState) {
      'strong' => 'Curent puternic',
      'moderate' => 'Curent moderat',
      'weak' => 'Curent slab',
      'stagnant' => 'Apă stagnantă',
      _ => 'Curent necunoscut',
    };
    final operation = switch (state.operationSignal) {
      'possible_release' => 'Posibilă evacuare',
      'possible_turbining' => 'Posibilă turbinare',
      'possible_spill' => 'Posibil deversor activ',
      _ => null,
    };
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: FigmaSectionLabel('Starea apei')),
              _TinyStatusPill(label: source, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                trend == 'rising'
                    ? Icons.trending_up_rounded
                    : trend == 'falling'
                    ? Icons.trending_down_rounded
                    : trend == 'stable'
                    ? Icons.trending_flat_rounded
                    : Icons.help_outline_rounded,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (state.confidence > 0)
                Text(
                  '${(state.confidence * 100).round()}% încredere',
                  style: figmaBody(size: 9),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyStatusPill(
                label: flow.toUpperCase(),
                color: FigmaFluviTokens.textSecondary,
              ),
              if (operation != null)
                _TinyStatusPill(
                  label: operation.toUpperCase(),
                  color: FigmaFluviTokens.amber,
                ),
              if (state.communityEvidenceCount > 0)
                _TinyStatusPill(
                  label: '${state.communityEvidenceCount} RAPOARTE',
                  color: FigmaFluviTokens.violet,
                ),
            ],
          ),
          if (state.disclaimer?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(state.disclaimer!, style: figmaBody(size: 9)),
          ],
        ],
      ),
    );
  }

  Widget _geometryNotice(WaterRiverRef river) => FigmaSurface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          river.mapGeometryAvailable
              ? Icons.map_rounded
              : Icons.polyline_rounded,
          color: river.mapGeometryAvailable
              ? FigmaFluviTokens.green
              : FigmaFluviTokens.amber,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            river.mapGeometryAvailable
                ? 'Geometria oficială a râului este disponibilă pentru hartă.'
                : 'Catalogul râului este real. Linia oficială a cursului de apă nu este încă importată în Mapbox; FluviAI nu inventează un traseu aproximativ.',
            style: figmaBody(size: 9.5),
          ),
        ),
      ],
    ),
  );

  Widget _linkedList(String title, List<WaterRiverLinkedAsset> items) =>
      FigmaSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FigmaSectionLabel(title),
            const SizedBox(height: 6),
            for (final item in items.take(60))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.type == 'station'
                      ? Icons.speed_rounded
                      : item.type == 'dam'
                      ? Icons.account_balance_rounded
                      : Icons.water_rounded,
                  color: FigmaFluviTokens.cyan,
                ),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  [
                    if (item.county?.isNotEmpty == true) item.county!,
                    item.hasOperationalData ? 'date operaționale' : 'catalog',
                  ].join(' · '),
                  style: figmaBody(size: 8.5),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: FigmaFluviTokens.textSecondary,
                ),
                onTap: () => _openLinked(item),
              ),
          ],
        ),
      );

  void _openLinked(WaterRiverLinkedAsset item) {
    final lat = item.latitude;
    final lng = item.longitude;
    if (item.type == 'station') {
      if (lat == null || lng == null) return;
      AppNavigator.open<void>(
        context,
        AppDestination.contextualMap,
        arguments: ContextualMapEntry.forTarget(
          source: 'river-detail',
          target: RuntimeMapCameraTarget(
            source: 'river-detail',
            entityId: item.id,
            latitude: lat,
            longitude: lng,
            zoom: 13.2,
          ),
        ),
      );
      return;
    }
    if (lat == null || lng == null) return;
    AppNavigator.open<void>(
      context,
      AppDestination.reservoir,
      arguments: WaterAssetRef(
        type: item.type == 'dam'
            ? WaterAssetType.dam
            : WaterAssetType.reservoir,
        id: item.id,
        name: item.name,
        latitude: lat,
        longitude: lng,
        riverName: widget.river?.name,
        county: item.county,
        basinName: item.basinName,
        hasOperationalData: item.hasOperationalData,
      ),
    );
  }
}

class _WaterRiverPageData {
  const _WaterRiverPageData({required this.detail, required this.state});
  final WaterRiverDetail detail;
  final WaterEntityState state;
}

class FigmaReservoirPage extends ConsumerStatefulWidget {
  const FigmaReservoirPage({
    super.key,
    this.asset,
    this.label,
    this.service = const WaterAssetService(),
    this.savedItemsService = const SavedItemsService(),
  });

  final WaterAssetRef? asset;
  final String? label;
  final WaterAssetService service;
  final SavedItemsService savedItemsService;

  @override
  ConsumerState<FigmaReservoirPage> createState() => _FigmaReservoirPageState();
}

class _FigmaReservoirPageState extends ConsumerState<FigmaReservoirPage> {
  Future<_WaterAssetPageData>? _future;
  bool _saved = false;
  bool _saving = false;

  WaterAssetRef? get _asset => widget.asset;

  @override
  void initState() {
    super.initState();
    final asset = _asset;
    if (asset != null) {
      _future = _load(asset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(selectedContextProvider.notifier)
            .select(
              SelectedContext(
                countryCode: asset.countryCode,
                locationName: asset.name,
                latitude: asset.latitude,
                longitude: asset.longitude,
                waterId: asset.waterBodyId,
                waterName: asset.name,
                riverName: asset.riverName,
                damId: asset.type == WaterAssetType.dam ? asset.id : null,
                reservoirId: asset.type == WaterAssetType.reservoir
                    ? asset.id
                    : null,
                source: 'ANAR',
              ),
            );
      });
      _loadSaved(asset);
    }
  }

  Future<_WaterAssetPageData> _load(WaterAssetRef asset) async {
    final parts = await Future.wait<Object>([
      widget.service.getDetail(asset),
      widget.service.getState(asset),
    ]);
    return _WaterAssetPageData(
      detail: parts[0] as WaterAssetDetail,
      state: parts[1] as WaterEntityState,
    );
  }

  Future<void> _loadSaved(WaterAssetRef asset) async {
    try {
      final saved = await widget.savedItemsService.isSaved(
        type: asset.entityType,
        referenceId: asset.id,
      );
      if (mounted) setState(() => _saved = saved);
    } on Exception {
      // Favorite state is secondary; the Water detail remains usable.
    }
  }

  Future<void> _toggleSaved(WaterAssetRef asset) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_saved) {
        await widget.savedItemsService.remove(
          type: asset.entityType,
          referenceId: asset.id,
        );
      } else {
        await widget.savedItemsService.save(
          type: asset.entityType,
          referenceId: asset.id,
          title: asset.name,
          subtitle: [
            if (asset.riverName?.isNotEmpty == true) asset.riverName!,
            if (asset.county?.isNotEmpty == true) asset.county!,
          ].join(' · '),
          latitude: asset.latitude,
          longitude: asset.longitude,
          metadata: <String, Object?>{
            'source': 'ANAR',
            'basin_name': asset.basinName,
            'water_body_id': asset.waterBodyId,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        _saved = !_saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _saved ? 'Adăugat în Apele mele.' : 'Eliminat din Apele mele.',
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favoritele nu sunt disponibile momentan.'),
        ),
      );
    }
  }

  void _openMap(WaterAssetRef asset) {
    AppNavigator.open<void>(
      context,
      AppDestination.contextualMap,
      arguments: ContextualMapEntry.forTarget(
        source: 'water-asset-detail',
        target: RuntimeMapCameraTarget(
          source: 'water-asset-detail',
          entityId: asset.id,
          latitude: asset.latitude,
          longitude: asset.longitude,
          zoom: 13.4,
        ),
      ),
    );
  }

  void _addReport() {
    AppNavigator.open<void>(context, AppDestination.addReport);
  }

  void _addAlert(WaterAssetRef asset) {
    AppNavigator.open<void>(context, AppDestination.newAlert, arguments: asset);
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset == null) {
      return FigmaCanonicalScaffold(
        key: const ValueKey('figma-reservoir-detail'),
        title: widget.label ?? 'Baraj / acumulare',
        eyebrow: 'WATER',
        child: const FigmaTruthfulEmpty(
          icon: Icons.water_rounded,
          title: 'Nicio entitate selectată',
          message:
              'Selectează un baraj sau o acumulare reală din Căutare ori Hartă.',
        ),
      );
    }
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-reservoir-detail'),
      title: asset.name,
      eyebrow: asset.type == WaterAssetType.dam ? 'BARAJ' : 'LAC DE ACUMULARE',
      child: FutureBuilder<_WaterAssetPageData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Column(
              children: [
                const FigmaTruthfulEmpty(
                  icon: Icons.sync_problem_rounded,
                  title: 'Date Water indisponibile',
                  message:
                      'Catalogul există, dar detaliile nu au putut fi încărcate. Reîncearcă fără a pierde contextul selectat.',
                ),
                const SizedBox(height: 14),
                FigmaPrimaryButton(
                  label: 'Reîncearcă',
                  icon: Icons.refresh_rounded,
                  onPressed: () => setState(() => _future = _load(asset)),
                ),
              ],
            );
          }
          final data = snapshot.data!;
          final hasCurrentData = _hasCurrentWaterData(data);
          return ListView(
            children: [
              _assetIdentity(data.detail),
              const SizedBox(height: 12),
              if (hasCurrentData) ...[
                _waterState(data.state),
                const SizedBox(height: 12),
                _operationalData(data.detail),
                const SizedBox(height: 12),
              ],
              _catalogData(data.detail),
              if (data.detail.linkedAssets.isNotEmpty) ...[
                const SizedBox(height: 12),
                _linkedAssets(data.detail),
              ],
              if (!hasCurrentData) ...[
                const SizedBox(height: 12),
                _currentDataUnavailable(),
              ],
              const SizedBox(height: 14),
              _actions(data.detail.ref),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  bool _hasCurrentWaterData(_WaterAssetPageData data) {
    final source = data.state.source;
    return data.detail.metrics.isNotEmpty ||
        source == 'official' ||
        source == 'official_plus_community' ||
        source == 'community_observed' ||
        data.state.communityEvidenceCount > 0;
  }

  Widget _currentDataUnavailable() {
    return FigmaSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FigmaFluviTokens.textMuted.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: FigmaFluviTokens.textMuted.withValues(alpha: .26),
              ),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              color: FigmaFluviTokens.textSecondary,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FigmaSectionLabel('Date curente'),
                const SizedBox(height: 4),
                Text(
                  'Momentan indisponibile. Datele descriptive ANAR rămân disponibile mai sus; FluviAI nu inventează valori curente.',
                  style: figmaBody(
                    color: FigmaFluviTokens.textSecondary,
                    size: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _assetIdentity(WaterAssetDetail detail) {
    final asset = detail.ref;
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                asset.type == WaterAssetType.dam
                    ? Icons.account_balance_rounded
                    : Icons.water_rounded,
                color: FigmaFluviTokens.cyan,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: const TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (asset.riverName?.isNotEmpty == true)
                          asset.riverName!,
                        if (asset.basinName?.isNotEmpty == true)
                          asset.basinName!,
                      ].join(' · '),
                      style: figmaBody(size: 10),
                    ),
                  ],
                ),
              ),
              const _TinyStatusPill(
                label: 'ANAR',
                color: FigmaFluviTokens.cyan,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              if (asset.county?.isNotEmpty == true) 'Județ ${asset.county}',
              '${asset.latitude.toStringAsFixed(4)}, ${asset.longitude.toStringAsFixed(4)}',
            ].join(' · '),
            style: figmaBody(color: FigmaFluviTokens.textSecondary, size: 9),
          ),
        ],
      ),
    );
  }

  Widget _waterState(WaterEntityState state) {
    final trend = state.officialTrend != 'unknown'
        ? state.officialTrend
        : state.communityTrend;
    final trendLabel = switch (trend) {
      'rising' => 'Crește',
      'falling' => 'Scade',
      'stable' => 'Stabil',
      _ => 'Necunoscut',
    };
    final trendColor = switch (trend) {
      'rising' => const Color(0xFF2F8CFF),
      'falling' => FigmaFluviTokens.red,
      'stable' => FigmaFluviTokens.green,
      _ => FigmaFluviTokens.textMuted,
    };
    final sourceLabel = switch (state.source) {
      'official' => 'OFICIAL',
      'official_plus_community' => 'OFICIAL + COMUNITATE',
      'community_observed' => 'OBSERVAT ÎN COMUNITATE',
      _ => 'FĂRĂ STARE RECENTĂ',
    };
    final flowLabel = switch (state.flowState) {
      'strong' => 'Curent puternic',
      'moderate' => 'Curent moderat',
      'weak' => 'Curent slab',
      'stagnant' => 'Apă stagnantă',
      _ => 'Curent necunoscut',
    };
    final operationLabel = switch (state.operationSignal) {
      'possible_release' => 'Posibilă evacuare',
      'possible_turbining' => 'Posibilă turbinare',
      'possible_spill' => 'Posibil deversor activ',
      _ => null,
    };
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: FigmaSectionLabel('Starea apei')),
              _TinyStatusPill(label: sourceLabel, color: trendColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                trend == 'rising'
                    ? Icons.trending_up_rounded
                    : trend == 'falling'
                    ? Icons.trending_down_rounded
                    : trend == 'stable'
                    ? Icons.trending_flat_rounded
                    : Icons.help_outline_rounded,
                color: trendColor,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trendLabel,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (state.confidence > 0)
                Text(
                  '${(state.confidence * 100).round()}% încredere',
                  style: figmaBody(size: 9),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyStatusPill(
                label: flowLabel.toUpperCase(),
                color: FigmaFluviTokens.textSecondary,
              ),
              if (operationLabel != null)
                _TinyStatusPill(
                  label: operationLabel.toUpperCase(),
                  color: FigmaFluviTokens.amber,
                ),
              if (state.communityEvidenceCount > 0)
                _TinyStatusPill(
                  label: '${state.communityEvidenceCount} RAPOARTE',
                  color: FigmaFluviTokens.violet,
                ),
            ],
          ),
          if (state.disclaimer?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(state.disclaimer!, style: figmaBody(size: 9)),
          ],
        ],
      ),
    );
  }

  Widget _operationalData(WaterAssetDetail detail) {
    if (detail.metrics.isEmpty) {
      return FigmaSurface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.query_stats_rounded,
              color: FigmaFluviTokens.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FigmaSectionLabel('Date operaționale'),
                  const SizedBox(height: 4),
                  Text(
                    'Momentan nu sunt publicate valori numerice curente pentru această entitate.',
                    style: figmaBody(
                      color: FigmaFluviTokens.textSecondary,
                      size: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FigmaSectionLabel('Date operaționale'),
          const SizedBox(height: 10),
          for (final metric in detail.metrics) ...[
            Row(
              children: [
                Expanded(
                  child: Text(_metricLabel(metric), style: figmaBody(size: 10)),
                ),
                Text(
                  _metricValue(metric),
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Valorile de mai sus provin exclusiv din observații operaționale publicate și conectate.',
            style: figmaBody(color: FigmaFluviTokens.textMuted, size: 8.5),
          ),
        ],
      ),
    );
  }

  Widget _catalogData(WaterAssetDetail detail) {
    final raw = detail.staticData;
    final rows = <(String, String)>[];
    void addNum(String label, String key, String unit, {int decimals = 0}) {
      final value = raw[key];
      final number = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (number == null || !number.isFinite || number <= 0) return;
      rows.add((label, '${number.toStringAsFixed(decimals)} $unit'));
    }

    addNum('Suprafață', 'surface_area_km2', 'km²', decimals: 2);
    addNum('Volum nominal', 'volume_million_m3', 'mil. m³');
    addNum('Înălțime baraj', 'dam_height_m', 'm');
    addNum('Elevație', 'elevation_m', 'm', decimals: 1);
    final year = raw['commissioned_year']?.toString().trim();
    if (year != null && year.isNotEmpty && year != '0' && year != 'null') {
      rows.add(('An punere în funcțiune', year));
    }
    final importance = raw['importance_class']?.toString().trim();
    if (importance != null && importance.isNotEmpty && importance != 'null') {
      rows.add(('Clasă importanță', importance));
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FigmaSectionLabel('Date catalog ANAR'),
          const SizedBox(height: 10),
          for (final row in rows) ...[
            Row(
              children: [
                Expanded(child: Text(row.$1, style: figmaBody(size: 10))),
                Text(
                  row.$2,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          Text(
            'Date descriptive ale obiectivului; nu reprezintă starea curentă a acumulării.',
            style: figmaBody(color: FigmaFluviTokens.textMuted, size: 8.5),
          ),
        ],
      ),
    );
  }

  Widget _linkedAssets(WaterAssetDetail detail) {
    final targetType = detail.ref.type == WaterAssetType.dam
        ? WaterAssetType.reservoir
        : WaterAssetType.dam;
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FigmaSectionLabel(
            targetType == WaterAssetType.dam
                ? 'Baraje asociate'
                : 'Acumulări asociate',
          ),
          const SizedBox(height: 8),
          for (final linked in detail.linkedAssets)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                targetType == WaterAssetType.dam
                    ? Icons.account_balance_rounded
                    : Icons.water_rounded,
                color: FigmaFluviTokens.cyan,
              ),
              title: Text(
                linked['name']?.toString() ?? 'Entitate Water',
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                [
                  if (linked['confidence'] != null)
                    'încredere ${linked['confidence']}',
                  if (linked['review_status'] != null)
                    linked['review_status'].toString(),
                ].join(' · '),
                style: figmaBody(size: 8.5),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: FigmaFluviTokens.textSecondary,
              ),
              onTap: () {
                final id = linked['id']?.toString();
                final lat = _asDouble(linked['latitude']);
                final lng = _asDouble(linked['longitude']);
                if (id == null || lat == null || lng == null) return;
                AppNavigator.open<void>(
                  context,
                  AppDestination.reservoir,
                  arguments: WaterAssetRef(
                    type: targetType,
                    id: id,
                    name: linked['name']?.toString() ?? 'Water',
                    latitude: lat,
                    longitude: lng,
                    riverName: detail.ref.riverName,
                    county: detail.ref.county,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _actions(WaterAssetRef asset) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: FigmaPrimaryButton(
              label: 'Hartă',
              icon: Icons.map_outlined,
              secondary: true,
              onPressed: () => _openMap(asset),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FigmaPrimaryButton(
              label: _saving ? '...' : (_saved ? 'Salvat' : 'Salvează'),
              icon: _saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              secondary: true,
              onPressed: _saving ? null : () => _toggleSaved(asset),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: FigmaPrimaryButton(
              label: 'Alertă',
              icon: Icons.notifications_active_outlined,
              secondary: true,
              onPressed: () => _addAlert(asset),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FigmaPrimaryButton(
              label: 'Raport',
              icon: Icons.add_alert_rounded,
              secondary: true,
              onPressed: _addReport,
            ),
          ),
        ],
      ),
    ],
  );

  String _metricLabel(WaterOperationalMetric metric) => switch (metric.code) {
    'reservoir_level_m' => 'Nivel acumulare',
    'reservoir_volume_million_m3' => 'Volum curent',
    'filling_percent' => 'Grad de umplere',
    'inflow_m3s' => 'Debit afluent',
    'outflow_m3s' => 'Debit evacuat',
    'turbine_flow_m3s' => 'Debit turbinat',
    'spill_flow_m3s' => 'Debit deversat',
    'generation_mw' => 'Producție',
    _ => metric.name?.trim().isNotEmpty == true ? metric.name! : metric.code,
  };

  String _metricValue(WaterOperationalMetric metric) {
    final value = metric.value;
    if (value == null) return '—';
    final decimals = value.abs() < 10 ? 1 : 0;
    final unit = metric.unit?.trim();
    return '${value.toStringAsFixed(decimals)}${unit == null || unit.isEmpty ? '' : ' $unit'}';
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _WaterAssetPageData {
  const _WaterAssetPageData({required this.detail, required this.state});
  final WaterAssetDetail detail;
  final WaterEntityState state;
}

class FigmaHydropowerPage extends ConsumerStatefulWidget {
  const FigmaHydropowerPage({
    super.key,
    this.label,
    this.service = const WaterAssetService(),
    this.savedItemsService = const SavedItemsService(),
  });

  final String? label;
  final WaterAssetService service;
  final SavedItemsService savedItemsService;

  @override
  ConsumerState<FigmaHydropowerPage> createState() =>
      _FigmaHydropowerPageState();
}

class _FigmaHydropowerPageState extends ConsumerState<FigmaHydropowerPage> {
  String? _plantId;
  Future<HydropowerPlantState?>? _future;
  bool _saved = false;
  bool _saving = false;
  bool _openingWater = false;

  void _bindPlant(String plantId) {
    if (!mounted || (_plantId == plantId && _future != null)) return;
    setState(() {
      _plantId = plantId;
      _future = widget.service.getHydropowerPlantState(plantId);
      _saved = false;
    });
    _loadSaved(plantId);
  }

  Future<void> _loadSaved(String plantId) async {
    try {
      final saved = await widget.savedItemsService.isSaved(
        type: 'hydropower',
        referenceId: plantId,
      );
      if (mounted && _plantId == plantId) {
        setState(() => _saved = saved);
      }
    } on Exception {
      // Favorite state is secondary; hydropower truth remains usable.
    }
  }

  Future<void> _toggleSaved(
    HydropowerPlantState state,
    SelectedContext selected,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_saved) {
        await widget.savedItemsService.remove(
          type: 'hydropower',
          referenceId: state.plantId,
        );
      } else {
        await widget.savedItemsService.save(
          type: 'hydropower',
          referenceId: state.plantId,
          title: state.name,
          subtitle: selected.riverName ?? state.sectorName,
          latitude: state.latitude ?? selected.latitude,
          longitude: state.longitude ?? selected.longitude,
          metadata: <String, Object?>{
            'canonical_key': state.canonicalKey,
            'water_body_id': state.waterBodyId,
            'dam_id': state.damId,
            'reservoir_id': state.reservoirId,
            'operator_name': state.operatorName,
            'evidence_class': state.evidenceClass,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        _saved = !_saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _saved ? 'Adăugat în Apele mele.' : 'Eliminat din Apele mele.',
          ),
        ),
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favoritele nu sunt disponibile momentan.'),
        ),
      );
    }
  }

  void _openMap(HydropowerPlantState state, SelectedContext selected) {
    final latitude = state.latitude ?? selected.latitude;
    final longitude = state.longitude ?? selected.longitude;
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordonatele nu sunt disponibile.')),
      );
      return;
    }
    AppNavigator.open<void>(
      context,
      AppDestination.contextualMap,
      arguments: ContextualMapEntry.forTarget(
        source: 'hydropower-detail',
        target: RuntimeMapCameraTarget(
          source: 'hydropower-detail',
          entityId: state.plantId,
          latitude: latitude,
          longitude: longitude,
          zoom: 13.4,
        ),
      ),
    );
  }

  Future<void> _openWater(
    HydropowerPlantState state,
    SelectedContext selected,
  ) async {
    if (_openingWater) return;
    final reservoirId = state.reservoirId;
    final damId = state.damId;
    final type = reservoirId != null
        ? WaterAssetType.reservoir
        : damId != null
        ? WaterAssetType.dam
        : null;
    final entityId = reservoirId ?? damId;
    if (type == null || entityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nu există încă un baraj sau o acumulare asociată acestei hidrocentrale.',
          ),
        ),
      );
      return;
    }

    setState(() => _openingWater = true);
    try {
      final detail = await widget.service.getDetail(
        WaterAssetRef(
          type: type,
          id: entityId,
          name: state.name,
          latitude: state.latitude ?? selected.latitude ?? 0,
          longitude: state.longitude ?? selected.longitude ?? 0,
          waterBodyId: state.waterBodyId ?? selected.waterId,
          riverName: selected.riverName,
        ),
      );
      if (!mounted) return;
      setState(() => _openingWater = false);
      await AppNavigator.open<void>(
        context,
        AppDestination.reservoir,
        arguments: detail.ref,
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _openingWater = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entitatea Water asociată nu este disponibilă momentan.',
          ),
        ),
      );
    }
  }

  void _addReport() {
    AppNavigator.open<void>(context, AppDestination.addReport);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedContextProvider);
    final plantId = selected?.hydropowerPlantId;
    if (plantId == null || plantId.trim().isEmpty) {
      return FigmaCanonicalScaffold(
        key: const ValueKey('figma-hydropower-detail'),
        title: widget.label ?? 'Hidrocentrală',
        eyebrow: 'CONTEXT HIDROTEHNIC',
        child: const FigmaTruthfulEmpty(
          icon: Icons.electric_bolt_rounded,
          title: 'Nicio hidrocentrală selectată',
          message:
              'Selectează o hidrocentrală reală din Hartă. FluviAI nu inventează stări operaționale sau valori de producție.',
        ),
      );
    }

    if (_plantId != plantId || _future == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bindPlant(plantId));
      return FigmaCanonicalScaffold(
        key: const ValueKey('figma-hydropower-detail'),
        title: widget.label ?? selected?.locationName ?? 'Hidrocentrală',
        eyebrow: 'CONTEXT HIDROTEHNIC',
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-hydropower-detail'),
      title: widget.label ?? selected?.locationName ?? 'Hidrocentrală',
      eyebrow: 'CONTEXT HIDROTEHNIC',
      child: FutureBuilder<HydropowerPlantState?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return Column(
              children: [
                const FigmaTruthfulEmpty(
                  icon: Icons.sync_problem_rounded,
                  title: 'Starea hidro nu poate fi încărcată',
                  message:
                      'Entitatea rămâne selectată. Reîncearcă fără a inventa o stare operațională.',
                ),
                const SizedBox(height: 14),
                FigmaPrimaryButton(
                  label: 'Reîncearcă',
                  icon: Icons.refresh_rounded,
                  onPressed: () => setState(
                    () => _future = widget.service.getHydropowerPlantState(
                      plantId,
                    ),
                  ),
                ),
              ],
            );
          }
          final state = snapshot.data;
          if (state == null) {
            return const FigmaTruthfulEmpty(
              icon: Icons.electric_bolt_rounded,
              title: 'Stare operațională indisponibilă',
              message:
                  'Hidrocentrala există în catalog, dar nu există o stare operațională publică verificată pentru acest moment.',
            );
          }
          return ListView(
            children: [
              _identity(state, selected!),
              const SizedBox(height: 12),
              _stateCard(state),
              const SizedBox(height: 12),
              _evidenceCard(state),
              const SizedBox(height: 12),
              _actions(state, selected),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _identity(HydropowerPlantState state, SelectedContext selected) =>
      FigmaSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.electric_bolt_rounded,
                  color: FigmaFluviTokens.amber,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.name,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (selected.riverName?.isNotEmpty == true)
                            selected.riverName!,
                          if (state.sectorName?.isNotEmpty == true)
                            state.sectorName!,
                        ].join(' · '),
                        style: figmaBody(size: 10),
                      ),
                    ],
                  ),
                ),
                const _TinyStatusPill(
                  label: 'HIDRO',
                  color: FigmaFluviTokens.amber,
                ),
              ],
            ),
            if (state.operatorName?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                state.operatorName!,
                style: figmaBody(
                  color: FigmaFluviTokens.textSecondary,
                  size: 9.5,
                ),
              ),
            ],
            if (state.installedPowerMw != null && state.installedPowerMw! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Putere instalată (catalog): '
                  '${state.installedPowerMw!.toStringAsFixed(1)} MW',
                  style: figmaBody(color: FigmaFluviTokens.textMuted, size: 9),
                ),
              ),
          ],
        ),
      );

  Widget _stateCard(HydropowerPlantState state) {
    final operationLabel = switch (state.operationState) {
      'ACTIVE' => 'Activă',
      'INACTIVE' => 'Inactivă',
      'POSSIBLE_ACTIVE' => 'Posibil activă',
      _ => 'Necunoscută',
    };
    final evidenceLabel = switch (state.evidenceClass) {
      'MEASURED' => 'MĂSURAT',
      'DERIVED' => 'CALCULAT',
      'ESTIMATED' => 'ML ESTIMAT',
      'OBSERVED' => 'OBSERVAT',
      _ => 'NECUNOSCUT',
    };
    final freshnessLabel = switch (state.freshnessStatus) {
      'fresh' => 'ACTUAL',
      'recent' => 'RECENT',
      'stale' => 'VECHI',
      _ => 'FĂRĂ DATE',
    };
    final operationColor = switch (state.operationState) {
      'ACTIVE' => FigmaFluviTokens.green,
      'POSSIBLE_ACTIVE' => FigmaFluviTokens.amber,
      _ => FigmaFluviTokens.textMuted,
    };
    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: FigmaSectionLabel('Stare operațională')),
              _TinyStatusPill(label: evidenceLabel, color: operationColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.power_rounded, color: operationColor, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  operationLabel,
                  style: TextStyle(
                    color: operationColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (state.confidence > 0)
                Text(
                  '${(state.confidence * 100).round()}% încredere',
                  style: figmaBody(size: 9),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyStatusPill(
                label: freshnessLabel,
                color: FigmaFluviTokens.textSecondary,
              ),
              if (state.communityReportCount > 0)
                _TinyStatusPill(
                  label: '${state.communityReportCount} RAPOARTE',
                  color: FigmaFluviTokens.violet,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _evidenceCard(HydropowerPlantState state) {
    if (state.evidenceClass == 'UNKNOWN') {
      return const FigmaTruthfulEmpty(
        icon: Icons.query_stats_rounded,
        title: 'Fără dovadă operațională curentă',
        message:
            'FluviAI păstrează starea UNKNOWN până când există o observație măsurată, calculată, estimată explicit sau o observație comunitară etichetată.',
      );
    }

    final rows = <(String, String)>[];
    rows.add(('Clasă dovadă', _evidenceClassLabel(state.evidenceClass)));
    rows.add(('Sursă', _evidenceSourceLabel(state.evidenceSource)));
    if (state.evidenceObservedAt != null) {
      final text = state.evidenceObservedAt!
          .toLocal()
          .toIso8601String()
          .replaceFirst('T', ' ');
      rows.add(('Observat', text.substring(0, 16)));
    }
    final metricValue = _operationalEvidenceValue(state);
    if (metricValue != null) {
      rows.add(('Dovadă operațională', metricValue));
    }
    if (state.evidenceClass == 'OBSERVED' &&
        state.communityOperationSignal != 'unknown') {
      rows.add((
        'Semnal comunitate',
        _communitySignalLabel(state.communityOperationSignal),
      ));
    }

    return FigmaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FigmaSectionLabel('Dovadă și proveniență'),
          const SizedBox(height: 10),
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 126,
                  child: Text(row.$1, style: figmaBody(size: 9)),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: FigmaFluviTokens.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          Text(
            'MEASURED / DERIVED / ESTIMATED / OBSERVED sunt păstrate separat. '
            'O observație comunitară nu devine valoare oficială.',
            style: figmaBody(color: FigmaFluviTokens.textMuted, size: 8.5),
          ),
        ],
      ),
    );
  }

  Widget _actions(HydropowerPlantState state, SelectedContext selected) =>
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FigmaPrimaryButton(
                  label: 'Hartă',
                  icon: Icons.map_outlined,
                  secondary: true,
                  onPressed: () => _openMap(state, selected),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FigmaPrimaryButton(
                  label: _saving ? '...' : (_saved ? 'Salvat' : 'Salvează'),
                  icon: _saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  secondary: true,
                  onPressed: _saving
                      ? null
                      : () => _toggleSaved(state, selected),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FigmaPrimaryButton(
                  label: _openingWater ? '...' : 'Water',
                  icon: Icons.water_rounded,
                  secondary: true,
                  onPressed: _openingWater
                      ? null
                      : () => _openWater(state, selected),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FigmaPrimaryButton(
                  label: 'Raport',
                  icon: Icons.add_alert_rounded,
                  secondary: true,
                  onPressed: _addReport,
                ),
              ),
            ],
          ),
        ],
      );

  String _evidenceClassLabel(String value) => switch (value) {
    'MEASURED' => 'Măsurat',
    'DERIVED' => 'Calculat',
    'ESTIMATED' => 'ML estimat',
    'OBSERVED' => 'Observat în comunitate',
    _ => 'Necunoscut',
  };

  String _evidenceSourceLabel(String value) => switch (value) {
    'official_measured' => 'Sursă oficială măsurată',
    'calculated_from_operational_data' => 'Calcul din date operaționale',
    'model_estimated' => 'Model estimativ',
    'community_observed' => 'Observație comunitară',
    _ => 'Indisponibilă',
  };

  String _communitySignalLabel(String value) => switch (value) {
    'possible_turbining' => 'Posibilă turbinare',
    'possible_release' => 'Posibilă evacuare',
    'possible_spill' => 'Posibil deversor activ',
    _ => 'Necunoscut',
  };

  String? _operationalEvidenceValue(HydropowerPlantState state) {
    final metric = state.evidenceMetric;
    final value = state.evidenceValue;
    if (metric == null || value == null) return null;
    if (metric == 'hydropower_operation_state' ||
        metric == 'hydropower_generation_active') {
      return value > 0 ? 'Activă' : 'Inactivă';
    }
    final unit = state.evidenceUnit?.trim();
    final decimals = value.abs() < 10 ? 1 : 0;
    return '${value.toStringAsFixed(decimals)}'
        '${unit == null || unit.isEmpty ? '' : ' $unit'}';
  }
}
