import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/weather.dart';

enum WeatherVisualKind {
  clear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  rain,
  snow,
  storm,
  unknown,
}

WeatherVisualKind weatherVisualKind(String condition) {
  final value = condition.trim().toLowerCase();
  if (value.contains('thunder') || value.contains('storm')) {
    return WeatherVisualKind.storm;
  }
  if (value.contains('snow') || value.contains('sleet')) {
    return WeatherVisualKind.snow;
  }
  if (value.contains('rain') || value.contains('shower')) {
    return WeatherVisualKind.rain;
  }
  if (value.contains('drizzle')) return WeatherVisualKind.drizzle;
  if (value.contains('fog') || value.contains('mist')) {
    return WeatherVisualKind.fog;
  }
  if (value.contains('overcast')) return WeatherVisualKind.overcast;
  if (value.contains('cloud')) return WeatherVisualKind.partlyCloudy;
  if (value.contains('clear') || value.contains('sunny')) {
    return WeatherVisualKind.clear;
  }
  return WeatherVisualKind.unknown;
}

bool weatherIsDaylight(WeatherData data, {DateTime? now}) {
  if (data.isDay != null) return data.isDay!;
  final localNow = (now ?? DateTime.now()).toLocal();
  final sunrise = data.sunrise?.toLocal();
  final sunset = data.sunset?.toLocal();
  if (sunrise != null && sunset != null && sunset.isAfter(sunrise)) {
    return !localNow.isBefore(sunrise) && localNow.isBefore(sunset);
  }
  return localNow.hour >= 6 && localNow.hour < 20;
}

String weatherConditionLabel(String condition, {required bool isRomanian}) {
  if (!isRomanian) return condition;
  return switch (condition.trim().toLowerCase()) {
    'clear' || 'clear sky' || 'sunny' => 'Senin',
    'mainly clear' || 'mostly clear' => 'Mai mult senin',
    'partly cloudy' => 'Parțial înnorat',
    'cloudy' => 'Înnorat',
    'overcast' => 'Cer acoperit',
    'fog' || 'mist' => 'Ceață',
    'drizzle' => 'Burniță',
    'rain' || 'light rain' || 'moderate rain' || 'heavy rain' => 'Ploaie',
    'showers' || 'rain showers' => 'Averse',
    'snow' || 'snow showers' => 'Ninsoare',
    'sleet' => 'Lapoviță',
    'thunderstorm' || 'thunderstorms' => 'Furtună',
    'hail' => 'Grindină',
    _ => condition,
  };
}

IconData weatherVisualIcon(
  WeatherVisualKind kind, {
  required bool isDaylight,
}) => switch (kind) {
  WeatherVisualKind.clear =>
    isDaylight ? Icons.wb_sunny_rounded : Icons.nightlight_round,
  WeatherVisualKind.partlyCloudy => Icons.cloud_outlined,
  WeatherVisualKind.overcast => Icons.cloud_rounded,
  WeatherVisualKind.fog => Icons.blur_on_rounded,
  WeatherVisualKind.drizzle => Icons.grain_rounded,
  WeatherVisualKind.rain => Icons.water_drop_rounded,
  WeatherVisualKind.snow => Icons.ac_unit_rounded,
  WeatherVisualKind.storm => Icons.flash_on_rounded,
  WeatherVisualKind.unknown => Icons.cloud_outlined,
};

