import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../models/station.dart';
import '../../models/weather.dart';
import '../../services/weather_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherData>(
      future: _weatherFuture,
      builder: (context, snapshot) {
        final weather = snapshot.data;
        final temperature = weather == null
            ? '--'
            : weather.temperature.round().toString();
        final condition = snapshot.hasError
            ? 'Weather unavailable'
            : weather?.condition ?? 'Loading...';
        final humidity = weather == null
            ? '--'
            : '${weather.humidity.round()}%';
        final wind = weather == null
            ? '--'
            : '${weather.windSpeed.toStringAsFixed(1)} km/h';

        return LayoutBuilder(
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
                          'WEATHER',
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
                                    (compact ? 26 : 32) * layout.titleFontScale,
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
