from pathlib import Path

MAP = Path('lib/screens/map_page.dart')
PANEL = Path('lib/widgets/fluviai/hydro_intelligence_panel.dart')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'ABORT {label}: expected exactly 1 anchor, found {count}')
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_count = text.count(start)
    end_count = text.count(end)
    if start_count != 1 or end_count != 1:
        raise SystemExit(
            f'ABORT {label}: start={start_count}, end={end_count}; B45C source drifted'
        )
    i = text.index(start)
    j = text.index(end, i)
    return text[:i] + replacement + text[j:]


map_text = MAP.read_text(encoding='utf-8')
panel_text = PANEL.read_text(encoding='utf-8')

# B45C identity guards. Never patch a different map baseline.
for required in (
    "final WaterAssetService _waterAssetService = const WaterAssetService();",
    "mapbox.PointAnnotationManager? _stationAnnotationManager;",
    "Future<void> _loadStations() async {",
    "var hydropowerPins = pins\n          .where((pin) => pin.isHydropower)",
    "if (state?.installedPowerMw case final power?)",
):
    if required not in map_text:
        raise SystemExit(f'ABORT map guard missing: {required}')

for required in (
    "class HydroIntelligenceViewData {",
    "class _OperationalSummary extends StatelessWidget {",
    "key: const ValueKey('hydro-panel-operational-summary')",
):
    if required not in panel_text:
        raise SystemExit(f'ABORT panel guard missing: {required}')

map_text = replace_once(
    map_text,
    "import '../services/favorite_stations_service.dart';\nimport '../services/location_service.dart';",
    "import '../services/favorite_stations_service.dart';\n"
    "import '../services/hydro_map_canonical_service.dart';\n"
    "import '../services/hydro_map_dispatch_presentation.dart';\n"
    "import '../services/location_service.dart';",
    'imports',
)

map_text = replace_once(
    map_text,
    "  final WaterAssetService _waterAssetService = const WaterAssetService();\n"
    "  final SavedItemsService _savedItemsService = const SavedItemsService();",
    "  final WaterAssetService _waterAssetService = const WaterAssetService();\n"
    "  final HydroMapCanonicalService _hydroMapCanonicalService =\n"
    "      const HydroMapCanonicalService();\n"
    "  final SavedItemsService _savedItemsService = const SavedItemsService();",
    'service field',
)

map_text = replace_once(
    map_text,
    "  WaterMapPin? _previewHydropowerPin;\n"
    "  HydropowerPlantState? _previewHydropowerState;",
    "  WaterMapPin? _previewHydropowerPin;\n"
    "  HydropowerPlantState? _previewHydropowerState;\n"
    "  HydroMapDispatchSnapshot? _previewHydroDispatchSnapshot;",
    'dispatch preview field',
)

# Clear forecast state whenever the B45C selection clears its Hydro state.
null_anchor = "_previewHydropowerState = null;"
null_count = map_text.count(null_anchor)
if null_count != 7:
    raise SystemExit(f'ABORT stale-state guard: expected 7 Hydro clears, found {null_count}')
map_text = map_text.replace(
    null_anchor,
    null_anchor + "\n      _previewHydroDispatchSnapshot = null;",
)

