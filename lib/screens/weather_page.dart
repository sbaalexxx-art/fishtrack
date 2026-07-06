import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/weather.dart';
import '../services/astronomy_service.dart';
import '../services/weather_service.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _service = WeatherService();
  late Future<_WeatherViewData> _weather;

  @override
  void initState() {
    super.initState();
    _weather = _load();
  }

  Future<_WeatherViewData> _load() async {
    final values = await Future.wait([
      _service.getCurrentWeather(),
      _service.getAstronomyContext(),
    ]);
    return _WeatherViewData(
      weather: values[0] as WeatherData,
      astronomy: values[1] as AstronomyContext,
    );
  }

  Future<void> _refresh() async {
    final weather = _load();
    setState(() => _weather = weather);
    await weather;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(context.l10n.weather)),
      body: SafeArea(
        child: FutureBuilder<_WeatherViewData>(
          future: _weather,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _WeatherMessage(onRetry: _refresh);
            }
            return _WeatherContent(
              weather: snapshot.data!.weather,
              astronomy: snapshot.data!.astronomy,
              onRefresh: _refresh,
            );
          },
        ),
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({
    required this.weather,
    required this.astronomy,
    required this.onRefresh,
  });

  final WeatherData weather;
  final AstronomyContext astronomy;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          Card(
            color: const Color(0xFF17324A),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.wb_sunny_rounded,
                    color: Colors.orange,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${weather.temperature.round()}°C',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    weather.condition,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                  if (weather.feelsLike != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Feels like ${weather.feelsLike!.round()}°C',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                _metric(
                  Icons.water_drop_outlined,
                  'Humidity',
                  _value(weather.humidity, suffix: '%'),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.air_rounded,
                  'Wind speed',
                  _value(weather.windSpeed, suffix: ' km/h', decimals: 1),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.explore_outlined,
                  'Wind direction',
                  _windDirection(
                    weather.windDirectionDegrees,
                    weather.windDirectionLabel,
                  ),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.air_rounded,
                  'Wind gusts',
                  _value(weather.windGusts, suffix: ' km/h', decimals: 1),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.umbrella_outlined,
                  'Precipitation probability',
                  _value(weather.precipitationProbability, suffix: '%'),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.cloud_outlined,
                  'Cloud cover',
                  _value(weather.cloudCover, suffix: '%'),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.speed_rounded,
                  'Pressure',
                  _value(weather.pressure, suffix: ' hPa'),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.schedule_rounded,
                  'Last updated',
                  _time(context, weather.observedAt),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Next 24 hours',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (weather.hourlyForecast.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No data'),
              ),
            )
          else
            SizedBox(
              height: 174,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: weather.hourlyForecast.take(24).length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final hour = weather.hourlyForecast[index];
                  return SizedBox(
                    width: 166,
                    child: Card(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _time(context, hour.time),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Temperature: '
                              '${_value(hour.temperature, suffix: '°C')}',
                            ),
                            Text(
                              'Wind: '
                              '${_value(hour.windSpeed, suffix: ' km/h', decimals: 1)}',
                            ),
                            Text(
                              'Direction: '
                              '${_windDirection(hour.windDirectionDegrees, hour.windDirectionLabel)}',
                            ),
                            Text(
                              'Precipitation: '
                              '${_value(hour.precipitationProbability, suffix: '%')}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '3-day forecast',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...weather.forecast
              .take(3)
              .map(
                (day) => Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_today_rounded,
                      color: Color(0xFF1565C0),
                    ),
                    title: Text(_dayLabel(day.date)),
                    subtitle: Text(day.condition),
                    trailing: Text(
                      '${day.minimumTemperature.round()}° / ${day.maximumTemperature.round()}°',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                _metric(
                  Icons.wb_twilight_rounded,
                  'Sunrise',
                  weather.sunrise == null
                      ? 'No data'
                      : _time(context, weather.sunrise!),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.nights_stay_rounded,
                  'Sunset',
                  weather.sunset == null
                      ? 'No data'
                      : _time(context, weather.sunset!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF26334A),
            child: ListTile(
              leading: const Icon(
                Icons.dark_mode_rounded,
                color: Color(0xFFE0E7FF),
              ),
              title: Text(
                '${astronomy.moon.name} • '
                '${astronomy.moon.illuminationPercent.round()}% illuminated',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Moon age ${astronomy.moon.ageDays.toStringAsFixed(1)} days',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              leading: const Icon(Icons.wb_twilight_rounded),
              title: Text(context.l10n.goldenHour),
              subtitle: Text(_goldenHourLabel(astronomy)),
            ),
          ),
        ],
      ),
    );
  }

  static ListTile _metric(IconData icon, String label, String value) =>
      ListTile(
        leading: Icon(icon, color: const Color(0xFF1565C0)),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );

  static String _time(BuildContext context, DateTime dateTime) =>
      TimeOfDay.fromDateTime(dateTime.toLocal()).format(context);

  static String _value(
    double? value, {
    required String suffix,
    int decimals = 0,
  }) {
    if (value == null || !value.isFinite) return 'No data';
    return '${value.toStringAsFixed(decimals)}$suffix';
  }

  static String _windDirection(double? degrees, String label) {
    if (degrees == null || !degrees.isFinite || label.isEmpty) return 'No data';
    return '$label (${degrees.round()}°)';
  }

  static String _dayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  static String _goldenHourLabel(AstronomyContext context) {
    final golden = context.goldenHour;
    if (context.availability == AstronomyAvailability.locationRequired) {
      return 'Location required';
    }
    if (context.availability == AstronomyAvailability.notAvailable ||
        golden == null) {
      return 'Not available';
    }
    return '${_clock(golden.morningStart)}–${_clock(golden.morningEnd)} or '
        '${_clock(golden.eveningStart)}–${_clock(golden.eveningEnd)}';
  }

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _WeatherViewData {
  const _WeatherViewData({required this.weather, required this.astronomy});
  final WeatherData weather;
  final AstronomyContext astronomy;
}

class _WeatherMessage extends StatelessWidget {
  const _WeatherMessage({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 12),
        Text(context.l10n.weatherUnavailable),
        TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
}
