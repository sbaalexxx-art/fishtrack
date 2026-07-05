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
    final stations = stationNames.toList(growable: false);
    final requested = stations
        .map(DanubeHisWaterProvider.normalizedName)
        .where((name) => name.isNotEmpty)
        .toSet();
    developer.log(
      'AFDJ request URL: $endpoint; requested stations: ${stations.join(', ')}',
      name: 'AIFishMap.Water',
    );
    try {
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: const {'User-Agent': 'Mozilla/5.0 AIFishMap/1.0'},
          )
          .timeout(const Duration(seconds: 15));
      final contentType = response.headers['content-type'] ?? 'not provided';
      final body = response.body;
      final bodyPreview = body
          .substring(0, body.length < 300 ? body.length : 300)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final challengeDetected =
          body.contains('Attention Required!') ||
          body.contains('/cdn-cgi/') ||
          body.toLowerCase().contains('cloudflare');
      final responseKind =
          contentType.toLowerCase().contains('pdf') || body.startsWith('%PDF')
          ? 'PDF'
          : contentType.toLowerCase().contains('html') ||
                body.toLowerCase().contains('<html')
          ? 'HTML'
          : 'unknown';
      developer.log(
        'AFDJ response: status=${response.statusCode}; '
        'content-type=$contentType; kind=$responseKind; '
        'challengeDetected=$challengeDetected; body[0..300]=$bodyPreview',
        name: 'AIFishMap.Water',
      );
      if (response.statusCode != 200 || challengeDetected) {
        developer.log(
          'AFDJ parse summary: station rows parsed=0; matched stations=none; '
          'reason=${challengeDetected ? 'challenge page detected' : 'HTTP status ${response.statusCode}'}',
          name: 'AIFishMap.Water',
        );
        throw AfdjProviderException(
          challengeDetected
              ? 'AFDJ endpoint returned a Cloudflare challenge'
              : 'AFDJ endpoint returned HTTP ${response.statusCode}',
        );
      }

      final text = _plainText(body);
      final levels = <String, List<WaterLevel>>{};
      var stationRowsParsed = 0;
      final matchedStationNames = <String>[];
      final failureReasons = <String>[];
      for (final stationName in stations) {
        final normalized = DanubeHisWaterProvider.normalizedName(stationName);
        if (!requested.contains(normalized)) continue;
        final escapedName = RegExp.escape(stationName);
        final match = RegExp(
          '$escapedName\\s+Km\\s+[0-9.]+\\s+Cota\\s+'
          r'(-?[0-9.]+)\s+cm\s+Variatia\s+(-?[0-9.,]+).*?'
          r'Data actualizarii\s+[^,]+,\s*(\d{2}/\d{2}/\d{4})'
          r'\s*-\s*(\d{2}:\d{2})',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(text);
        if (match == null) {
          failureReasons.add('$stationName: station row pattern not found');
          developer.log(
            'AFDJ no valid reading: $stationName; '
            'reason=station row pattern not found',
            name: 'AIFishMap.Water',
          );
          continue;
        }
        stationRowsParsed++;
        final level = _romanianNumber(match.group(1));
        final variation = _romanianNumber(match.group(2));
        final timestamp = _dateTime(match.group(3), match.group(4));
        if (level == null || variation == null || timestamp == null) {
          failureReasons.add(
            '$stationName: invalid level, variation, or timestamp',
          );
          developer.log(
            'AFDJ no valid reading: $stationName; '
            'reason=invalid level, variation, or timestamp; '
            'level=${match.group(1)}; variation=${match.group(2)}; '
            'date=${match.group(3)}; time=${match.group(4)}',
            name: 'AIFishMap.Water',
          );
          continue;
        }
        matchedStationNames.add(stationName);
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
      developer.log(
        'AFDJ parse summary: station rows parsed=$stationRowsParsed; '
        'valid readings=${levels.length}; matched stations='
        '${matchedStationNames.isEmpty ? 'none' : matchedStationNames.join(', ')}; '
        'failures=${failureReasons.isEmpty ? 'none' : failureReasons.join(' | ')}',
        name: 'AIFishMap.Water',
      );
      if (levels.isEmpty && requested.isNotEmpty) {
        throw AfdjProviderException(
          'AFDJ response contained no valid requested station readings: '
          '${failureReasons.isEmpty ? 'no parseable station rows' : failureReasons.join(' | ')}',
        );
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

class AfdjProviderException implements Exception {
  const AfdjProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}
