import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/build_mode_service.dart';
import '../../services/diagnostics_service.dart';
import '../../services/location_service.dart';

import '../../models/station.dart';
import '../../models/water_asset.dart';
import '../../models/water_river.dart';
import '../../services/water_service.dart';
import 'current_location.dart';
import 'environmental_context.dart';

enum SelectedContextOrigin {
  automaticStation,
  selectedStation,
  selectedEntity,
  favorite,
}

enum FluviResolvedContextSource {
  physicalGps,
  selectedStation,
  selectedEntity,
  favorite,
}

/// The single location/water contract carried between FluviAI destinations.
///
/// Every field is optional because the app must remain truthful when a source
/// has not resolved an entity yet. No placeholder location is ever created.
class SelectedContext {
  const SelectedContext({
    this.countryCode,
    this.region,
    this.locationName,
    this.latitude,
    this.longitude,
    this.waterId,
    this.waterName,
    this.riverName,
    this.riverKey,
    this.stationId,
    this.stationName,
    this.damId,
    this.reservoirId,
    this.hydropowerPlantId,
    this.placeId,
    this.source,
    this.observedAt,
    this.selectedAt,
    this.origin = SelectedContextOrigin.selectedEntity,
  });

  final String? countryCode;
  final String? region;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final String? waterId;
  final String? waterName;
  final String? riverName;
  final String? riverKey;
  final String? stationId;
  final String? stationName;
  final String? damId;
  final String? reservoirId;
  final String? hydropowerPlantId;
  final String? placeId;
  final String? source;
  final DateTime? observedAt;
  final DateTime? selectedAt;
  final SelectedContextOrigin origin;

  factory SelectedContext.fromStation(Station station) => SelectedContext(
    countryCode: station.countryCode,
    locationName: station.name,
    latitude: station.latitude,
    longitude: station.longitude,
    // A monitoring-station identifier is never a water-body identifier.
    waterId: null,
    waterName: station.river.isEmpty ? station.name : station.river,
    riverName: station.river.isEmpty ? null : station.river,
    stationId: station.id,
    stationName: station.name,
    source: station.waterLevelSource,
    observedAt: station.hasWaterLevel ? station.lastUpdate : null,
    origin: SelectedContextOrigin.selectedStation,
  );

  factory SelectedContext.fromRiver(WaterRiverRef river) => SelectedContext(
    countryCode: river.countryCode,
    locationName: river.name,
    waterId: river.waterBodyId,
    waterName: river.name,
    riverName: river.name,
    riverKey: river.key,
    source: river.provenanceSource,
    origin: SelectedContextOrigin.selectedEntity,
  );

  factory SelectedContext.fromHydropowerComplex(
    WaterHydropowerComplex complex,
  ) => SelectedContext(
    countryCode: 'RO',
    locationName: complex.displayName,
    latitude: complex.latitude,
    longitude: complex.longitude,
    waterId: complex.waterBodyId,
    waterName: complex.riverName ?? complex.reservoirName,
    riverName: complex.riverName,
    damId: complex.damId,
    reservoirId: complex.reservoirId,
    hydropowerPlantId: complex.plantId,
    source: complex.evidenceClass,
    origin: SelectedContextOrigin.selectedEntity,
  );

  factory SelectedContext.fromHydropowerPin(WaterMapPin plant) =>
      SelectedContext(
        countryCode: plant.countryCode,
        locationName: plant.name,
        latitude: plant.latitude,
        longitude: plant.longitude,
        waterId: plant.waterBodyId,
        waterName: plant.riverName,
        riverName: plant.riverName,
        hydropowerPlantId: plant.entityId,
        source: plant.stateSource,
        origin: SelectedContextOrigin.selectedEntity,
      );

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get hasEntity =>
      waterId != null ||
      riverKey != null ||
      stationId != null ||
      damId != null ||
      reservoirId != null ||
      hydropowerPlantId != null ||
      placeId != null;

  String? get primaryLabel =>
      stationName ?? waterName ?? riverName ?? locationName;

