import 'package:flutter/material.dart';

import '../models/station.dart';
import '../services/water_service.dart';
import '../widgets/station_card.dart';
import 'station_details_page.dart';

class WaterLevelPage extends StatelessWidget {
  const WaterLevelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Station> stations = WaterService.getStations();

    return Scaffold(
      appBar: AppBar(title: const Text("Nivelul Apelor"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.water_drop, color: Colors.blue, size: 60),

                  SizedBox(height: 16),

                  Text(
                    "Dunărea",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),

                  SizedBox(height: 8),

                  Text(
                    "13 stații monitorizate",
                    style: TextStyle(color: Colors.grey),
                  ),

                  SizedBox(height: 12),

                  Text(
                    "Actualizat acum câteva minute",
                    style: TextStyle(
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
      ),
    );
  }
}
