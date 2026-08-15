import 'fluviai_utility_registry.dart';

enum FluviExploreSection {
  conditionsAndWater,
  fluviIntelligence,
  activity,
  saved,
  rulesAndSafety,
  accountAndApp,
}

abstract final class FluviExploreCatalog {
  static const sectionOrder = <FluviExploreSection>[
    FluviExploreSection.conditionsAndWater,
    FluviExploreSection.fluviIntelligence,
    FluviExploreSection.activity,
    FluviExploreSection.saved,
    FluviExploreSection.rulesAndSafety,
    FluviExploreSection.accountAndApp,
  ];

  static FluviExploreSection sectionFor(
    FluviUtilityFamily family,
  ) => switch (family) {
    FluviUtilityFamily.waterIntelligence ||
    FluviUtilityFamily.mapExploration ||
    FluviUtilityFamily.weatherSolunar => FluviExploreSection.conditionsAndWater,
    FluviUtilityFamily.fluviAi => FluviExploreSection.fluviIntelligence,
    FluviUtilityFamily.communityReports ||
    FluviUtilityFamily.catchesJournal => FluviExploreSection.activity,
    FluviUtilityFamily.myWatersFavorites => FluviExploreSection.saved,
    FluviUtilityFamily.rulesPermitsSafety => FluviExploreSection.rulesAndSafety,
    FluviUtilityFamily.accountSettings => FluviExploreSection.accountAndApp,
  };

  static Map<FluviExploreSection, List<FluviUtilityDefinition>> grouped(
    Iterable<FluviUtilityDefinition> definitions,
  ) {
    final result = <FluviExploreSection, List<FluviUtilityDefinition>>{
      for (final section in sectionOrder) section: <FluviUtilityDefinition>[],
    };
    for (final definition in definitions) {
      result[sectionFor(definition.family)]!.add(definition);
    }
    return result;
  }
}