  EnvironmentalContext? get environmentalContext {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return null;
    return EnvironmentalContext(
      source: stationId != null
          ? EnvironmentalContextSource.selectedStation
          : EnvironmentalContextSource.selectedWater,
      latitude: lat,
      longitude: lng,
      observedAt: observedAt ?? selectedAt ?? DateTime.now(),
      displayLabel: primaryLabel,
      locality: locationName,
      region: region,
      countryCode: countryCode,
      waterId: waterId,
      waterName: waterName,
      stationId: stationId,
      stationName: stationName,
    );
  }

  SelectedContext copyWith({
    String? countryCode,
    String? region,
    String? locationName,
    double? latitude,
    double? longitude,
    String? waterId,
    String? waterName,
    String? riverName,
    String? riverKey,
    String? stationId,
    String? stationName,
    String? damId,
    String? reservoirId,
    String? hydropowerPlantId,
    String? placeId,
    String? source,
    DateTime? observedAt,
    DateTime? selectedAt,
    SelectedContextOrigin? origin,
  }) => SelectedContext(
    countryCode: countryCode ?? this.countryCode,
    region: region ?? this.region,
    locationName: locationName ?? this.locationName,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    waterId: waterId ?? this.waterId,
    waterName: waterName ?? this.waterName,
    riverName: riverName ?? this.riverName,
    riverKey: riverKey ?? this.riverKey,
    stationId: stationId ?? this.stationId,
    stationName: stationName ?? this.stationName,
    damId: damId ?? this.damId,
    reservoirId: reservoirId ?? this.reservoirId,
    hydropowerPlantId: hydropowerPlantId ?? this.hydropowerPlantId,
    placeId: placeId ?? this.placeId,
    source: source ?? this.source,
    observedAt: observedAt ?? this.observedAt,
    selectedAt: selectedAt ?? this.selectedAt,
    origin: origin ?? this.origin,
  );
}

/// Immutable, non-persistent projection of the existing location and
/// selection state. It resolves context precedence without becoming another
/// controller or source of truth.
class FluviResolvedContext {
  const FluviResolvedContext({
    required this.contextKey,
    required this.source,
    required this.provenance,
    this.entityType,
    this.entityId,
    this.stationId,
    this.primaryLabel,
    this.countryCode,
    this.latitude,
    this.longitude,
  });

  final String contextKey;
  final FluviResolvedContextSource source;
  final String? entityType;
  final String? entityId;
  final String? stationId;
  final String? primaryLabel;
  final String? countryCode;
  final double? latitude;
  final double? longitude;
  final String provenance;

  bool get hasUsableCoordinates => _validCoordinates(latitude, longitude);

  EnvironmentalContext? get environmentalContext {
    if (!hasUsableCoordinates) return null;
    return EnvironmentalContext(
      source: switch (source) {
        FluviResolvedContextSource.physicalGps =>
          EnvironmentalContextSource.deviceGps,
        FluviResolvedContextSource.selectedStation =>
          EnvironmentalContextSource.selectedStation,
        FluviResolvedContextSource.selectedEntity ||
        FluviResolvedContextSource.favorite =>
          EnvironmentalContextSource.selectedWater,
      },
      latitude: latitude!,
      longitude: longitude!,
      observedAt: DateTime.now(),
      displayLabel: primaryLabel,
      countryCode: countryCode,
      stationId: stationId,
      stationName: stationId == null ? null : primaryLabel,
      waterId: entityType == 'water' ? entityId : null,
      waterName: entityType == 'water' ? primaryLabel : null,
    );
  }

  static bool _validCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (latitude != 0 || longitude != 0);
}

