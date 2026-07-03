import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';

class WeatherCardPremium extends StatelessWidget {
  const WeatherCardPremium({
    super.key,
    this.temperature = 24,
    this.condition = 'Sunny',
    this.wind = '9 km/h',
    this.humidity = '58%',
  });

  final int temperature;
  final String condition;
  final String wind;
  final String humidity;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 185,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2216),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFB300), size: 20),
              SizedBox(width: 8),
              Text(
                'Weather',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const Spacer(),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.wb_sunny_rounded,
                size: 46,
                color: Color(0xFFFFC107),
              ),

              const SizedBox(width: 14),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$temperature°',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(condition, style: AppTextStyles.caption),
                ],
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.water_drop_outlined,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(humidity, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.air, color: Colors.white70, size: 16),
                    const SizedBox(width: 5),
                    Text(wind, style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
