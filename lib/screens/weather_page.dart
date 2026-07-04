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
      appBar: AppBar(title: const Text('Weather')),
      body: SafeArea(
        child: FutureBuilder<WeatherData>(
          future: _weather,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _WeatherMessage(onRetry: _refresh);
            }
            final weather = snapshot.data;
            if (weather == null) return _WeatherMessage(onRetry: _refresh);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                children: [
                  Card(
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
                            '${weather.temperature.round()}°',
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          Text(
                            weather.condition,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.water_drop_outlined),
                          title: const Text('Humidity'),
                          trailing: Text('${weather.humidity.round()}%'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.air_rounded),
                          title: const Text('Wind'),
                          trailing: Text(
                            '${weather.windSpeed.toStringAsFixed(1)} km/h',
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule_rounded),
                          title: const Text('Last updated'),
                          trailing: Text(
                            TimeOfDay.fromDateTime(
                              weather.observedAt.toLocal(),
                            ).format(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
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
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 12),
        const Text('Weather is currently unavailable.'),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
