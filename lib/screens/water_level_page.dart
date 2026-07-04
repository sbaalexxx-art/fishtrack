import 'package:flutter/material.dart';

import '../models/station.dart';
import '../services/water_service.dart';
import '../widgets/station_card.dart';
import 'station_details_page.dart';

class WaterLevelPage extends StatefulWidget {
  const WaterLevelPage({super.key});

  @override
  State<WaterLevelPage> createState() => _WaterLevelPageState();
}

class _WaterLevelPageState extends State<WaterLevelPage> {
  final WaterService _waterService = WaterService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nivelul Apelor"), centerTitle: true),
      body: FutureBuilder<List<Station>>(
        future: _waterService.getStations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "A apărut o eroare.\n\n${snapshot.error}",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final stations = snapshot.data ?? [];

          if (stations.isEmpty) {
            return const Center(child: Text("Nu există stații disponibile."));
          }

          final latestUpdate = stations
              .map((station) => station.lastUpdate)
              .where((timestamp) => timestamp.millisecondsSinceEpoch > 0)
              .fold<DateTime?>(
                null,
                (latest, timestamp) =>
                    latest == null || timestamp.isAfter(latest)
                    ? timestamp
                    : latest,
              );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.water_drop,
                        color: Colors.blue,
                        size: 60,
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        "Live Water Levels",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        "${stations.length} stații monitorizate",
                        style: const TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        latestUpdate == null
                            ? 'Update time unavailable'
                            : _relativeUpdate(latestUpdate),
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                "Stații monitorizate",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              ...stations.map(
                (station) => StationCard(
                  station: station,
                  onTap: () {
                    _waterService.selectStation(station);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StationDetailsPage(station: station),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  static String _relativeUpdate(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return 'Updated just now';
    }
    if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return 'Updated ${difference.inHours} h ago';
    }
    return 'Updated ${difference.inDays} d ago';
  }
}
