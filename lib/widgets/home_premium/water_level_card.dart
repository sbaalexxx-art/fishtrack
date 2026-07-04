import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import 'home_premium_layout.dart';

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

  Color get _trendColor => switch (trend) {
    WaterTrend.rising => const Color(0xFF2196F3),
    WaterTrend.stable => const Color(0xFF43A047),
    WaterTrend.falling => const Color(0xFFE53935),
  };

  IconData get _trendIcon => switch (trend) {
    WaterTrend.rising => Icons.arrow_upward_rounded,
    WaterTrend.stable => Icons.remove_rounded,
    WaterTrend.falling => Icons.arrow_downward_rounded,
  };

  String get _status => switch (trend) {
    WaterTrend.rising => 'Rising',
    WaterTrend.stable => 'Stable',
    WaterTrend.falling => 'Falling',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HomePremiumLayout.of(context);
        final compact = constraints.maxWidth < 180;

        return Container(
          padding: EdgeInsets.all(
            layout.isSmallPhone ? 8 : (layout.isTablet ? 12 : 10),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF17293A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFF42A5F5),
                    size: 20 * layout.iconScale,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'WATER LEVEL',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(
                        fontSize: 16 * layout.titleFontScale,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                stationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          waterLevel,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize:
                                (compact ? 25 : 30) * layout.titleFontScale,
                            height: 1,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(_trendIcon, color: _trendColor, size: 16),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                trendValue,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _trendColor,
                                  fontSize: compact ? 12 : 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: compact ? 46 : 68,
                    height: 38,
                    child: CustomPaint(painter: _MiniChartPainter(_trendColor)),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: Colors.white54),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '$_status • $lastUpdate',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
  bool shouldRepaint(_MiniChartPainter oldDelegate) =>
      oldDelegate.color != color;
}
