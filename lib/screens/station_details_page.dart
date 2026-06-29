import 'package:flutter/material.dart';

import '../models/station.dart';

class StationDetailsPage extends StatelessWidget {
  final Station station;

  const StationDetailsPage({super.key, required this.station});

  Color get trendColor {
    switch (station.trend) {
      case WaterTrend.rising:
        return Colors.green;
      case WaterTrend.falling:
        return Colors.red;
      case WaterTrend.stable:
        return Colors.orange;
    }
  }

  IconData get trendIcon {
    switch (station.trend) {
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
    return Scaffold(
      appBar: AppBar(title: Text(station.name), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.blue,
                      child: Icon(
                        Icons.water_drop,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      station.name,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      station.river,
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),

                    const SizedBox(height: 25),

                    Text(
                      "${station.level.toStringAsFixed(0)} cm",
                      style: const TextStyle(
                        fontSize: 46,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(trendIcon, color: trendColor),

                        const SizedBox(width: 8),

                        Text(
                          station.trendText,
                          style: TextStyle(
                            color: trendColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "Actualizat: ${station.lastUpdate.day}.${station.lastUpdate.month}.${station.lastUpdate.year}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              "Informații despre stație",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const Icon(Icons.location_on, color: Colors.red),
                title: const Text("Coordonate"),
                subtitle: Text("${station.latitude}, ${station.longitude}"),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: const ListTile(
                leading: Icon(Icons.show_chart, color: Colors.blue),
                title: Text("Grafic nivel apă"),
                subtitle: Text("Disponibil în versiunea următoare"),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: const ListTile(
                leading: Icon(Icons.cloud, color: Colors.orange),
                title: Text("Meteo"),
                subtitle: Text("Integrare OpenWeather în curând"),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.favorite_border),
                label: const Text("Adaugă la Favorite"),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.campaign),
                label: const Text("Raportează o captură"),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
