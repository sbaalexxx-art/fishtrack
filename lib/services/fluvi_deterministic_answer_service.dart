import '../features/commercial_home/data/commercial_home_data_source.dart';
import '../models/station.dart';

class FluviAnswer {
  const FluviAnswer({
    required this.text,
    required this.confidence,
    required this.sources,
    required this.hasEnoughData,
  });

  final String text;
  final int confidence;
  final List<String> sources;
  final bool hasEnoughData;
}

class FluviDeterministicAnswerService {
  const FluviDeterministicAnswerService();

  FluviAnswer answer({
    required String question,
    required CommercialHomeSnapshot snapshot,
  }) {
    final normalized = question.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const FluviAnswer(
        text: 'Scrie o întrebare despre apă, vreme sau condițiile de pescuit.',
        confidence: 0,
        sources: [],
        hasEnoughData: false,
      );
    }

    if (_containsAny(normalized, const [
      'apă',
      'apa',
      'nivel',
      'debit',
      'crește',
      'creste',
      'scade',
      'trend',
      'water',
      'level',
    ])) {
      return _waterAnswer(snapshot);
    }
    if (_containsAny(normalized, const [
      'vreme',
      'meteo',
      'vânt',
      'vant',
      'rafal',
      'ploa',
      'temperatur',
      'weather',
      'wind',
      'rain',
    ])) {
      return _weatherAnswer(snapshot);
    }
    if (_containsAny(normalized, const [
      'când',
      'cand',
      'merită',
      'merita',
      'pesc',
      'partid',
      'scor',
      'fluviscore',
      'best time',
      'fish',
    ])) {
      return _scoreAnswer(snapshot);
    }
    if (_containsAny(normalized, const [
      'raport',
      'comunit',
      'captur',
      'activitate',
      'community',
      'catch',
    ])) {
      return _communityAnswer(snapshot);
    }
    return _summaryAnswer(snapshot);
  }

  FluviAnswer _waterAnswer(CommercialHomeSnapshot snapshot) {
    final water = snapshot.water;
    final latest = water?.latestReading;
    if (latest == null) {
      final label = _contextLabel(snapshot);
      return FluviAnswer(
        text:
            'Pentru $label nu am o observație Water reală. Nu pot estima nivelul fără date.',
        confidence: 0,
        sources: const ['Water'],
        hasEnoughData: false,
      );
    }
    final delta = latest.reportedDeltaCm24h ?? water?.deltaCm;
    final trend = _trendLabel(water?.trend ?? latest.knownTrend);
    final station = snapshot.station?.name ?? 'stația selectată';
    final temperature = latest.waterTemperatureC;
    final pieces = <String>[
      'La $station nivelul oficial este ${latest.value.toStringAsFixed(0)} ${latest.unit}.',
      if (delta != null)
        'Variația publicată/validată pentru 24h este ${_signed(delta)} cm.',
      if (trend != null)
        'Trendul compatibil cu observațiile reale este $trend.',
      if (temperature != null)
        'Temperatura apei raportată este ${temperature.toStringAsFixed(0)}°C.',
      water?.isStale == true
          ? 'Datele sunt marcate ca vechi/cache; verifică prospețimea înainte de decizie.'
          : 'Datele sunt din contractul Water curent.',
    ];
    return FluviAnswer(
      text: pieces.join(' '),
      confidence: water?.isStale == true ? 55 : 88,
      sources: [water?.sourceName ?? latest.sourceName, 'Water observations'],
      hasEnoughData: true,
    );
  }

  FluviAnswer _weatherAnswer(CommercialHomeSnapshot snapshot) {
    final result = snapshot.weather;
    final weather = result?.data;
    if (weather == null) {
      return FluviAnswer(
        text:
            'Pentru ${_contextLabel(snapshot)} nu am date meteo reale. Nu voi completa prognoza din presupuneri.',
        confidence: 0,
        sources: const ['Weather'],
        hasEnoughData: false,
      );
    }
    final stale = result?.isStale == true;
    final label = _contextLabel(snapshot);
    return FluviAnswer(
      text:
          'Pentru $label sunt acum ${weather.temperature.toStringAsFixed(0)}°C, ${weather.condition.toLowerCase()}, '
          'vânt ${weather.windSpeed.toStringAsFixed(0)} km/h și rafale până la ${weather.windGusts.toStringAsFixed(0)} km/h. '
          'Probabilitatea de precipitații este ${weather.precipitationProbability.toStringAsFixed(0)}%. '
          '${stale ? 'Datele sunt cache/vechi, deci folosește-le cu prudență.' : 'Datele provin din providerul meteo runtime al aplicației.'}',
      confidence: stale ? 55 : 85,
      sources: ['Open-Meteo / Weather runtime'],
      hasEnoughData: true,
    );
  }

  FluviAnswer _scoreAnswer(CommercialHomeSnapshot snapshot) {
    final score = snapshot.score;
    if (score == null || !score.hasEnoughData) {
      final missing = score?.missingFactors.take(3).join(', ');
      return FluviAnswer(
        text: missing == null || missing.isEmpty
            ? 'Pentru ${_contextLabel(snapshot)} nu sunt suficiente intrări reale pentru un FluviScore. Nu voi inventa o recomandare.'
            : 'Pentru ${_contextLabel(snapshot)} nu sunt suficiente intrări pentru FluviScore. Lipsesc: $missing.',
        confidence: 0,
        sources: const ['FluviScore deterministic'],
        hasEnoughData: false,
      );
    }
    final positives = score.positiveFactors.take(2).join('; ');
    final negatives = score.negativeFactors.take(2).join('; ');
    final explanation = <String>[
      'Pentru ${_contextLabel(snapshot)}, FluviScore este ${score.score!.round()}/100, cu încredere ${score.confidence}%.',
      score.recommendation,
      'Fereastra indicată: ${score.bestTime}.',
      if (positives.isNotEmpty) 'Factori favorabili: $positives.',
      if (negatives.isNotEmpty) 'Riscuri: $negatives.',
      'Scorul este determinist; un model AI nu modifică valoarea numerică.',
    ];
    return FluviAnswer(
      text: explanation.join(' '),
      confidence: score.confidence,
      sources: const [
        'FluviScore deterministic',
        'Water',
        'Weather',
        'Community',
      ],
      hasEnoughData: true,
    );
  }

  FluviAnswer _communityAnswer(CommercialHomeSnapshot snapshot) {
    final posts = snapshot.communityPosts
        .where((post) => !post.isSuspicious)
        .toList();
    final activeReports = posts.where((post) => post.isActiveReport).length;
    final catches = posts.where((post) => post.type.name == 'catchPost').length;
    if (posts.isEmpty) {
      return FluviAnswer(
        text:
            'Pentru ${_contextLabel(snapshot)} nu am activitate Community reală disponibilă. Nu voi simula rapoarte sau capturi.',
        confidence: 0,
        sources: const ['Community'],
        hasEnoughData: false,
      );
    }
    return FluviAnswer(
      text:
          'Pentru ${_contextLabel(snapshot)} sunt $activeReports rapoarte active și $catches capturi publice locale disponibile. '
          'Am exclus elementele marcate suspecte; locațiile private nu sunt folosite pentru explicație.',
      confidence: 80,
      sources: const ['Community / Supabase'],
      hasEnoughData: true,
    );
  }

  FluviAnswer _summaryAnswer(CommercialHomeSnapshot snapshot) {
    final score = _scoreAnswer(snapshot);
    if (score.hasEnoughData) return score;
    final water = _waterAnswer(snapshot);
    if (water.hasEnoughData) return water;
    final weather = _weatherAnswer(snapshot);
    if (weather.hasEnoughData) return weather;
    return FluviAnswer(
      text:
          'Pentru ${_contextLabel(snapshot)} nu am suficiente date reale pentru un răspuns sigur. Deschide Water/Weather sau permite locația și încearcă din nou.',
      confidence: 0,
      sources: const [],
      hasEnoughData: false,
    );
  }

  static bool _containsAny(String input, List<String> needles) =>
      needles.any(input.contains);

  static String _contextLabel(CommercialHomeSnapshot snapshot) =>
      snapshot.resolvedContext?.primaryLabel ??
      snapshot.station?.name ??
      snapshot.environmentalContext?.primaryLabel ??
      'contextul curent';

  static String _signed(double value) =>
      value > 0 ? '+${value.toStringAsFixed(0)}' : value.toStringAsFixed(0);

  static String? _trendLabel(WaterTrend? trend) => switch (trend) {
    WaterTrend.rising => 'în creștere',
    WaterTrend.falling => 'în scădere',
    WaterTrend.stable => 'stabil',
    null => null,
  };
}
