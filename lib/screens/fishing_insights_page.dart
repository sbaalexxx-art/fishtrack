import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
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

  void _reload() => setState(
    () => _decision = _service.calculate(forceRefresh: true),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.fishingInsights)),
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
                          _localizedRating(context, result.rating!),
                          style: TextStyle(
                            color: _ratingColor(result.rating!),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _localizedRecommendation(
                            context,
                            result.recommendation,
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _localizedExplanation(context, result.explanation),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(context.l10n.confidence(result.confidence)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FactorCard(
                  title: context.l10n.positiveFactors,
                  icon: Icons.add_circle_outline,
                  color: Colors.green,
                  factors: result.positiveFactors
                      .map((factor) => _localizedFactor(context, factor))
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                _FactorCard(
                  title: context.l10n.negativeFactors,
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  factors: result.negativeFactors
                      .map((factor) => _localizedFactor(context, factor))
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule, color: Colors.blue),
                    title: Text(context.l10n.bestTimeWindow),
                    subtitle: Text(
                      _localizedTimeValue(context, result.bestTime),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.dark_mode_outlined,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      _localizedMoonPhaseValue(context, result.moonPhase),
                    ),
                    subtitle: Text(
                      context.l10n.goldenHourValue(
                        _localizedTimeValue(context, result.goldenHour),
                      ),
                    ),
                  ),
                ),
                if (result.missingFactors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _FactorCard(
                    title: context.l10n.missingData,
                    icon: Icons.info_outline,
                    color: Colors.grey,
                    factors: result.missingFactors
                        .map(
                          (factor) =>
                              _localizedMissingFactor(context, factor),
                        )
                        .toList(growable: false),
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

  static bool _isRomanian(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ro';

  static String _localizedRating(
    BuildContext context,
    FishingScoreRating rating,
  ) {
    if (!_isRomanian(context)) return rating.name.toUpperCase();
    return switch (rating) {
      FishingScoreRating.excellent => 'EXCELENT',
      FishingScoreRating.good => 'BUN',
      FishingScoreRating.fair => 'ACCEPTABIL',
      FishingScoreRating.poor => 'SLAB',
    };
  }

  static String _localizedRecommendation(
    BuildContext context,
    String value,
  ) {
    if (!_isRomanian(context)) return value;
    return switch (value.trim().toLowerCase()) {
      'not enough data yet' => 'Nu există încă suficiente date',
      'excellent' => 'Excelent',
      'good' => 'Bun',
      'fair' => 'Acceptabil',
      'poor' => 'Slab',
      _ => value,
    };
  }

  static String _localizedExplanation(BuildContext context, String value) {
    if (!_isRomanian(context)) return value;
    final normalized = value.trim().toLowerCase();
    if (normalized == 'not enough data yet') {
      return 'Nu există încă suficiente date';
    }
    if (normalized == 'no strong factors detected.') {
      return 'Nu au fost detectați factori importanți.';
    }

    final combined = RegExp(
      r'^helps:\s*(.*?)\.\s*watch:\s*(.*?)\.$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (combined != null) {
      return 'Ajută: ${_localizedFactor(context, combined.group(1)!)}. '
          'Atenție: ${_localizedFactor(context, combined.group(2)!)}.';
    }

    final helps = RegExp(
      r'^helps:\s*(.*?)\.$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (helps != null) {
      return 'Ajută: ${_localizedFactor(context, helps.group(1)!)}.';
    }

    final watch = RegExp(
      r'^watch:\s*(.*?)\.$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (watch != null) {
      return 'Atenție: ${_localizedFactor(context, watch.group(1)!)}.';
    }
    return value;
  }

  static String _localizedFactor(BuildContext context, String value) {
    if (!_isRomanian(context)) return value;
    final trimmed = value.trim();
    final normalized = trimmed.toLowerCase();
    final staticValue = switch (normalized) {
      'current time is within golden hour' =>
        'Ora curentă este în intervalul orei de aur',
      'productive water-side temperature' =>
        'Temperatură favorabilă în apropierea apei',
      'usable air temperature' => 'Temperatură acceptabilă a aerului',
      'moderate atmospheric pressure' => 'Presiune atmosferică moderată',
      'moderate humidity' => 'Umiditate moderată',
      'low precipitation probability' =>
        'Probabilitate redusă de precipitații',
      'useful cloud cover' => 'Nebulozitate favorabilă',
      'verified water level available' =>
        'Nivel verificat al apei disponibil',
      'stable water trend' => 'Tendință stabilă a nivelului apei',
      'rising water trend' => 'Nivelul apei este în creștere',
      'water history supports the trend' =>
        'Istoricul nivelului apei confirmă tendința',
      'community reports are mostly confirmed' =>
        'Raportările comunității sunt confirmate în mare parte',
      'extreme air temperature' => 'Temperatură extremă a aerului',
      'dangerous wind gusts' => 'Rafale de vânt periculoase',
      'strong wind gusts' => 'Rafale puternice de vânt',
      'extreme atmospheric pressure' => 'Presiune atmosferică extremă',
      'unfavourable humidity' => 'Umiditate nefavorabilă',
      'high precipitation probability' =>
        'Probabilitate ridicată de precipitații',
      'very bright, clear conditions' =>
        'Condiții foarte luminoase și senine',
      'falling water trend' => 'Nivelul apei este în scădere',
      'water reading is outdated' =>
        'Măsurătoarea nivelului apei este învechită',
      'water reading may be delayed' =>
        'Măsurătoarea nivelului apei poate fi întârziată',
      'community reports have accuracy concerns' =>
        'Există îndoieli privind acuratețea raportărilor comunității',
      _ => null,
    };
    if (staticValue != null) return staticValue;

    final illuminated = RegExp(
      r'^(.+?)\s*\((\d+(?:\.\d+)?)% illuminated\)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (illuminated != null) {
      return '${_localizedMoonPhase(context, illuminated.group(1)!)} '
          '(${illuminated.group(2)}% iluminată)';
    }

    final wind = RegExp(
      r'^(moderate|light|strong)\s+(.+?)\s+wind$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (wind != null) {
      final direction = _localizedWindDirection(context, wind.group(2)!);
      return switch (wind.group(1)!.toLowerCase()) {
        'moderate' => 'Vânt moderat din direcția $direction',
        'light' => 'Vânt slab din direcția $direction',
        'strong' => 'Vânt puternic din direcția $direction',
        _ => value,
      };
    }

    final freshWater = RegExp(
      r'^fresh\s+(.+?)\s+water data$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (freshWater != null) {
      return 'Date recente despre apă de la ${freshWater.group(1)}';
    }

    final counted = RegExp(
      r'^(\d+)\s+(positive reports|caution reports|recent catches|recently reported species|catches include weight data)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (counted != null) {
      final countText = counted.group(1)!;
      final count = int.parse(countText);
      return switch (counted.group(2)!.toLowerCase()) {
        'positive reports' => count == 1
            ? '1 raportare pozitivă'
            : '$countText raportări pozitive',
        'caution reports' => count == 1
            ? '1 raportare de avertizare'
            : '$countText raportări de avertizare',
        'recent catches' => count == 1
            ? '1 captură recentă'
            : '$countText capturi recente',
        'recently reported species' => count == 1
            ? '1 specie raportată recent'
            : '$countText specii raportate recent',
        'catches include weight data' => count == 1
            ? '1 captură include date despre greutate'
            : '$countText capturi includ date despre greutate',
        _ => value,
      };
    }
    return value;
  }

  static String _localizedMissingFactor(BuildContext context, String value) {
    if (!_isRomanian(context)) return value;
    return switch (value.trim().toLowerCase()) {
      'no live inputs are currently available.' =>
        'Momentan nu sunt disponibile date în timp real.',
      'score calculated without live weather data.' =>
        'Scor calculat fără date meteo în timp real.',
      'water history is insufficient for a verified trend.' =>
        'Istoricul nivelului apei este insuficient pentru verificarea tendinței.',
      'score calculated without live water data.' =>
        'Scor calculat fără date în timp real despre apă.',
      'score calculated without active community reports.' =>
        'Scor calculat fără raportări active din comunitate.',
      'score calculated without recent catch data.' =>
        'Scor calculat fără date despre capturi recente.',
      _ => value,
    };
  }

  static String _localizedTimeValue(BuildContext context, String value) {
    if (!_isRomanian(context)) return value;
    final exactValue = switch (value.trim().toLowerCase()) {
      'no data' => 'Nu există date',
      'no sunrise/sunset data' =>
        'Nu există date despre răsărit și apus',
      'location required' => 'Este necesară locația',
      'not available' => 'Indisponibil',
      _ => null,
    };
    if (exactValue != null) return exactValue;
    return value.replaceAll(
      RegExp(r'\sor\s', caseSensitive: false),
      ' sau ',
    );
  }

  static String _localizedMoonPhaseValue(
    BuildContext context,
    String value,
  ) {
    if (!_isRomanian(context)) return value;
    final match = RegExp(
      r'^(.+?)\s*•\s*(\d+(?:\.\d+)?)% illuminated$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return _localizedMoonPhase(context, value);
    return '${_localizedMoonPhase(context, match.group(1)!)} • '
        '${match.group(2)}% iluminată';
  }

  static String _localizedMoonPhase(BuildContext context, String value) {
    if (!_isRomanian(context)) return value;
    return switch (value.trim().toLowerCase()) {
      'not available' => 'Indisponibil',
      'new moon' => 'Lună nouă',
      'waxing crescent' => 'Semilună în creștere',
      'first quarter' => 'Primul pătrar',
      'waxing gibbous' => 'Lună gibboasă în creștere',
      'full moon' => 'Lună plină',
      'waning gibbous' => 'Lună gibboasă în descreștere',
      'last quarter' || 'third quarter' => 'Ultimul pătrar',
      'waning crescent' => 'Semilună în descreștere',
      _ => value,
    };
  }

  static String _localizedWindDirection(BuildContext context, String value) {
    if (!_isRomanian(context)) return value;
    return switch (value.trim().toLowerCase()) {
      'n' || 'north' => 'N',
      'ne' || 'northeast' || 'north east' => 'NE',
      'e' || 'east' => 'E',
      'se' || 'southeast' || 'south east' => 'SE',
      's' || 'south' => 'S',
      'sw' || 'southwest' || 'south west' => 'SV',
      'w' || 'west' => 'V',
      'nw' || 'northwest' || 'north west' => 'NV',
      _ => value,
    };
  }
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
              Text(context.l10n.noSignificantFactors)
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
          Text(
            context.l10n.notEnoughData,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    ),
  );
}
