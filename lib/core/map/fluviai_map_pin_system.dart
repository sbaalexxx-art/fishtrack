import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'map_feature_registry.dart';

/// Canonical visual renderer for FluviAI map pins.
///
/// The same semantic presentation can be rasterized once and reused by Mapbox
/// PointAnnotation or style-layer sprites. The renderer intentionally combines
/// shape + icon + color, so pin meaning never depends on color alone.
abstract final class FluviMapPinSystem {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  static Future<Uint8List> rasterize(
    MapFeaturePresentation presentation, {
    required String cacheKey,
    double logicalSize = 42,
    double pixelRatio = 2,
    int badgeCount = 0,
  }) async {
    final safeBadge = badgeCount.clamp(0, 99);
    final key = '$cacheKey|${logicalSize.toStringAsFixed(1)}|${pixelRatio.toStringAsFixed(1)}|b$safeBadge';
    final cached = _cache[key];
    if (cached != null) return cached;

    final width = (logicalSize + 8) * pixelRatio;
    final height = (logicalSize + 8) * pixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio, pixelRatio);

    final center = Offset((logicalSize + 8) / 2, (logicalSize + 8) * .57);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
    final fillPaint = Paint()..color = presentation.color;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFF7FBFF).withValues(alpha: .96);
    final innerPaint = Paint()
      ..color = const Color(0xFF07131C).withValues(alpha: .20);

    final shapePath = _shapePath(
      presentation.markerShape,
      logicalSize,
      center,
    );
    canvas.save();
    canvas.translate(0, 2.2);
    canvas.drawPath(shapePath, shadowPaint);
    canvas.restore();
    canvas.drawPath(shapePath, fillPaint);
    canvas.drawPath(shapePath, borderPaint);

    // Small inner disc keeps Material glyphs readable on satellite imagery.
    final innerRadius = logicalSize * .225;
    canvas.drawCircle(center.translate(0, -1), innerRadius, innerPaint);

    final iconPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(presentation.icon.codePoint),
        style: TextStyle(
          inherit: false,
          color: Colors.white,
          fontSize: logicalSize * .38,
          fontFamily: presentation.icon.fontFamily,
          package: presentation.icon.fontPackage,
          height: 1,
        ),
      ),
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        center.dx - iconPainter.width / 2,
        center.dy - iconPainter.height / 2 - 1,
      ),
    );

    if (safeBadge > 0) {
      final badgeCenter = Offset(center.dx + logicalSize * .31, center.dy - logicalSize * .31);
      final badgeRadius = logicalSize * .145;
      canvas.drawCircle(
        badgeCenter,
        badgeRadius + 1.5,
        Paint()..color = const Color(0xFF07131C),
      );
      canvas.drawCircle(
        badgeCenter,
        badgeRadius,
        Paint()..color = const Color(0xFFF6F9FB),
      );
      final badgePainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: safeBadge > 9 ? '9+' : '$safeBadge',
          style: TextStyle(
            inherit: false,
            color: const Color(0xFF07131C),
            fontSize: logicalSize * .16,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      )..layout();
      badgePainter.paint(
        canvas,
        Offset(
          badgeCenter.dx - badgePainter.width / 2,
          badgeCenter.dy - badgePainter.height / 2,
        ),
      );
    }

    final image = await recorder.endRecording().toImage(
      width.ceil(),
      height.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('Unable to rasterize FluviAI map pin: $cacheKey');
    }
    final result = bytes.buffer.asUint8List();
    _cache[key] = result;
    return result;
  }

  static Path _shapePath(
    MapMarkerShape shape,
    double size,
    Offset center,
  ) {
    final r = size * .39;
    switch (shape) {
      case MapMarkerShape.circle:
        return Path()..addOval(Rect.fromCircle(center: center, radius: r));
      case MapMarkerShape.square:
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: center, width: r * 1.8, height: r * 1.8),
              Radius.circular(size * .16),
            ),
          );
      case MapMarkerShape.diamond:
        return Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r, center.dy)
          ..lineTo(center.dx, center.dy + r)
          ..lineTo(center.dx - r, center.dy)
          ..close();
      case MapMarkerShape.warning:
        return Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r * .96, center.dy + r * .82)
          ..lineTo(center.dx - r * .96, center.dy + r * .82)
          ..close();
      case MapMarkerShape.shield:
        return Path()
          ..moveTo(center.dx, center.dy - r)
          ..quadraticBezierTo(center.dx + r, center.dy - r * .8, center.dx + r * .82, center.dy + r * .2)
          ..quadraticBezierTo(center.dx + r * .62, center.dy + r * .82, center.dx, center.dy + r)
          ..quadraticBezierTo(center.dx - r * .62, center.dy + r * .82, center.dx - r * .82, center.dy + r * .2)
          ..quadraticBezierTo(center.dx - r, center.dy - r * .8, center.dx, center.dy - r)
          ..close();
      case MapMarkerShape.pin:
        final topCenter = center.translate(0, -size * .08);
        return Path()
          ..addOval(Rect.fromCircle(center: topCenter, radius: r * .86))
          ..moveTo(topCenter.dx - r * .48, topCenter.dy + r * .52)
          ..lineTo(center.dx, center.dy + r * 1.18)
          ..lineTo(topCenter.dx + r * .48, topCenter.dy + r * .52)
          ..close();
    }
  }
}