load_function = r'''  Future<void> _loadWaterAssetsForCenter(
    LatLng center, {
    double? zoom,
    bool force = false,
  }) async {
    if (!_hasPremiumWater || !_hydroPreferences.enabled) {
      if ((_waterAssets.isNotEmpty || _hydropowerPins.isNotEmpty) && mounted) {
        setState(() {
          _waterAssets = const [];
          _hydropowerPins = const [];
          _previewWaterAsset = null;
          _previewHydropowerPin = null;
          _previewHydropowerState = null;
          _previewHydroDispatchSnapshot = null;
          _waterAssetLoadError = null;
        });
        await _syncWaterAssetAnnotations();
        await _syncHydropowerAnnotations();
      }
      return;
    }
    if (_isLoadingWaterAssets) return;
    final effectiveZoom = zoom ?? 11.5;
    if (effectiveZoom < 5) {
      if ((_waterAssets.isNotEmpty || _hydropowerPins.isNotEmpty) && mounted) {
        setState(() {
          _waterAssets = const [];
          _hydropowerPins = const [];
          _previewWaterAsset = null;
          _previewHydropowerPin = null;
          _previewHydropowerState = null;
          _previewHydroDispatchSnapshot = null;
          _waterAssetLoadError = null;
        });
        await _syncWaterAssetAnnotations();
        await _syncHydropowerAnnotations();
      }
      return;
    }
    final radiusKm = _waterAssetRadiusForZoom(effectiveZoom);
    final previous = _lastWaterAssetQueryCenter;
    final previousRadius = _lastWaterAssetQueryRadiusKm;
    if (!force && previous != null && previousRadius == radiusKm) {
      const distance = Distance();
      final movedKm = distance.as(LengthUnit.Kilometer, previous, center);
      if (movedKm < (radiusKm * .22).clamp(2.0, 18.0)) return;
    }

    if (mounted) {
      setState(() {
        _isLoadingWaterAssets = true;
        _waterAssetLoadError = null;
      });
    }
    try {
      final pins = await _waterAssetService.getMapPins(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusKm: radiusKm,
        zoom: effectiveZoom,
        limit: effectiveZoom >= 12
            ? 650
            : effectiveZoom >= 9
            ? 500
            : 350,
      );
      final canonicalSites = await _hydroMapCanonicalService.getVerifiedSites(
        countryCode: 'RO',
      );
      final canonicalDamIds = canonicalSites
          .map((site) => site.damId)
          .whereType<String>()
          .toSet();
      final canonicalReservoirIds = canonicalSites
          .map((site) => site.reservoirId)
          .whereType<String>()
          .toSet();

      final assets = pins
          .map((pin) => pin.toWaterAssetRef())
          .whereType<WaterAssetRef>()
          .where((asset) {
            if (asset.type == WaterAssetType.dam) {
              return !canonicalDamIds.contains(asset.id);
            }
            if (asset.type == WaterAssetType.reservoir) {
              return !canonicalReservoirIds.contains(asset.id);
            }
            return true;
          })
          .toList(growable: false);

      const distance = Distance();
      var hydropowerPins = canonicalSites
          .where(
            (site) =>
                distance.as(
                  LengthUnit.Kilometer,
                  center,
                  LatLng(site.latitude, site.longitude),
                ) <=
                radiusKm,
          )
          .map((site) => site.toWaterMapPin())
          .toList(growable: false);

      Set<String> savedKeys = _savedWaterAssetKeys;
      if (_savedItemsService.isAuthenticated) {
        try {
          final items = await _savedItemsService.getItems();
          savedKeys = items
              .where(
                (item) =>
                    item.type == 'dam' ||
                    item.type == 'reservoir' ||
                    item.type == 'hydropower' ||
                    item.type == 'river',
              )
              .map((item) => '${item.type}:${item.referenceId}')
              .toSet();
        } on Exception {
          // Keep the last saved state when favorites are temporarily unavailable.
        }
      }
      if (!mounted) return;
      final activeEntityId = _cameraCoordinator.activeTarget?.entityId;
      WaterAssetRef? focusedAsset;
      WaterMapPin? focusedHydropower;
      if (activeEntityId != null) {
        for (final asset in assets) {
          if (asset.id == activeEntityId) {
            focusedAsset = asset;
            break;
          }
        }
        if (focusedAsset == null) {
          for (final site in canonicalSites) {
            if (site.plantId == activeEntityId ||
                site.damId == activeEntityId ||
                site.reservoirId == activeEntityId) {
              focusedHydropower = site.toWaterMapPin();
              break;
            }
          }
          if (focusedHydropower != null &&
              !hydropowerPins.any(
                (pin) => pin.entityId == focusedHydropower!.entityId,
              )) {
            hydropowerPins = <WaterMapPin>[
              ...hydropowerPins,
              focusedHydropower,
            ];
          }
        }
      }
      setState(() {
        _waterAssets = assets;
        _hydropowerPins = hydropowerPins;
        _savedWaterAssetKeys = savedKeys;
        _lastWaterAssetQueryCenter = center;
        _lastWaterAssetQueryRadiusKm = radiusKm;
        if (focusedAsset != null) _previewWaterAsset = focusedAsset;
        if (focusedHydropower != null) {
          _previewHydropowerPin = focusedHydropower;
          _previewHydropowerState = null;
          _previewHydroDispatchSnapshot = null;
          _isLoadingHydroSelection = true;
        }
      });
      logMapRuntime(
        'layers.water-map-pins-fetched',
        fields: {
          'genericCount': pins.length,
          'radiusKm': radiusKm,
          'zoom': effectiveZoom,
          'dams': assets.where((a) => a.type == WaterAssetType.dam).length,
          'reservoirs': assets
              .where((a) => a.type == WaterAssetType.reservoir)
              .length,
          'hydropower': hydropowerPins.length,
          'canonicalHydroSites': canonicalSites.length,
          'suppressedHydroDams': canonicalDamIds.length,
          'suppressedHydroReservoirs': canonicalReservoirIds.length,
          'genericHydropowerIgnored': pins.where((pin) => pin.isHydropower).length,
        },
      );
      await _syncWaterAssetAnnotations();
      await _syncHydropowerAnnotations();
      if (focusedHydropower != null) {
        _publishHydropowerContext(focusedHydropower);
        unawaited(_refreshHydropowerPreview(focusedHydropower));
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _waterAssetLoadError =
            'Water Intelligence nu este disponibil momentan.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingWaterAssets = false);
    }
  }

'''
map_text = replace_between(
    map_text,
    '  Future<void> _loadWaterAssetsForCenter(',
    '  double _waterAssetRadiusForZoom',
    load_function,
    'canonical Hydro loader',
)

