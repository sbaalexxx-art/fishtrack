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
        final wind = weather == null
            ? '--'
            : '${weather.windSpeed.toStringAsFixed(1)} km/h';

        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = HomePremiumLayout.of(context);
              final compact = constraints.maxWidth < 180;

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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.wb_sunny_rounded,
                          size: compact ? 32 : 40,
                          color: const Color(0xFFFFC107),
                        ),
                        SizedBox(width: compact ? 8 : 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$temperature°',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize:
                                      (compact ? 26 : 32) *
                                      layout.titleFontScale,
                                  height: 1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                condition,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: _WeatherMetric(
                            icon: Icons.water_drop_outlined,
                            value: humidity,
                            compact: compact,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _WeatherMetric(
                            icon: Icons.air,
                            value: wind,
                            compact: compact,
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
    required this.value,
    required this.compact,
  });

  final IconData icon;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 15),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: compact ? 11 : 13),
          ),
        ),
      ],
    );
  }
}
