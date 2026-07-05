import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/station.dart';
import '../models/water_level.dart';
import 'danube_his_water_provider.dart';

class DanubeFisWaterProvider {
  const DanubeFisWaterProvider();

  static const endpoint = 'https://www.danubeportal.com/waterLevel';
  static const sourceName = 'DanubeFIS / Danube Portal';

  Future<Map<String, List<WaterLevel>>> getLevels(
    Iterable<String> stationNames,
  ) async {
    final requested = stationNames
        .map(DanubeHisWaterProvider.normalizedName)
        .where((name) => name.isNotEmpty && name != 'periprava')
        .toSet();
    try {
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: const {'User-Agent': 'AIFishMap/1.0'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(
          'Danube Portal request failed (${response.statusCode})',
        );
      }

      final levels = <String, List<WaterLevel>>{};
      for (final row in RegExp(
        r'<tr[^>]*>(.*?)</tr>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(response.body)) {
        final columns = _columns(row.group(1) ?? '');
        if (columns.length < 5) continue;
        final stationName = columns[0];
        final normalized = DanubeHisWaterProvider.normalizedName(stationName);
        if (!requested.contains(normalized) || normalized == 'periprava') {
          continue;
        }
        final river = columns[1];
        final riverKm = double.tryParse(columns[2]);
        final timestamp = DateTime.tryParse(columns[3]);
        final value = double.tryParse(columns[4]);
        if (river.isEmpty ||
            riverKm == null ||
            !riverKm.isFinite ||
            timestamp == null ||
            value == null ||
            !value.isFinite) {
          developer.log(
            'DanubeFIS parse skipped: $stationName',
            name: 'AIFishMap.Water',
          );
          continue;
        }
        final station = _DanubeFisStation(
          name: stationName,
          river: river,
          riverKm: riverKm,
          timestamp: timestamp,
          levelCm: value,
        );
        levels[normalized] = [station.toWaterLevel()];
      }
      if (levels.isEmpty && requested.isNotEmpty) {
        throw const FormatException('No requested DanubeFIS stations parsed');
      }
      return levels;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'DanubeFIS fetch/parse failed',
        name: 'AIFishMap.Water',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static List<String> _columns(String rowHtml) {
    final withSeparators = rowHtml.replaceAll(
      RegExp(r'</td\s*>', caseSensitive: false),
      '|',
    );
    final plain = withSeparators.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeEntities(plain)
        .split('|')
        .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static String _decodeEntities(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        final code = int.tryParse(match.group(1) ?? '');
        return code == null ? match.group(0)! : String.fromCharCode(code);
      })
      .replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false), (
        match,
      ) {
        final code = int.tryParse(match.group(1) ?? '', radix: 16);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      });
}

class _DanubeFisStation {
  const _DanubeFisStation({
    required this.name,
    required this.river,
    required this.riverKm,
    required this.timestamp,
    required this.levelCm,
  });

  final String name;
  final String river;
  final double riverKm;
  final DateTime timestamp;
  final double levelCm;

  WaterLevel toWaterLevel() => WaterLevel(
    stationId: DanubeHisWaterProvider.normalizedName(name),
    value: levelCm,
    timestamp: timestamp,
    trend: WaterTrend.stable,
    source: WaterLevelSource.danubeFis,
    unit: 'cm',
    sourceName: DanubeFisWaterProvider.sourceName,
  );
}