publish_method = r'''  void _publishHydropowerContext(
    WaterMapPin pin, {
    HydroMapDispatchSnapshot? snapshot,
  }) {
    final payload = pin.statePayload;
    final damId = snapshot?.damId ?? payload['dam_id']?.toString();
    final reservoirId =
        snapshot?.reservoirId ?? payload['reservoir_id']?.toString();
    ref
        .read(selectedContextProvider.notifier)
        .select(
          SelectedContext(
            countryCode: pin.countryCode,
            locationName: pin.name,
            latitude: pin.latitude,
            longitude: pin.longitude,
            waterId: pin.waterBodyId,
            waterName: pin.riverName,
            riverName: pin.riverName,
            damId: damId,
            reservoirId: reservoirId,
            hydropowerPlantId: pin.entityId,
            source: snapshot?.evidenceClass ?? pin.stateSource,
          ),
        );
  }

'''
map_text = replace_between(
    map_text,
    '  void _publishHydropowerContext(WaterMapPin pin) {',
    '  Future<void> _refreshHydropowerPreview',
    publish_method,
    'canonical SelectedContext',
)

refresh_method = r'''  Future<void> _refreshHydropowerPreview(WaterMapPin pin) async {
    try {
      final snapshot = await _hydroMapCanonicalService.getDispatchSnapshot(
        pin.entityId,
      );
      if (!mounted || _previewHydropowerPin?.entityId != pin.entityId) return;
      setState(() {
        _previewHydropowerState = null;
        _previewHydroDispatchSnapshot = snapshot;
      });
      _publishHydropowerContext(pin, snapshot: snapshot);
    } on Exception {
      if (!mounted || _previewHydropowerPin?.entityId != pin.entityId) return;
      setState(() {
        _previewHydropowerState = null;
        _previewHydroDispatchSnapshot = null;
      });
    } finally {
      if (mounted && _previewHydropowerPin?.entityId == pin.entityId) {
        setState(() => _isLoadingHydroSelection = false);
      }
    }
  }

'''
map_text = replace_between(
    map_text,
    '  Future<void> _refreshHydropowerPreview(WaterMapPin pin) async {',
    '  Future<void> _toggleHydropowerFavorite',
    refresh_method,
    'safe dispatch preview',
)

open_details = r'''  Future<void> _openHydropowerDetails(WaterMapPin pin) async {
    if (!mounted) return;
    await AppNavigator.open<void>(
      context,
      AppDestination.hydropower,
      arguments: pin.name,
    );
  }

'''
map_text = replace_between(
    map_text,
    '  Future<void> _openHydropowerDetails(WaterMapPin pin) async {',
    '  Future<String?> _ensureWaterAssetStyleImage',
    open_details,
    'no heavy map detail prefetch',
)

relationships_method = r'''  List<HydroRelationshipItem> _hydropowerRelationships(
    WaterMapPin plant,
    HydropowerPlantState? state,
  ) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final payload = plant.statePayload;
    final reservoirId = state?.reservoirId ?? payload['reservoir_id']?.toString();
    final damId = state?.damId ?? payload['dam_id']?.toString();
    return <HydroRelationshipItem>[
      if (plant.riverName?.isNotEmpty == true)
        HydroRelationshipItem(
          label: isRomanian ? 'Pe apă' : 'On water',
          title: plant.riverName!,
          typeLabel: context.l10n.hydroRiver,
          icon: Icons.waves_rounded,
        ),
      if (reservoirId != null)
        HydroRelationshipItem(
          label: isRomanian ? 'Aici' : 'Here',
          title: isRomanian ? 'Acumulare asociată' : 'Linked reservoir',
          typeLabel: context.l10n.hydroReservoir,
          icon: Icons.water_rounded,
        ),
      if (damId != null)
        HydroRelationshipItem(
          label: isRomanian ? 'Aici' : 'Here',
          title: isRomanian ? 'Baraj asociat' : 'Linked dam',
          typeLabel: context.l10n.hydroDam,
          icon: Icons.account_balance_rounded,
        ),
    ];
  }

'''
map_text = replace_between(
    map_text,
    '  List<HydroRelationshipItem> _hydropowerRelationships(',
    '  bool _isOfficialOrAnalyticalEvidence',
    relationships_method,
    'canonical Hydro relationships',
)