FluviResolvedContext? resolveFluviContext({
  required SelectedContext? selected,
  required CurrentDeviceLocation? physicalLocation,
}) {
  if (selected != null &&
      selected.origin != SelectedContextOrigin.automaticStation) {
    final entityType = selected.stationId != null
        ? 'station'
        : selected.hydropowerPlantId != null
        ? 'hydropower'
        : selected.damId != null
        ? 'dam'
        : selected.reservoirId != null
        ? 'reservoir'
        : selected.riverKey != null
        ? 'river'
        : selected.waterId != null
        ? 'water'
        : selected.placeId != null
        ? 'place'
        : 'location';
    final entityId =
        selected.stationId ??
        selected.hydropowerPlantId ??
        selected.damId ??
        selected.reservoirId ??
        selected.riverKey ??
        selected.waterId ??
        selected.placeId;
    final source = switch (selected.origin) {
      SelectedContextOrigin.favorite => FluviResolvedContextSource.favorite,
      SelectedContextOrigin.selectedStation =>
        FluviResolvedContextSource.selectedStation,
      SelectedContextOrigin.selectedEntity =>
        FluviResolvedContextSource.selectedEntity,
      SelectedContextOrigin.automaticStation =>
        FluviResolvedContextSource.physicalGps,
    };
    final latitude = selected.latitude;
    final longitude = selected.longitude;
    final coordinateKey =
        FluviResolvedContext._validCoordinates(latitude, longitude)
        ? '${latitude!.toStringAsFixed(5)}:${longitude!.toStringAsFixed(5)}'
        : 'unknown-coordinates';
    return FluviResolvedContext(
      contextKey:
          '${source.name}:$entityType:${entityId ?? selected.primaryLabel ?? 'unknown'}:$coordinateKey',
      source: source,
      entityType: entityType,
      entityId: entityId,
      stationId: selected.stationId,
      primaryLabel: selected.primaryLabel,
      countryCode: selected.countryCode?.trim().toUpperCase(),
      latitude: latitude,
      longitude: longitude,
      provenance: selected.source ?? 'SelectedContext',
    );
  }

  if (physicalLocation == null || !physicalLocation.hasValidCoordinates) {
    return null;
  }
  final latitude = physicalLocation.latitude;
  final longitude = physicalLocation.longitude;
  return FluviResolvedContext(
    contextKey:
        'physicalGps:${latitude.toStringAsFixed(5)}:${longitude.toStringAsFixed(5)}',
    source: FluviResolvedContextSource.physicalGps,
    primaryLabel: physicalLocation.label ?? physicalLocation.locality,
    countryCode: physicalLocation.countryCode?.trim().toUpperCase(),
    latitude: latitude,
    longitude: longitude,
    provenance: physicalLocation.isFreshAt(DateTime.now())
        ? 'Device GPS'
        : 'Device last-known location',
  );
}

class SelectedContextController extends Notifier<SelectedContext?> {
  @override
  SelectedContext? build() => null;

  void select(SelectedContext selection) {
    final selectedAt = DateTime.now();
    final next = selection.copyWith(selectedAt: selectedAt);
    state = next;

    final countryCode = next.countryCode?.trim().toUpperCase();
    if (countryCode == null || countryCode.isEmpty) return;

    final activeRegion = ref.read(contentRegionProvider);
    final region = next.region?.trim();

    final alreadyCanonical =
        activeRegion?.countryCode == countryCode &&
        activeRegion?.isExplicit == true &&
        (region == null || region.isEmpty || activeRegion?.region == region);

    if (alreadyCanonical) return;

    unawaited(
      ref
          .read(contentRegionProvider.notifier)
          .selectCountry(countryCode: countryCode, region: region),
    );
  }

  /// Publishes an explicit station choice and persists it as the Water
  /// selection. Use [publishStation] for automatic/GPS-derived context so the
  /// act of sharing context does not silently pin Water.
  void selectStation(Station station) {
    WaterService().selectStation(station);
    select(SelectedContext.fromStation(station));
  }

  /// Shares station context across modules without changing Water selection
  /// mode. This keeps physical GPS, automatic Water resolution and explicit
  /// user pinning as distinct states.
  void publishStation(Station station) {
    select(SelectedContext.fromStation(station));
  }

  void publishAutomaticStation(Station station) {
    final current = state;
    if (current != null &&
        current.origin != SelectedContextOrigin.automaticStation) {
      return;
    }
    select(
      SelectedContext.fromStation(
        station,
      ).copyWith(origin: SelectedContextOrigin.automaticStation),
    );
  }

  void selectFavorite(SelectedContext selection) {
    select(selection.copyWith(origin: SelectedContextOrigin.favorite));
  }

  void clearAutomaticStation() {
    if (state?.origin == SelectedContextOrigin.automaticStation) state = null;
  }

