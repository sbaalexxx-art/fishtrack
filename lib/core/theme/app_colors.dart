import 'package:flutter/material.dart';

import 'fluviai_commercial_tokens.dart';

class AppColors {
  AppColors._();

  // Canonical aliases retained for the older widgets still in the runtime.
  static const Color background = FluviAICommercialTokens.background;

  // Cards
  static const Color card = FluviAICommercialTokens.surface;

  // Primary
  static const Color primary = FluviAICommercialTokens.accent;

  // Trend colors
  static const Color rising = FluviAICommercialTokens.waterRising;
  static const Color stable = FluviAICommercialTokens.waterStable;
  static const Color falling = FluviAICommercialTokens.waterFalling;

  // Sections
  static const Color weather = FluviAICommercialTokens.warning;
  static const Color community = FluviAICommercialTokens.waterStable;
  static const Color ai = FluviAICommercialTokens.brandFocus;

  // Text
  static const Color textPrimary = FluviAICommercialTokens.textPrimary;
  static const Color textSecondary = FluviAICommercialTokens.textSecondary;
  static const Color textMuted = FluviAICommercialTokens.textMuted;

  // Divider
  static const Color divider = FluviAICommercialTokens.border;
}
