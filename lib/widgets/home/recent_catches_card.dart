import 'package:flutter/material.dart';

class RecentCatchesCard extends StatelessWidget {
  const RecentCatchesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.phishing, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recent Catches',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  'Nearby',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            const _CatchTile(
              species: 'Common Carp',
              weight: '12.4 kg',
              time: '18 min ago',
              angler: 'Michael',
            ),

            const SizedBox(height: 12),

            const _CatchTile(
              species: 'Pike',
              weight: '7.8 kg',
              time: '46 min ago',
              angler: 'Daniel',
            ),

            const SizedBox(height: 12),

            const _CatchTile(
              species: 'Perch',
              weight: '1.3 kg',
              time: '1 h ago',
              angler: 'Alex',
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.analytics_outlined, color: Colors.lightBlueAccent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Catch activity is above average during the last 24 hours.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatchTile extends StatelessWidget {
  final String species;
  final String weight;
  final String time;
  final String angler;

  const _CatchTile({
    required this.species,
    required this.weight,
    required this.time,
    required this.angler,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF1565C0),
            child: Icon(Icons.phishing, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  species,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$weight • $angler',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
