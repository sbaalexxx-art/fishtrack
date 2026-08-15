import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

class ReportImageOptimizationException implements Exception {
  const ReportImageOptimizationException(this.message);

  final String message;
}

class OptimizedReportImage {
  const OptimizedReportImage({
    required this.file,
    required this.byteLength,
    required this.width,
    required this.height,
    required Directory temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory;

  final File file;
  final int byteLength;
  final int width;
  final int height;
  final Directory _temporaryDirectory;

  Future<void> dispose() => _deleteDirectoryBestEffort(_temporaryDirectory);
}

class ReportImageOptimizer {
  const ReportImageOptimizer();

  static const hardByteLimit = 700 * 1024;
  static const _targetByteLimit = 450 * 1024;
  static const _dimensionSteps = <int>[1600, 1400, 1200, 1000, 800];
  static const _qualitySteps = <int>[88, 84, 80, 76, 72];

  Future<OptimizedReportImage> optimize(File source) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'fluviai-report-',
    );
    final output = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}report.jpg',
    );

    try {
      final result = await Isolate.run(
        () => _optimizeImage(source.path, output.path),
      );
      return OptimizedReportImage(
        file: output,
        byteLength: result.byteLength,
        width: result.width,
        height: result.height,
        temporaryDirectory: temporaryDirectory,
      );
    } catch (error, stackTrace) {
      await _deleteDirectoryBestEffort(temporaryDirectory);
      if (error is ReportImageOptimizationException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw ReportImageOptimizationException(
        'The report photo could not be optimized: $error',
      );
    }
  }
}

({int byteLength, int width, int height}) _optimizeImage(
  String sourcePath,
  String outputPath,
) {
  final decoded = image.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) {
    throw const ReportImageOptimizationException(
      'The report photo is not a supported image.',
    );
  }

  final oriented = image.bakeOrientation(decoded);
  oriented.exif.clear();
  final originalLongSide = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final dimensions = <int>[];
  for (final limit in ReportImageOptimizer._dimensionSteps) {
    final dimension = originalLongSide < limit ? originalLongSide : limit;
    if (!dimensions.contains(dimension)) {
      dimensions.add(dimension);
    }
  }

  Uint8List? fallbackBytes;
  var fallbackWidth = 0;
  var fallbackHeight = 0;

  for (final dimension in dimensions) {
    final resized = dimension == originalLongSide
        ? oriented
        : oriented.width >= oriented.height
        ? image.copyResize(
            oriented,
            width: dimension,
            interpolation: image.Interpolation.average,
          )
        : image.copyResize(
            oriented,
            height: dimension,
            interpolation: image.Interpolation.average,
          );
    resized.exif.clear();

    for (final quality in ReportImageOptimizer._qualitySteps) {
      final encoded = image.encodeJpg(resized, quality: quality);
      if (encoded.length <= ReportImageOptimizer._targetByteLimit) {
        File(outputPath).writeAsBytesSync(encoded, flush: true);
        return (
          byteLength: encoded.length,
          width: resized.width,
          height: resized.height,
        );
      }
      if (fallbackBytes == null &&
          encoded.length <= ReportImageOptimizer.hardByteLimit) {
        fallbackBytes = encoded;
        fallbackWidth = resized.width;
        fallbackHeight = resized.height;
      }
    }
  }

  if (fallbackBytes != null) {
    File(outputPath).writeAsBytesSync(fallbackBytes, flush: true);
    return (
      byteLength: fallbackBytes.length,
      width: fallbackWidth,
      height: fallbackHeight,
    );
  }
  throw const ReportImageOptimizationException(
    'The report photo could not be reduced below 700 KiB.',
  );
}

Future<void> _deleteDirectoryBestEffort(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } catch (_) {
    // Temporary cleanup must never replace the result of report publication.
  }
}
