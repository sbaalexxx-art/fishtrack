import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/station.dart';
import '../models/water_level.dart';

class DanubeHisWaterProvider {
  const DanubeHisWaterProvider();

  static const _baseUrl = 'https://www.danubehis.org';
  static const _sourceName = 'DanubeHIS';

  Future<Map<String, List<WaterLevel>>> getLevels(
    Iterable<String> stationNames, {
    int limit = 30,
  }) async {
    final requested = stationNames.map(normalizedName).toSet();
    try {
      final directory = await _fetchDirectory();
      final matches = directory.where(
        (station) => requested.contains(normalizedName(station.name)),
      );
      final entries = await Future.wait(
        matches.map((station) async {
          try {
            final history = await _fetchHistory(station, limit: limit);
            return MapEntry(normalizedName(station.name), history);
          } on Exception catch (error, stackTrace) {
            _logFailure('history ${station.name}', error, stackTrace);
            return MapEntry(normalizedName(station.name), [
              _latestReading(station),
            ]);
          }
        }),
      );
      return Map.fromEntries(entries);
    } on Exception catch (error, stackTrace) {
      _logFailure('Romanian station directory', error, stackTrace);
      rethrow;
    }
  }

  Future<List<_DanubeHisStation>> _fetchDirectory() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl/time-series/stations/h?country=RO'),
          headers: const {'User-Agent': 'AIFishMap/1.0'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'DanubeHIS station request failed (${response.statusCode})',
      );
    }

    final pattern = RegExp(
      r'<tr[^>]*>.*?views-field-name[^>]*>\s*([^<]+?)\s*</td>.*?'
      r'views-field-latest-result-time[^>]*data-sort-value="(\d+)".*?'
      r'views-field-value[^>]*data-sort-value="([^"]+)".*?'
      r'href="/results/([^?"/]+)',
      caseSensitive: false,
      dotAll: true,
    );
    final stations = <_DanubeHisStation>[];
    for (final match in pattern.allMatches(response.body)) {
      final rawName = match.group(1)?.trim() ?? '';
      if (!rawName.endsWith(' RO')) continue;
      final value = double.tryParse(match.group(3) ?? '');
      final seconds = int.tryParse(match.group(2) ?? '');
      final providerId = match.group(4);
      if (value == null ||
          !value.isFinite ||
          seconds == null ||
          providerId == null) {
        developer.log(
          'Skipped invalid DanubeHIS station row: $rawName',
          name: 'AIFishMap.Water',
        );
        continue;
      }
      stations.add(
        _DanubeHisStation(
          name: rawName.substring(0, rawName.length - 3).trim(),
          providerId: providerId,
          latestValue: value,
          latestTimestamp: DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ),
        ),
      );
    }
    if (stations.isEmpty) {
      throw const FormatException('No Romanian DanubeHIS stations parsed');
    }
    return stations;
  }

  Future<List<WaterLevel>> _fetchHistory(
    _DanubeHisStation station, {
    required int limit,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 14));
    final uri = Uri.parse('$_baseUrl/results/${station.providerId}').replace(
      queryParameters: {
        'symbol[h]': 'h',
        'time_from': _date(from),
        'time_to': _date(now),
      },
    );
    final response = await http
        .get(uri, headers: const {'User-Agent': 'AIFishMap/1.0'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'DanubeHIS history request failed (${response.statusCode})',
      );
    }

    final series = RegExp(
      r'&quot;data&quot;:\s*(\[\[.*?\]\])',
      dotAll: true,
    ).firstMatch(response.body)?.group(1);
    if (series == null) {
      throw const FormatException('DanubeHIS history series missing');
    }
    final readings =
        RegExp(r'\[(\d{10,13}),(-?\d+(?:\.\d+)?)\]')
            .allMatches(series)
            .map((match) {
              final milliseconds = int.tryParse(match.group(1) ?? '');
              final value = double.tryParse(match.group(2) ?? '');
              if (milliseconds == null || value == null || !value.isFinite) {
                return null;
              }
              return WaterLevel(
                stationId: normalizedName(station.name),
                value: value,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  milliseconds,
                  isUtc: true,
                ),
                trend: WaterTrend.stable,
                source: WaterLevelSource.danubeHis,
                unit: 'cm',
                sourceName: _sourceName,
              );
            })
            .whereType<WaterLevel>()
            .toList(growable: false)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (readings.isEmpty) return [_latestReading(station)];
    return readings.take(limit).toList(growable: false);
  }

  static WaterLevel _latestReading(_DanubeHisStation station) => WaterLevel(
    stationId: normalizedName(station.name),
    value: station.latestValue,
    timestamp: station.latestTimestamp,
    trend: WaterTrend.stable,
    source: WaterLevelSource.danubeHis,
    unit: 'cm',
    sourceName: _sourceName,
  );

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';

  static String normalizedName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[ăâáàä]'), 'a')
      .replaceAll(RegExp('[îíìï]'), 'i')
      .replaceAll(RegExp('[șş]'), 's')
      .replaceAll(RegExp('[țţ]'), 't')
      .replaceAll(RegExp(r'\s+ro$'), '')
      .replaceAll(RegExp('[^a-z0-9]'), '');

  static void _logFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      'DanubeHIS $operation failed',
      name: 'AIFishMap.Water',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _DanubeHisStation {
  const _DanubeHisStation({
    required this.name,
    required this.providerId,
    required this.latestValue,
    required this.latestTimestamp,
  });

  final String name;
  final String providerId;
  final double latestValue;
  final DateTime latestTimestamp;
}
