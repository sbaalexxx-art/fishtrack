class EuropeanFreshwaterSpecies {
  const EuropeanFreshwaterSpecies({
    required this.scientificName,
    required this.romanianName,
    required this.englishName,
    required this.aliases,
  });

  final String scientificName;
  final String romanianName;
  final String englishName;
  final List<String> aliases;
}

class SpeciesTaxonomyMatch {
  const SpeciesTaxonomyMatch({
    required this.scientificName,
    required this.displayName,
  });

  final String scientificName;
  final String displayName;
}

class EuropeanFreshwaterSpeciesCatalog {
  const EuropeanFreshwaterSpeciesCatalog._();

  static const species = <EuropeanFreshwaterSpecies>[
    EuropeanFreshwaterSpecies(
      scientificName: 'Abramis brama',
      romanianName: 'Plătică',
      englishName: 'Common bream',
      aliases: ['platica', 'plătică', 'bream', 'common bream'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Alburnus alburnus',
      romanianName: 'Oblete',
      englishName: 'Bleak',
      aliases: ['oblete', 'bleak'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Barbus barbus',
      romanianName: 'Mreană',
      englishName: 'Common barbel',
      aliases: ['mreana', 'mreană', 'barbel', 'common barbel'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Carassius carassius',
      romanianName: 'Caras',
      englishName: 'Crucian carp',
      aliases: ['caras', 'crucian carp'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Carassius gibelio',
      romanianName: 'Caras argintiu',
      englishName: 'Prussian carp',
      aliases: ['caras argintiu', 'prussian carp', 'gibel carp'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Cyprinus carpio',
      romanianName: 'Crap',
      englishName: 'Common carp',
      aliases: ['crap', 'carp', 'common carp', 'mirror carp', 'crap oglinda', 'crap oglindă'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Esox lucius',
      romanianName: 'Știucă',
      englishName: 'Northern pike',
      aliases: ['stiuca', 'știucă', 'pike', 'northern pike'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Gobio gobio',
      romanianName: 'Porcușor',
      englishName: 'Gudgeon',
      aliases: ['porcusor', 'porcușor', 'gudgeon'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Lota lota',
      romanianName: 'Mihalț',
      englishName: 'Burbot',
      aliases: ['mihalt', 'mihalț', 'burbot'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Perca fluviatilis',
      romanianName: 'Biban',
      englishName: 'European perch',
      aliases: ['biban', 'perch', 'european perch'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Rutilus rutilus',
      romanianName: 'Babușcă',
      englishName: 'Roach',
      aliases: ['babusca', 'babușcă', 'roach', 'common roach'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Scardinius erythrophthalmus',
      romanianName: 'Roșioară',
      englishName: 'Rudd',
      aliases: ['rosioara', 'roșioară', 'rudd'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Salmo trutta',
      romanianName: 'Păstrăv brun',
      englishName: 'Brown trout',
      aliases: ['pastrav', 'păstrăv', 'pastrav brun', 'păstrăv brun', 'brown trout'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Sander lucioperca',
      romanianName: 'Șalău',
      englishName: 'Zander',
      aliases: ['salau', 'șalău', 'zander', 'pike-perch', 'pike perch'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Silurus glanis',
      romanianName: 'Somn',
      englishName: 'Wels catfish',
      aliases: ['somn', 'catfish', 'wels', 'wels catfish', 'european catfish'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Tinca tinca',
      romanianName: 'Lin',
      englishName: 'Tench',
      aliases: ['lin', 'tench'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Squalius cephalus',
      romanianName: 'Clean',
      englishName: 'European chub',
      aliases: ['clean', 'chub', 'european chub'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Chondrostoma nasus',
      romanianName: 'Scobar',
      englishName: 'Common nase',
      aliases: ['scobar', 'nase', 'common nase'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Vimba vimba',
      romanianName: 'Morunaș',
      englishName: 'Vimba bream',
      aliases: ['morunas', 'morunaș', 'vimba', 'vimba bream'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Leuciscus idus',
      romanianName: 'Văduviță',
      englishName: 'Ide',
      aliases: ['vaduvita', 'văduviță', 'ide'],
    ),
    EuropeanFreshwaterSpecies(
      scientificName: 'Aspius aspius',
      romanianName: 'Avat',
      englishName: 'Asp',
      aliases: ['avat', 'asp', 'aspius'],
    ),
  ];

  static SpeciesTaxonomyMatch? match(String rawValue, {String languageCode = 'ro'}) {
    final normalized = _normalize(rawValue);
    if (normalized.isEmpty) return null;

    for (final entry in species) {
      if (_normalize(entry.scientificName) == normalized ||
          _normalize(entry.romanianName) == normalized ||
          _normalize(entry.englishName) == normalized ||
          entry.aliases.any((alias) => _normalize(alias) == normalized)) {
        return SpeciesTaxonomyMatch(
          scientificName: entry.scientificName,
          displayName: languageCode.toLowerCase().startsWith('ro')
              ? entry.romanianName
              : entry.englishName,
        );
      }
    }
    return null;
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ă', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ș', 's')
      .replaceAll('ş', 's')
      .replaceAll('ț', 't')
      .replaceAll('ţ', 't')
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
