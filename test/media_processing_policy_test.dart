import 'dart:typed_data';

import 'package:fishtrack/services/media_processing_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media hard limits match backend bucket limits', () {
    expect(MediaPolicy.catchPhoto.hardLimitBytes, 2 * 1024 * 1024);
    expect(MediaPolicy.reportPhoto.hardLimitBytes, 1536 * 1024);
    expect(MediaPolicy.avatar.hardLimitBytes, 1024 * 1024);
  });

  test('all policies target below hard limit and only scale down', () {
    for (final purpose in MediaPurpose.values) {
      final policy = MediaPolicy.forPurpose(purpose);
      expect(policy.targetBytes, lessThan(policy.hardLimitBytes));
      expect(policy.dimensionLimits, isNotEmpty);
      expect(policy.qualities, isNotEmpty);
      for (var i = 1; i < policy.dimensionLimits.length; i++) {
        expect(
          policy.dimensionLimits[i],
          lessThan(policy.dimensionLimits[i - 1]),
        );
      }
      for (var i = 1; i < policy.qualities.length; i++) {
        expect(policy.qualities[i], lessThan(policy.qualities[i - 1]));
      }
      expect(policy.qualities.every((value) => value >= 60 && value <= 90), isTrue);
    }
  });

  test('upload representation is canonical JPEG', () {
    expect(ProcessedMedia.contentType, 'image/jpeg');
    expect(ProcessedMedia.extension, '.jpg');
  });

  test('SHA-256 is stable for exact uploaded bytes', () {
    final digest = MediaProcessingService.sha256Hex(
      Uint8List.fromList('abc'.codeUnits),
    );
    expect(
      digest,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
