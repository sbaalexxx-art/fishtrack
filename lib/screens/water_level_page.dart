import 'package:flutter/material.dart';

class WaterLevelPage extends StatelessWidget {
  const WaterLevelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final stations = [
      {"name": "Baziaș", "level": "248 cm", "trend": "↑ +3 cm"},
      {"name": "Moldova Veche", "level": "262 cm", "trend": "↓ -1 cm"},
      {"name": "Orșova", "level": "301 cm", "trend": "↑ +5 cm"},
      {"name": "Drobeta", "level": "287 cm", "trend": "→ Stabil"},
      {"name": "Calafat", "level": "315 cm", "trend": "↑ +2 cm"},
      {"name": "Bechet", "level": "298 cm", "trend": "↓ -4 cm"},
      {"name": "Corabia", "level": "281 cm", "trend": "↑ +1 cm"},
      {"name": "Turnu Măgurele", "level": "294 cm", "trend": "↑ +6 cm"},
      {"name": "Giurgiu", "level": "336 cm", "trend": "→ Stabil"},
      {"name": "Oltenița", "level": "322 cm", "trend": "↓ -2 cm"},
      {"name": "Călărași", "level": "340 cm", "trend": "↑ +4 cm"},
      {"name": "Cernavodă", "level": "352 cm", "trend": "↑ +3 cm"},
      {"name": "Tulcea", "level": "365 cm", "trend": "→ Stabil"},
    ];

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
                  Icon(Icons.water_drop, color: Colors.blue, size: 55),

                  SizedBox(height: 12),

                  Text(
                    "Dunărea",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),

                  SizedBox(height: 8),

                  Text(
                    "23 stații monitorizate",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),

                  SizedBox(height: 15),

                  Text(
                    "Actualizat acum 5 minute",
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 25),

          const Text(
            "Stații monitorizate",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 15),
          ...stations.map(
            (station) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.water_drop, color: Colors.white),
                ),
                title: Text(
                  station["name"]!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(station["trend"]!),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      station["level"]!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
                onTap: () {},
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