Color weatherVisualAccent(
  WeatherVisualKind kind, {
  required bool isDaylight,
  required Brightness brightness,
}) {
  final dark = brightness == Brightness.dark;
  return switch (kind) {
    WeatherVisualKind.clear =>
      isDaylight
          ? (dark ? const Color(0xFFFFD166) : const Color(0xFFD58A00))
          : const Color(0xFFBFCBFF),
    WeatherVisualKind.partlyCloudy =>
      dark ? const Color(0xFFAEC8D8) : const Color(0xFF4E7187),
    WeatherVisualKind.overcast =>
      dark ? const Color(0xFF9FB0BA) : const Color(0xFF52636D),
    WeatherVisualKind.fog =>
      dark ? const Color(0xFFB8C8C9) : const Color(0xFF647A7C),
    WeatherVisualKind.drizzle || WeatherVisualKind.rain =>
      dark ? const Color(0xFF71C9F4) : const Color(0xFF147EBD),
    WeatherVisualKind.snow =>
      dark ? const Color(0xFFD7F0FF) : const Color(0xFF4B7D9D),
    WeatherVisualKind.storm =>
      dark ? const Color(0xFFD7BCFF) : const Color(0xFF7651B5),
    WeatherVisualKind.unknown =>
      dark ? const Color(0xFF9DB1BC) : const Color(0xFF607D8B),
  };
}

List<Color> weatherAtmosphereGradient(
  WeatherVisualKind kind, {
  required bool isDaylight,
  required Brightness brightness,
}) {
  final dark = brightness == Brightness.dark;
  if (!isDaylight) {
    return switch (kind) {
      WeatherVisualKind.storm => const [Color(0xFF17142B), Color(0xFF282047)],
      WeatherVisualKind.rain ||
      WeatherVisualKind.drizzle => const [Color(0xFF0B1E2B), Color(0xFF12384C)],
      WeatherVisualKind.snow => const [Color(0xFF172633), Color(0xFF2B4150)],
      _ => const [Color(0xFF0A1628), Color(0xFF142A45)],
    };
  }
  if (dark) {
    return switch (kind) {
      WeatherVisualKind.clear => const [Color(0xFF283A43), Color(0xFF405C61)],
      WeatherVisualKind.partlyCloudy => const [
        Color(0xFF22343D),
        Color(0xFF3D555C),
      ],
      WeatherVisualKind.overcast ||
      WeatherVisualKind.fog => const [Color(0xFF253137), Color(0xFF3D4A50)],
      WeatherVisualKind.rain ||
      WeatherVisualKind.drizzle => const [Color(0xFF183141), Color(0xFF24526B)],
      WeatherVisualKind.snow => const [Color(0xFF2A3D48), Color(0xFF49606C)],
      WeatherVisualKind.storm => const [Color(0xFF28243B), Color(0xFF4A3B63)],
      WeatherVisualKind.unknown => const [Color(0xFF223038), Color(0xFF394A52)],
    };
  }
  return switch (kind) {
    WeatherVisualKind.clear => const [Color(0xFFDFF4FF), Color(0xFFFFF0C6)],
    WeatherVisualKind.partlyCloudy => const [
      Color(0xFFDCECF4),
      Color(0xFFF1F5F6),
    ],
    WeatherVisualKind.overcast ||
    WeatherVisualKind.fog => const [Color(0xFFE2E8EA), Color(0xFFF4F6F7)],
    WeatherVisualKind.rain ||
    WeatherVisualKind.drizzle => const [Color(0xFFD7EAF4), Color(0xFFE8F1F5)],
    WeatherVisualKind.snow => const [Color(0xFFE6F4FA), Color(0xFFF8FCFD)],
    WeatherVisualKind.storm => const [Color(0xFFE7E1F5), Color(0xFFF3EFFA)],
    WeatherVisualKind.unknown => const [Color(0xFFE5EEF2), Color(0xFFF5F7F8)],
  };
}

