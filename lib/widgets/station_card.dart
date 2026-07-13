import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/station.dart';
import '../models/water_level.dart';
import '../services/water_service.dart';

class StationCard extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;
  final WaterUiResult? waterResult;

  const StationCard({
    super.key,
    required this.station,
    required this.onTap,
    this.waterResult,
  });

  static Color _trendColor(WaterTrend trend) {
    switch (trend) {
      case WaterTrend.rising:
        return Colors.blue;

      case WaterTrend.falling:
        return Colors.red;

      case WaterTrend.stable:
        return Colors.green;
    }
  }

  static IconData _trendIcon(WaterTrend trend) {
    switch (trend) {
      case WaterTrend.rising:
        return Icons.trending_up;

      case WaterTrend.falling:
        return Icons.trending_down;

      case WaterTrend.stable:
        return Icons.trending_flat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canonicalReading = waterResult?.latestReading;
    final usesCanonicalResult = waterResult != null;
    final hasReading = usesCanonicalResult
        ? canonicalReading != null
        : station.hasWaterLevel;
    final value = canonicalReading?.value ?? station.level;
    final unit = canonicalReading?.unit ?? station.waterLevelUnit;
    final trend = canonicalReading?.trend ?? station.trend;
    final hasKnownTrend = usesCanonicalResult
        ? canonicalReading?.hasKnownTrend == true
        : station.hasKnownTrend;
    final trendColor = hasKnownTrend ? _trendColor(trend) : Colors.grey;
    final source = usesCanonicalResult ? waterResult?.source : null;
    final freshness = usesCanonicalResult && hasReading
        ? _freshnessLabel(context, waterResult!)
        : null;
    final updateUnavailable =
        usesCanonicalResult &&
        hasReading &&
        waterResult?.status == WaterUiStatus.providerError;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,
        isThreeLine: usesCanonicalResult && hasReading,

        leading: const CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(Icons.water_drop, color: Colors.white),
        ),

        title: Text(
          station.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),

        subtitle: hasReading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasKnownTrend
                            ? _trendIcon(trend)
                            : Icons.help_outline_rounded,
                        color: trendColor,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          hasKnownTrend
                              ? _trendLabel(context, trend)
                              : context.l10n.unknown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: trendColor),
                        ),
                      ),
                    ],
                  ),
                  if (usesCanonicalResult &&
                      source != null &&
                      freshness != null)
                    Text(
                      '${_sourceLabel(source)} \u2022 $freshness',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  if (updateUnavailable)
                    Text(
                      _updateUnavailableLabel(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 11,
                      ),
                    ),
                ],
              )
            : Text(context.l10n.noData),

        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              hasReading
                  ? '${value.toStringAsFixed(0)} $unit'
                  : context.l10n.noData,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  static String _trendLabel(BuildContext context, WaterTrend trend) =>
      switch (trend) {
        WaterTrend.rising => context.l10n.rising,
        WaterTrend.falling => context.l10n.falling,
        WaterTrend.stable => context.l10n.stable,
      };

  static String _sourceLabel(WaterLevelSource source) => switch (source) {
    WaterLevelSource.afdj => 'AFDJ',
    WaterLevelSource.danubeHis => 'DanubeHIS',
    WaterLevelSource.danubeFis => 'DanubeFIS',
    WaterLevelSource.inhga => 'INHGA',
    WaterLevelSource.manualFallback => 'Manual',
  };

  static String _freshnessLabel(BuildContext context, WaterUiResult result) {
    final timestamp = result.measurementTimestamp;
    if (timestamp == null || timestamp.millisecondsSinceEpoch <= 0) {
      return context.l10n.updateTimeUnavailable;
    }
    final measuredAge =
        result.dataAge ?? DateTime.now().difference(timestamp.toLocal());
    final age = measuredAge.isNegative ? Duration.zero : measuredAge;
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    if (age.inMinutes < 1) return isRo ? 'Acum' : 'Now';

    final ageLabel = _compactAgeLabel(age, isRo: isRo);
    if (result.isStale) {
      return isRo ? 'Vechi \u2022 $ageLabel' : 'Stale \u2022 $ageLabel';
    }
    return isRo ? 'Acum $ageLabel' : '$ageLabel ago';
  }

  static String _compactAgeLabel(Duration age, {required bool isRo}) {
    if (age.inMinutes < 60) {
      final value = age.inMinutes;
      if (!isRo) return '$value ${value == 1 ? 'minute' : 'minutes'}';
      return '$value ${value == 1 ? 'minut' : 'minute'}';
    }
    if (age.inHours < 24) {
      final value = age.inHours;
      if (!isRo) return '$value ${value == 1 ? 'hour' : 'hours'}';
      return '$value ${value == 1 ? 'or\u0103' : 'ore'}';
    }
    final value = age.inDays;
    if (!isRo) return '$value ${value == 1 ? 'day' : 'days'}';
    return '$value ${value == 1 ? 'zi' : 'zile'}';
  }

  static String _updateUnavailableLabel(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ro'
      ? 'Actualizare temporar indisponibil\u0103'
      : 'Update temporarily unavailable';
}
