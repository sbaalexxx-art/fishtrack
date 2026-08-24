import 'dart:io';

import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/navigation/app_navigator.dart';
import 'package:fishtrack/core/navigation/figma_runtime_manifest.dart';
import 'package:fishtrack/core/localization/locale_controller.dart';
import 'package:fishtrack/core/theme/theme_controller.dart';
import 'package:fishtrack/core/theme/app_theme.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/features/shell/presentation/utilities_hub_page.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/screens/developer_mode_page.dart';
import 'package:fishtrack/screens/main_navigation.dart';
import 'package:fishtrack/widgets/navigation/fluviai_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

late LocaleController _localeController;
late ThemeController _themeController;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'shell-navigation-test-key',
    );
    final preferences = await SharedPreferences.getInstance();
    _localeController = LocaleController(preferences);
    _themeController = ThemeController(preferences);
  });

  testWidgets(
    'approved Home keeps a clean header while preserving the real More drawer',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));

      expect(find.byKey(const ValueKey('home-more-menu-action')), findsNothing);
      expect(
        find.byKey(const ValueKey('commercial-home-context-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('canonical-home-alerts')),
        findsOneWidget,
      );

      await _openMoreDrawer(tester);
      expect(find.byKey(const ValueKey('home-more-drawer')), findsOneWidget);
      expect(find.byType(DeveloperModePage), findsNothing);
    },
  );

  testWidgets('More opens the canonical complete Utilities Hub', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915), realUtilities: true);

    await _openMoreDrawer(tester);
    final utilities = await _revealMoreEntry(tester, 'utilities');
    await tester.ensureVisible(utilities);
    await tester.pump();
    await tester.tap(utilities);
    await _pumpNavigation(tester);

    expect(_findDestination(AppDestination.utilities), findsOneWidget);
    expect(find.byType(FluviAIUtilitiesHubPage), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-nav-fluvi')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active shell opens the approved continuous Home', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(390, 844));

    expect(find.byKey(const ValueKey('canonical-home')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-continuous-canvas')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('commercial-home-map')), findsNothing);
    expect(
      find.byKey(const ValueKey('main-bottom-navigation')),
      findsOneWidget,
    );
    expect(
      Theme.of(tester.element(find.byType(CommercialHomePage))).brightness,
      tester.platformDispatcher.platformBrightness,
    );
    final waterRect = tester.getRect(
      find.byKey(const ValueKey('commercial-water-card')),
    );
    final navigationRect = tester.getRect(
      find.byKey(const ValueKey('main-bottom-navigation')),
    );
    expect(waterRect.top, lessThan(navigationRect.top));

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    final lastContentRect = tester.getRect(
      find.byKey(const ValueKey('home-ask-fluvi')),
    );
    expect(lastContentRect.bottom, lessThan(navigationRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved Home remains safe in landscape', (tester) async {
    await _pumpShell(tester, const Size(915, 412));
    expect(find.byKey(const ValueKey('home-more-menu-action')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-continuous-canvas')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'drawer roots keep navigation while pushed routes use compact hierarchy',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));
      expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);

      await _openMoreDrawer(tester);
      expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);

      final profile = await _revealMoreEntry(tester, 'profile');
      await tester.ensureVisible(profile);
      await tester.pump();
      await tester.tap(profile);
      await _pumpNavigation(tester);
      expect(_findDestination(AppDestination.profile), findsOneWidget);
      expect(find.byType(FluviAIBottomNavigationBar), findsNothing);
      expect(
        find.byKey(const ValueKey('figma-back-button-target')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await _pumpNavigation(tester);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-quick-add')));
      await tester.pumpAndSettle();
      expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);
      expect(find.byType(MainAddActionSheet), findsOneWidget);

      await tester.binding.handlePopRoute();
      await _pumpNavigation(tester);
      expect(find.byType(MainAddActionSheet), findsNothing);
      expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);
      expect(_findDestination(AppDestination.home), findsOneWidget);
    },
  );

  testWidgets(
    'back from a normal route restores its originating selected tab',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));
      await tester.tap(find.byKey(const ValueKey('bottom-nav-map')));
      await tester.pump();

      AppNavigator.open<void>(_shellContext(tester), AppDestination.search);
      await _pumpNavigation(tester);
      await tester.binding.handlePopRoute();
      await _pumpNavigation(tester);

      final navigation = tester.widget<FluviAIBottomNavigationBar>(
        find.byType(FluviAIBottomNavigationBar),
      );
      expect(navigation.selectedIndex, 1);
      expect(_findDestination(AppDestination.map), findsOneWidget);
    },
  );

  testWidgets('Settings theme persists across navigation and updates the app', (
    tester,
  ) async {
    await _themeController.setPreference(AppThemePreference.automatic);
    await _pumpShell(tester, const Size(412, 915));
    AppNavigator.open<void>(_shellContext(tester), AppDestination.settings);
    await _pumpNavigation(tester);

    await tester.tap(find.text('Zi'));
    await tester.pumpAndSettle();
    expect(_themeController.preference, AppThemePreference.light);
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('figma-settings-page'))),
      ).brightness,
      Brightness.light,
    );

    await tester.binding.handlePopRoute();
    await _pumpNavigation(tester);
    AppNavigator.open<void>(_shellContext(tester), AppDestination.settings);
    await _pumpNavigation(tester);
    final selector = tester.widget<SegmentedButton<AppThemePreference>>(
      find.byKey(const ValueKey('settings-theme-selector')),
    );
    expect(selector.selected, {AppThemePreference.light});
    await _themeController.setPreference(AppThemePreference.automatic);
  });

  testWidgets('Alerts settings action opens notification preferences', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    AppNavigator.open<void>(_shellContext(tester), AppDestination.alerts);
    await _pumpNavigation(tester);

    await tester.tap(find.byKey(const ValueKey('alerts-open-settings')));
    await _pumpNavigation(tester);
    expect(
      _findDestination(AppDestination.notificationPreferences),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every canonical More child opens its destination and returns', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    final entries = <(String, AppDestination)>[
      ('profile', AppDestination.profile),
      ('accountSecurity', AppDestination.accountSecurity),
      ('notificationPreferences', AppDestination.notificationPreferences),
      ('alerts', AppDestination.alerts),
      ('myReports', AppDestination.myReports),
      ('myCatches', AppDestination.myCatches),
      ('favorites', AppDestination.favorites),
      ('journal', AppDestination.journal),
      ('premium', AppDestination.premium),
      ('regulations', AppDestination.regulations),
      ('settings', AppDestination.settings),
      ('privacy', AppDestination.privacy),
      ('terms', AppDestination.terms),
      ('licences', AppDestination.licences),
      ('legal', AppDestination.legal),
      ('support', AppDestination.support),
      ('about', AppDestination.about),
    ];

    for (final (keySuffix, destination) in entries) {
      await _returnHome(tester);
      await _openMoreDrawer(tester);
      final entry = await _revealMoreEntry(tester, keySuffix);
      expect(
        entry,
        findsOneWidget,
        reason: 'Missing More entry key more-$keySuffix',
      );
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await _pumpNavigation(tester);
      expect(
        _findDestination(destination),
        findsOneWidget,
        reason: 'More entry $keySuffix did not open ${destination.name}',
      );
      expect(find.byType(DeveloperModePage), findsNothing);
      expect(tester.takeException(), isNull, reason: 'More entry $keySuffix');
      await tester.binding.handlePopRoute();
      await _pumpNavigation(tester);
      expect(_findDestination(AppDestination.home), findsOneWidget);
    }
  });

  testWidgets(
    'Saved waters and places opens the canonical Favorites destination',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));

      await _openMoreDrawer(tester);
      final entry = await _revealMoreEntry(tester, 'favorites');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await _pumpNavigation(tester);

      expect(_findDestination(AppDestination.favorites), findsOneWidget);
      expect(
        find.byKey(const ValueKey('figma-favorites-page')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('utilities-hub-page')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Utilities Hydro Pulse Back restores the Utilities caller', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915), realUtilities: true);
    final context = _shellContext(tester);
    final container = ProviderScope.containerOf(context, listen: false);
    container
        .read(fluviAccessTierProvider.notifier)
        .setTier(FluviAccessTier.premium);

    await AppNavigator.open<void>(context, AppDestination.utilities);
    await _pumpNavigation(tester);
    expect(find.byKey(const ValueKey('utilities-hub-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('utility-water.hydro-pulse')));
    await _pumpNavigation(tester);
    expect(find.text('Map runtime'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpNavigation(tester);
    expect(find.byKey(const ValueKey('utilities-hub-page')), findsOneWidget);
    expect(find.text('Map runtime'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('programmatic main-tab launch preserves a non-Home caller', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915), realUtilities: true);
    final context = _shellContext(tester);

    await AppNavigator.open<void>(context, AppDestination.utilities);
    await _pumpNavigation(tester);
    await AppNavigator.open<void>(context, AppDestination.activity);
    await _pumpNavigation(tester);
    expect(find.text('Community runtime'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpNavigation(tester);
    expect(find.byKey(const ValueKey('utilities-hub-page')), findsOneWidget);
    expect(find.text('Community runtime'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Global Search dismisses its autofocus IME before route Back', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915), realUtilities: true);
    final context = _shellContext(tester);

    await AppNavigator.open<void>(context, AppDestination.utilities);
    await _pumpNavigation(tester);
    await tester.tap(
      find.byKey(const ValueKey('utilities-section-discoveryAndAssistance')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('utility-map.search')));
    await _pumpNavigation(tester);

    final searchField = find.byKey(const ValueKey('figma-global-search-field'));
    expect(searchField, findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(searchField, findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpNavigation(tester);
    expect(find.byKey(const ValueKey('utilities-hub-page')), findsOneWidget);
    expect(searchField, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation and Quick Add execute every action', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));

    for (final (key, destination) in const [
      ('bottom-nav-map', AppDestination.map),
      ('bottom-nav-activity', AppDestination.activity),
      ('bottom-nav-fluvi', AppDestination.fluvi),
      ('bottom-nav-home', AppDestination.home),
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      expect(_findDestination(destination), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('bottom-nav-map')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_findDestination(AppDestination.home), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bottom-nav-quick-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-save-place')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Select a place, water or station first.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bottom-nav-quick-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-catch')));
    await _pumpNavigation(tester);
    expect(_findDestination(AppDestination.addCatch), findsOneWidget);

    await _returnHome(tester);
    await tester.tap(find.byKey(const ValueKey('bottom-nav-quick-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-report')));
    await _pumpNavigation(tester);
    expect(_findDestination(AppDestination.addReport), findsOneWidget);
  });

  testWidgets('all companion paths open real runtime widgets', (tester) async {
    await _pumpShell(tester, const Size(412, 915));
    final paths = <(String, AppDestination)>[
      ('/home', AppDestination.home),
      ('/map', AppDestination.map),
      ('/activity', AppDestination.activity),
      ('/utilities', AppDestination.utilities),
      ('/water/runtime-entity', AppDestination.water),
      ('/alerts/new', AppDestination.newAlert),
      ('/alerts', AppDestination.alerts),
      ('/reports/new', AppDestination.addReport),
      ('/me/reports', AppDestination.myReports),
      ('/community', AppDestination.community),
      ('/reports/runtime-report', AppDestination.reportDetail),
      ('/catches/new', AppDestination.addCatch),
      ('/me/catches', AppDestination.myCatches),
      ('/favorites', AppDestination.favorites),
      ('/fluvi/runtime-entity', AppDestination.fluvi),
      ('/ask-fluvi', AppDestination.askFluvi),
      ('/profile', AppDestination.profile),
      ('/account/security', AppDestination.accountSecurity),
      ('/premium', AppDestination.premium),
      ('/reports/runtime-report/confirmed', AppDestination.reportConfirmed),
      ('/premium/restored', AppDestination.premiumRestored),
    ];

    for (final (path, destination) in paths) {
      await _returnHome(tester);
      final context = _shellContext(tester);
      AppNavigator.openPath<void>(context, path);
      await _pumpNavigation(tester);
      expect(
        _findDestination(destination),
        findsOneWidget,
        reason: '$path did not render ${destination.name}',
      );
    }
  });

  testWidgets('secondary hubs do not duplicate the root bottom navigation', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    AppNavigator.open<void>(_shellContext(tester), AppDestination.water);
    await _pumpNavigation(tester);

    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
    expect(find.byKey(const ValueKey('bottom-nav-home')), findsNothing);
    expect(find.byKey(const ValueKey('bottom-nav-map')), findsNothing);
    expect(find.byKey(const ValueKey('bottom-nav-quick-add')), findsNothing);
    expect(find.byKey(const ValueKey('bottom-nav-activity')), findsNothing);
    expect(find.byKey(const ValueKey('bottom-nav-fluvi')), findsNothing);
    expect(
      find.byKey(const ValueKey('figma-back-button-target')),
      findsOneWidget,
    );
  });

  testWidgets('every registered destination has an executable runtime widget', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    for (final destination in AppDestination.values) {
      await _returnHome(tester);
      final context = _shellContext(tester);
      AppNavigator.open<void>(context, destination);
      await _pumpNavigation(tester);
      expect(
        _findDestination(_runtimeDestination(destination)),
        findsOneWidget,
        reason: '${destination.name} has no executable runtime widget',
      );
    }
  });

  testWidgets(
    'all current canonical Figma frame contracts resolve at runtime',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));
      expect(FigmaRuntimeManifest.allOfficialFrames, hasLength(11));
      for (final frame in FigmaRuntimeManifest.allOfficialFrames) {
        await _returnHome(tester);
        AppNavigator.open<void>(_shellContext(tester), frame.destination);
        await _pumpNavigation(tester);
        expect(
          _findDestination(frame.destination),
          findsOneWidget,
          reason: '${frame.nodeId} ${frame.name} is not executable',
        );
      }
    },
  );

  testWidgets('all canonical Figma connections execute their target widgets', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    for (final connection in FigmaRuntimeManifest.connections) {
      await _returnHome(tester);
      final context = _shellContext(tester);
      AppNavigator.open<void>(context, connection.to);
      await _pumpNavigation(tester);
      expect(
        _findDestination(connection.to),
        findsOneWidget,
        reason:
            'Connection ${connection.index} did not open ${connection.to.name}',
      );
    }
  });

  testWidgets('the seven critical flows open every runtime step', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    const flows = <List<AppDestination>>[
      [AppDestination.water, AppDestination.newAlert, AppDestination.alerts],
      [AppDestination.map, AppDestination.addReport, AppDestination.myReports],
      [AppDestination.addCatch, AppDestination.myCatches],
      [
        AppDestination.community,
        AppDestination.reportDetail,
        AppDestination.reportConfirmed,
      ],
      [AppDestination.favorites, AppDestination.water],
      [AppDestination.fluvi, AppDestination.askFluvi],
      [
        AppDestination.profile,
        AppDestination.premium,
        AppDestination.premiumRestored,
      ],
    ];

    for (final flow in flows) {
      for (final destination in flow) {
        await _returnHome(tester);
        final context = _shellContext(tester);
        AppNavigator.open<void>(context, destination);
        await _pumpNavigation(tester);
        expect(_findDestination(destination), findsOneWidget);
      }
    }
  });

  testWidgets(
    'station Map intent pushes context and publishes station identity',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));
      final station = _batchOneStation();
      final context = _shellContext(tester);

      AppNavigator.open<void>(context, AppDestination.map, arguments: station);
      await _pumpNavigation(tester);

      final selected = ProviderScope.containerOf(
        _shellContext(tester),
        listen: false,
      ).read(selectedContextProvider);
      expect(selected?.stationId, station.id);
      expect(selected?.latitude, station.latitude);
      expect(selected?.longitude, station.longitude);
      expect(_findDestination(AppDestination.map), findsOneWidget);
      expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);
      final navigation = tester.widget<FluviAIBottomNavigationBar>(
        find.byType(FluviAIBottomNavigationBar),
      );
      expect(navigation.selectedIndex, 1);
    },
  );

  testWidgets(
    'contextual Water Map reuses the root map runtime without duplicate routes',
    (tester) async {
      await _pumpShell(tester, const Size(412, 915));

      for (final station in [_batchOneStation(), _secondBatchOneStation()]) {
        AppNavigator.open<void>(
          _shellContext(tester),
          AppDestination.water,
          arguments: station,
        );
        await _pumpNavigation(tester);
        expect(_findDestination(AppDestination.water), findsOneWidget);

        AppNavigator.open<void>(
          _shellContext(tester),
          AppDestination.map,
          arguments: station,
        );
        await _pumpNavigation(tester);

        expect(_findDestination(AppDestination.map), findsOneWidget);
        expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);

        await tester.binding.handlePopRoute();
        await _pumpNavigation(tester);

        final selected = ProviderScope.containerOf(
          _shellContext(tester),
          listen: false,
        ).read(selectedContextProvider);
        expect(selected?.stationId, station.id);
        expect(selected?.latitude, station.latitude);
        expect(selected?.longitude, station.longitude);
        expect(_findDestination(AppDestination.home), findsOneWidget);
        expect(find.byType(FluviAIBottomNavigationBar), findsOneWidget);
        final navigation = tester.widget<FluviAIBottomNavigationBar>(
          find.byType(FluviAIBottomNavigationBar),
        );
        expect(navigation.selectedIndex, 0);
      }
    },
  );

  testWidgets('Alert Editor preserves explicit Water station context', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));
    final station = _batchOneStation();

    AppNavigator.open<void>(
      _shellContext(tester),
      AppDestination.newAlert,
      arguments: station,
    );
    await _pumpNavigation(tester);

    expect(find.text('Baziaș'), findsOneWidget);
    expect(find.text('Nicio entitate selectată'), findsNothing);
    expect(find.byKey(const ValueKey('main-bottom-navigation')), findsNothing);
  });

  testWidgets('Premium and restore use the existing immersive shell contract', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(412, 915));

    for (final destination in [
      AppDestination.premium,
      AppDestination.restore,
    ]) {
      await _returnHome(tester);
      AppNavigator.open<void>(_shellContext(tester), destination);
      await _pumpNavigation(tester);
      expect(_findDestination(destination), findsOneWidget);
      expect(
        find.byKey(const ValueKey('main-bottom-navigation')),
        findsNothing,
        reason: '${destination.name} must remain immersive',
      );
    }
  });

  test('runtime shell has no empty interaction callbacks or legacy imports', () {
    final files = <String>[
      'lib/screens/main_navigation.dart',
      'lib/core/navigation/app_navigator.dart',
      'lib/widgets/home_premium/side_menu.dart',
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ];
    final emptyCallback = RegExp(
      r'(?:onTap|onPressed)\s*:\s*\(\)\s*(?:async\s*)?\{\s*\}',
      multiLine: true,
    );
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(emptyCallback.hasMatch(source), isFalse, reason: path);
      expect(source, isNot(contains('design_lab')), reason: path);
      if (path ==
          'lib/features/commercial_home/presentation/commercial_home_page.dart') {
        expect(
          source,
          contains('if (!BuildModeService.isDeveloperVisible) return;'),
          reason: 'Developer Mode must refuse access outside debug/PO builds',
        );
        expect(
          RegExp(
            r'onDeveloperMode:\s*BuildModeService\.isDeveloperVisible\s*'
            r'\?\s*_openDeveloperMode\s*:\s*null',
            multiLine: true,
          ).hasMatch(source),
          isTrue,
          reason: 'Home must hide Developer Mode outside debug/PO builds',
        );
        expect(
          source,
          contains('DeveloperModePage'),
          reason: 'PO Developer Console is an intentional v10 capability',
        );
      } else {
        expect(source, isNot(contains('DeveloperModePage')), reason: path);
      }
      expect(source, isNot(contains("screens/home_page.dart")), reason: path);
      expect(
        source,
        isNot(contains("screens/home_premium_page.dart")),
        reason: path,
      );
    }
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  bool realUtilities = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: LocaleScope(
        controller: _localeController,
        child: ThemeScope(
          controller: _themeController,
          child: ListenableBuilder(
            listenable: _themeController,
            builder: (context, _) => MaterialApp(
              theme: AppTheme.lightTheme.copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              darkTheme: AppTheme.darkTheme.copyWith(
                splashFactory: NoSplash.splashFactory,
              ),
              themeMode: _themeController.themeMode,
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MainNavigation(
                homeDataSource: _EmptyCommercialHomeDataSource(),
                homeMapOverride: const ColoredBox(color: Color(0xFF0B151E)),
                mapPageOverride: const _ShellStub(label: 'Map runtime'),
                communityPageOverride: const _ShellStub(
                  label: 'Community runtime',
                ),
                favoritesPageOverride: realUtilities
                    ? null
                    : const _ShellStub(label: 'Favorites runtime'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _returnHome(WidgetTester tester) async {
  final context = _shellContext(tester);
  Navigator.of(context).popUntil((route) => route.isFirst);
  AppNavigator.open<void>(context, AppDestination.home);
  await _pumpNavigation(tester);
}

BuildContext _shellContext(WidgetTester tester) =>
    tester.element(find.byType(MainNavigation, skipOffstage: false));

Finder _findDestination(AppDestination destination) =>
    find.byKey(AppNavigator.destinationKey(destination), skipOffstage: false);

AppDestination _runtimeDestination(AppDestination destination) =>
    destination == AppDestination.contextualMap
    ? AppDestination.map
    : destination;

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openMoreDrawer(WidgetTester tester) async {
  final scaffold = find.descendant(
    of: find.byType(CommercialHomePage, skipOffstage: false),
    matching: find.byType(Scaffold, skipOffstage: false),
  );
  expect(scaffold, findsOneWidget);
  tester.state<ScaffoldState>(scaffold).openDrawer();
  await tester.pumpAndSettle();
}

Future<Finder> _revealMoreEntry(WidgetTester tester, String keySuffix) async {
  final entry = find.byKey(ValueKey('more-$keySuffix'));
  if (entry.evaluate().isNotEmpty) return entry;

  final familyIndex = switch (keySuffix) {
    'favorites' || 'myCatches' || 'journal' || 'myReports' => 0,
    'utilities' || 'alerts' || 'notificationPreferences' => 1,
    'regulations' => 2,
    'profile' || 'accountSecurity' || 'premium' || 'settings' => 3,
    'support' || 'privacy' || 'terms' || 'licences' || 'legal' || 'about' => 4,
    _ => throw StateError('No Foundation 1A family for more-$keySuffix'),
  };
  final family = find.byKey(ValueKey('burger-family-$familyIndex'));
  expect(family, findsOneWidget);
  await tester.ensureVisible(family);
  await tester.tap(family);
  await tester.pumpAndSettle();

  return entry;
}

class _EmptyCommercialHomeDataSource implements CommercialHomeDataSource {
  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      CommercialHomeSnapshot(
        station: null,
        water: null,
        weather: null,
        score: null,
        communityPosts: const [],
        loadedAt: DateTime.now(),
      );
}

class _ShellStub extends StatelessWidget {
  const _ShellStub({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF071018),
    child: Center(child: Text(label)),
  );
}

Station _batchOneStation() => Station(
  id: 'bazias-canonical',
  name: 'Baziaș',
  river: 'Dunărea',
  level: 548,
  trend: WaterTrend.rising,
  latitude: 44.8167,
  longitude: 21.3944,
  lastUpdate: DateTime(2026, 8, 4),
  hasWaterLevel: true,
  hasKnownTrend: true,
  waterLevelSource: 'AFDJ',
);

Station _secondBatchOneStation() => Station(
  id: 'runtime-station-two',
  name: 'Runtime station two',
  river: 'Dunărea',
  level: 612,
  trend: WaterTrend.stable,
  latitude: 45.25,
  longitude: 22.75,
  lastUpdate: DateTime(2026, 8, 4),
  hasWaterLevel: true,
  hasKnownTrend: true,
  waterLevelSource: 'runtime-test',
);