class WeatherSparkline extends StatelessWidget {
  const WeatherSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 92,
    this.strokeWidth = 2.4,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final finite = values
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (finite.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Icon(
            Icons.horizontal_rule_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WeatherSparklinePainter(
          values: finite,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _WeatherSparklinePainter extends CustomPainter {
  const _WeatherSparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    final spread = (maximum - minimum).abs();
    final left = 2.0;
    final right = math.max(left, size.width - 2);
    final top = 8.0;
    final bottom = math.max(top, size.height - 8);

    Offset point(int index) {
      final x = left + (right - left) * index / (values.length - 1);
      final normalized = spread < .0001
          ? .5
          : (values[index] - minimum) / spread;
      final y = bottom - (bottom - top) * normalized;
      return Offset(x, y);
    }

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var index = 1; index < values.length; index++) {
      final previous = point(index - 1);
      final current = point(index);
      final midX = (previous.dx + current.dx) / 2;
      path.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(right, size.height)
      ..lineTo(left, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: .24), color.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final last = point(values.length - 1);
    canvas.drawCircle(last, 4.2, Paint()..color = color);
    canvas.drawCircle(
      last,
      7.4,
      Paint()
        ..color = color.withValues(alpha: .18)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _WeatherSparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

class WeatherHourlyOverviewChart extends StatelessWidget {
  const WeatherHourlyOverviewChart({
    super.key,
    required this.hours,
    required this.lineColor,
    required this.rainColor,
    this.height = 132,
  });

  final List<WeatherForecastHour> hours;
  final Color lineColor;
  final Color rainColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final usable = hours
        .where((hour) => hour.temperature.isFinite)
        .toList(growable: false);
    if (usable.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Icon(
            Icons.horizontal_rule_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WeatherHourlyOverviewPainter(
          hours: usable,
          lineColor: lineColor,
          rainColor: rainColor,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _WeatherHourlyOverviewPainter extends CustomPainter {
  const _WeatherHourlyOverviewPainter({
    required this.hours,
    required this.lineColor,
    required this.rainColor,
    required this.gridColor,
  });

  final List<WeatherForecastHour> hours;
  final Color lineColor;
  final Color rainColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (hours.length < 2 || size.isEmpty) return;
    final temperatures = hours.map((hour) => hour.temperature).toList();
    final minimum = temperatures.reduce(math.min);
    final maximum = temperatures.reduce(math.max);
    final spread = math.max(1.0, maximum - minimum);
    const left = 4.0;
    final right = math.max(left, size.width - 4);
    const top = 10.0;
    final graphBottom = math.max(top + 1, size.height * .72);
    final rainBottom = size.height - 4;

    for (var index = 1; index <= 2; index++) {
      final y = top + (graphBottom - top) * index / 3;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = gridColor.withValues(alpha: .20)
          ..strokeWidth = 1,
      );
    }

    double xAt(int index) => left + (right - left) * index / (hours.length - 1);
    double yAt(int index) {
      final normalized = (temperatures[index] - minimum) / spread;
      return graphBottom - (graphBottom - top) * normalized;
    }

    final barWidth = math.max(2.5, (right - left) / hours.length * .34);
    for (var index = 0; index < hours.length; index++) {
      final chance =
          hours[index].precipitationProbability.clamp(0, 100).toDouble() / 100;
      final amount = (hours[index].precipitation ?? 0).clamp(0, 12).toDouble();
      final normalized = math.max(chance, amount / 12);
      if (normalized <= 0) continue;
      final x = xAt(index);
      final height = (rainBottom - graphBottom - 7) * normalized;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - barWidth / 2, rainBottom - height, barWidth, height),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = rainColor.withValues(alpha: .38));
    }

    final path = Path()..moveTo(xAt(0), yAt(0));
    for (var index = 1; index < hours.length; index++) {
      final previousX = xAt(index - 1);
      final currentX = xAt(index);
      final midX = (previousX + currentX) / 2;
      path.cubicTo(
        midX,
        yAt(index - 1),
        midX,
        yAt(index),
        currentX,
        yAt(index),
      );
    }

    final fill = Path.from(path)
      ..lineTo(right, graphBottom)
      ..lineTo(left, graphBottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: .18),
            lineColor.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, top, size.width, graphBottom - top)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final first = Offset(xAt(0), yAt(0));
    canvas.drawCircle(first, 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _WeatherHourlyOverviewPainter oldDelegate) =>
      oldDelegate.hours != hours ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.rainColor != rainColor ||
      oldDelegate.gridColor != gridColor;
}

class WeatherAtmosphereBackdrop extends StatelessWidget {
  const WeatherAtmosphereBackdrop({
    super.key,
    required this.kind,
    required this.isDaylight,
    required this.foreground,
    this.compact = false,
  });

  final WeatherVisualKind kind;
  final bool isDaylight;
  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: .82, end: 1),
        builder: (context, progress, _) => CustomPaint(
          painter: _WeatherAtmospherePainter(
            kind: kind,
            isDaylight: isDaylight,
            foreground: foreground,
            compact: compact,
            progress: progress,
          ),
        ),
      ),
    );
  }
}

class _WeatherAtmospherePainter extends CustomPainter {
  const _WeatherAtmospherePainter({
    required this.kind,
    required this.isDaylight,
    required this.foreground,
    required this.compact,
    required this.progress,
  });

  final WeatherVisualKind kind;
  final bool isDaylight;
  final Color foreground;
  final bool compact;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final opacity = progress.clamp(0.0, 1.0).toDouble();
    final scale = compact ? .72 : 1.0;
    final celestialCenter = Offset(
      size.width * (compact ? .82 : .79),
      size.height * (compact ? .28 : .27),
    );
    final celestialRadius = (compact ? 24.0 : 42.0) * scale;

    if (kind == WeatherVisualKind.clear ||
        kind == WeatherVisualKind.partlyCloudy ||
        kind == WeatherVisualKind.unknown) {
      if (isDaylight) {
        final glow = Paint()
          ..color = const Color(0xFFFFD166).withValues(alpha: .12 * opacity);
        canvas.drawCircle(celestialCenter, celestialRadius * 1.65, glow);
        canvas.drawCircle(
          celestialCenter,
          celestialRadius,
          Paint()
            ..color = const Color(0xFFFFD166).withValues(alpha: .28 * opacity),
        );
      } else {
        canvas.drawCircle(
          celestialCenter,
          celestialRadius,
          Paint()..color = foreground.withValues(alpha: .18 * opacity),
        );
        canvas.drawCircle(
          celestialCenter.translate(
            celestialRadius * .35,
            -celestialRadius * .14,
          ),
          celestialRadius * .92,
          Paint()..color = const Color(0xFF0A1628).withValues(alpha: .88),
        );
      }
    }

    final cloudPaint = Paint()
      ..color = foreground.withValues(alpha: (compact ? .10 : .13) * opacity);

    void cloud(double x, double y, double w, double h) {
      final cloud = Path()
        ..moveTo(x, y + h * .72)
        ..cubicTo(
          x + w * .03,
          y + h * .46,
          x + w * .18,
          y + h * .39,
          x + w * .30,
          y + h * .43,
        )
        ..cubicTo(
          x + w * .34,
          y + h * .16,
          x + w * .50,
          y + h * .06,
          x + w * .63,
          y + h * .31,
        )
        ..cubicTo(
          x + w * .76,
          y + h * .22,
          x + w * .91,
          y + h * .36,
          x + w * .91,
          y + h * .55,
        )
        ..cubicTo(
          x + w,
          y + h * .59,
          x + w,
          y + h * .82,
          x + w * .88,
          y + h * .86,
        )
        ..lineTo(x + w * .15, y + h * .86)
        ..cubicTo(x + w * .04, y + h * .86, x, y + h * .80, x, y + h * .72)
        ..close();
      canvas.drawPath(cloud, cloudPaint);
    }

    final cloudy =
        kind == WeatherVisualKind.partlyCloudy ||
        kind == WeatherVisualKind.overcast ||
        kind == WeatherVisualKind.rain ||
        kind == WeatherVisualKind.drizzle ||
        kind == WeatherVisualKind.storm ||
        kind == WeatherVisualKind.snow;

    if (cloudy) {
      cloud(
        size.width * .58,
        size.height * .35,
        size.width * .40,
        size.height * (compact ? .24 : .22),
      );
      if (!compact) {
        cloud(
          size.width * .68,
          size.height * .10,
          size.width * .28,
          size.height * .15,
        );
      }
    }

    if (kind == WeatherVisualKind.rain ||
        kind == WeatherVisualKind.drizzle ||
        kind == WeatherVisualKind.storm) {
      final dropPaint = Paint()
        ..color = const Color(0xFF71C9F4).withValues(alpha: .22 * opacity)
        ..strokeWidth = compact ? 1.3 : 1.7
        ..strokeCap = StrokeCap.round;
      final count = compact ? 5 : 10;
      for (var i = 0; i < count; i++) {
        final x = size.width * (.61 + (i % 5) * .07);
        final y = size.height * (.60 + (i ~/ 5) * .10);
        canvas.drawLine(
          Offset(x, y),
          Offset(x - 4 * scale, y + 10 * scale),
          dropPaint,
        );
      }
    }

    if (kind == WeatherVisualKind.snow) {
      final snowPaint = Paint()
        ..color = foreground.withValues(alpha: .22 * opacity);
      final count = compact ? 5 : 10;
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(
          Offset(
            size.width * (.60 + (i % 5) * .075),
            size.height * (.58 + (i ~/ 5) * .12),
          ),
          compact ? 1.5 : 2.1,
          snowPaint,
        );
      }
    }

    if (kind == WeatherVisualKind.fog) {
      final fogPaint = Paint()
        ..color = foreground.withValues(alpha: .10 * opacity)
        ..strokeWidth = compact ? 2 : 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < (compact ? 3 : 5); i++) {
        final y = size.height * (.35 + i * .10);
        canvas.drawLine(
          Offset(size.width * .58, y),
          Offset(size.width * .95, y),
          fogPaint,
        );
      }
    }

