import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:http/http.dart' as http;

import '../../services/diagnostics_service.dart';

class ApiClient {
  const ApiClient();

  Future<dynamic> get(String url) async {
    final uri = Uri.parse(url);
    final stopwatch = Stopwatch()..start();
    HttpMetric? metric;
    if (Firebase.apps.isNotEmpty) {
      try {
        final safeUri = uri.replace(query: '', fragment: '');
        metric = FirebasePerformance.instance.newHttpMetric(
          safeUri.toString(),
          HttpMethod.Get,
        );
        await metric.start();
      } on Object {
        metric = null;
      }
    }
    try {
      final response = await http.get(uri);
      stopwatch.stop();
      if (metric != null) {
        metric
          ..httpResponseCode = response.statusCode
          ..responsePayloadSize = response.bodyBytes.length
          ..responseContentType = response.headers['content-type'];
      }
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.network,
        operation: 'GET',
        message: '${uri.host}${uri.path}',
        duration: stopwatch.elapsed,
        level: response.statusCode >= 400
            ? DiagnosticLevel.warning
            : DiagnosticLevel.info,
        metadata: <String, Object?>{
          'status': response.statusCode,
          'bytes': response.bodyBytes.length,
          'host': uri.host,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      throw Exception(
        'Request failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    } on Object catch (error, stackTrace) {
      if (stopwatch.isRunning) stopwatch.stop();
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.network,
        operation: 'GET',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'host': uri.host,
          'path': uri.path,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      rethrow;
    } finally {
      if (metric != null) {
        try {
          await metric.stop();
        } on Object {
          // Performance telemetry must never affect the request result.
        }
      }
    }
  }
}
