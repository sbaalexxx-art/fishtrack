import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/utility/fluviai_explore_catalog.dart';
import 'package:fishtrack/core/utility/fluviai_utility_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'utility registry has stable unique ids and executable destinations',
    () {
      final ids = FluviUtilityRegistry.definitions
          .map((definition) => definition.id)
          .toList(growable: false);

      expect(ids.toSet(), hasLength(ids.length));
      expect(FluviUtilityRegistry.definitions, hasLength(34));

      for (final utility in FluviUtilityRegistry.definitions) {
        expect(utility.id, isNotEmpty);
        expect(utility.titleRo, isNotEmpty);
        expect(utility.titleEn, isNotEmpty);
        expect(utility.subtitleRo, isNotEmpty);
        expect(utility.subtitleEn, isNotEmpty);
        expect(
          AppDestinationRegistry.definitions,
          contains(utility.destination),
          reason: '${utility.id} points to an unregistered destination',
        );
        expect(utility.countryPacks, isNotEmpty);
        expect(utility.contexts, isNotEmpty);
      }
    },
  );

  test('all nine protected utility families remain represented', () {
    final represented = FluviUtilityRegistry.definitions
        .map((definition) => definition.family)
        .toSet();

    expect(represented, FluviUtilityFamily.values.toSet());
  });

  test('three visible categories expose five distinct tools exactly once', () {
    final grouped = FluviExploreCatalog.grouped(
      FluviUtilityRegistry.definitions,
    );
    final groupedItems = [
      for (final section in FluviExploreCatalog.sectionOrder)
        ...grouped[section] ?? const <FluviUtilityDefinition>[],
    ];

    expect(FluviExploreCatalog.sectionOrder, hasLength(3));
    expect(grouped.keys, FluviExploreCatalog.sectionOrder.toSet());
    expect(groupedItems, hasLength(5));
    expect(
      groupedItems.map((utility) => utility.id).toSet(),
      FluviExploreCatalog.visibleUtilityIds,
    );
    expect(FluviUtilityRegistry.definitions, hasLength(34));
  });

  test('search works in Romanian and English without changing routes', () {
    final romanian = FluviUtilityRegistry.search('uzinare', isRomanian: true);
    final english = FluviUtilityRegistry.search(
      'Hydro Pulse',
      isRomanian: false,
    );

    expect(romanian.map((item) => item.id), contains('water.hydro-pulse'));
    expect(english.map((item) => item.id), contains('water.hydro-pulse'));
    expect(romanian.single.destination, english.single.destination);
  });

  test(
    'visible search excludes canonical launchers and unavailable entries',
    () {
      final allVisible = FluviExploreCatalog.searchVisible(
        '',
        isRomanian: false,
      );

      expect(allVisible.map((item) => item.id).toSet(), {
        'water.hydro-pulse',
        'water.stations',
        'weather.solunar',
        'map.search',
        'fluvi.ask',
      });
      expect(
        allVisible.map((item) => item.id),
        isNot(
          containsAll(<String>[
            'water.overview',
            'map.full',
            'weather.forecast',
            'fluvi.score',
            'community.feed',
            'fluvi.vision',
          ]),
        ),
      );
    },
  );
}
