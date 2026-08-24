import 'package:fishtrack/features/shell/presentation/utilities_hub_page.dart';
import 'package:fishtrack/core/utility/fluviai_explore_catalog.dart';
import 'package:fishtrack/core/utility/fluviai_utility_registry.dart';
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

  testWidgets('Utilities exposes three categories and searches useful tools', (
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
      find.byKey(const ValueKey('utility-water.hydro-pulse')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utility-water.stations')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utilities-section-waterTools')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utilities-section-weatherAndLight')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('utilities-section-discoveryAndAssistance')),
      findsOneWidget,
    );

    for (final (query, id) in const [
      ('Pulsul apei', 'water.hydro-pulse'),
      ('Stații hidrometrice', 'water.stations'),
      ('Solunar', 'weather.solunar'),
      ('Căutare globală', 'map.search'),
      ('Întreabă Fluvi', 'fluvi.ask'),
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

  testWidgets('inventory stays 34 while only five distinct tools are visible', (
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

    expect(FluviUtilityRegistry.definitions, hasLength(34));
    expect(FluviExploreCatalog.visibleDefinitions, hasLength(5));

    final search = find.byKey(const ValueKey('utilities-search-field'));
    for (final utility in FluviExploreCatalog.visibleDefinitions) {
      await tester.enterText(search, utility.titleRo);
      await tester.pump();
      expect(
        find.byKey(ValueKey('utility-search-${utility.id}')),
        findsOneWidget,
        reason: '${utility.id} is not reachable through the deduplicated Hub',
      );
    }

    await tester.enterText(search, 'Fluvi Vision');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('utility-search-fluvi.vision')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
