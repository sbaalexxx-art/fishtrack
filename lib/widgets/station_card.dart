import 'package:flutter/material.dart';

import '../models/station.dart';

class StationCard extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;

  const StationCard({super.key, required this.station, required this.onTap});

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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,

        leading: const CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(Icons.water_drop, color: Colors.white),
        ),

        title: Text(
          station.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),

        subtitle: Row(
          children: [
            Icon(trendIcon, color: trendColor, size: 18),
            const SizedBox(width: 6),
            Text(station.trendText, style: TextStyle(color: trendColor)),
          ],
        ),

        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "${station.level.toStringAsFixed(0)} cm",
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
