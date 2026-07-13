import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../models/weather.dart';
import '../../services/weather_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

class WeatherCardPremium extends StatefulWidget {
  const WeatherCardPremium({super.key, this.fallbackStation});

  final Station? fallbackStation;

  @override
  State<WeatherCardPremium> createState() => _WeatherCardPremiumState();
}

class _WeatherCardPremiumState extends State<WeatherCardPremium> {
  final WeatherService _weatherService = WeatherService();
  late Future<WeatherHomeResult> _weatherFuture;

  @override
  void initState() {
    super.initState();
    _weatherFuture = _loadWeather();
  }

  @override
  void didUpdateWidget(covariant WeatherCardPremium oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fallbackStation?.id != widget.fallbackStation?.id) {
      _weatherFuture = _loadWeather();
    }
  }

  Future<WeatherHomeResult> _loadWeather() {
    return _weatherService.getHomeWeatherResult(
      fallbackStation: widget.fallbackStation,
    );
  }

  String _localizedCondition(BuildContext context, String? condition) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';

    final value = condition?.trim();
    if (value == null || value.isEmpty) {
      return context.l10n.loadingEllipsis;
    }

    if (!isRo) {
      return value;
    }

    switch (value.toLowerCase()) {
      case 'clear sky':
        return 'Cer senin';
      case 'partly cloudy':
        return 'Parțial înnorat';
      case 'overcast':
        return 'Cer acoperit';
      case 'fog':
        return 'Ceață';
      case 'drizzle':
        return 'Burniță';
      case 'rain':
        return 'Ploaie';
      case 'snow':
        return 'Ninsoare';
      case 'rain showers':
        return 'Averse de ploaie';
      case 'snow showers':
        return 'Averse de ninsoare';
      case 'thunderstorm':
        return 'Furtună';
      case 'unknown':
        return 'Necunoscut';
      default:
        return value;
    }
  }

  String _localizedWindDirection(BuildContext context, String value) {
    if (Localizations.localeOf(context).languageCode != 'ro') return value;
    return switch (value.trim().toUpperCase()) {
      'SW' => 'SV',
      'W' => 'V',
      'NW' => 'NV',
      _ => value,
    };
  }

  String _unavailableLabel(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ro'
      ? 'Indisponibil'
      : 'Unavailable';

  String _pressureLabel(BuildContext context, double? pressure) {
    if (pressure == null || !pressure.isFinite) {
      return _unavailableLabel(context);
    }
    return '${pressure.round()} hPa';
  }

  String _solunarLabel(BuildContext context, FishingActivity? value) {
    if (value == null) return _unavailableLabel(context);
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    return switch (value) {
      FishingActivity.excellent => isRo ? 'Excelent' : 'Excellent',
      FishingActivity.good => isRo ? 'Bun' : 'Good',
      FishingActivity.fair => isRo ? 'Acceptabil' : 'Fair',
      FishingActivity.poor => isRo ? 'Slab' : 'Poor',
    };
  }

  // TODO(l10n): Move beta availability labels into ARB.
  String _availabilityLabel(
    BuildContext context,
    WeatherHomeStatus? status, {
    required bool hasSnapshotError,
  }) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    if (hasSnapshotError) {
      return isRo
          ? 'Date meteo temporar indisponibile'
          : 'Weather data temporarily unavailable';
    }
    return switch (status) {
      WeatherHomeStatus.providerError =>
        isRo
            ? 'Date meteo temporar indisponibile'
            : 'Weather data temporarily unavailable',
      WeatherHomeStatus.locationUnavailable =>
        isRo ? 'Loca\u021bie indisponibil\u0103' : 'Location unavailable',
      WeatherHomeStatus.unavailable ||
      null => isRo ? 'Date meteo indisponibile' : 'Weather data unavailable',
      WeatherHomeStatus.available || WeatherHomeStatus.staleFallback => '',
    };
  }

  String? _contextLabel(BuildContext context, WeatherHomeResult result) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final labels = <String>[];
    if (result.status == WeatherHomeStatus.staleFallback) {
      labels.add(isRo ? 'Date vechi' : 'Stale data');
    }
    if (result.locationSource == WeatherLocationSource.stationFallback ||
        result.locationSource == WeatherLocationSource.defaultFallback) {
      labels.add(isRo ? 'Loca\u021bie estimat\u0103' : 'Estimated location');
    }
    return labels.isEmpty ? null : labels.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherHomeResult>(
      future: _weatherFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final weather = result?.data;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            result == null;
        final temperature = weather == null
            ? null
            : '${weather.temperature.round()}\u00b0';
        final neutralValue = isLoading
            ? context.l10n.loadingEllipsis
            : _unavailableLabel(context);
        final conditionLabel = isLoading
            ? context.l10n.loadingEllipsis
            : weather != null
            ? _localizedCondition(context, weather.condition)
            : _availabilityLabel(
                context,
                result?.status,
                hasSnapshotError: snapshot.hasError,
              );
        final contextLabel = weather == null || result == null
            ? null
            : _contextLabel(context, result);
        final condition = contextLabel == null
            ? conditionLabel
            : '$conditionLabel\n$contextLabel';
        final humidity = weather == null
            ? neutralValue
            : '${weather.humidity.round()}%';
        final windSpeed = weather == null
            ? null
            : '${weather.windSpeed.toStringAsFixed(1)} km/h';
        final windDirection = weather == null
            ? null
            : _localizedWindDirection(context, weather.windDirectionLabel);
        final wind = windSpeed == null || windDirection == null
            ? neutralValue
            : '$windSpeed $windDirection';
        final pressure = weather == null
            ? neutralValue
            : _pressureLabel(context, weather.pressure);
        final precipitation = weather == null
            ? neutralValue
            : weather.precipitationProbability.isFinite
            ? '${weather.precipitationProbability.round()}%'
            : _unavailableLabel(context);
        final solunar = _solunarLabel(context, weather?.fishingActivity);

        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = HomePremiumLayout.of(context);
              final dense = constraints.maxWidth < 360;

              return Container(
                padding: EdgeInsets.all(
                  layout.isSmallPhone ? 8 : (layout.isTablet ? 12 : 10),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2216),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: dense ? 3 : 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.wb_sunny_rounded,
                                color: const Color(0xFFFFB300),
                                size: 18 * layout.iconScale,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  context.l10n.weather.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14 * layout.titleFontScale,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (temperature != null) ...[
                            Text(
                              temperature,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize:
                                    (dense ? 26 : 30) * layout.titleFontScale,
                                height: 1,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            condition,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dense ? 6 : 10),
                    Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    SizedBox(width: dense ? 6 : 10),
                    Expanded(
                      flex: dense ? 7 : 8,
                      child: LayoutBuilder(
                        builder: (context, metricConstraints) {
                          final spacing = dense ? 4.0 : 6.0;
                          final columns = metricConstraints.maxWidth >= 480
                              ? 5
                              : 3;
                          final metricWidth =
                              (metricConstraints.maxWidth -
                                  (spacing * (columns - 1))) /
                              columns;
                          final metrics = [
                            _WeatherMetric(
                              icon: Icons.air_rounded,
                              label: context.l10n.wind,
                              value: wind,
                              dense: dense,
                            ),
                            _WeatherMetric(
                              icon: Icons.speed_rounded,
                              label: context.l10n.pressure,
                              value: pressure,
                              dense: dense,
                            ),
                            _WeatherMetric(
                              icon: Icons.umbrella_outlined,
                              label: context.l10n.precipitation,
                              value: precipitation,
                              dense: dense,
                            ),
                            _WeatherMetric(
                              icon: Icons.water_drop_outlined,
                              label: context.l10n.humidity,
                              value: humidity,
                              dense: dense,
                            ),
                            _WeatherMetric(
                              icon: Icons.nights_stay_outlined,
                              label: 'Solunar',
                              value: solunar,
                              dense: dense,
                            ),
                          ];

                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: spacing,
                              runSpacing: dense ? 4 : 6,
                              children: [
                                for (final metric in metrics)
                                  SizedBox(width: metricWidth, child: metric),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.dense,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: dense ? 13 : 15),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white54,
                  fontSize: dense ? 8 : 9,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontSize: dense ? 9 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
