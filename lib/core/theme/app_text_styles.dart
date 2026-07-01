import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle location = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );

  static const TextStyle bigValue = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    color: AppColors.textMuted,
  );

  static const TextStyle trend = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}
