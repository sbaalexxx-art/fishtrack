import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../models/weather.dart';
import '../../services/weather_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

class WeatherCardPremium extends StatefulWidget {
  const WeatherCardPremium({
    super.key,
    required this.layout,
    this.fallbackStation,
  });

  final HomePremiumLayout layout;
  final Station? fallbackStation;

  @override
  State<WeatherCardPremium> createState() => _WeatherCardPremiumState();
}

class _WeatherCardPremiumState extends State<WeatherCardPremium> {
  static const _missingValue = '\u2014';

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

  String _pressureLabel(double? pressure) {
    if (pressure == null || !pressure.isFinite) {
      return _missingValue;
    }
    return '${pressure.round()} hPa';
  }

  String _solunarLabel(BuildContext context, FishingActivity? value) {
    if (value == null) return _missingValue;
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    return switch (value) {
      FishingActivity.excellent => isRo ? 'Excelent' : 'Excellent',
      FishingActivity.good => isRo ? 'Bun' : 'Good',
      FishingActivity.fair => isRo ? 'Acceptabil' : 'Fair',
      FishingActivity.poor => isRo ? 'Slab' : 'Poor',
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
            : _missingValue;
        final conditionLabel = isLoading
            ? context.l10n.loadingEllipsis
            : weather != null
            ? _localizedCondition(context, weather.condition)
            : _missingValue;
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
            : _pressureLabel(weather.pressure);
        final precipitation = weather == null
            ? neutralValue
            : weather.precipitationProbability.isFinite
            ? '${weather.precipitationProbability.round()}%'
            : _missingValue;
        final solunar = _solunarLabel(context, weather?.fishingActivity);

        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = widget.layout;
              final dense =
                  constraints.maxWidth < 360 ||
                  constraints.maxHeight < layout.weatherCardHeight * .95;
              final cardPadding = layout.isSmallPhone
                  ? 8.0
                  : (layout.isTablet ? 11.0 : 9.0);
              final metrics = [
                _WeatherMetric(
                  icon: Icons.thermostat_rounded,
                  label: context.l10n.weatherHomeDegrees,
                  value: temperature ?? neutralValue,
                  secondaryValue: condition,
                  accentColor: const Color(0xFFFFC84A),
                  dense: dense,
                ),
                _WeatherMetric(
                  icon: Icons.air_rounded,
                  label: context.l10n.wind,
                  value: wind,
                  accentColor: const Color(0xFF62D7F5),
                  dense: dense,
                ),
                _WeatherMetric(
                  icon: Icons.speed_rounded,
                  label: context.l10n.pressure,
                  value: pressure,
                  accentColor: const Color(0xFFA4D96C),
                  dense: dense,
                ),
                _WeatherMetric(
                  icon: Icons.water_drop_outlined,
                  label: context.l10n.humidity,
                  value: humidity,
                  accentColor: const Color(0xFF54B9FF),
                  dense: dense,
                ),
                _WeatherMetric(
                  icon: Icons.umbrella_outlined,
                  label: context.l10n.weatherHomeRain,
                  value: precipitation,
                  accentColor: const Color(0xFF7EA8FF),
                  dense: dense,
                ),
                _WeatherMetric(
                  icon: Icons.nights_stay_outlined,
                  label: context.l10n.solunar,
                  value: solunar,
                  accentColor: const Color(0xFFBE9AF7),
                  dense: dense,
                ),
              ];

              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: cardPadding,
                  vertical: cardPadding * .76,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF102630), Color(0xFF071821)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF39C6E6).withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF12D8D6).withValues(alpha: 0.06),
                      blurRadius: 18,
                      spreadRadius: -8,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: dense ? 24 : 28,
                          height: dense ? 24 : 28,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFC84A,
                            ).withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFFFFC84A,
                              ).withValues(alpha: 0.46),
                            ),
                          ),
                          child: Icon(
                            Icons.wb_sunny_rounded,
                            color: const Color(0xFFFFC84A),
                            size: (dense ? 14 : 16) * layout.iconScale,
                          ),
                        ),
                        SizedBox(width: dense ? 6 : 8),
                        Text(
                          context.l10n.weather.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFF4FCFF),
                            fontWeight: FontWeight.w800,
                            fontSize:
                                (dense ? 13.5 : 15.5) * layout.titleFontScale,
                            letterSpacing: 0.4,
                          ),
                        ),
                        SizedBox(width: dense ? 8 : 10),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: const Color(
                              0xFF62D7F5,
                            ).withValues(alpha: 0.18),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: dense ? 4 : 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < metrics.length;
                            index++
                          ) ...[
                            Expanded(child: metrics[index]),
                            if (index != metrics.length - 1)
                              SizedBox(width: dense ? 2 : 3),
                          ],
                        ],
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
    required this.accentColor,
    required this.dense,
    this.secondaryValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? secondaryValue;
  final Color accentColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final separator = value.indexOf(' ');
    final primaryValue = separator == -1
        ? value
        : value.substring(0, separator);
    final suffix = separator == -1 ? null : value.substring(separator + 1);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 3 : 4,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.18),
            const Color(0xFF12303B).withValues(alpha: 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.04),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: dense ? 20 : 22,
            height: dense ? 20 : 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accentColor.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: accentColor, size: dense ? 15 : 16),
          ),
          SizedBox(height: dense ? 2 : 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: Color.lerp(const Color(0xFFDCECF1), accentColor, 0.18),
              fontSize: (dense ? 9.5 : 11.5) * layout.bodyFontScale,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: primaryValue,
                      style: AppTextStyles.caption.copyWith(
                        color: const Color(0xFFFFFFFF),
                        fontSize: (dense ? 15 : 18) * layout.bodyFontScale,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (suffix != null)
                      TextSpan(
                        text: ' $suffix',
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFFDCECF1),
                          fontSize: (dense ? 9.5 : 10.5) * layout.bodyFontScale,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
          if (secondaryValue case final secondary?) ...[
            const SizedBox(height: 1),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: Color.lerp(const Color(0xFFDCECF1), accentColor, 0.25),
                fontSize: (dense ? 8.5 : 10.5) * layout.bodyFontScale,
                height: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
