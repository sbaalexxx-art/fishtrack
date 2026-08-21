import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/navigation/app_navigator.dart';
import 'package:fishtrack/main.dart' as app;

int _passes = 0;
int _warns = 0;
int _fails = 0;

void _record(String status, String screen, String check, [Object? detail]) {
  switch (status) {
    case 'PASS':
      _passes++;
    case 'WARN':
      _warns++;
    case 'FAIL':
      _fails++;
  }

  final clean = (detail ?? '')
      .toString()
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('|', '/')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final limited = clean.length > 1200 ? clean.substring(0, 1200) : clean;

  // Structured line consumed later by the PowerShell Beta report builder.
  // ignore: avoid_print
  print('FLUVIAI_BETA_AUDIT|$status|$screen|$check|$limited');
}

Future<void> _boundedPump(
  WidgetTester tester, {
  int cycles = 16,
  Duration step = const Duration(milliseconds: 250),
}) async {
  for (var i = 0; i < cycles; i++) {
    await tester.pump(step);
  }
}

Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return true;
  }

  return finder.evaluate().isNotEmpty;
}

Finder _destination(AppDestination destination) => find.byKey(
  AppNavigator.destinationKey(
    destination == AppDestination.contextualMap
        ? AppDestination.map
        : destination,
  ),
  skipOffstage: false,
);

BuildContext? _shellContext(WidgetTester tester) {
  final home = _destination(AppDestination.home);
  if (home.evaluate().isEmpty) return null;
  return tester.element(home.first);
}

Future<void> _drainFlutterExceptions(WidgetTester tester, String screen) async {
  var found = false;

  while (true) {
    final exception = tester.takeException();
    if (exception == null) break;

    found = true;
    _record('FAIL', screen, 'flutter-exception', exception);
  }

  if (!found) {
    _record('PASS', screen, 'flutter-exception', 'none');
  }
}

Future<void> _guideline(
  String screen,
  String name,
  Future<void> Function() action,
) async {
  try {
    await action();
    _record('PASS', screen, name);
  } catch (error) {
    // Do not abort the crawl. The complete defect set is more useful than
    // stopping at the first accessibility issue.
    _record('FAIL', screen, name, error);
  }
}

Future<void> _auditAccessibility(WidgetTester tester, String screen) async {
  await _guideline(
    screen,
    'a11y-android-touch-target-48',
    () => expectLater(tester, meetsGuideline(androidTapTargetGuideline)),
  );

  await _guideline(
    screen,
    'a11y-labeled-tap-targets',
    () => expectLater(tester, meetsGuideline(labeledTapTargetGuideline)),
  );

  await _guideline(
    screen,
    'a11y-text-contrast',
    () => expectLater(tester, meetsGuideline(textContrastGuideline)),
  );
}

Future<void> _auditScreen(WidgetTester tester, String screen) async {
  await _boundedPump(tester, cycles: 4);
  await _drainFlutterExceptions(tester, screen);
  await _auditAccessibility(tester, screen);
  await _drainFlutterExceptions(tester, screen);
}

Future<bool> _returnHome(WidgetTester tester) async {
  final context = _shellContext(tester);
  if (context == null) {
    _record('FAIL', 'shell', 'return-home', 'Home context missing');
    return false;
  }

  Navigator.of(context).popUntil((route) => route.isFirst);
  AppNavigator.open<void>(context, AppDestination.home);
  await _boundedPump(tester);

  final ready = _destination(AppDestination.home).evaluate().isNotEmpty;

  _record(
    ready ? 'PASS' : 'FAIL',
    'shell',
    'return-home',
    ready ? 'home restored' : 'home not restored',
  );

  return ready;
}

Future<void> _auditBottomTab(
  WidgetTester tester,
  String key,
  AppDestination destination,
) async {
  await _returnHome(tester);

  final finder = find.byKey(ValueKey(key));

  if (finder.evaluate().isEmpty) {
    _record('FAIL', destination.name, 'bottom-tab', 'key $key missing');
    return;
  }

  try {
    await tester.tap(finder);
    await _boundedPump(tester);

    final opened = _destination(destination).evaluate().isNotEmpty;

    _record(
      opened ? 'PASS' : 'FAIL',
      destination.name,
      'bottom-tab',
      opened ? key : '$key did not open ${destination.name}',
    );

    await _auditScreen(tester, destination.name);
  } catch (error) {
    _record('FAIL', destination.name, 'bottom-tab', error);
  }
}

Future<void> _auditHomeCard(
  WidgetTester tester,
  String key,
  String name,
  List<AppDestination> validDestinations,
) async {
  await _returnHome(tester);

  final finder = find.byKey(ValueKey(key));

  if (finder.evaluate().isEmpty) {
    _record('FAIL', 'home', 'card-$name', 'key $key missing');
    return;
  }

  try {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await _boundedPump(tester);

    AppDestination? opened;

    for (final destination in validDestinations) {
      if (_destination(destination).evaluate().isNotEmpty) {
        opened = destination;
        break;
      }
    }

    if (opened == null) {
      _record('FAIL', 'home', 'card-$name', 'no expected destination opened');
    } else {
      _record('PASS', 'home', 'card-$name', 'opened ${opened.name}');
      await _auditScreen(tester, opened.name);
    }
  } catch (error) {
    _record('FAIL', 'home', 'card-$name', error);
  }
}

