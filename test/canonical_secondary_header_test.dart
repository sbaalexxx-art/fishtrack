import 'package:fishtrack/features/figma_complete/presentation/figma_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('canonical secondary header is compact and keeps a 48dp target', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: FigmaCanonicalScaffold(
          title: 'Settings',
          subtitle: 'Account and app',
          child: SizedBox.expand(),
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final targetSize = tester.getSize(
      find.byKey(const ValueKey('figma-back-button-target')),
    );
    final visualSize = tester.getSize(
      find.byKey(const ValueKey('figma-back-button')),
    );

    expect(appBar.toolbarHeight, 56);
    expect(targetSize.width, greaterThanOrEqualTo(48));
    expect(targetSize.height, greaterThanOrEqualTo(48));
    expect(visualSize, const Size(36, 36));
    expect(tester.takeException(), isNull);
  });

  testWidgets('canonical secondary header remains safe at 1.5x text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(
          home: FigmaCanonicalScaffold(
            eyebrow: 'Fluvi Intelligence',
            title: 'Notification preferences',
            subtitle: 'Account and application controls',
            child: SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 76);
    expect(tester.takeException(), isNull);
  });
}
