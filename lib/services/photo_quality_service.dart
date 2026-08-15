import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as image;

class PhotoQualityResult {
  const PhotoQualityResult({
    required this.width,
    required this.height,
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.darkPixelRatio,
    required this.brightPixelRatio,
  });

  final int width;
  final int height;
  final double brightness;
  final double contrast;
  final double sharpness;
  final double darkPixelRatio;
  final double brightPixelRatio;

  bool get resolutionOk => width >= 720 && height >= 720;
  bool get exposureOk =>
      brightness >= 45 &&
      brightness <= 215 &&
      darkPixelRatio < 0.55 &&
      brightPixelRatio < 0.55;
  bool get contrastOk => contrast >= 24;
  bool get sharpnessOk => sharpness >= 12;

  bool get isGood => resolutionOk && exposureOk && contrastOk && sharpnessOk;

  List<PhotoQualityIssue> get issues {
    final result = <PhotoQualityIssue>[];
    if (!resolutionOk) result.add(PhotoQualityIssue.lowResolution);
    if (!exposureOk) {
      if (brightness < 45 || darkPixelRatio >= 0.55) {
        result.add(PhotoQualityIssue.tooDark);
      } else {
        result.add(PhotoQualityIssue.tooBright);
      }
    }
    if (!contrastOk) result.add(PhotoQualityIssue.lowContrast);
    if (!sharpnessOk) result.add(PhotoQualityIssue.blurry);
    return result;
  }
}

enum PhotoQualityIssue {
  lowResolution,
  tooDark,
  tooBright,
  lowContrast,
  blurry,
}

class PhotoQualityService {
  const PhotoQualityService();

  Future<PhotoQualityResult> analyzeFile(String path) =>
      Isolate.run(() => _analyzePhoto(path));
}

PhotoQualityResult _analyzePhoto(String path) {
  final decoded = image.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) {
    throw const PhotoQualityException('Unable to decode image.');
  }
  final source = image.bakeOrientation(decoded);
  final originalWidth = source.width;
  final originalHeight = source.height;
  final longSide = originalWidth > originalHeight ? originalWidth : originalHeight;
  final analysisImage = longSide <= 384
      ? source
      : originalWidth >= originalHeight
      ? image.copyResize(
          source,
          width: 384,
          interpolation: image.Interpolation.average,
        )
      : image.copyResize(
          source,
          height: 384,
          interpolation: image.Interpolation.average,
        );

  final width = analysisImage.width;
  final height = analysisImage.height;
  final count = width * height;
  if (count <= 0) {
    throw const PhotoQualityException('Image contains no pixels.');
  }

  var sum = 0.0;
  var sumSq = 0.0;
  var dark = 0;
  var bright = 0;
  final luminance = List<double>.filled(count, 0);

  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final pixel = analysisImage.getPixel(x, y);
      final luma =
          0.2126 * pixel.r.toDouble() +
          0.7152 * pixel.g.toDouble() +
          0.0722 * pixel.b.toDouble();
      luminance[row + x] = luma;
      sum += luma;
      sumSq += luma * luma;
      if (luma < 32) dark++;
      if (luma > 224) bright++;
    }
  }

  final mean = sum / count;
  final variance = (sumSq / count) - mean * mean;
  final contrast = variance <= 0 ? 0.0 : _sqrt(variance);

  var laplaceSum = 0.0;
  var laplaceCount = 0;
  for (var y = 1; y < height - 1; y++) {
    final row = y * width;
    for (var x = 1; x < width - 1; x++) {
      final p = row + x;
      final center = luminance[p];
      final laplace =
          4 * center -
          luminance[p - 1] -
          luminance[p + 1] -
          luminance[p - width] -
          luminance[p + width];
      laplaceSum += laplace.abs();
      laplaceCount++;
    }
  }
  final sharpness = laplaceCount == 0 ? 0.0 : laplaceSum / laplaceCount;

  return PhotoQualityResult(
    width: originalWidth,
    height: originalHeight,
    brightness: mean,
    contrast: contrast,
    sharpness: sharpness,
    darkPixelRatio: dark / count,
    brightPixelRatio: bright / count,
  );
}

double _sqrt(double value) {
  if (value <= 0) return 0;
  var x = value;
  for (var i = 0; i < 10; i++) {
    x = 0.5 * (x + value / x);
  }
  return x;
}

class PhotoQualityException implements Exception {
  const PhotoQualityException(this.message);
  final String message;

  @override
  String toString() => message;
}
