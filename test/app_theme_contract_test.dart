import 'dart:io';

import 'package:fishtrack/core/map/map_theme_style.dart';
import 'package:fishtrack/core/theme/app_dimensions.dart';
import 'package:fishtrack/core/theme/app_theme.dart';
import 'package:fishtrack/core/theme/app_text_styles.dart';
import 'package:fishtrack/core/theme/fluviai_commercial_tokens.dart';
import 'package:fishtrack/core/theme/theme_controller.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_foundation.dart';
import 'package:fishtrack/widgets/fluviai/fluviai_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('bundled font assets and licences are declared locally', () {
    const fontAssets = <String>[
      'assets/fonts/geist/Geist-Regular.ttf',
      'assets/fonts/geist/Geist-Medium.ttf',
      'assets/fonts/geist/Geist-SemiBold.ttf',
      'assets/fonts/geist/Geist-Bold.ttf',
      'assets/fonts/geist/Geist-ExtraBold.ttf',
      'assets/fonts/geist/Geist-Black.ttf',
      'assets/fonts/ibm_plex_mono/IBMPlexMono-Regular.ttf',
      'assets/fonts/ibm_plex_mono/IBMPlexMono-Medium.ttf',
      'assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf',
      'assets/fonts/ibm_plex_mono/IBMPlexMono-Bold.ttf',
      'assets/licenses/fonts/Geist-OFL.txt',
      'assets/licenses/fonts/IBM-Plex-Mono-OFL.txt',
    ];

    for (final path in fontAssets) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Missing local asset: $path',
      );
    }

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: Geist'));
    expect(pubspec, contains('family: IBM Plex Mono'));
    expect(pubspec, contains('assets/licenses/fonts/Geist-OFL.txt'));
    expect(pubspec, contains('assets/licenses/fonts/IBM-Plex-Mono-OFL.txt'));

    final home = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();
    expect(home, isNot(contains("fontFamily: 'monospace'")));
    expect(
      home,
      contains('fontFamily: FluviAICommercialTokens.monoFontFamily'),
    );
  });
  test(
    'typography contract is centralized without changing the effective font',
    () {
      expect(FluviAICommercialTokens.primaryFontFamily, 'Geist');
      expect(FluviAICommercialTokens.monoFontFamily, 'IBM Plex Mono');
      expect(
        FluviAICommercialTokens.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );

      expect(
        AppTextStyles.title.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.cardTitle.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.location.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.bigValue.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.body.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.caption.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.trend.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.display.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
      expect(
        AppTextStyles.eyebrow.fontFamily,
        FluviAICommercialTokens.primaryFontFamily,
      );
    },
  );
  test(
    'Bento palette anchors are canonical across production and Figma UI',
    () {
      expect(FluviAICommercialTokens.brandFocus, const Color(0xFF43D9CC));
      expect(FluviAICommercialTokens.accent, const Color(0xFF43D9CC));
      expect(FluviAICommercialTokens.textPrimary, const Color(0xFFF6F9FB));
      expect(FluviAICommercialTokens.waterFalling, const Color(0xFFFA4F4F));
      expect(FluviAICommercialTokens.warning, const Color(0xFFF0BD55));
      expect(FluviAICommercialTokens.premium, const Color(0xFFF0BD55));

      expect(FigmaFluviTokens.cyan, FluviAICommercialTokens.brandFocus);
      expect(FigmaFluviTokens.white, FluviAICommercialTokens.textPrimary);
      expect(FigmaFluviTokens.red, FluviAICommercialTokens.waterFalling);
      expect(FigmaFluviTokens.amber, FluviAICommercialTokens.warning);
      expect(FigmaFluviTokens.background, FluviAICommercialTokens.background);
      expect(FigmaFluviTokens.surface, FluviAICommercialTokens.surface);
    },
  );

  test('Night and Day themes share the approved brand and touch contract', () {
    expect(AppTheme.darkTheme.brightness, Brightness.dark);
    expect(AppTheme.lightTheme.brightness, Brightness.light);
    expect(
      AppTheme.darkTheme.colorScheme.primary,
      FluviAICommercialTokens.accent,
    );
    expect(
      AppTheme.lightTheme.colorScheme.primary,
      FluviAICommercialTokens.accent,
    );
    expect(AppDimensions.minimumTouchTarget, 48);
    expect(AppDimensions.mapControlVisualSize, 42);
  });

  test(
    'selected global theme persists and resolves platform brightness',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = ThemeController(preferences);

      expect(controller.preference, AppThemePreference.automatic);
      expect(controller.themeMode, ThemeMode.system);
      expect(
        controller.effectiveBrightness(Brightness.light),
        Brightness.light,
      );
      expect(controller.effectiveBrightness(Brightness.dark), Brightness.dark);

      await controller.setPreference(AppThemePreference.light);
      expect(controller.themeMode, ThemeMode.light);
      expect(ThemeController(preferences).preference, AppThemePreference.light);

      await controller.setPreference(AppThemePreference.dark);
      expect(controller.themeMode, ThemeMode.dark);
      expect(ThemeController(preferences).preference, AppThemePreference.dark);
    },
  );

  test('Mapbox styles are independent from global brightness', () {
    expect(
      MapThemeStyle.satellite,
      'mapbox://styles/mapbox/satellite-streets-v12',
    );
    expect(MapThemeStyle.standard, mapbox.MapboxStyles.STANDARD);
    expect(MapThemeStyle.outdoors, mapbox.MapboxStyles.OUTDOORS);
    expect(MapThemeStyle.streets, mapbox.MapboxStyles.MAPBOX_STREETS);
  });

  testWidgets('all canonical data states render explicit labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        home: const Scaffold(
          body: Wrap(
            children: [
              FluviStatusBadge(status: FluviDataStatus.live),
              FluviStatusBadge(status: FluviDataStatus.cache),
              FluviStatusBadge(status: FluviDataStatus.offline),
              FluviStatusBadge(status: FluviDataStatus.error),
              FluviStatusBadge(status: FluviDataStatus.loading),
              FluviStatusBadge(status: FluviDataStatus.empty),
            ],
          ),
        ),
      ),
    );
    for (final label in const [
      'LIVE',
      'CACHE',
      'OFFLINE',
      'ERROR',
      'LOADING',
      'NO DATA',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
