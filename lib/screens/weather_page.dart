import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../services/weather_service.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _service = WeatherService();
  late Future<WeatherData> _weather;

  @override
  void initState() {
    super.initState();
    _weather = _service.getCurrentWeather();
  }

  Future<void> _refresh() async {
    final weather = _service.getCurrentWeather();
    setState(() => _weather = weather);
    await weather;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(title: const Text('Weather')),
      body: SafeArea(
        child: FutureBuilder<WeatherData>(
          future: _weather,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _WeatherMessage(onRetry: _refresh);
            }
            return _WeatherContent(
              weather: snapshot.data!,
              onRefresh: _refresh,
            );
          },
        ),
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.weather, required this.onRefresh});

  final WeatherData weather;
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
            color: Colors.white,
            child: Column(
              children: [
                _metric(
                  Icons.water_drop_outlined,
                  'Humidity',
                  '${weather.humidity.round()}%',
                ),
                const Divider(height: 1),
                _metric(
                  Icons.air_rounded,
                  'Wind',
                  '${weather.windSpeed.toStringAsFixed(1)} km/h '
                      '${weather.windDirectionLabel} '
                      '(${weather.windDirectionDegrees.round()}°)',
                ),
                if (weather.pressure != null) ...[
                  const Divider(height: 1),
                  _metric(
                    Icons.speed_rounded,
                    'Pressure',
                    '${weather.pressure!.round()} hPa',
                  ),
                ],
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
            '3-day forecast',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF17293A),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...weather.forecast
              .take(3)
              .map(
                (day) => Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_today_rounded,
                      color: Color(0xFF1565C0),
                    ),
                    title: Text(_dayLabel(day.date)),
                    subtitle: Text(day.condition),
                    trailing: Text(
                      '${day.minimumTemperature.round()}° / ${day.maximumTemperature.round()}°',
                      style: const TextStyle(
                        color: Color(0xFF17293A),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white,
            child: Column(
              children: [
                _metric(
                  Icons.wb_twilight_rounded,
                  'Sunrise',
                  weather.sunrise == null
                      ? 'Unavailable'
                      : _time(context, weather.sunrise!),
                ),
                const Divider(height: 1),
                _metric(
                  Icons.nights_stay_rounded,
                  'Sunset',
                  weather.sunset == null
                      ? 'Unavailable'
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
                weather.moonPhase,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Solunar activity estimate',
                style: TextStyle(color: Colors.white70),
              ),
              trailing: Text(
                weather.fishingActivity.name.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF80CBC4),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ListTile _metric(IconData icon, String label, String value) =>
      ListTile(
        leading: Icon(icon, color: const Color(0xFF1565C0)),
        title: Text(label, style: const TextStyle(color: Color(0xFF17293A))),
        trailing: Text(
          value,
          style: const TextStyle(
            color: Color(0xFF17293A),
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  static String _time(BuildContext context, DateTime dateTime) =>
      TimeOfDay.fromDateTime(dateTime.toLocal()).format(context);

  static String _dayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}

class _WeatherMessage extends StatelessWidget {
  const _WeatherMessage({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 48,
          color: Color(0xFF455A64),
        ),
        const SizedBox(height: 12),
        const Text(
          'Weather is currently unavailable.',
          style: TextStyle(color: Color(0xFF263238)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
