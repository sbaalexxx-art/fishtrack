import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'package:fishtrack/services/report_image_optimizer.dart';

void main() {
  late Directory sourceDirectory;

  setUp(() async {
    sourceDirectory = await Directory.systemTemp.createTemp(
      'fluviai-report-test-',
    );
  });

  tearDown(() async {
    if (await sourceDirectory.exists()) {
      await sourceDirectory.delete(recursive: true);
    }
  });

  test('optimizes a large image into a disposable JPEG', () async {
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}source.png',
    );
    final sourceBytes = image.encodePng(
      image.Image(width: 2400, height: 1800)
        ..clear(image.ColorRgb8(32, 120, 178)),
    );
    await source.writeAsBytes(sourceBytes);
    final originalBytes = await source.readAsBytes();

    final optimized = await const ReportImageOptimizer().optimize(source);
    addTearDown(optimized.dispose);

    expect(optimized.file.path, isNot(source.path));
    expect(await optimized.file.exists(), isTrue);
    expect(optimized.width, lessThanOrEqualTo(1600));
    expect(optimized.height, lessThanOrEqualTo(1600));
    expect(optimized.byteLength, lessThanOrEqualTo(700 * 1024));
    expect(await optimized.file.length(), optimized.byteLength);

    final jpegBytes = await optimized.file.readAsBytes();
    expect(jpegBytes.take(2), orderedEquals(<int>[0xff, 0xd8]));
    expect(
      jpegBytes.skip(jpegBytes.length - 2),
      orderedEquals(<int>[0xff, 0xd9]),
    );
    final decoded = image.decodeJpg(jpegBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, optimized.width);
    expect(decoded.height, optimized.height);

    expect(await source.exists(), isTrue);
    expect(await source.readAsBytes(), orderedEquals(originalBytes));

    final outputDirectory = optimized.file.parent;
    await optimized.dispose();
    expect(await optimized.file.exists(), isFalse);
    expect(await outputDirectory.exists(), isFalse);
  });

  test('preserves the approximate aspect ratio of a portrait image', () async {
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}portrait.png',
    );
    await source.writeAsBytes(
      image.encodePng(
        image.Image(width: 900, height: 1800)
          ..clear(image.ColorRgb8(28, 92, 68)),
      ),
    );

    final optimized = await const ReportImageOptimizer().optimize(source);
    addTearDown(optimized.dispose);

    expect(optimized.height, lessThanOrEqualTo(1600));
    expect(optimized.height, greaterThan(optimized.width));
    expect(optimized.width / optimized.height, closeTo(900 / 1800, 0.01));
  });

  test('does not upscale a small image', () async {
    final source = await _writePng(
      sourceDirectory,
      'small.png',
      image.Image(width: 640, height: 480)
        ..clear(image.ColorRgb8(64, 112, 156)),
    );

    final optimized = await const ReportImageOptimizer().optimize(source);
    addTearDown(optimized.dispose);

    expect(optimized.width, 640);
    expect(optimized.height, 480);
  });

  test('cleans its temporary directory after an invalid image', () async {
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}invalid.jpg',
    );
    await source.writeAsBytes(<int>[0x46, 0x6c, 0x75, 0x76, 0x69, 0x41, 0x49]);
    final directoriesBefore = await _reportTemporaryDirectories();

    await expectLater(
      const ReportImageOptimizer().optimize(source),
      throwsA(isA<ReportImageOptimizationException>()),
    );

    expect(await _reportTemporaryDirectories(), directoriesBefore);
  });

  test('dispose can be called twice without throwing', () async {
    final source = await _writePng(
      sourceDirectory,
      'disposable.png',
      image.Image(width: 320, height: 240)..clear(image.ColorRgb8(22, 76, 104)),
    );
    final optimized = await const ReportImageOptimizer().optimize(source);

    await expectLater(optimized.dispose(), completes);
    await expectLater(optimized.dispose(), completes);
  });

  test(
    'keeps deterministic detailed output valid and below the hard limit',
    () async {
      final source = await _writePng(
        sourceDirectory,
        'detailed.png',
        _deterministicDetailedImage(999, 999),
      );

      final optimized = await const ReportImageOptimizer().optimize(source);
      addTearDown(optimized.dispose);
      final bytes = await optimized.file.readAsBytes();

      expect(optimized.width, lessThanOrEqualTo(999));
      expect(optimized.height, lessThanOrEqualTo(999));
      expect(bytes.length, lessThanOrEqualTo(700 * 1024));
      _expectValidJpeg(bytes);
    },
  );

  test('leaves the original photo untouched', () async {
    final source = await _writePng(
      sourceDirectory,
      'original.png',
      image.Image(width: 1280, height: 720)
        ..clear(image.ColorRgb8(105, 88, 52)),
    );
    final originalBytes = await source.readAsBytes();

    final optimized = await const ReportImageOptimizer().optimize(source);
    addTearDown(optimized.dispose);

    expect(await source.exists(), isTrue);
    expect(await source.readAsBytes(), orderedEquals(originalBytes));
    expect(optimized.file.path, isNot(source.path));
  });
}

Future<File> _writePng(
  Directory directory,
  String name,
  image.Image source,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(image.encodePng(source));
  return file;
}

image.Image _deterministicDetailedImage(int width, int height) {
  final result = image.Image(width: width, height: height);
  var state = 0x6d2b79f5;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      state = (state * 1664525 + 1013904223) & 0xffffffff;
      result.setPixelRgb(
        x,
        y,
        state & 0xff,
        (state >> 8) & 0xff,
        (state >> 16) & 0xff,
      );
    }
  }
  return result;
}

Future<Set<String>> _reportTemporaryDirectories() async {
  final paths = <String>{};
  await for (final entity in Directory.systemTemp.list(followLinks: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (entity is Directory && name.startsWith('fluviai-report-')) {
      paths.add(entity.absolute.path);
    }
  }
  return paths;
}

void _expectValidJpeg(Uint8List bytes) {
  expect(bytes.take(2), orderedEquals(<int>[0xff, 0xd8]));
  expect(bytes.skip(bytes.length - 2), orderedEquals(<int>[0xff, 0xd9]));
  expect(image.decodeJpg(bytes), isNotNull);
}
