import 'package:flutter/material.dart';

class AIFishingInsightsCard extends StatelessWidget {
  const AIFishingInsightsCard({super.key});

  @override
  Widget build(BuildContext context) {
    const score = 8.4;

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
                Icon(
                  Icons.psychology_rounded,
                  color: Color(0xFF1E88E5),
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Fishing Conditions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Live',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      score.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Conditions are favourable today.\n'
                    'A rising water level combined with stable pressure '
                    'indicates increased fish activity during the next few hours.',
                    style: TextStyle(color: Colors.white70, height: 1.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Confidence',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: const LinearProgressIndicator(
                value: 0.84,
                minHeight: 8,
                backgroundColor: Color(0xFF323232),
                valueColor: AlwaysStoppedAnimation(Color(0xFF1E88E5)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Recommended Species',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _SpeciesChip(icon: Icons.waves, label: 'Carp'),
                _SpeciesChip(icon: Icons.waves, label: 'Zander'),
                _SpeciesChip(icon: Icons.waves, label: 'Catfish'),
                _SpeciesChip(icon: Icons.waves, label: 'Perch'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeciesChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SpeciesChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: const Color(0xFF2A2A2A),
      side: BorderSide.none,
      avatar: Icon(icon, size: 16, color: const Color(0xFF1E88E5)),
      label: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
