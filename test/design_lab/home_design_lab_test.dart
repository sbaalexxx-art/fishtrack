import 'package:fishtrack/design_lab/home_design_lab_page.dart';
import 'package:fishtrack/design_lab/home_design_lab_tokens.dart';
import 'package:fishtrack/widgets/home_premium/home_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDesignLab(
    WidgetTester tester, {
    required Size size,
    HomeDesignLabTier tier = HomeDesignLabTier.free,
    double textScale = 1,
    Locale locale = const Locale('ro'),
    EdgeInsets viewPadding = EdgeInsets.zero,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          viewPadding: viewPadding,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [Locale('ro'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            platform: platform,
            scaffoldBackgroundColor: HomeDesignLabTokens.background,
          ).copyWith(splashFactory: NoSplash.splashFactory),
          home: HomeDesignLabPage(initialTier: tier),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home Free se construiește și păstrează wordmark-ul din header', (
    tester,
  ) async {
    await pumpDesignLab(tester, size: const Size(432, 932));

    expect(find.byType(HomePremiumHeader), findsOneWidget);
    expect(find.bySemanticsLabel('FluviAI'), findsOneWidget);
    expect(find.text('Cernavodă'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Premium se construiește cu datele sale de preview', (
    tester,
  ) async {
    await pumpDesignLab(
      tester,
      size: const Size(432, 932),
      tier: HomeDesignLabTier.premium,
    );

    expect(find.byType(HomePremiumHeader), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-design-lab-tier-pill')),
        matching: find.text('PREMIUM'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Favorite'), findsOneWidget);
    expect(find.bySemanticsLabel('Alertă'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectorul Free Premium schimbă preview-ul', (tester) async {
    await pumpDesignLab(tester, size: const Size(432, 932));

    expect(find.bySemanticsLabel('Avatar profil Free'), findsOneWidget);
    final freeWaterType = tester
        .widget(find.byKey(const Key('home-design-lab-water-card')))
        .runtimeType;
    final freeWeatherType = tester
        .widget(find.byKey(const Key('home-design-lab-weather-card')))
        .runtimeType;
    await tester.tap(find.byKey(const Key('home-design-lab-tier-pill')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('home-design-lab-tier-picker')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('home-design-lab-tier-premium')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Avatar profil Premium'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-design-lab-tier-pill')),
        matching: find.text('PREMIUM'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Favorite'), findsOneWidget);
    expect(
      tester
          .widget(find.byKey(const Key('home-design-lab-water-card')))
          .runtimeType,
      freeWaterType,
    );
    expect(
      tester
          .widget(find.byKey(const Key('home-design-lab-weather-card')))
          .runtimeType,
      freeWeatherType,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tier-ul este overlay pe hartă și nu rezervă spațiu în Home', (
    tester,
  ) async {
    await pumpDesignLab(tester, size: const Size(432, 936));

    final pill = find.byKey(const Key('home-design-lab-tier-pill'));
    final map = find.byKey(const Key('home-design-lab-map'));
    final location = find.byKey(const Key('home-design-lab-location-chip'));
    expect(pill, findsOneWidget);
    expect(find.ancestor(of: pill, matching: map), findsOneWidget);
    expect(location, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-design-lab-header')),
        matching: find.text('Patchway, South Gloucestershire'),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('home-design-lab-tier-picker')), findsNothing);
    expect(find.text('DATE DEMONSTRATIVE • LOCAL'), findsNothing);
    expect(find.text('DEMONSTRATION DATA • LOCAL'), findsNothing);

    final mapRect = tester.getRect(map);
    final locationRect = tester.getRect(location);
    final waterRect = tester.getRect(
      find.byKey(const Key('home-design-lab-water-card')),
    );
    final navigationRect = tester.getRect(
      find.byKey(const Key('home-design-lab-bottom-navigation')),
    );
    final waterTitleRect = tester.getRect(find.text('Water'));
    final selectorRect = tester.getRect(find.text('Dunăre'));
    final riversRect = tester.getRect(find.text('Râuri'));
    final damsRect = tester.getRect(find.text('Baraje & acumulări'));
    final stationRect = tester.getRect(find.text('Cernavodă'));
    final primaryValueRect = tester.getRect(find.text('−12 cm / 24h'));
    final sourceRect = tester.getRect(find.text('Sursa: AFDJ'));
    final detailsRect = tester.getRect(find.text('Vezi detalii'));
    expect((locationRect.center.dx - 216).abs(), lessThan(.1));
    expect(mapRect.top - locationRect.bottom, inInclusiveRange(4, 6));
    expect(mapRect.height, greaterThanOrEqualTo(navigationRect.top * .40));
    expect(
      waterRect.bottom,
      lessThanOrEqualTo(navigationRect.top),
      reason:
          'map=$mapRect water=$waterRect navigation=$navigationRect '
          'title=$waterTitleRect selector=$selectorRect rivers=$riversRect '
          'dams=$damsRect station=$stationRect '
          'primary=$primaryValueRect source=$sourceRect details=$detailsRect',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Water Premium rămâne complet în primul viewport la 432 px', (
    tester,
  ) async {
    await pumpDesignLab(
      tester,
      size: const Size(432, 936),
      tier: HomeDesignLabTier.premium,
    );

    final waterRect = tester.getRect(
      find.byKey(const Key('home-design-lab-water-card')),
    );
    final navigationRect = tester.getRect(
      find.byKey(const Key('home-design-lab-bottom-navigation')),
    );
    final mapRect = tester.getRect(
      find.byKey(const Key('home-design-lab-map')),
    );
    final flowRect = tester.getRect(find.text('Debit'));
    final temperatureRect = tester.getRect(find.text('Temp. apă'));
    final sourceRect = tester.getRect(find.text('Sursa: AFDJ'));
    final detailsRect = tester.getRect(find.text('Vezi detalii'));
    expect(
      waterRect.bottom,
      lessThanOrEqualTo(navigationRect.top),
      reason:
          'map=$mapRect water=$waterRect navigation=$navigationRect '
          'flow=$flowRect temperature=$temperatureRect source=$sourceRect '
          'details=$detailsRect',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation reproduce ordinea și iconurile producției', (
    tester,
  ) async {
    await pumpDesignLab(tester, size: const Size(432, 936));

    final navigation = find.byKey(
      const Key('home-design-lab-bottom-navigation'),
    );
    final destinations = [
      find.byKey(const Key('home-design-lab-nav-home')),
      find.byKey(const Key('home-design-lab-nav-map')),
      find.byKey(const Key('home-design-lab-nav-add')),
      find.byKey(const Key('home-design-lab-nav-reports')),
      find.byKey(const Key('home-design-lab-nav-favorites')),
    ];
    expect(navigation, findsOneWidget);
    for (final destination in destinations) {
      expect(
        find.descendant(of: navigation, matching: destination),
        findsOneWidget,
      );
    }
    final centers = destinations
        .map((destination) => tester.getCenter(destination).dx)
        .toList();
    expect(centers, orderedEquals([...centers]..sort()));
    expect(
      find.descendant(
        of: navigation,
        matching: find.byIcon(Icons.home_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.byIcon(Icons.map_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigation,
        matching: find.byIcon(Icons.bar_chart_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navigation,
        matching: find.byIcon(Icons.bookmark_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('432 px portrait nu produce excepții de layout', (tester) async {
    await pumpDesignLab(tester, size: const Size(432, 932), textScale: 1.3);

    expect(
      find.byKey(const Key('home-design-lab-portrait-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape folosește hartă stânga și conținut scrollabil', (
    tester,
  ) async {
    await pumpDesignLab(
      tester,
      size: const Size(932, 432),
      tier: HomeDesignLabTier.premium,
      textScale: 1.3,
    );

    expect(
      find.byKey(const Key('home-design-lab-landscape-scroll')),
      findsOneWidget,
    );
    expect(find.text('Water'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final phoneMatrix = <({String label, Size size})>[
    (label: '320 × 568 portrait', size: const Size(320, 568)),
    (label: '360 × 800 portrait', size: const Size(360, 800)),
    (label: '390 × 844 portrait', size: const Size(390, 844)),
    (label: '412 × 915 portrait', size: const Size(412, 915)),
    (label: '432 × 936 portrait', size: const Size(432, 936)),
    (label: '568 × 320 landscape', size: const Size(568, 320)),
    (label: '800 × 360 landscape', size: const Size(800, 360)),
    (label: '915 × 412 landscape', size: const Size(915, 412)),
    (label: '936 × 432 landscape', size: const Size(936, 432)),
  ];

  for (final testCase in phoneMatrix) {
    for (final locale in const [Locale('ro'), Locale('en')]) {
      for (final textScale in const [1.0, 1.3, 1.5]) {
        testWidgets(
          '${testCase.label}, ${locale.languageCode}, text scale $textScale '
          'nu produce overflow',
          (tester) async {
            await pumpDesignLab(
              tester,
              size: testCase.size,
              tier: HomeDesignLabTier.premium,
              textScale: textScale,
              locale: locale,
            );

            final isRomanian = locale.languageCode == 'ro';
            expect(find.byType(HomeDesignLabPage), findsOneWidget);
            expect(find.text('−12 cm / 24h'), findsOneWidget);
            expect(
              find.text(isRomanian ? 'Vezi detalii' : 'View details'),
              findsOneWidget,
            );
            expect(
              find.text(isRomanian ? 'Detalii meteo' : 'Weather details'),
              findsOneWidget,
            );
            expect(
              find.text(isRomanian ? 'Vezi toate' : 'View all'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('432 px păstrează cardurile pe rând și patru capturi vizibile', (
    tester,
  ) async {
    await pumpDesignLab(tester, size: const Size(432, 936));

    final scoreRect = tester.getRect(
      find.byKey(const Key('home-design-lab-fluviscore-card')),
    );
    final communityRect = tester.getRect(
      find.byKey(const Key('home-design-lab-community-card')),
    );
    expect((scoreRect.top - communityRect.top).abs(), lessThan(.1));
    expect((scoreRect.height - communityRect.height).abs(), lessThan(.1));

    await tester.ensureVisible(find.text('Capturi recente'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      final cardRect = tester.getRect(
        find.byKey(Key('home-design-lab-catch-card-$index')),
      );
      expect(cardRect.left, greaterThanOrEqualTo(0));
      expect(cardRect.right, lessThanOrEqualTo(432));
    }
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('ro'), Locale('en')]) {
    for (final size in const [Size(320, 568), Size(568, 320)]) {
      testWidgets(
        'CTA-urile rămân accesibile la ${size.width} × ${size.height}, '
        '${locale.languageCode}, scale 1.5',
        (tester) async {
          await pumpDesignLab(
            tester,
            size: size,
            tier: HomeDesignLabTier.premium,
            textScale: 1.5,
            locale: locale,
          );

          final isRomanian = locale.languageCode == 'ro';
          final uniqueLabels = [
            isRomanian ? 'Vezi detalii' : 'View details',
            isRomanian ? 'Detalii meteo' : 'Weather details',
            isRomanian ? 'Vezi toate' : 'View all',
          ];
          for (final label in uniqueLabels) {
            final target = find.text(label);
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            expect(target.hitTestable(), findsOneWidget);
          }

          final analysis = find.text(
            isRomanian ? 'Analiza completă' : 'Full analysis',
          );
          for (var index = 0; index < 2; index++) {
            await tester.ensureVisible(analysis.at(index));
            await tester.pumpAndSettle();
            expect(analysis.at(index).hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('SafeArea iOS cu notch și gesture navigation rămâne adaptiv', (
    tester,
  ) async {
    await pumpDesignLab(
      tester,
      size: const Size(390, 844),
      tier: HomeDesignLabTier.premium,
      textScale: 1.5,
      locale: const Locale('en'),
      viewPadding: const EdgeInsets.fromLTRB(0, 47, 0, 34),
      platform: TargetPlatform.iOS,
    );

    expect(
      find.byKey(const Key('home-design-lab-portrait-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SafeArea iOS landscape nu comprimă layout-ul portrait', (
    tester,
  ) async {
    await pumpDesignLab(
      tester,
      size: const Size(568, 320),
      tier: HomeDesignLabTier.premium,
      textScale: 1.5,
      locale: const Locale('en'),
      viewPadding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
      platform: TargetPlatform.iOS,
    );

    expect(
      find.byKey(const Key('home-design-lab-landscape-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
