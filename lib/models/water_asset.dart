import 'package:flutter/foundation.dart';

enum WaterAssetType { dam, reservoir }

@immutable
class WaterAssetRef {
  const WaterAssetRef({
    required this.type,
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.subtitle,
    this.riverName,
    this.countryCode,
    this.county,
    this.basinName,
    this.waterBodyId,
    this.hasOperationalData = false,
    this.stateTrend = 'unknown',
    this.stateSource = 'unavailable',
    this.stateConfidence = 0,
    this.communityReportCount = 0,
  });

  final WaterAssetType type;
  final String id;
  final String name;
  final String? subtitle;
  final String? riverName;
  final String? countryCode;
  final String? county;
  final String? basinName;
  final double latitude;
  final double longitude;
  final String? waterBodyId;
  final bool hasOperationalData;
  final String stateTrend;
  final String stateSource;
  final double stateConfidence;
  final int communityReportCount;

  String get entityType => type == WaterAssetType.dam ? 'dam' : 'reservoir';

  factory WaterAssetRef.fromJson(Map<String, dynamic> json) => WaterAssetRef(
    type: json['asset_type']?.toString() == 'dam'
        ? WaterAssetType.dam
        : WaterAssetType.reservoir,
    id: json['entity_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    subtitle: _text(json['subtitle']),
    riverName: _text(json['river_name']),
    countryCode: _text(json['country_code'])?.toUpperCase(),
    county: _text(json['county']),
    basinName: _text(json['basin_name']),
    latitude: _double(json['latitude']) ?? 0,
    longitude: _double(json['longitude']) ?? 0,
    waterBodyId: _text(json['water_body_id']),
    hasOperationalData: json['has_operational_data'] == true,
    stateTrend: json['state_trend']?.toString() ?? 'unknown',
    stateSource: json['state_source']?.toString() ?? 'unavailable',
    stateConfidence: _double(json['state_confidence']) ?? 0,
    communityReportCount: _int(json['community_report_count']) ?? 0,
  );
}

@immutable
class WaterOperationalMetric {
  const WaterOperationalMetric({
    required this.code,
    this.name,
    this.value,
    this.unit,
    this.availabilityStatus,
    this.observedAt,
    this.qualityStatus,
    this.confidence,
  });

  final String code;
  final String? name;
  final double? value;
  final String? unit;
  final String? availabilityStatus;
  final DateTime? observedAt;
  final String? qualityStatus;
  final String? confidence;

  factory WaterOperationalMetric.fromJson(Map<String, dynamic> json) =>
      WaterOperationalMetric(
        code: json['metric_code']?.toString() ?? '',
        name: _text(json['metric_name']),
        value: _double(json['value']),
        unit: _text(json['unit']),
        availabilityStatus: _text(json['availability_status']),
        observedAt: DateTime.tryParse(json['observed_at']?.toString() ?? ''),
        qualityStatus: _text(json['quality_status']),
        confidence: _text(json['confidence']),
      );
}

@immutable
class WaterAssetDetail {
  const WaterAssetDetail({
    required this.ref,
    required this.source,
    required this.metrics,
    required this.linkedAssets,
    this.staticData = const <String, Object?>{},
  });

  final WaterAssetRef ref;
  final String source;
  final List<WaterOperationalMetric> metrics;
  final List<Map<String, dynamic>> linkedAssets;
  final Map<String, Object?> staticData;

  WaterOperationalMetric? metric(String code) {
    for (final metric in metrics) {
      if (metric.code == code && metric.availabilityStatus == 'available') {
        return metric;
      }
    }
    return null;
  }

