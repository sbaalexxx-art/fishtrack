import 'package:flutter/foundation.dart';

@immutable
class WaterRiverRef {
  const WaterRiverRef({
    required this.key,
    required this.name,
    required this.countryCode,
    this.basinCode,
    required this.damCount,
    required this.reservoirCount,
    required this.basinNames,
    required this.counties,
    this.waterBodyId,
    this.canonicalKey,
    this.canonicalWaterBody = false,
    this.mapGeometryAvailable = false,
    this.provenanceSource = 'ANAR-derived',
  });

  final String key;
  final String name;
  final String countryCode;
  final String? basinCode;
  final int damCount;
  final int reservoirCount;
  final List<String> basinNames;
  final List<String> counties;
  final String? waterBodyId;
  final String? canonicalKey;
  final bool canonicalWaterBody;
  final bool mapGeometryAvailable;
  final String provenanceSource;

  factory WaterRiverRef.fromJson(Map<String, dynamic> json) => WaterRiverRef(
    key: json['river_key']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    countryCode: json['country_code']?.toString().trim().toUpperCase() ?? '',
    basinCode: _text(json['basin_code']),
    damCount: _int(json['dam_count']) ?? 0,
    reservoirCount: _int(json['reservoir_count']) ?? 0,
    basinNames: _strings(json['basin_names']),
    counties: _strings(json['counties']),
    waterBodyId: _text(json['water_body_id']),
    canonicalKey: _text(json['canonical_key']),
    canonicalWaterBody: json['canonical_water_body'] == true,
    mapGeometryAvailable: json['map_geometry_available'] == true,
    provenanceSource: json['provenance_source']?.toString() ?? 'ANAR-derived',
  );
}

@immutable
class WaterRiverLinkedAsset {
  const WaterRiverLinkedAsset({
    required this.id,
    required this.name,
    required this.type,
    this.latitude,
    this.longitude,
    this.county,
    this.basinName,
    this.hasOperationalData = false,
  });

  final String id;
  final String name;
  final String type;
  final double? latitude;
  final double? longitude;
  final String? county;
  final String? basinName;
  final bool hasOperationalData;

  factory WaterRiverLinkedAsset.fromJson(
    Map<String, dynamic> json, {
    required String type,
  }) => WaterRiverLinkedAsset(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    type: type,
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    county: _text(json['county']),
    basinName: _text(json['basin_name']),
    hasOperationalData: json['has_operational_data'] == true,
  );
}

@immutable
class WaterRiverDetail {
  const WaterRiverDetail({
    required this.ref,
    required this.stations,
    required this.dams,
    required this.reservoirs,
  });

  final WaterRiverRef ref;
  final List<WaterRiverLinkedAsset> stations;
  final List<WaterRiverLinkedAsset> dams;
  final List<WaterRiverLinkedAsset> reservoirs;

  factory WaterRiverDetail.fromJson(Map<String, dynamic> json) {
    final ref = WaterRiverRef.fromJson(json);
    List<WaterRiverLinkedAsset> read(String key, String type) =>
        (json[key] as List? ?? const <Object?>[])
            .whereType<Map>()
            .map(
              (item) => WaterRiverLinkedAsset.fromJson(
                Map<String, dynamic>.from(item),
                type: type,
              ),
            )
            .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
            .toList(growable: false);
    return WaterRiverDetail(
      ref: ref,
      stations: read('stations', 'station'),
      dams: read('dams', 'dam'),
      reservoirs: read('reservoirs', 'reservoir'),
    );
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item?.toString().trim())
      .whereType<String>()
      .where((item) => item.isNotEmpty && item != 'null')
      .toList(growable: false);
}
