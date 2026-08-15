import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/screens/premium_page.dart';
import 'package:fishtrack/services/billing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('successful restore changes entitlement and shows result', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const PremiumPage(
            billingRepository: _RestoredBillingRepository(),
          ),
        ),
      ),
    );

    expect(find.text('FREE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('premium-restore-action')));
    await tester.pumpAndSettle();

    expect(container.read(fluviAccessTierProvider), FluviAccessTier.premium);
    expect(find.text('Premium restored'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable billing remains truthful and does not unlock', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const PremiumPage(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('premium-restore-action')));
    await tester.pumpAndSettle();

    expect(container.read(fluviAccessTierProvider), FluviAccessTier.free);
    expect(find.text('Restore is unavailable'), findsOneWidget);
  });
}

class _RestoredBillingRepository implements BillingRepository {
  const _RestoredBillingRepository();

  @override
  Future<BillingRestoreResult> restorePurchases() async =>
      BillingRestoreResult.restored;
}