  factory WaterAssetDetail.fromJson(
    Map<String, dynamic> json, {
    required WaterAssetType type,
  }) {
    final linkedKey = type == WaterAssetType.dam
        ? 'linked_reservoirs'
        : 'linked_dams';
    final metrics = (json['latest_metrics'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (item) =>
              WaterOperationalMetric.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.code.isNotEmpty)
        .toList(growable: false);
    final linked = (json[linkedKey] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    return WaterAssetDetail(
      ref: WaterAssetRef(
        type: type,
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        subtitle: _text(json['basin_name']),
        riverName: _text(json['river_name']),
        countryCode: _text(json['country_code'])?.toUpperCase(),
        county: _text(json['county']),
        basinName: _text(json['basin_name']),
        latitude: _double(json['latitude']) ?? 0,
        longitude: _double(json['longitude']) ?? 0,
        waterBodyId: _text(json['water_body_id']),
        hasOperationalData: metrics.isNotEmpty,
      ),
      source: json['source']?.toString() ?? 'ANAR',
      metrics: metrics,
      linkedAssets: linked,
      staticData: Map<String, Object?>.from(json),
    );
  }
}

@immutable
class WaterHydropowerComplex {
  const WaterHydropowerComplex({
    required this.reservoirId,
    required this.reservoirName,
    required this.latitude,
    required this.longitude,
    required this.importanceClass,
    required this.hydropowerUse,
    required this.operationState,
    required this.evidenceClass,
    required this.freshnessStatus,
    required this.communityReportCount,
    required this.hasOperationalData,
    this.damId,
    this.damName,
    this.waterBodyId,
    this.riverName,
    this.county,
    this.basinName,
    this.volumeMillionM3,
    this.surfaceAreaKm2,
    this.plantId,
    this.plantName,
  });

  final String reservoirId;
  final String reservoirName;
  final String? damId;
  final String? damName;
  final String? waterBodyId;
  final String? riverName;
  final String? county;
  final String? basinName;
  final double latitude;
  final double longitude;
  final String importanceClass;
  final double? volumeMillionM3;
  final double? surfaceAreaKm2;
  final String hydropowerUse;
  final String? plantId;
  final String? plantName;
  final String operationState;
  final String evidenceClass;
  final String freshnessStatus;
  final int communityReportCount;
  final bool hasOperationalData;

  String get displayName =>
      damName?.trim().isNotEmpty == true ? damName! : reservoirName;

  factory WaterHydropowerComplex.fromJson(Map<String, dynamic> json) =>
      WaterHydropowerComplex(
        reservoirId: json['reservoir_id']?.toString() ?? '',
        reservoirName: json['reservoir_name']?.toString() ?? '',
        damId: _text(json['dam_id']),
        damName: _text(json['dam_name']),
        waterBodyId: _text(json['water_body_id']),
        riverName: _text(json['river_name']),
        county: _text(json['county']),
        basinName: _text(json['basin_name']),
        latitude: _double(json['latitude']) ?? double.nan,
        longitude: _double(json['longitude']) ?? double.nan,
        importanceClass: json['importance_class']?.toString() ?? '',
        volumeMillionM3: _double(json['volume_million_m3']),
        surfaceAreaKm2: _double(json['surface_area_km2']),
        hydropowerUse: json['hydropower_use']?.toString() ?? '',
        plantId: _text(json['plant_id']),
        plantName: _text(json['plant_name']),
        operationState: json['operation_state']?.toString() ?? 'UNKNOWN',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        freshnessStatus: json['freshness_status']?.toString() ?? 'unavailable',
        communityReportCount: _int(json['community_report_count']) ?? 0,
        hasOperationalData: json['has_operational_data'] == true,
      );
}

@immutable
class WaterEntityState {
  const WaterEntityState({
    required this.source,
    required this.officialTrend,
    required this.communityTrend,
    required this.flowState,
    required this.operationSignal,
    required this.confidence,
    required this.communityEvidenceCount,
    this.disclaimer,
  });

  final String source;
  final String officialTrend;
  final String communityTrend;
  final String flowState;
  final String operationSignal;
  final double confidence;
  final int communityEvidenceCount;
  final String? disclaimer;

  bool get hasCommunityEvidence => communityEvidenceCount > 0;

  factory WaterEntityState.fromJson(Map<String, dynamic> json) =>
      WaterEntityState(
        source: json['state_source']?.toString() ?? 'unavailable',
        officialTrend: json['official_trend']?.toString() ?? 'unknown',
        communityTrend: json['community_trend']?.toString() ?? 'unknown',
        flowState: json['flow_state']?.toString() ?? 'unknown',
        operationSignal: json['operation_signal']?.toString() ?? 'unknown',
        confidence: _double(json['confidence']) ?? 0,
        communityEvidenceCount:
            (json['community_evidence'] as List?)?.length ?? 0,
        disclaimer: _text(json['disclaimer']),
      );
}

@immutable
class WaterMapPin {
  const WaterMapPin({
    required this.entityType,
    required this.entityId,
    required this.canonicalKey,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.riverName,
    this.countryCode,
    this.waterBodyId,
    this.distanceKm,
    this.trendState = 'unknown',
    this.operationState = 'UNKNOWN',
    this.evidenceClass = 'UNKNOWN',
    this.stateSource = 'unavailable',
    this.confidence = 0,
    this.freshnessStatus = 'unavailable',
    this.priority = 0,
    this.hasOperationalData = false,
    this.communityReportCount = 0,
    this.statePayload = const <String, Object?>{},
  });

  final String entityType;
  final String entityId;
  final String canonicalKey;
  final String name;
  final String? riverName;
  final String? countryCode;
  final double latitude;
  final double longitude;
  final String? waterBodyId;
  final double? distanceKm;
  final String trendState;
  final String operationState;
  final String evidenceClass;
  final String stateSource;
  final double confidence;
  final String freshnessStatus;
  final int priority;
  final bool hasOperationalData;
  final int communityReportCount;
  final Map<String, Object?> statePayload;

  bool get isDam => entityType == 'dam';
  bool get isReservoir => entityType == 'reservoir';
  bool get isHydropower => entityType == 'hydro_plant';

  factory WaterMapPin.fromJson(Map<String, dynamic> json) {
    final payload = json['state_payload'];
    return WaterMapPin(
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString() ?? '',
      canonicalKey: json['canonical_key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      riverName: _text(json['river_name']),
      countryCode: _text(json['country_code'])?.toUpperCase(),
      latitude: _double(json['latitude']) ?? double.nan,
      longitude: _double(json['longitude']) ?? double.nan,
      waterBodyId: _text(json['water_body_id']),
      distanceKm: _double(json['distance_km']),
      trendState: json['trend_state']?.toString() ?? 'unknown',
      operationState: json['operation_state']?.toString() ?? 'UNKNOWN',
      evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
      stateSource: json['state_source']?.toString() ?? 'unavailable',
      confidence: _double(json['confidence']) ?? 0,
      freshnessStatus: json['freshness_status']?.toString() ?? 'unavailable',
      priority: _int(json['priority']) ?? 0,
      hasOperationalData: json['has_operational_data'] == true,
      communityReportCount: _int(json['community_report_count']) ?? 0,
      statePayload: payload is Map
          ? Map<String, Object?>.from(payload)
          : const <String, Object?>{},
    );
  }

  WaterAssetRef? toWaterAssetRef() {
    if (!isDam && !isReservoir) return null;
    return WaterAssetRef(
      type: isDam ? WaterAssetType.dam : WaterAssetType.reservoir,
      id: entityId,
      name: name,
      subtitle: _text(statePayload['subtitle']),
      riverName: riverName,
      countryCode: countryCode,
      county: _text(statePayload['county']),
      basinName: _text(statePayload['basin_name']),
      latitude: latitude,
      longitude: longitude,
      waterBodyId: waterBodyId,
      hasOperationalData: hasOperationalData,
      stateTrend: trendState,
      stateSource: stateSource,
      stateConfidence: confidence,
      communityReportCount: communityReportCount,
    );
  }
}

@immutable
class HydropowerPlantState {
  const HydropowerPlantState({
    required this.plantId,
    required this.canonicalKey,
    required this.name,
    required this.operationState,
    this.countryCode,
    required this.evidenceClass,
    required this.evidenceSource,
    required this.confidence,
    required this.freshnessStatus,
    this.operatorName,
    this.operatorUnit,
    this.sectorName,
    this.plantKind,
    this.installedPowerMw,
    this.waterBodyId,
    this.damId,
    this.reservoirId,
    this.latitude,
    this.longitude,
    this.evidenceMetric,
    this.evidenceValue,
    this.evidenceUnit,
    this.evidenceObservedAt,
    this.communityOperationSignal = 'unknown',
    this.communityReportCount = 0,
    this.evidenceSourceUrl,
    this.plantSourceUrl,
  });

  final String plantId;
  final String canonicalKey;
  final String name;
  final String? countryCode;
  final String? operatorName;
  final String? operatorUnit;
  final String? sectorName;
  final String? plantKind;
  final double? installedPowerMw;
  final String? waterBodyId;
  final String? damId;
  final String? reservoirId;
  final double? latitude;
  final double? longitude;
  final String operationState;
  final String evidenceClass;
  final String evidenceSource;
  final String? evidenceMetric;
  final double? evidenceValue;
  final String? evidenceUnit;
  final DateTime? evidenceObservedAt;
  final double confidence;
  final String freshnessStatus;
  final String communityOperationSignal;
  final int communityReportCount;
  final String? evidenceSourceUrl;
  final String? plantSourceUrl;

  factory HydropowerPlantState.fromJson(Map<String, dynamic> json) =>
      HydropowerPlantState(
        plantId: json['plant_id']?.toString() ?? '',
        canonicalKey: json['canonical_key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        countryCode: _text(json['country_code'])?.toUpperCase(),
        operatorName: _text(json['operator_name']),
        operatorUnit: _text(json['operator_unit']),
        sectorName: _text(json['sector_name']),
        plantKind: _text(json['plant_kind']),
        installedPowerMw: _double(json['installed_power_mw']),
        waterBodyId: _text(json['water_body_id']),
        damId: _text(json['dam_id']),
        reservoirId: _text(json['reservoir_id']),
        latitude: _double(json['latitude']),
        longitude: _double(json['longitude']),
        operationState: json['operation_state']?.toString() ?? 'UNKNOWN',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        evidenceSource: json['evidence_source']?.toString() ?? 'unavailable',
        evidenceMetric: _text(json['evidence_metric']),
        evidenceValue: _double(json['evidence_value']),
        evidenceUnit: _text(json['evidence_unit']),
        evidenceObservedAt: DateTime.tryParse(
          json['evidence_observed_at']?.toString() ?? '',
        ),
        confidence: _double(json['confidence']) ?? 0,
        freshnessStatus: json['freshness_status']?.toString() ?? 'unavailable',
        communityOperationSignal:
            json['community_operation_signal']?.toString() ?? 'unknown',
        communityReportCount: _int(json['community_report_count']) ?? 0,
        evidenceSourceUrl: _text(json['evidence_source_url']),
        plantSourceUrl: _text(json['plant_source_url']),
      );
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
