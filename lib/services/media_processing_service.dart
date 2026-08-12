import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_image_compress/flutter_image_compress.dart';

enum MediaPurpose { catchPhoto, reportPhoto, avatar }

class MediaPolicy {
  const MediaPolicy({
    required this.dimensionLimits,
    required this.qualities,
    required this.targetBytes,
    required this.hardLimitBytes,
  });

  final List<int> dimensionLimits;
  final List<int> qualities;
  final int targetBytes;
  final int hardLimitBytes;

  static const catchPhoto = MediaPolicy(
    dimensionLimits: [1920, 1600, 1440],
    qualities: [84, 78, 72, 66],
    targetBytes: 1468006, // ~1.4 MiB; bucket hard limit is 2 MiB.
    hardLimitBytes: 2097152,
  );

  static const reportPhoto = MediaPolicy(
    dimensionLimits: [1600, 1440, 1280],
    qualities: [80, 74, 68, 62],
    targetBytes: 943718, // ~0.9 MiB; bucket hard limit is 1.5 MiB.
    hardLimitBytes: 1572864,
  );

  static const avatar = MediaPolicy(
    dimensionLimits: [768, 640, 512],
    qualities: [82, 76, 70],
    targetBytes: 471859, // ~0.45 MiB; bucket hard limit is 1 MiB.
    hardLimitBytes: 1048576,
  );

  static MediaPolicy forPurpose(MediaPurpose purpose) => switch (purpose) {
        MediaPurpose.catchPhoto => catchPhoto,
        MediaPurpose.reportPhoto => reportPhoto,
        MediaPurpose.avatar => avatar,
      };
}

class ProcessedMedia {
  const ProcessedMedia({
    required this.bytes,
    required this.sha256Hex,
    required this.originalBytes,
    required this.outputBytes,
    required this.dimensionLimit,
    required this.quality,
  });

  static const contentType = 'image/jpeg';
  static const extension = '.jpg';

  final Uint8List bytes;
  final String sha256Hex;
  final int originalBytes;
  final int outputBytes;
  final int dimensionLimit;
  final int quality;
}

class MediaProcessingException implements Exception {
  const MediaProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Canonical on-device media pipeline for public FluviAI uploads.
///
/// The output is always an upright JPEG with source EXIF deliberately removed.
/// This prevents camera GPS/device metadata from bypassing the app's explicit
/// exact/approximate/hidden location controls. A SHA-256 digest is calculated
/// from the exact bytes uploaded so dedupe/audit use the same representation.
class MediaProcessingService {
  const MediaProcessingService();

  Future<ProcessedMedia> processFile({
    required String path,
    required MediaPurpose purpose,
  }) async {
    final source = File(path);
    if (!await source.exists()) {
      throw const MediaProcessingException(
        'The selected image is no longer available.',
      );
    }

    final originalBytes = await source.length();
    if (originalBytes <= 0) {
      throw const MediaProcessingException('The selected image is empty.');
    }

    final policy = MediaPolicy.forPurpose(purpose);
    Uint8List? smallest;
    var smallestDimension = policy.dimensionLimits.first;
    var smallestQuality = policy.qualities.first;

    for (final dimension in policy.dimensionLimits) {
      for (final quality in policy.qualities) {
        final candidate = await FlutterImageCompress.compressWithFile(
          source.absolute.path,
          minWidth: dimension,
          minHeight: dimension,
          quality: quality,
          rotate: 0,
          autoCorrectionAngle: true,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        if (candidate == null || candidate.isEmpty) continue;

        if (smallest == null || candidate.lengthInBytes < smallest.lengthInBytes) {
          smallest = candidate;
          smallestDimension = dimension;
          smallestQuality = quality;
        }

        if (candidate.lengthInBytes <= policy.targetBytes) {
          return _result(
            candidate,
            originalBytes: originalBytes,
            dimensionLimit: dimension,
            quality: quality,
          );
        }
      }
    }

    if (smallest == null) {
      throw const MediaProcessingException(
        'The image could not be processed. Please take the photo again.',
      );
    }
    if (smallest.lengthInBytes > policy.hardLimitBytes) {
      throw const MediaProcessingException(
        'The image is too large to upload safely. Please take the photo again.',
      );
    }

    return _result(
      smallest,
      originalBytes: originalBytes,
      dimensionLimit: smallestDimension,
      quality: smallestQuality,
    );
  }

  static String sha256Hex(Uint8List bytes) =>
      crypto.sha256.convert(bytes).toString();

  static ProcessedMedia _result(
    Uint8List bytes, {
    required int originalBytes,
    required int dimensionLimit,
    required int quality,
  }) {
    return ProcessedMedia(
      bytes: bytes,
      sha256Hex: sha256Hex(bytes),
      originalBytes: originalBytes,
      outputBytes: bytes.lengthInBytes,
      dimensionLimit: dimensionLimit,
      quality: quality,
    );
  }
}
