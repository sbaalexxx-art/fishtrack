import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'fluviai_commercial_tokens.dart';

class AppTextStyles {
  AppTextStyles._();

  // Section titles

  static const TextStyle title = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  // Card titles

  static const TextStyle cardTitle = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle location = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 14,
    color: AppColors.textSecondary,
  );

  static const TextStyle bigValue = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 34,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 15,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 13,
    color: AppColors.textMuted,
  );

  static const TextStyle trend = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle display = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  static const TextStyle eyebrow = TextStyle(
    fontFamily: FluviAICommercialTokens.primaryFontFamily,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );
}