bool _openDestinationNow(WidgetTester tester, AppDestination destination) {
  final context = _shellContext(tester);
  if (context == null) return false;

  AppNavigator.open<void>(context, destination);
  return true;
}

Future<void> _auditDestination(
  WidgetTester tester,
  AppDestination destination,
) async {
  if (!await _returnHome(tester)) return;

  try {
    if (!_openDestinationNow(tester, destination)) {
      _record('FAIL', destination.name, 'route-open', 'shell context absent');
      return;
    }
    await _boundedPump(tester);

    final finder = _destination(destination);
    final opened = finder.evaluate().isNotEmpty;

    _record(
      opened ? 'PASS' : 'FAIL',
      destination.name,
      'route-open',
      opened ? 'runtime widget found' : 'destination widget missing',
    );

    if (opened) {
      await _auditScreen(tester, destination.name);
    }
  } catch (error) {
    _record('FAIL', destination.name, 'route-open', error);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FluviAI canonical beta safe-mode 360 runtime audit', (
    tester,
  ) async {
    _record('PASS', 'audit', 'started', DateTime.now().toIso8601String());

    try {
      await Future<void>.sync(() => app.main());
    } catch (error) {
      _record('FAIL', 'launch', 'main', error);
    }

    final homeReady = await _waitFor(tester, _destination(AppDestination.home));

    if (!homeReady) {
      _record(
        'FAIL',
        'launch',
        'canonical-home',
        'Home did not become reachable within 25 seconds',
      );

      binding.reportData = <String, dynamic>{
        'passes': _passes,
        'warnings': _warns,
        'failures': _fails,
        'blocked': true,
      };

      return;
    }

    final view = tester.view;

    _record(
      'PASS',
      'device',
      'viewport',
      'logical=${view.physicalSize / view.devicePixelRatio} '
          'physical=${view.physicalSize} '
          'dpr=${view.devicePixelRatio}',
    );

    _record('PASS', 'launch', 'canonical-home', 'reachable');

    await _auditScreen(tester, 'home');

    // Real Home user paths.
    await _auditHomeCard(tester, 'commercial-water-card', 'water', const [
      AppDestination.water,
    ]);

    await _auditHomeCard(tester, 'commercial-weather-card', 'weather', const [
      AppDestination.weather,
    ]);

    await _auditHomeCard(tester, 'commercial-score-card', 'fluvi-score', const [
      AppDestination.fluvi,
    ]);

    await _auditHomeCard(
      tester,
      'commercial-community-card',
      'local-pulse',
      const [AppDestination.community],
    );

    await _auditHomeCard(tester, 'commercial-reports-card', 'reports', const [
      AppDestination.myReports,
      AppDestination.reportDetail,
    ]);

    // Canonical shell interaction.
    for (final entry in const <(String, AppDestination)>[
      ('bottom-nav-home', AppDestination.home),
      ('bottom-nav-map', AppDestination.map),
      ('bottom-nav-activity', AppDestination.activity),
      ('bottom-nav-utilities', AppDestination.utilities),
    ]) {
      await _auditBottomTab(tester, entry.$1, entry.$2);
    }

    // SAFE MODE:
    // Open/read/navigate only. No publish/save/delete/confirm/purchase actions.
    const safeDestinations = <AppDestination>[
      AppDestination.water,
      AppDestination.weather,
      AppDestination.fluvi,
      AppDestination.askFluvi,
      AppDestination.community,
      AppDestination.myReports,
      AppDestination.addReport,
      AppDestination.myCatches,
      AppDestination.addCatch,
      AppDestination.favorites,
      AppDestination.journal,
      AppDestination.alerts,
      AppDestination.notifications,
      AppDestination.notificationPreferences,
      AppDestination.search,
      AppDestination.toolkit,
      AppDestination.permit,
      AppDestination.regulations,
      AppDestination.safety,
      AppDestination.reservoir,
      AppDestination.hydropower,
      AppDestination.profile,
      AppDestination.accountSecurity,
      AppDestination.settings,
      AppDestination.premium,
      AppDestination.support,
      AppDestination.privacy,
      AppDestination.terms,
      AppDestination.licences,
      AppDestination.legal,
      AppDestination.about,
    ];

    for (final destination in safeDestinations) {
      await _auditDestination(tester, destination);
    }

    await _returnHome(tester);
    await _drainFlutterExceptions(tester, 'final');

    _record(
      _fails == 0 ? 'PASS' : 'WARN',
      'audit',
      'summary',
      'PASS=$_passes WARN=$_warns FAIL=$_fails',
    );

    binding.reportData = <String, dynamic>{
      'passes': _passes,
      'warnings': _warns,
      'failures': _fails,
      'blocked': false,
    };
  });
}
