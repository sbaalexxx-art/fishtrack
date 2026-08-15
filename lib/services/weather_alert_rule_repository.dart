import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';

enum WeatherAlertKind {
  strongWind,
  strongGusts,
  heavyRain,
  thunderstorm,
  extremeHeat,
  extremeCold,
}

class WeatherAlertTarget {
  const WeatherAlertTarget({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;

  factory WeatherAlertTarget.fromStation(Station station) => WeatherAlertTarget(
    id: 'station:${station.id}',
    label: station.name,
    latitude: station.latitude,
    longitude: station.longitude,
  );

  factory WeatherAlertTarget.fromCoordinates({
    required double latitude,
    required double longitude,
    String label = 'Locația mea',
  }) {
    final latKey = latitude.toStringAsFixed(4);
    final lonKey = longitude.toStringAsFixed(4);
    return WeatherAlertTarget(
      id: 'location:$latKey:$lonKey',
      label: label,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class WeatherAlertRule {
  const WeatherAlertRule({
    required this.id,
    required this.target,
    required this.kind,
    required this.createdAt,
    this.threshold,
    this.enabled = true,
  });

  final String id;
  final WeatherAlertTarget target;
  final WeatherAlertKind kind;
  final DateTime createdAt;
  final double? threshold;
  final bool enabled;

  WeatherAlertRule copyWith({
    String? id,
    WeatherAlertTarget? target,
    WeatherAlertKind? kind,
    double? threshold,
    bool? enabled,
  }) => WeatherAlertRule(
    id: id ?? this.id,
    target: target ?? this.target,
    kind: kind ?? this.kind,
    createdAt: createdAt,
    threshold: threshold ?? this.threshold,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'target_id': target.id,
    'target_label': target.label,
    'latitude': target.latitude,
    'longitude': target.longitude,
    'kind': kind.name,
    'threshold': threshold,
    'enabled': enabled,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static WeatherAlertRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final id = map['id']?.toString();
    final targetId = map['target_id']?.toString();
    final targetLabel = map['target_label']?.toString();
    final lat = _asDouble(map['latitude']);
    final lon = _asDouble(map['longitude']);
    final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
    final kindName = map['kind']?.toString();
    WeatherAlertKind? kind;
    for (final candidate in WeatherAlertKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    if (id == null ||
        targetId == null ||
        targetLabel == null ||
        lat == null ||
        lon == null ||
        createdAt == null ||
        kind == null) {
      return null;
    }
    return WeatherAlertRule(
      id: id,
      target: WeatherAlertTarget(
        id: targetId,
        label: targetLabel,
        latitude: lat,
        longitude: lon,
      ),
      kind: kind,
      createdAt: createdAt,
      threshold: _asDouble(map['threshold']),
      enabled: map['enabled'] != false,
    );
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class WeatherAlertRuleRepository {
  const WeatherAlertRuleRepository({SupabaseClient? client}) : _client = client;

  static const _storageKey = 'fluviai.weather_alert_rules.v1';
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  String? get _userId {
    final injectedClient = _client;
    if (injectedClient != null) {
      return injectedClient.auth.currentUser?.id;
    }

    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } on AssertionError {
      return null;
    }
  }

  Future<List<WeatherAlertRule>> load() async {
    final userId = _userId;
    if (userId != null) {
      try {
        final rows = await _supabase
            .from('weather_alert_rules')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        final rules = (rows as List)
            .map(WeatherAlertRule.fromJson)
            .whereType<WeatherAlertRule>()
            .toList(growable: false);
        await _writeCache(rules);
        return rules;
      } on Exception {
        // Offline fallback is the latest successful server snapshot.
      }
    }
    return _loadCache();
  }

  Future<WeatherAlertRule> save(WeatherAlertRule rule) async {
    final userId = _userId;
    if (userId == null) {
      throw const AuthException('Authentication is required.');
    }
    final payload = <String, Object?>{
      'user_id': userId,
      'target_id': rule.target.id,
      'target_label': rule.target.label,
      'latitude': rule.target.latitude,
      'longitude': rule.target.longitude,
      'kind': rule.kind.name,
      'threshold': rule.threshold,
      'enabled': rule.enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (_isUuid(rule.id)) payload['id'] = rule.id;

    final row = await _supabase
        .from('weather_alert_rules')
        .upsert(payload, onConflict: 'user_id,target_id,kind')
        .select()
        .single();
    final saved = WeatherAlertRule.fromJson(row);
    if (saved == null) {
      throw const FormatException('Invalid weather alert rule response.');
    }
    final rules = [...await _loadCache()]
      ..removeWhere(
        (candidate) =>
            candidate.id == rule.id ||
            candidate.id == saved.id ||
            (candidate.target.id == saved.target.id &&
                candidate.kind == saved.kind),
      )
      ..insert(0, saved);
    await _writeCache(rules);
    return saved;
  }

  Future<void> remove(String id) async {
    final userId = _userId;
    if (userId == null) {
      throw const AuthException('Authentication is required.');
    }
    if (_isUuid(id)) {
      await _supabase
          .from('weather_alert_rules')
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
    }
    final rules = [...await _loadCache()]..removeWhere((rule) => rule.id == id);
    await _writeCache(rules);
  }

  Future<List<WeatherAlertRule>> _loadCache() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return const [];
      return decoded
          .map(WeatherAlertRule.fromJson)
          .whereType<WeatherAlertRule>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeCache(List<WeatherAlertRule> rules) async {
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
