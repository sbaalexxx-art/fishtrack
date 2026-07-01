import 'package:flutter/material.dart';

class WaterLevelCard extends StatelessWidget {
  const WaterLevelCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.water, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Water Level',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            const Text(
              'Danube • Giurgiu',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),

            const SizedBox(height: 8),

            const Text(
              '318 cm',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: const [
                Icon(Icons.arrow_upward, color: Colors.blue, size: 18),
                SizedBox(width: 4),
                Text(
                  '+12 cm / 24h',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'Water Level Graph',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              'Updated 15 minutes ago',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