  void clearWaterContext() {
    final current = state;
    if (current == null) return;
    if (current.stationId != null ||
        current.waterId != null ||
        current.riverKey != null ||
        current.damId != null ||
        current.reservoirId != null ||
        current.hydropowerPlantId != null) {
      state = null;
    }
  }

  void clear() => state = null;
}

final selectedContextProvider =
    NotifierProvider<SelectedContextController, SelectedContext?>(
      SelectedContextController.new,
    );

final canonicalFluviContextProvider = Provider<FluviResolvedContext?>((ref) {
  final selected = ref.watch(selectedContextProvider);
  final locationState = ref.watch(currentLocationProvider);
  return resolveFluviContext(
    selected: selected,
    physicalLocation: locationState.hasUsableLocation
        ? locationState.location
        : null,
  );
});

enum FluviAccessTier { free, premium }

enum FluviDeveloperEntitlementMode { storeReal, forceFree, forcePremium }

class FluviAccessTierController extends Notifier<FluviAccessTier> {
  FluviAccessTier _storeTier = FluviAccessTier.free;
  FluviAccessTier? _developerOverride;

  @override
  FluviAccessTier build() {
    if (BuildModeService.isProductOwner) {
      _developerOverride = FluviAccessTier.premium;
      return FluviAccessTier.premium;
    }
    return FluviAccessTier.free;
  }

  /// Sets the entitlement coming from the real Store/backend contract.
  /// PO overrides never mutate this value.
  void setTier(FluviAccessTier tier) {
    _storeTier = tier;
    state = _developerOverride ?? _storeTier;
  }

  void setDeveloperOverride(FluviAccessTier? tier) {
    if (!BuildModeService.isDeveloperVisible) return;
    _developerOverride = tier;
    state = _developerOverride ?? _storeTier;
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.entitlement,
      operation: 'override',
      message: tier == null
          ? 'Store-real entitlement selected'
          : 'PO entitlement override selected',
      metadata: <String, Object?>{
        'effective_tier': state.name,
        'override': tier?.name ?? 'storeReal',
      },
    );
  }
}

final fluviAccessTierProvider =
    NotifierProvider<FluviAccessTierController, FluviAccessTier>(
      FluviAccessTierController.new,
    );

class FluviDeveloperEntitlementController
    extends Notifier<FluviDeveloperEntitlementMode> {
  static const _preferenceKey = 'po_entitlement_mode_v2_account';

  @override
  FluviDeveloperEntitlementMode build() {
    if (BuildModeService.isDeveloperVisible) {
      unawaited(_restore());
    }
    return BuildModeService.isProductOwner
        ? FluviDeveloperEntitlementMode.forcePremium
        : FluviDeveloperEntitlementMode.storeReal;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey);
    if (stored == null) {
      if (BuildModeService.isProductOwner) {
        await setMode(
          FluviDeveloperEntitlementMode.forcePremium,
          persist: false,
        );
      }
      return;
    }
    FluviDeveloperEntitlementMode? mode;
    for (final value in FluviDeveloperEntitlementMode.values) {
      if (value.name == stored) {
        mode = value;
        break;
      }
    }
    if (mode != null) setMode(mode, persist: false);
  }

  Future<void> setMode(
    FluviDeveloperEntitlementMode mode, {
    bool persist = true,
  }) async {
    if (!BuildModeService.isDeveloperVisible) return;
    state = mode;
    final access = ref.read(fluviAccessTierProvider.notifier);
    switch (mode) {
      case FluviDeveloperEntitlementMode.storeReal:
        access.setDeveloperOverride(null);
        break;
      case FluviDeveloperEntitlementMode.forceFree:
        access.setDeveloperOverride(FluviAccessTier.free);
        break;
      case FluviDeveloperEntitlementMode.forcePremium:
        access.setDeveloperOverride(FluviAccessTier.premium);
        break;
    }
    if (persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, mode.name);
    }
  }
}

final fluviDeveloperEntitlementModeProvider =
    NotifierProvider<
      FluviDeveloperEntitlementController,
      FluviDeveloperEntitlementMode
    >(FluviDeveloperEntitlementController.new);
