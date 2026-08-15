import 'package:fishtrack/features/shell/presentation/utilities_hub_page.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('Explore exposes six families and searches the full registry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ro'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('utility-water.overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utilities-notifications-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utilities-category-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utilities-filter-conditionsAndWater')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey('utilities-category-strip')),
      const Offset(-600, 0),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('utilities-filter-accountAndApp')),
      findsOneWidget,
    );

    for (final (query, id) in const [
      ('Pulsul apei', 'water.hydro-pulse'),
      ('Jurnal de pescuit', 'journal.sessions'),
      ('Apele mele', 'favorites.my-waters'),
      ('Permise', 'rules.permits'),
      ('Profil', 'account.profile'),
    ]) {
      await tester.enterText(
        find.byKey(const ValueKey('utilities-search-field')),
        query,
      );
      await tester.pump();

      expect(find.byKey(ValueKey('utility-search-$id')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
