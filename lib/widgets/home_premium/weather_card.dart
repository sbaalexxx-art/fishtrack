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
  late Future<WeatherData> _weatherFuture;

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

  Future<WeatherData> _loadWeather() {
    return _weatherService.getCurrentWeather(
      fallbackStation: widget.fallbackStation,
    );
  }

  String _localizedCondition(
    BuildContext context, {
    required bool hasError,
    required String? condition,
  }) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';

    if (hasError) {
      return isRo
          ? 'Nu se pot actualiza datele acum'
          : 'Unable to update data right now';
    }

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

  String _timeLabel(BuildContext context, DateTime? value) {
    if (value == null) return _unavailableLabel(context);
    return TimeOfDay.fromDateTime(value.toLocal()).format(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherData>(
      future: _weatherFuture,
      builder: (context, snapshot) {
        final weather = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final temperature = weather == null
            ? '--'
            : weather.temperature.round().toString();
        final condition = _localizedCondition(
          context,
          hasError: snapshot.hasError,
          condition: weather?.condition,
        );
        final humidity = weather == null
            ? '--'
            : '${weather.humidity.round()}%';
        final windSpeed = weather == null
            ? '--'
            : '${weather.windSpeed.toStringAsFixed(1)} km/h';
        final windDirection = weather == null
            ? '--'
            : _localizedWindDirection(context, weather.windDirectionLabel);
        final wind = weather == null ? '--' : '$windSpeed $windDirection';
        final pressure = _pressureLabel(context, weather?.pressure);
        final precipitation = weather == null
            ? '--'
            : weather.precipitationProbability.isFinite
            ? '${weather.precipitationProbability.round()}%'
            : _unavailableLabel(context);
        final sunrise = _timeLabel(context, weather?.sunrise);
        final sunset = _timeLabel(context, weather?.sunset);

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wb_sunny_rounded,
                          color: const Color(0xFFFFB300),
                          size: 20 * layout.iconScale,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.weather.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16 * layout.titleFontScale,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: dense ? 3 : 4,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.wb_sunny_rounded,
                                  size: dense ? 28 : 38,
                                  color: const Color(0xFFFFC107),
                                ),
                                SizedBox(width: dense ? 6 : 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$temperature°',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize:
                                              (dense ? 23 : 30) *
                                              layout.titleFontScale,
                                          height: 1,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        condition,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: dense ? 6 : 12),
                          Expanded(
                            flex: dense ? 4 : 5,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _WeatherMetric(
                                        icon: Icons.air_rounded,
                                        label: context.l10n.wind,
                                        value: wind,
                                        dense: dense,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _WeatherMetric(
                                        icon: Icons.speed_rounded,
                                        label: context.l10n.pressure,
                                        value: pressure,
                                        dense: dense,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _WeatherMetric(
                                        icon: Icons.water_drop_outlined,
                                        label: context.l10n.humidity,
                                        value: humidity,
                                        dense: dense,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _WeatherMetric(
                                        icon: Icons.umbrella_outlined,
                                        label: context.l10n.precipitation,
                                        value: precipitation,
                                        dense: dense,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _WeatherMetric(
                            icon: Icons.wb_twilight_rounded,
                            label: context.l10n.sunrise,
                            value: sunrise,
                            dense: dense,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _WeatherMetric(
                            icon: Icons.nights_stay_outlined,
                            label: context.l10n.sunset,
                            value: sunset,
                            dense: dense,
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
