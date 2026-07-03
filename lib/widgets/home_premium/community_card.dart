import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';

class CommunityCardPremium extends StatelessWidget {
  const CommunityCardPremium({
    super.key,
    this.activeAnglers = 248,
    this.liveReports = 37,
  });

  final int activeAnglers;
  final int liveReports;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 185,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF183021),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                color: Color(0xFF4CAF50),
                size: 20,
              ),

              const SizedBox(width: 8),

              Text(
                "Community",
                style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "LIVE",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: const [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white),
              ),
              SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white),
              ),
              SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            "$activeAnglers anglers nearby",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text("$liveReports new reports today", style: AppTextStyles.caption),

          const Spacer(),

          Row(
            children: const [
              Icon(Icons.circle, size: 10, color: Color(0xFF4CAF50)),
              SizedBox(width: 6),
              Text(
                "Live activity",
                style: TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
