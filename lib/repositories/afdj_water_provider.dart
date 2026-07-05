import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/station.dart';
import '../models/water_level.dart';
import 'danube_his_water_provider.dart';

class AfdjWaterProvider {
  const AfdjWaterProvider();

  static const endpoint = 'https://www.afdj.ro/ro/cotele-dunarii';
  static const sourceName = 'AFDJ';

  Future<Map<String, List<WaterLevel>>> getLevels(
    Iterable<String> stationNames,
  ) async {
    final requested = stationNames
        .map(DanubeHisWaterProvider.normalizedName)
        .where((name) => name.isNotEmpty)
        .toSet();
    try {
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: const {'User-Agent': 'Mozilla/5.0 AIFishMap/1.0'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          response.body.contains('Attention Required!') ||
          response.body.contains('/cdn-cgi/')) {
        throw Exception('AFDJ request unavailable (${response.statusCode})');
      }

      final text = _plainText(response.body);
      final levels = <String, List<WaterLevel>>{};
      for (final stationName in stationNames) {
        final normalized = DanubeHisWaterProvider.normalizedName(stationName);
        if (!requested.contains(normalized)) continue;
        final escapedName = RegExp.escape(stationName);
        final match = RegExp(
          '$escapedName\\s+Km\\s+[0-9.]+\\s+Cota\\s+'
          r'(-?[0-9.]+)s+cms+Variatias+(-?[0-9.,]+).*?'
          r'Data actualizariis+[^,]+,s*(d{2}/d{2}/d{4})'
          r's*-s*(d{2}:d{2})',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(text);
        if (match == null) {
          developer.log(
            'AFDJ unmatched station: $stationName',
            name: 'AIFishMap.Water',
          );
          continue;
        }
        final level = _romanianNumber(match.group(1));
        final variation = _romanianNumber(match.group(2));
        final timestamp = _dateTime(match.group(3), match.group(4));
        if (level == null || variation == null || timestamp == null) {
          developer.log(
            'AFDJ parse failure: $stationName',
            name: 'AIFishMap.Water',
          );
          continue;
        }
        levels[normalized] = [
          WaterLevel(
            stationId: normalized,
            value: level,
            timestamp: timestamp,
            trend: variation > 0
                ? WaterTrend.rising
                : variation < 0
                ? WaterTrend.falling
                : WaterTrend.stable,
            source: WaterLevelSource.afdj,
            unit: 'cm',
            sourceName: sourceName,
            hasKnownTrend: true,
          ),
        ];
      }
      if (levels.isEmpty && requested.isNotEmpty) {
        throw const FormatException('No requested AFDJ stations parsed');
      }
      return levels;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'AFDJ fetch/parse failed',
        name: 'AIFishMap.Water',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static String _plainText(String html) => _decodeEntities(
    html.replaceAll(RegExp(r'<[^>]+>'), ' '),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _decodeEntities(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        final code = int.tryParse(match.group(1) ?? '');
        return code == null ? match.group(0)! : String.fromCharCode(code);
      });

  static double? _romanianNumber(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll('.', '').replaceAll(',', '.');
    final number = double.tryParse(normalized);
    return number?.isFinite == true ? number : null;
  }

  static DateTime? _dateTime(String? date, String? time) {
    final parts = date?.split('/') ?? const [];
    final clock = time?.split(':') ?? const [];
    if (parts.length != 3 || clock.length != 2) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    final hour = int.tryParse(clock[0]);
    final minute = int.tryParse(clock[1]);
    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    return DateTime(year, month, day, hour, minute);
  }
}
