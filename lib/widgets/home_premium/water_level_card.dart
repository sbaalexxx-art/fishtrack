import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';

enum WaterTrend { rising, stable, falling }

class WaterLevelCardPremium extends StatelessWidget {
  const WaterLevelCardPremium({
    super.key,
    this.stationName = 'River Thames',
    this.waterLevel = '2.48 m',
    this.trend = WaterTrend.rising,
    this.trendValue = '+12 cm',
    this.lastUpdate = '12 min ago',
  });

  final String stationName;
  final String waterLevel;
  final WaterTrend trend;
  final String trendValue;
  final String lastUpdate;

  Color get _trendColor {
    switch (trend) {
      case WaterTrend.rising:
        return const Color(0xFF2196F3);
      case WaterTrend.stable:
        return const Color(0xFF43A047);
      case WaterTrend.falling:
        return const Color(0xFFE53935);
    }
  }

  IconData get _trendIcon {
    switch (trend) {
      case WaterTrend.rising:
        return Icons.arrow_upward_rounded;
      case WaterTrend.stable:
        return Icons.remove_rounded;
      case WaterTrend.falling:
        return Icons.arrow_downward_rounded;
    }
  }

  String get _status {
    switch (trend) {
      case WaterTrend.rising:
        return "Rising";
      case WaterTrend.stable:
        return "Stable";
      case WaterTrend.falling:
        return "Falling";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 185,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17293A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.water_drop_rounded,
                color: Color(0xFF42A5F5),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "Water Level",
                style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(stationName, style: AppTextStyles.caption),

          const Spacer(),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      waterLevel,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        Icon(_trendIcon, color: _trendColor, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          trendValue,
                          style: TextStyle(
                            color: _trendColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    Text(_status, style: AppTextStyles.caption),
                  ],
                ),
              ),

              SizedBox(
                width: 80,
                height: 60,
                child: CustomPaint(painter: _MiniChartPainter(_trendColor)),
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: Colors.white54),
              const SizedBox(width: 5),
              Text(lastUpdate, style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * .75)
      ..lineTo(size.width * .18, size.height * .68)
      ..lineTo(size.width * .35, size.height * .72)
      ..lineTo(size.width * .55, size.height * .50)
      ..lineTo(size.width * .75, size.height * .55)
      ..lineTo(size.width, size.height * .20);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