plant_block = r'''    final plant = _previewHydropowerPin;
    if (plant != null) {
      final snapshot = _previewHydroDispatchSnapshot;
      final forecast = HydroMapDispatchPresenter.present(
        snapshot,
        isRomanian: isRomanian,
      );
      final observedState =
          snapshot?.observedState.toUpperCase() ?? 'NO_RECENT_OBSERVATION';
      final observedActive = observedState == 'OBSERVED_ACTIVE';
      final observedEnded = observedState == 'OBSERVED_ENDED';
      final operation = observedActive
          ? 'ACTIVE'
          : observedEnded
          ? 'INACTIVE'
          : 'UNKNOWN';
      final hasObservedOperation = observedActive || observedEnded;
      final observedConfidence = snapshot?.observedConfidence ?? 0;
      final data = <HydroIntelligenceDatum>[
        if (plant.riverName?.isNotEmpty == true)
          HydroIntelligenceDatum(
            label: l10n.hydroRiver,
            value: plant.riverName!,
            icon: Icons.waves_rounded,
          ),
      ];
      return HydroIntelligenceViewData(
        name: plant.name,
        typeLabel: l10n.hydroPlant,
        contextLabel: plant.riverName,
        forecastProbabilityLabel: forecast.available
            ? forecast.probabilityLabel
            : null,
        forecastWindowLabel: forecast.available ? forecast.windowLabel : null,
        forecastConfidenceLabel: forecast.available
            ? forecast.confidenceLabel
            : null,
        forecastEvidenceLabel: forecast.available
            ? forecast.evidenceLabel
            : null,
        icon: Icons.bolt_rounded,
        accentColor: MapFeatureRegistry.hydropower,
        statusTitle: isRomanian ? 'Stare de funcționare' : 'Operating status',
        unavailableLabel: isRomanian
            ? 'Fără observație recentă în teren'
            : 'No recent field observation',
        statusLabel: hasObservedOperation
            ? _localizedOperation(operation)
            : l10n.hydroEvidenceUnknown,
        hasOperationalStatus: hasObservedOperation,
        statusColor: _hydropowerOperationColor(operation),
        evidenceLabel: hasObservedOperation
            ? _evidenceExplanation('OBSERVED')
            : _evidenceExplanation('UNKNOWN'),
        sourceLabel: hasObservedOperation
            ? (isRomanian ? 'Observații comunitare' : 'Community observations')
            : null,
        freshnessLabel: null,
        confidenceLabel: hasObservedOperation && observedConfidence > 0
            ? _confidenceExplanation(observedConfidence)
            : null,
        relationships: _hydropowerRelationships(plant, null),
        unknownMessage: l10n.hydroUnknownState,
        data: data,
        loading: _isLoadingHydroSelection,
      );
    }

'''
map_text = replace_between(
    map_text,
    '    final plant = _previewHydropowerPin;',
    '    final selection = _hydroPublicSelection;',
    plant_block,
    'safe Hydro panel data',
)

