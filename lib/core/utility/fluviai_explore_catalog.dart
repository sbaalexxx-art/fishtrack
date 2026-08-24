import 'fluviai_utility_registry.dart';

/// Product-facing categories derived from the surviving, useful tools.
///
/// The 34 registry definitions remain the complete functional inventory. This
/// catalog controls launcher visibility only; it does not delete or reroute any
/// underlying destination.
enum FluviExploreSection { waterTools, weatherAndLight, discoveryAndAssistance }

abstract final class FluviExploreCatalog {
  static const sectionOrder = <FluviExploreSection>[
    FluviExploreSection.waterTools,
    FluviExploreSection.weatherAndLight,
    FluviExploreSection.discoveryAndAssistance,
  ];

  static const visibleUtilityIds = <String>{
    'water.hydro-pulse',
    'water.stations',
    'weather.solunar',
    'map.search',
    'fluvi.ask',
  };

  static List<FluviUtilityDefinition> get visibleDefinitions =>
      FluviUtilityRegistry.definitions
          .where((definition) => visibleUtilityIds.contains(definition.id))
          .toList(growable: false);

  static FluviExploreSection sectionFor(
    FluviUtilityDefinition definition,
  ) => switch (definition.id) {
    'water.hydro-pulse' || 'water.stations' => FluviExploreSection.waterTools,
    'weather.solunar' => FluviExploreSection.weatherAndLight,
    'map.search' || 'fluvi.ask' => FluviExploreSection.discoveryAndAssistance,
    _ => throw StateError(
      'Utility ${definition.id} is not visible in Foundation 1A',
    ),
  };

  static Map<FluviExploreSection, List<FluviUtilityDefinition>> grouped(
    Iterable<FluviUtilityDefinition> definitions,
  ) {
    final result = <FluviExploreSection, List<FluviUtilityDefinition>>{
      for (final section in sectionOrder) section: <FluviUtilityDefinition>[],
    };
    for (final definition in definitions) {
      if (!visibleUtilityIds.contains(definition.id)) continue;
      result[sectionFor(definition)]!.add(definition);
    }
    return result;
  }

  static List<FluviUtilityDefinition> searchVisible(
    String query, {
    required bool isRomanian,
  }) {
    final normalized = query.trim().toLowerCase();
    final visible = visibleDefinitions;
    if (normalized.isEmpty) return visible;
    return visible
        .where((definition) {
          final haystack = <String>[
            definition.id,
            definition.title(isRomanian),
            definition.subtitle(isRomanian),
            definition.family.title(isRomanian),
          ].join(' ').toLowerCase();
          return haystack.contains(normalized);
        })
        .toList(growable: false);
  }
}