    if (kind == WeatherVisualKind.storm && !compact) {
      final bolt = Path()
        ..moveTo(size.width * .80, size.height * .48)
        ..lineTo(size.width * .73, size.height * .68)
        ..lineTo(size.width * .79, size.height * .66)
        ..lineTo(size.width * .74, size.height * .83)
        ..lineTo(size.width * .88, size.height * .59)
        ..lineTo(size.width * .81, size.height * .61)
        ..close();
      canvas.drawPath(
        bolt,
        Paint()
          ..color = const Color(0xFFFFD166).withValues(alpha: .34 * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherAtmospherePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.isDaylight != isDaylight ||
      oldDelegate.foreground != foreground ||
      oldDelegate.compact != compact ||
      oldDelegate.progress != progress;
}

class WeatherInteractiveSeriesChart extends StatefulWidget {
  const WeatherInteractiveSeriesChart({
    super.key,
    required this.values,
    required this.timeLabels,
    required this.valueLabels,
    required this.color,
    this.height = 136,
  });

  final List<double?> values;
  final List<String> timeLabels;
  final List<String> valueLabels;
  final Color color;
  final double height;

  @override
  State<WeatherInteractiveSeriesChart> createState() =>
      _WeatherInteractiveSeriesChartState();
}

class _WeatherInteractiveSeriesChartState
    extends State<WeatherInteractiveSeriesChart> {
  int? _selectedIndex;

  void _select(double dx, double width) {
    if (widget.values.isEmpty || width <= 0) return;
    final normalized = (dx / width).clamp(0.0, 1.0);
    final index = (normalized * (widget.values.length - 1))
        .round()
        .clamp(0, widget.values.length - 1)
        .toInt();
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finite = widget.values.whereType<double>().where((v) => v.isFinite);
    if (finite.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Icon(
            Icons.horizontal_rule_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _select(details.localPosition.dx, constraints.maxWidth),
          onHorizontalDragStart: (details) =>
              _select(details.localPosition.dx, constraints.maxWidth),
          onHorizontalDragUpdate: (details) =>
              _select(details.localPosition.dx, constraints.maxWidth),
          child: CustomPaint(
            painter: _WeatherInteractiveSeriesPainter(
              values: widget.values,
              timeLabels: widget.timeLabels,
              valueLabels: widget.valueLabels,
              color: widget.color,
              gridColor: theme.colorScheme.outlineVariant,
              textColor: theme.colorScheme.onSurface,
              tooltipColor: theme.colorScheme.surfaceContainerHighest,
              selectedIndex: _selectedIndex,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherInteractiveSeriesPainter extends CustomPainter {
  const _WeatherInteractiveSeriesPainter({
    required this.values,
    required this.timeLabels,
    required this.valueLabels,
    required this.color,
    required this.gridColor,
    required this.textColor,
    required this.tooltipColor,
    required this.selectedIndex,
  });

  final List<double?> values;
  final List<String> timeLabels;
  final List<String> valueLabels;
  final Color color;
  final Color gridColor;
  final Color textColor;
  final Color tooltipColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.length < 2) return;
    final validIndexes = <int>[
      for (var i = 0; i < values.length; i++)
        if (values[i] != null && values[i]!.isFinite) i,
    ];
    if (validIndexes.length < 2) return;

    final validValues = validIndexes.map((i) => values[i]!).toList();
    final minimum = validValues.reduce(math.min);
    final maximum = validValues.reduce(math.max);
    final spread = math.max(1.0, maximum - minimum);

    const left = 4.0;
    final right = math.max(left, size.width - 4);
    const top = 18.0;
    final bottom = math.max(top + 1, size.height - 12);

    for (var i = 1; i <= 3; i++) {
      final y = top + (bottom - top) * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = gridColor.withValues(alpha: .18)
          ..strokeWidth = 1,
      );
    }

    double xAt(int index) =>
        left + (right - left) * index / (values.length - 1);
    double yFor(double value) =>
        bottom - (bottom - top) * ((value - minimum) / spread);

    final points = <Offset>[
      for (final index in validIndexes)
        Offset(xAt(index), yFor(values[index]!)),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midX = (previous.dx + current.dx) / 2;
      path.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, bottom)
      ..lineTo(points.first.dx, bottom)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .26), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, top, size.width, bottom - top)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final selected = selectedIndex;
    if (selected == null ||
        selected < 0 ||
        selected >= values.length ||
        values[selected] == null ||
        !values[selected]!.isFinite) {
      final lastIndex = validIndexes.last;
      canvas.drawCircle(
        Offset(xAt(lastIndex), yFor(values[lastIndex]!)),
        4.2,
        Paint()..color = color,
      );
      return;
    }

    final point = Offset(xAt(selected), yFor(values[selected]!));
    canvas.drawLine(
      Offset(point.dx, top),
      Offset(point.dx, bottom),
      Paint()
        ..color = color.withValues(alpha: .42)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(point, 5.2, Paint()..color = color);
    canvas.drawCircle(point, 9, Paint()..color = color.withValues(alpha: .18));

    final time = selected < timeLabels.length ? timeLabels[selected] : '';
    final value = selected < valueLabels.length
        ? valueLabels[selected]
        : values[selected]!.toStringAsFixed(1);
    final label = time.isEmpty ? value : '$time · $value';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: math.min(size.width * .62, 170));

    final bubbleWidth = painter.width + 16;
    final bubbleHeight = painter.height + 10;
    var bubbleLeft = point.dx - bubbleWidth / 2;
    bubbleLeft = bubbleLeft
        .clamp(2.0, math.max(2.0, size.width - bubbleWidth - 2))
        .toDouble();
    final bubbleTop = math.max(1.0, point.dy - bubbleHeight - 12);
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleWidth, bubbleHeight),
      const Radius.circular(9),
    );
    canvas.drawRRect(
      bubble,
      Paint()..color = tooltipColor.withValues(alpha: .96),
    );
    canvas.drawRRect(
      bubble,
      Paint()
        ..color = color.withValues(alpha: .38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    painter.paint(canvas, Offset(bubbleLeft + 8, bubbleTop + 5));
  }

  @override
  bool shouldRepaint(covariant _WeatherInteractiveSeriesPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.timeLabels != timeLabels ||
      oldDelegate.valueLabels != valueLabels ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.tooltipColor != tooltipColor ||
      oldDelegate.selectedIndex != selectedIndex;
}
