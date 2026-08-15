class Catch {
  final String id;
  final String stationId;

  final String species;
  final String? speciesScientific;
  final String speciesSource;
  final double? speciesConfidence;
  final String? speciesModelVersion;
  final bool speciesUserConfirmed;

  final double? weight;
  final double? length;

  final DateTime date;

  const Catch({
    required this.id,
    required this.stationId,
    required this.species,
    this.speciesScientific,
    this.speciesSource = 'manual',
    this.speciesConfidence,
    this.speciesModelVersion,
    this.speciesUserConfirmed = true,
    required this.weight,
    required this.length,
    required this.date,
  });
}
