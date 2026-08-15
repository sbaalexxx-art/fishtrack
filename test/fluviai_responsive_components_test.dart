import 'package:fishtrack/features/figma_complete/presentation/figma_account_pages.dart';
import 'package:fishtrack/widgets/fluviai/fluviai_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const FigmaToolkitPage(),
      ),
    );
    await tester.pump();
  }

  testWidgets('responsive classes cover compact, phone, wide and landscape', (
    tester,
  ) async {
    await pumpAt(tester, const Size(360, 800));
    expect(
      fluviResponsiveClass(tester.element(find.byType(FigmaToolkitPage))),
      FluviResponsiveClass.compact,
    );

    await pumpAt(tester, const Size(412, 915));
    expect(
      fluviResponsiveClass(tester.element(find.byType(FigmaToolkitPage))),
      FluviResponsiveClass.phone,
    );

    await pumpAt(tester, const Size(700, 900));
    expect(
      fluviResponsiveClass(tester.element(find.byType(FigmaToolkitPage))),
      FluviResponsiveClass.wide,
    );

    await pumpAt(tester, const Size(915, 412));
    expect(
      fluviResponsiveClass(tester.element(find.byType(FigmaToolkitPage))),
      FluviResponsiveClass.landscape,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'canonical destination remains overflow-free at 200 percent text',
    (tester) async {
      await pumpAt(tester, const Size(320, 640), textScale: 2);
      final list = find.byType(ListView);
      expect(list, findsOneWidget);
      await tester.drag(list, const Offset(0, -420));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
