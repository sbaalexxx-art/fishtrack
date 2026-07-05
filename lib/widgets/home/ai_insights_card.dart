import 'package:flutter/material.dart';

import '../../services/fishing_score_service.dart';

class AIFishingInsightsCard extends StatefulWidget {
  const AIFishingInsightsCard({super.key});

  @override
  State<AIFishingInsightsCard> createState() => _AIFishingInsightsCardState();
}

class _AIFishingInsightsCardState extends State<AIFishingInsightsCard> {
  late final Future<FishingScoreResult> _decision = FishingScoreService()
      .calculate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FishingScoreResult>(
      future: _decision,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final score = result?.score;
        return Card(
          elevation: 0,
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_rounded, color: Color(0xFF1E88E5)),
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
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        score == null ? '--' : '${score.round()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        snapshot.hasError ||
                                (result != null && !result.hasEnoughData)
                            ? 'Not enough data yet'
                            : result?.explanation ?? 'Calculating…',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  result == null
                      ? 'Confidence: --'
                      : 'Confidence: ${result.confidence}%',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: result == null ? null : result.confidence / 100,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF323232),
                    color: const Color(0xFF1E88E5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
