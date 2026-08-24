import 'package:fishtrack/core/localization/locale_controller.dart';
import 'package:fishtrack/core/theme/app_theme.dart';
import 'package:fishtrack/core/theme/theme_controller.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_account_pages.dart';
import 'package:fishtrack/features/shell/presentation/activity_hub_page.dart';
import 'package:fishtrack/features/shell/presentation/utilities_hub_page.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/widgets/home_premium/side_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'day-night-foundation-test-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const {
      'fluviai_language_code': 'ro',
    });
  });

  test('Auto follows both platform brightness values', () async {
    final preferences = await SharedPreferences.getInstance();
    final controller = ThemeController(preferences);

    expect(controller.preference, AppThemePreference.automatic);
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.effectiveBrightness(Brightness.light), Brightness.light);
    expect(controller.effectiveBrightness(Brightness.dark), Brightness.dark);
  });

  testWidgets('Activity and Explore share the canonical themed canvas', (
    tester,
  ) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await _pumpPage(
        tester,
        brightness: brightness,
        page: const FluviAIActivityHubPage(),
      );
      final activity = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('activity-hub-page')),
      );
      final expectedTheme = brightness == Brightness.light
          ? AppTheme.lightTheme
          : AppTheme.darkTheme;
      expect(activity.color, expectedTheme.scaffoldBackgroundColor);

      await _pumpPage(
        tester,
        brightness: brightness,
        page: FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}),
      );
      final utilities = tester.widget<Material>(
        find.byKey(const ValueKey('utilities-hub-page')),
      );
      expect(utilities.color, expectedTheme.scaffoldBackgroundColor);
    }
  });

  testWidgets('Utilities search is one functional semantic surface', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      brightness: Brightness.light,
      page: FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}),
    );

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('utilities-search-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect(decoration.border, isA<Border>());
    expect(surface.constraints?.minHeight, greaterThanOrEqualTo(48));

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('utilities-search-field')),
    );
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.enabledBorder, InputBorder.none);
    expect(field.decoration?.focusedBorder, InputBorder.none);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('shared surfaces consume the active Day and Night schemes', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      brightness: Brightness.light,
      page: const FigmaSettingsPage(),
    );
    final dayMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('settings-appearance-surface')),
    );
    expect(dayMaterial.color, AppTheme.lightTheme.colorScheme.surface);

    await _pumpPage(
      tester,
      brightness: Brightness.light,
      page: FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}),
    );
    final dayUtilities = tester.widget<Material>(
      find.byKey(const ValueKey('utilities-hub-page')),
    );
    expect(dayUtilities.color, AppTheme.lightTheme.scaffoldBackgroundColor);

    await _pumpPage(
      tester,
      brightness: Brightness.dark,
      page: const FigmaSettingsPage(),
    );
    final nightMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('settings-appearance-surface')),
    );
    expect(nightMaterial.color, AppTheme.darkTheme.colorScheme.surface);

    await _pumpPage(
      tester,
      brightness: Brightness.dark,
      page: FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}),
    );
    final nightUtilities = tester.widget<Material>(
      find.byKey(const ValueKey('utilities-hub-page')),
    );
    expect(nightUtilities.color, AppTheme.darkTheme.scaffoldBackgroundColor);
  });

  testWidgets('Burger and Utilities remain touch-safe in Day and Night', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await _pumpPage(
        tester,
        brightness: brightness,
        page: const HomeSideMenu(),
      );
      for (var index = 0; index < 5; index++) {
        final family = find.byKey(ValueKey('burger-family-$index'));
        expect(family, findsOneWidget);
        expect(tester.getSize(family).height, greaterThanOrEqualTo(52));
      }
      await tester.tap(find.byKey(const ValueKey('burger-family-3')));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('more-profile'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);

      await _pumpPage(
        tester,
        brightness: brightness,
        page: FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}),
      );
      final section = find.byKey(
        const ValueKey('utilities-section-toggle-waterTools'),
      );
      expect(tester.getSize(section).height, greaterThanOrEqualTo(56));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('utility-water.hydro-pulse')))
            .height,
        greaterThanOrEqualTo(60),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required Brightness brightness,
  required Widget page,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  await theme.setPreference(
    brightness == Brightness.light
        ? AppThemePreference.light
        : AppThemePreference.dark,
  );
  final locale = LocaleController(preferences);

  await tester.pumpWidget(
    ProviderScope(
      child: LocaleScope(
        controller: locale,
        child: ThemeScope(
          controller: theme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ro'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            home: page,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
