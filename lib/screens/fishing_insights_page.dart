import 'package:flutter/material.dart';

import '../services/fishing_score_service.dart';

class FishingInsightsPage extends StatefulWidget {
  const FishingInsightsPage({super.key});

  @override
  State<FishingInsightsPage> createState() => _FishingInsightsPageState();
}

class _FishingInsightsPageState extends State<FishingInsightsPage> {
  final _service = FishingScoreService();
  late Future<FishingScoreResult> _decision;

  @override
  void initState() {
    super.initState();
    _decision = _service.calculate();
  }

  void _reload() => setState(() => _decision = _service.calculate());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fishing Insights')),
      body: FutureBuilder<FishingScoreResult>(
        future: _decision,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data;
          if (snapshot.hasError || result == null || !result.hasEnoughData) {
            return _NotEnoughData(onRetry: _reload);
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _decision;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          '${result.score!.round()} / 100',
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: _ratingColor(result.rating!),
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          result.rating!.name.toUpperCase(),
                          style: TextStyle(
                            color: _ratingColor(result.rating!),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          result.recommendation,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(result.explanation, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text('Confidence: ${result.confidence}%'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FactorCard(
                  title: 'Positive factors',
                  icon: Icons.add_circle_outline,
                  color: Colors.green,
                  factors: result.positiveFactors,
                ),
                const SizedBox(height: 12),
                _FactorCard(
                  title: 'Negative factors',
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  factors: result.negativeFactors,
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule, color: Colors.blue),
                    title: const Text('Best time window'),
                    subtitle: Text(result.bestTime),
                  ),
                ),
                if (result.missingFactors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _FactorCard(
                    title: 'Missing data',
                    icon: Icons.info_outline,
                    color: Colors.grey,
                    factors: result.missingFactors,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static Color _ratingColor(FishingScoreRating rating) => switch (rating) {
    FishingScoreRating.excellent => Colors.green,
    FishingScoreRating.good => Colors.lightGreen,
    FishingScoreRating.fair => Colors.orange,
    FishingScoreRating.poor => Colors.red,
  };
}

class _FactorCard extends StatelessWidget {
  const _FactorCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.factors,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> factors;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            if (factors.isEmpty)
              const Text('No significant factors available.')
            else
              for (final factor in factors)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.circle, size: 9, color: color),
                  title: Text(factor),
                ),
          ],
        ),
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights_outlined, size: 52),
          const SizedBox(height: 12),
          const Text(
            'Not enough data yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
