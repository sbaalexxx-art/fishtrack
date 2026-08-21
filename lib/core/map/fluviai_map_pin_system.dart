import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'map_feature_registry.dart';

/// Canonical visual renderer for FluviAI map pins.
///
/// The same semantic presentation can be rasterized once and reused by Mapbox
/// PointAnnotation or style-layer sprites. The renderer intentionally combines
/// shape + icon + color, so pin meaning never depends on color alone.
///
/// The premium treatment is deliberately restrained: a dark satellite-safe
/// contact shadow, a low-alpha semantic halo, a two-stop semantic gradient,
/// and a high-contrast inner glyph disc. No state or business meaning is
/// encoded by decoration alone.
abstract final class FluviMapPinSystem {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  static const Color _ink = Color(0xFF07131C);
  static const Color _deepInk = Color(0xFF030B10);
  static const Color _paper = Color(0xFFF7FBFF);

  static Future<Uint8List> rasterize(
    MapFeaturePresentation presentation, {
    required String cacheKey,
    double logicalSize = 42,
    double pixelRatio = 2,
    int badgeCount = 0,
  }) async {
    final safeBadge = badgeCount.clamp(0, 99);
    final key =
        '$cacheKey|premium-v2|${logicalSize.toStringAsFixed(1)}|'
        '${pixelRatio.toStringAsFixed(1)}|b$safeBadge';
    final cached = _cache[key];
    if (cached != null) return cached;

    final width = (logicalSize + 10) * pixelRatio;
    final height = (logicalSize + 11) * pixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio, pixelRatio);

    final center = Offset((logicalSize + 10) / 2, (logicalSize + 9) * .57);
    final shapePath = _shapePath(
      presentation.markerShape,
      logicalSize,
      center,
    );

    // A soft semantic halo improves discovery on satellite imagery without
    // turning the marker into a neon glow.
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.2
      ..color = presentation.color.withValues(alpha: .16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.2);
    canvas.drawPath(shapePath, haloPaint);

    // Two shadows: one ambient and one short contact shadow. This gives the
    // marker depth while keeping its footprint readable on bright basemaps.
    final ambientShadow = Paint()
      ..color = Colors.black.withValues(alpha: .34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.6);
    canvas.save();
    canvas.translate(0, 3.0);
    canvas.drawPath(shapePath, ambientShadow);
    canvas.restore();

    final contactShadow = Paint()
      ..color = _deepInk.withValues(alpha: .58)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.7);
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawPath(shapePath, contactShadow);
    canvas.restore();

    final bounds = shapePath.getBounds();
    final topColor = Color.lerp(presentation.color, Colors.white, .14)!;
    final bottomColor = Color.lerp(presentation.color, _ink, .34)!;
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(bounds.center.dx, bounds.top),
        Offset(bounds.center.dx, bounds.bottom),
        <Color>[topColor, presentation.color, bottomColor],
        const <double>[0, .52, 1],
      );
    canvas.drawPath(shapePath, fillPaint);

    // Thin dark keyline under a crisp light edge keeps every semantic color
    // readable in day/night, outdoors and over photographic satellite tiles.
    final keylinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.25
      ..color = _ink.withValues(alpha: .62);
    canvas.drawPath(shapePath, keylinePaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..color = _paper.withValues(alpha: .96);
    canvas.drawPath(shapePath, borderPaint);

    // A restrained top highlight gives the pin a premium enamel-like finish
    // while leaving the semantic color dominant.
    final highlightRect = Rect.fromCenter(
      center: center.translate(0, -logicalSize * .205),
      width: logicalSize * .42,
      height: logicalSize * .105,
    );
    canvas.drawOval(
      highlightRect,
      Paint()..color = Colors.white.withValues(alpha: .17),
    );

    // The inner disc isolates the glyph from the semantic color. A subtle
    // semantic ring still links the glyph to the outer marker.
    final innerCenter = center.translate(0, -1);
    final innerRadius = logicalSize * .225;
    canvas.drawCircle(
      innerCenter,
      innerRadius + 1.25,
      Paint()..color = _paper.withValues(alpha: .88),
    );
    canvas.drawCircle(
      innerCenter,
      innerRadius,
      Paint()..color = _ink.withValues(alpha: .92),
    );
    canvas.drawCircle(
      innerCenter,
      innerRadius - .8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = presentation.color.withValues(alpha: .68),
    );

    final iconPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(presentation.icon.codePoint),
        style: TextStyle(
          inherit: false,
          color: _paper,
          fontSize: logicalSize * .36,
          fontFamily: presentation.icon.fontFamily,
          package: presentation.icon.fontPackage,
          height: 1,
        ),
      ),
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        innerCenter.dx - iconPainter.width / 2,
        innerCenter.dy - iconPainter.height / 2,
      ),
    );

    if (safeBadge > 0) {
      final badgeCenter = Offset(
        center.dx + logicalSize * .31,
        center.dy - logicalSize * .31,
      );
      final badgeRadius = logicalSize * .145;
      canvas.drawCircle(
        badgeCenter,
        badgeRadius + 2,
        Paint()..color = _ink,
      );
      canvas.drawCircle(
        badgeCenter,
        badgeRadius + .75,
        Paint()..color = presentation.color,
      );
      canvas.drawCircle(
        badgeCenter,
        badgeRadius,
        Paint()..color = _paper,
      );
      final badgePainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: safeBadge > 9 ? '9+' : '$safeBadge',
          style: TextStyle(
            inherit: false,
            color: _ink,
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
              Rect.fromCenter(
                center: center,
                width: r * 1.8,
                height: r * 1.8,
              ),
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
          ..quadraticBezierTo(
            center.dx + r,
            center.dy - r * .8,
            center.dx + r * .82,
            center.dy + r * .2,
          )
          ..quadraticBezierTo(
            center.dx + r * .62,
            center.dy + r * .82,
            center.dx,
            center.dy + r,
          )
          ..quadraticBezierTo(
            center.dx - r * .62,
            center.dy + r * .82,
            center.dx - r * .82,
            center.dy + r * .2,
          )
          ..quadraticBezierTo(
            center.dx - r,
            center.dy - r * .8,
            center.dx,
            center.dy - r,
          )
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