# Panel DTO: additive forecast fields only.
panel_text = replace_once(
    panel_text,
    "    this.contextLabel,\n    this.metadataLabel,\n    this.statusColor,",
    "    this.contextLabel,\n"
    "    this.metadataLabel,\n"
    "    this.forecastProbabilityLabel,\n"
    "    this.forecastWindowLabel,\n"
    "    this.forecastConfidenceLabel,\n"
    "    this.forecastEvidenceLabel,\n"
    "    this.statusColor,",
    'panel constructor forecast fields',
)
panel_text = replace_once(
    panel_text,
    "  final String? contextLabel;\n  final String? metadataLabel;\n  final IconData icon;",
    "  final String? contextLabel;\n"
    "  final String? metadataLabel;\n"
    "  final String? forecastProbabilityLabel;\n"
    "  final String? forecastWindowLabel;\n"
    "  final String? forecastConfidenceLabel;\n"
    "  final String? forecastEvidenceLabel;\n"
    "  final IconData icon;",
    'panel DTO forecast fields',
)
panel_text = replace_once(
    panel_text,
    "                    _OperationalSummary(\n"
    "                      sectionTitle: isRomanian\n"
    "                          ? 'CE ȘTIM ACUM'\n"
    "                          : 'WHAT WE KNOW NOW',\n"
    "                      title: data.statusTitle,\n"
    "                      status: data.statusLabel,\n"
    "                      unavailableLabel: data.unavailableLabel,\n"
    "                      available: data.hasOperationalStatus,\n"
    "                      color: effectiveStatusColor,\n"
    "                    ),\n"
    "                    if (data.evidenceLabel?.isNotEmpty == true ||",
    "                    _OperationalSummary(\n"
    "                      sectionTitle: isRomanian\n"
    "                          ? 'CE ȘTIM ACUM'\n"
    "                          : 'WHAT WE KNOW NOW',\n"
    "                      title: data.statusTitle,\n"
    "                      status: data.statusLabel,\n"
    "                      unavailableLabel: data.unavailableLabel,\n"
    "                      available: data.hasOperationalStatus,\n"
    "                      color: effectiveStatusColor,\n"
    "                    ),\n"
    "                    if (data.forecastProbabilityLabel?.isNotEmpty == true &&\n"
    "                        data.forecastWindowLabel?.isNotEmpty == true) ...<Widget>[\n"
    "                      const SizedBox(height: 8),\n"
    "                      _DispatchForecastSummary(\n"
    "                        probability: data.forecastProbabilityLabel!,\n"
    "                        window: data.forecastWindowLabel!,\n"
    "                        confidence: data.forecastConfidenceLabel,\n"
    "                        evidence: data.forecastEvidenceLabel,\n"
    "                        color: data.accentColor,\n"
    "                      ),\n"
    "                    ],\n"
    "                    if (data.evidenceLabel?.isNotEmpty == true ||",
    'panel forecast block',
)

dispatch_widget = r'''class _DispatchForecastSummary extends StatelessWidget {
  const _DispatchForecastSummary({
    required this.probability,
    required this.window,
    required this.color,
    this.confidence,
    this.evidence,
  });

  final String probability;
  final String window;
  final String? confidence;
  final String? evidence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return Container(
      key: const ValueKey('hydro-panel-dispatch-summary'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            color.withValues(alpha: .16),
            const Color(0xFF0A1920).withValues(alpha: .96),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isRomanian
                      ? 'PROBABILITATE DE UZINARE'
                      : 'GENERATION PROBABILITY',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
              ),
              if (evidence?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color.withValues(alpha: .35)),
                  ),
                  child: Text(
                    evidence!,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                probability,
                style: const TextStyle(
                  color: Color(0xFFF6FBFD),
                  fontSize: 29,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    isRomanian ? 'Interval estimat' : 'Estimated window',
                    style: const TextStyle(
                      color: Color(0xFF91A8B5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    window,
                    style: const TextStyle(
                      color: Color(0xFFF6FBFD),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (confidence?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              confidence!,
              style: const TextStyle(
                color: Color(0xFF9FB4BE),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

'''
panel_text = replace_once(
    panel_text,
    'class _OperationalSummary extends StatelessWidget {',
    dispatch_widget + 'class _OperationalSummary extends StatelessWidget {',
    'dispatch summary widget',
)

# Postconditions are deliberately strict.
if ".where((pin) => pin.isHydropower)\n          .toList" in map_text:
    raise SystemExit('ABORT postcondition: generic Hydro pins still drive rendering')
if "if (state?.installedPowerMw case final power?)" in map_text:
    raise SystemExit('ABORT postcondition: MW still present in Hydro map panel')
for required in (
    '_stationAnnotationManager',
    'Future<void> _loadStations() async {',
    '_stationAnnotationOptions(',
    '_hydroMapCanonicalService.getVerifiedSites',
    'canonicalDamIds.contains(asset.id)',
    'canonicalReservoirIds.contains(asset.id)',
    '_previewHydroDispatchSnapshot',
):
    if required not in map_text:
        raise SystemExit(f'ABORT postcondition missing: {required}')
for required in (
    'forecastProbabilityLabel',
    'hydro-panel-dispatch-summary',
    'PROBABILITATE DE UZINARE',
    'Interval estimat',
):
    if required not in panel_text:
        raise SystemExit(f'ABORT panel postcondition missing: {required}')

MAP.write_text(map_text, encoding='utf-8')
PANEL.write_text(panel_text, encoding='utf-8')
print('B45C Hydro canonical patch applied with all guards satisfied.')
