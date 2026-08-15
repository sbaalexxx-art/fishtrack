import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AlertRuleKind {
  levelAbove,
  levelBelow,
  rapidChange,
  stateChange,
  communityReport,
}

class AlertRule {
  const AlertRule({
    required this.id,
    required this.entityId,
    required this.entityLabel,
    required this.kind,
    this.entityType = 'station',
    required this.createdAt,
    this.threshold,
    this.enabled = true,
  });

  final String id;
  final String entityId;
  final String entityLabel;
  final AlertRuleKind kind;
  final String entityType;
  final DateTime createdAt;
  final double? threshold;
  final bool enabled;

  AlertRule copyWith({
    String? id,
    String? entityLabel,
    String? entityType,
    AlertRuleKind? kind,
    double? threshold,
    bool? enabled,
  }) => AlertRule(
    id: id ?? this.id,
    entityId: entityId,
    entityLabel: entityLabel ?? this.entityLabel,
    entityType: entityType ?? this.entityType,
    kind: kind ?? this.kind,
    createdAt: createdAt,
    threshold: threshold ?? this.threshold,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'entityId': entityId,
    'entityLabel': entityLabel,
    'entityType': entityType,
    'kind': kind.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'threshold': threshold,
    'enabled': enabled,
  };

  static AlertRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final id = map['id']?.toString();
    final entityId = (map['entity_id'] ?? map['entityId'])?.toString();
    final entityLabel = (map['entity_label'] ?? map['entityLabel'])?.toString();
    final entityType =
        (map['entity_type'] ?? map['entityType'])?.toString() ?? 'station';
    final kindName = map['kind']?.toString();
    final createdAt = DateTime.tryParse(
      (map['created_at'] ?? map['createdAt'])?.toString() ?? '',
    );
    AlertRuleKind? kind;
    for (final candidate in AlertRuleKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    if (id == null ||
        entityId == null ||
        entityLabel == null ||
        kind == null ||
        createdAt == null) {
      return null;
    }
    final thresholdValue = map['threshold'];
    return AlertRule(
      id: id,
      entityId: entityId,
      entityLabel: entityLabel,
      entityType: entityType,
      kind: kind,
      createdAt: createdAt,
      threshold: thresholdValue is num
          ? thresholdValue.toDouble()
          : double.tryParse(thresholdValue?.toString() ?? ''),
      enabled: map['enabled'] != false,
    );
  }
}

class AlertRuleRepository {
  const AlertRuleRepository({SupabaseClient? client}) : _client = client;

  static const _storageKey = 'fluviai.alert_rules.v1';
  final SupabaseClient? _client;

  SupabaseClient? get _supabaseOrNull {
    final provided = _client;
    if (provided != null) return provided;

    try {
      return Supabase.instance.client;
    } on AssertionError {
      // Unit tests and local-only flows may intentionally run before
      // Supabase initialization.
      return null;
    }
  }

  Future<List<AlertRule>> load() async {
    final supabase = _supabaseOrNull;
    final userId = supabase?.auth.currentUser?.id;

    if (supabase != null && userId != null) {
      try {
        final rows = await supabase
            .from('water_alert_rules')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);

        final rules = (rows as List)
            .map(AlertRule.fromJson)
            .whereType<AlertRule>()
            .toList(growable: false);

        await _writeCache(rules);
        return rules;
      } on Exception {
        // Offline/network fallback: keep the latest locally cached rule set.
      }
    }

    return _loadCache();
  }

  Future<void> save(AlertRule rule) async {
    final supabase = _supabaseOrNull;
    final userId = supabase?.auth.currentUser?.id;

    if (supabase == null || userId == null) {
      final rules = [...await _loadCache()]
        ..removeWhere((candidate) => candidate.id == rule.id)
        ..insert(0, rule);
      await _writeCache(rules);
      return;
    }

    final payload = <String, Object?>{
      'user_id': userId,
      'entity_id': rule.entityId,
      'entity_label': rule.entityLabel,
      'entity_type': rule.entityType,
      'kind': rule.kind.name,
      'threshold': rule.threshold,
      'enabled': rule.enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final existingUuid = _isUuid(rule.id) ? rule.id : null;
    if (existingUuid != null) payload['id'] = existingUuid;

    final row = await supabase
        .from('water_alert_rules')
        .upsert(payload)
        .select()
        .single();

    final saved = AlertRule.fromJson(row);
    if (saved == null) {
      throw const FormatException('Invalid water alert rule response.');
    }

    final rules = [...await _loadCache()]
      ..removeWhere(
        (candidate) => candidate.id == rule.id || candidate.id == saved.id,
      )
      ..insert(0, saved);

    await _writeCache(rules);
  }

  Future<void> remove(String id) async {
    final supabase = _supabaseOrNull;
    final userId = supabase?.auth.currentUser?.id;

    if (supabase != null && userId != null && _isUuid(id)) {
      await supabase
          .from('water_alert_rules')
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
    }

    final rules = [...await _loadCache()]..removeWhere((rule) => rule.id == id);

    await _writeCache(rules);
  }

  Future<List<AlertRule>> _loadCache() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return const [];
      return decoded
          .map(AlertRule.fromJson)
          .whereType<AlertRule>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeCache(List<AlertRule> rules) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(rules.map((rule) => rule.toJson()).toList()),
    );
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
