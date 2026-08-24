import 'package:fishtrack/core/theme/fluviai_commercial_tokens.dart';
import 'package:fishtrack/widgets/navigation/fluviai_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved bottom navigation tokens match the Bento contract', () {
    expect(FluviAICommercialTokens.bottomNavigationVisualHeight, 56);
    expect(FluviAICommercialTokens.bottomNavigationHorizontalMargin, 0);
    expect(FluviAICommercialTokens.bottomNavigationRadius, 0);
    expect(FluviAICommercialTokens.bottomNavigationQuickAddWidth, 52);
    expect(FluviAICommercialTokens.bottomNavigationQuickAddVisualHeight, 40);
    expect(FluviAICommercialTokens.bottomNavigationQuickAddRadius, 12);
    expect(FluviAICommercialTokens.bottomNavigationIconSize, 18);
    expect(FluviAICommercialTokens.bottomNavigationLabelSize, 11);
    expect(
      FluviAICommercialTokens.bottomNavigationBackground,
      const Color(0xFF071015),
    );
    expect(
      FluviAICommercialTokens.bottomNavigationInactive,
      const Color(0xFF9AABB4),
    );
    expect(
      FluviAICommercialTokens.bottomNavigationBorder,
      const Color(0xD1263941),
    );
  });

  testWidgets(
    'approved bottom navigation keeps full-slot interaction and Romanian labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var selectedIndex = -1;
      var addPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          locale: const Locale('ro'),
          supportedLocales: const [Locale('ro'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            backgroundColor: FluviAICommercialTokens.background,
            bottomNavigationBar: FluviAIBottomNavigationBar(
              selectedIndex: 0,
              onSelect: (index) => selectedIndex = index,
              onAdd: () => addPressed = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Acasă'), findsOneWidget);
      expect(find.text('Hartă'), findsOneWidget);
      expect(find.text('Activitate'), findsOneWidget);
      expect(find.text('Fluvi'), findsOneWidget);
      expect(find.text('Utilități'), findsNothing);

      expect(
        tester.getSize(find.byKey(const ValueKey('main-bottom-navigation'))),
        const Size(390, 56),
      );
      final navigationSurface = tester.widget<Material>(
        find.byKey(const ValueKey('bottom-navigation-surface')),
      );
      expect(navigationSurface.clipBehavior, Clip.none);
      expect(navigationSurface.shape, isA<Border>());
      final navigationShape = navigationSurface.shape! as Border;
      expect(navigationShape.top.style, BorderStyle.solid);
      expect(navigationShape.left.style, BorderStyle.none);
      expect(navigationShape.right.style, BorderStyle.none);
      expect(navigationShape.bottom.style, BorderStyle.none);
      expect(
        tester.getSize(find.byKey(const ValueKey('bottom-nav-quick-add'))),
        const Size(52, 56),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('bottom-nav-quick-add-visual')),
        ),
        const Size(40, 40),
      );

      for (final key in const [
        'bottom-nav-home',
        'bottom-nav-map',
        'bottom-nav-activity',
        'bottom-nav-fluvi',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, 56);
        expect(size.width, greaterThanOrEqualTo(60));
      }

      expect(
        tester.getSize(find.byKey(const ValueKey('bottom-nav-quick-add'))),
        const Size(52, 56),
      );

      await tester.tap(find.byKey(const ValueKey('bottom-nav-map')));
      await tester.pump();
      expect(selectedIndex, 1);

      await tester.tap(find.byKey(const ValueKey('bottom-nav-quick-add')));
      await tester.pump();
      expect(addPressed, isTrue);
    },
  );
}
