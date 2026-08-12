import 'dart:io';

import 'media_processing_service.dart';

class SpamReportHistory {
  const SpamReportHistory({
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.imageHash,
  });

  final String category;
  final String description;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final String? imageHash;
}

class SpamAssessment {
  const SpamAssessment({required this.score, required this.reasons});

  final int score;
  final List<String> reasons;
  bool get isSuspicious => score > 30;
  String? get reason => reasons.isEmpty ? null : reasons.join('; ');
}

/// Explainable, rule-based report moderation. It only labels reports; it never
/// blocks publication or changes a user's account.
class ReportSpamService {
  const ReportSpamService({
    MediaProcessingService mediaProcessor = const MediaProcessingService(),
  }) : _mediaProcessor = mediaProcessor;

  final MediaProcessingService _mediaProcessor;

  /// Compatibility entry point for the existing report submission pipeline.
  ///
  /// Reports are camera-only, and [image] is an app-owned temporary capture.
  /// Before CommunityService uploads it, this method replaces those temporary
  /// bytes with the canonical privacy-sanitized JPEG and returns the SHA-256 of
  /// the exact bytes that will be uploaded. This keeps moderation/dedupe and
  /// Storage on one representation while preventing EXIF/GPS leakage.
  Future<String?> imageHash(File? image) async {
    if (image == null) return null;
    final processed = await _mediaProcessor.processFile(
      path: image.path,
      purpose: MediaPurpose.reportPhoto,
    );
    await image.writeAsBytes(processed.bytes, flush: true);
    return processed.sha256Hex;
  }

  SpamAssessment assess({
    required String category,
    required String description,
    required double latitude,
    required double longitude,
    required DateTime now,
    required List<SpamReportHistory> history,
    String? imageHash,
  }) {
    var score = 0;
    final reasons = <String>[];
    void add(int points, String reason) {
      score += points;
      reasons.add(reason);
    }

    final hourAgo = now.subtract(const Duration(hours: 1));
    final recent = history.where((item) => item.createdAt.isAfter(hourAgo));
    final recentCount = recent.length;
    if (recentCount >= 7) {
      add(35, 'High report frequency');
    } else if (recentCount >= 4) {
      add(25, 'Elevated report frequency');
    } else if (recentCount >= 2) {
      add(15, 'Several reports in a short period');
    }

    final normalized = _normalize(description);
    if (normalized.isEmpty) {
      add(15, 'Empty description');
    } else {
      final meaningful = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (meaningful.length < 4) add(20, 'Very short or meaningless text');
      final nonText = description.runes.where((rune) {
        final character = String.fromCharCode(rune);
        return !RegExp(r'[\p{L}\p{N}\s]', unicode: true).hasMatch(character);
      }).length;
      if (description.runes.isNotEmpty &&
          nonText / description.runes.length > 0.5) {
        add(15, 'Excessive emoji or symbols');
      }
      if (history.any(
        (item) =>
            normalized.length >= 4 &&
            _normalize(item.description) == normalized,
      )) {
        add(30, 'Repeated description');
      }
    }

    if (history.where((item) => item.category == category).length >= 4) {
      add(20, 'Category repeated frequently');
    }
    if (history.where((item) {
          if (item.latitude == null || item.longitude == null) return false;
          return (item.latitude! - latitude).abs() <= 0.0001 &&
              (item.longitude! - longitude).abs() <= 0.0001;
        }).length >=
        3) {
      add(20, 'Location repeated frequently');
    }
    if (imageHash != null &&
        history.any((item) => item.imageHash == imageHash)) {
      add(35, 'Duplicate image');
    }

    return SpamAssessment(score: score.clamp(0, 100), reasons: reasons);
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
