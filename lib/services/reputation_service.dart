import 'package:supabase_flutter/supabase_flutter.dart';

enum TrustLevel {
  newUser('New'),
  trusted('Trusted'),
  reliable('Reliable'),
  expert('Expert');

  const TrustLevel(this.label);
  final String label;

  static TrustLevel fromScore(int score) {
    if (score >= 85) return expert;
    if (score >= 65) return reliable;
    if (score >= 40) return trusted;
    return newUser;
  }

  static TrustLevel parse(Object? value) => values.firstWhere(
    (level) => level.label.toLowerCase() == value?.toString().toLowerCase(),
    orElse: () => newUser,
  );
}

class ReputationMetrics {
  const ReputationMetrics({
    required this.userId,
    required this.reputationScore,
    required this.trustLevel,
    this.reportsCount = 0,
    this.catchesCount = 0,
    this.confirmedCount = 0,
    this.notAccurateCount = 0,
    this.abuseFlagsCount = 0,
    this.suspiciousReportsCount = 0,
    this.updatedAt,
  });

  factory ReputationMetrics.fallback(String userId) => ReputationMetrics(
    userId: userId,
    reputationScore: 50,
    trustLevel: TrustLevel.newUser,
  );

  final String userId;
  final int reputationScore;
  final TrustLevel trustLevel;
  final int reportsCount;
  final int catchesCount;
  final int confirmedCount;
  final int notAccurateCount;
  final int abuseFlagsCount;
  final int suspiciousReportsCount;
  final DateTime? updatedAt;
}

class ReputationCalculator {
  const ReputationCalculator();

  int calculate({
    required int confirmedCount,
    required int notAccurateCount,
    required int abuseFlagsCount,
    required int suspiciousReportsCount,
    required int catchesCount,
    required int reportsCount,
  }) =>
      (50 +
              confirmedCount * 2 -
              notAccurateCount * 3 -
              abuseFlagsCount * 5 -
              suspiciousReportsCount * 4 +
              catchesCount +
              reportsCount)
          .clamp(0, 100);
}

class ReputationService {
  const ReputationService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<ReputationMetrics> getCurrentUserReputation() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return ReputationMetrics.fallback('');
    return getReputation(userId);
  }

  Future<ReputationMetrics> getReputation(String userId) async {
    final row = await _supabase
        .from('user_reputation')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null
        ? ReputationMetrics.fallback(userId)
        : _fromRow(Map<String, dynamic>.from(row));
  }

  Future<Map<String, ReputationMetrics>> getReputations(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return const {};
    final response = await _supabase
        .from('user_reputation')
        .select()
        .inFilter('user_id', ids.toList());
    final rows = response.whereType<Map>().map(
      (row) => _fromRow(Map<String, dynamic>.from(row)),
    );
    return {for (final row in rows) row.userId: row};
  }

  static ReputationMetrics _fromRow(Map<String, dynamic> row) {
    int count(String key) => row[key] is num
        ? (row[key] as num).toInt()
        : int.tryParse('${row[key]}') ?? 0;
    final userId = row['user_id']?.toString() ?? '';
    final score = count('reputation_score').clamp(0, 100);
    return ReputationMetrics(
      userId: userId,
      reputationScore: score,
      trustLevel: TrustLevel.parse(row['trust_level']),
      reportsCount: count('reports_count'),
      catchesCount: count('catches_count'),
      confirmedCount: count('confirmed_count'),
      notAccurateCount: count('not_accurate_count'),
      abuseFlagsCount: count('abuse_flags_count'),
      suspiciousReportsCount: count('suspicious_reports_count'),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }
}
