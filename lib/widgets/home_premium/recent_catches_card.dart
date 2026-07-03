import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';

class RecentCatchesCardPremium extends StatelessWidget {
  const RecentCatchesCardPremium({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171B24),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_rounded, color: Color(0xFFFFB300)),
              const SizedBox(width: 8),
              Text(
                "Recent Catches",
                style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
              ),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text("See all")),
            ],
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                _CatchCard(
                  fish: "Carp",
                  weight: "8.4 kg",
                  angler: "John",
                  color: Color(0xFF8D6E63),
                ),
                SizedBox(width: 12),
                _CatchCard(
                  fish: "Pike",
                  weight: "5.8 kg",
                  angler: "Michael",
                  color: Color(0xFF546E7A),
                ),
                SizedBox(width: 12),
                _CatchCard(
                  fish: "Perch",
                  weight: "1.3 kg",
                  angler: "Daniel",
                  color: Color(0xFF455A64),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatchCard extends StatelessWidget {
  const _CatchCard({
    required this.fish,
    required this.weight,
    required this.angler,
    required this.color,
  });

  final String fish;
  final String weight;
  final String angler;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF202633),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: const Center(
                child: Icon(Icons.image, size: 40, color: Colors.white54),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fish,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  weight,
                  style: const TextStyle(
                    color: Color(0xFFFFB300),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(angler, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
