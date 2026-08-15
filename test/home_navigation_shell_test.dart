import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/screens/main_navigation.dart';
import 'package:fishtrack/widgets/home_premium/side_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  Widget localized({
    required Widget child,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: appChild!,
      ),
      home: ProviderScope(child: Scaffold(body: child)),
    );
  }

  testWidgets('Add sheet exposes four responsive actions', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var reportRequests = 0;
    var catchRequests = 0;
    var savePlaceRequests = 0;
    await tester.pumpWidget(
      localized(
        textScale: 1.5,
        child: MainAddActionSheet(
          onAddReport: () => reportRequests++,
          onAddCatch: () => catchRequests++,
          onSavePlace: () => savePlaceRequests++,
        ),
      ),
    );

    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Catch'), findsOneWidget);
    expect(find.text('Saved place'), findsOneWidget);
    expect(find.text('Session'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Report'));
    await tester.tap(find.text('Catch'));
    await tester.tap(find.text('Saved place'));
    expect(reportRequests, 1);
    expect(catchRequests, 1);
    expect(savePlaceRequests, 1);
  });

  testWidgets('More menu exposes the approved utility destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(localized(child: const HomeSideMenu()));

    for (final label in const [
      'My catches',
      'My waters & saved places',
      'Fishing journal',
      'My reports',
      'Search',
      'Notifications',
      'Alerts & notifications',
      'Water hub',
      'Weather & solunar',
      'Fluvi Hub',
      'Ask Fluvi',
      'Fishing permit',
      'Regulations & sizes',
      'Safety',
      'Profile',
      'Account & security',
      'Premium',
      'Settings',
      'Help & FAQ',
      'Send feedback',
      'Contact us',
      'Privacy',
      'Terms',
      'Licences',
      'Legal hub',
      'About FluviAI',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    for (final primaryLabel in const [
      'Home',
      'Map',
      'Community',
      'Add catch',
    ]) {
      expect(find.text(primaryLabel), findsNothing);
    }
    expect(find.text('Developer mode'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Romanian Add labels remain complete', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      localized(
        locale: const Locale('ro'),
        textScale: 1.5,
        child: MainAddActionSheet(
          onAddReport: () {},
          onAddCatch: () {},
          onSavePlace: () {},
        ),
      ),
    );

    expect(find.text('Raport'), findsOneWidget);
    expect(find.text('Captură'), findsOneWidget);
    expect(find.text('Loc salvat'), findsOneWidget);
    expect(find.text('Partidă'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
