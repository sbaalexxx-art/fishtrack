import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../core/map/pending_map_camera.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/map_entry.dart';
import '../../../models/station.dart';
import '../../../models/water_asset.dart';
import '../../../models/water_river.dart';
import '../../../services/alert_rule_repository.dart';
import '../../../services/billing_repository.dart';
import '../../../services/map_search_service.dart';
import '../../../services/water_service.dart';
import '../../../services/water_asset_service.dart';
import '../../../services/weather_alert_rule_repository.dart';
import 'figma_foundation.dart';

class FigmaGlobalSearchPage extends StatefulWidget {
  const FigmaGlobalSearchPage({
    super.key,
    this.waterService,
    this.searchService = const MapSearchService(),
    this.assetService = const WaterAssetService(),
  });

  final WaterService? waterService;
  final MapSearchService searchService;
  final WaterAssetService assetService;

  @override
  State<FigmaGlobalSearchPage> createState() => _FigmaGlobalSearchPageState();
}

class _FigmaGlobalSearchPageState extends State<FigmaGlobalSearchPage> {
  late final WaterService _waterService;
  late Future<List<Station>> _future;
  Future<_RemoteSearchResults> _remoteFuture = Future.value(
    const _RemoteSearchResults(),
  );
  final _query = TextEditingController();
  Timer? _searchDebounce;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _waterService = widget.waterService ?? WaterService();
    _future = _waterService.getStations();
    _query.addListener(_onChanged);
  }

  void _onChanged() {
    _searchDebounce?.cancel();
    final query = _query.text.trim();
    setState(() {
      if (query.length < 2) {
        _remoteFuture = Future.value(const _RemoteSearchResults());
      }
    });
    if (query.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || query != _query.text.trim()) return;
      setState(() {
        _remoteFuture = _searchRemote(query);
      });
    });
  }

  Future<_RemoteSearchResults> _searchRemote(String query) async {
    final places = await widget.searchService.search(query);
    final anchor = places.isEmpty ? null : places.first;
    final parts = await Future.wait<Object>([
      widget.assetService.searchAssets(query, limit: 50),
      widget.assetService.searchRivers(query, limit: 50),
      widget.assetService.searchHydropower(
        query,
        limit: 50,
        anchorLatitude: anchor?.latitude,
        anchorLongitude: anchor?.longitude,
      ),
    ]);
    return _RemoteSearchResults(
      places: places,
      assets: parts[0] as List<WaterAssetRef>,
      rivers: parts[1] as List<WaterRiverRef>,
      hydropower: parts[2] as List<WaterMapPin>,
    );
  }

  @override
  void dispose() {
    _query.removeListener(_onChanged);
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-global-search'),
      title: 'Căutare',
      eyebrow: 'GLOBAL',
      child: FutureBuilder<List<Station>>(
        future: _future,
        builder: (context, state) {
          final all = state.data ?? const <Station>[];
          final filteredStations = all
              .where((station) {
                if (_filter == 1 &&
                    station.waterBodyType != WaterBodyType.river) {
                  return false;
                }
                if (_filter == 3) return false;
                if (query.isEmpty) return true;
                final haystack =
                    '${station.name} ${station.river} ${station.id}'
                        .toLowerCase();
                return haystack.contains(query);
              })
              .take(50)
              .toList(growable: false);
          return FutureBuilder<_RemoteSearchResults>(
            future: _remoteFuture,
            builder: (context, remoteState) {
              final remote = remoteState.data ?? const _RemoteSearchResults();
              final places = _filter == 1 || _filter == 2
                  ? const <MapSearchResult>[]
                  : remote.places;
              final assets = _filter == 2 || _filter == 3
                  ? const <WaterAssetRef>[]
                  : remote.assets;
              final rivers = _filter == 2 || _filter == 3
                  ? const <WaterRiverRef>[]
                  : remote.rivers;
              final hydropower = _filter == 2 || _filter == 3
                  ? const <WaterMapPin>[]
                  : remote.hydropower;
              final isSearchingPlaces =
                  query.length >= 2 &&
                  remoteState.connectionState == ConnectionState.waiting;
              final resultCount =
                  filteredStations.length +
                  rivers.length +
                  assets.length +
                  hydropower.length +
                  places.length;
              return Column(
                children: [
                  TextField(
                    key: const ValueKey('figma-global-search-field'),
                    controller: _query,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Caută ape, stații, baraje, locuri…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        FigmaPill(
                          label: 'Toate',
                          active: _filter == 0,
                          onTap: () => setState(() => _filter = 0),
                        ),
                        const SizedBox(width: 8),
                        FigmaPill(
                          label: 'Ape',
                          active: _filter == 1,
                          onTap: () => setState(() => _filter = 1),
                        ),
                        const SizedBox(width: 8),
                        FigmaPill(
                          label: 'Stații',
                          active: _filter == 2,
                          onTap: () => setState(() => _filter = 2),
                        ),
                        const SizedBox(width: 8),
                        FigmaPill(
                          label: 'Locuri',
                          active: _filter == 3,
                          onTap: () => setState(() => _filter = 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child:
                        state.connectionState == ConnectionState.waiting &&
                            !state.hasData
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : resultCount == 0 && isSearchingPlaces
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : resultCount == 0
                        ? const FigmaTruthfulEmpty(
                            icon: Icons.search_off_rounded,
                            title: 'Niciun rezultat',
                            message:
                                'Căutarea globală nu a găsit un loc sau o stație reală.',
                          )
                        : ListView.separated(
                            itemCount: resultCount,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (index < filteredStations.length) {
                                return _SearchResultTile(
                                  station: filteredStations[index],
                                );
                              }
                              final waterIndex =
                                  index - filteredStations.length;
                              if (waterIndex < rivers.length) {
                                return _WaterRiverSearchResultTile(
                                  river: rivers[waterIndex],
                                );
                              }
                              final assetIndex = waterIndex - rivers.length;
                              if (assetIndex < assets.length) {
                                return _WaterAssetSearchResultTile(
                                  asset: assets[assetIndex],
                                );
                              }
                              final hydropowerIndex =
                                  assetIndex - assets.length;
                              if (hydropowerIndex < hydropower.length) {
                                return _HydropowerSearchResultTile(
                                  plant: hydropower[hydropowerIndex],
                                );
                              }
                              return _PlaceSearchResultTile(
                                result:
                                    places[hydropowerIndex - hydropower.length],
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Locurile mută doar camera. Locația GPS rămâne neschimbată.',
                    style: figmaBody(size: 9),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _RemoteSearchResults {
  const _RemoteSearchResults({
    this.places = const <MapSearchResult>[],
    this.assets = const <WaterAssetRef>[],
    this.rivers = const <WaterRiverRef>[],
    this.hydropower = const <WaterMapPin>[],
  });

  final List<MapSearchResult> places;
  final List<WaterAssetRef> assets;
  final List<WaterRiverRef> rivers;
  final List<WaterMapPin> hydropower;
}

ContextualMapEntry hydropowerSearchMapEntry(WaterMapPin plant) =>
    ContextualMapEntry.forTarget(
      source: 'global-search-hydropower',
      target: RuntimeMapCameraTarget(
        source: 'global-search-hydropower',
        entityId: plant.entityId,
        latitude: plant.latitude,
        longitude: plant.longitude,
        zoom: 13.4,
      ),
    );

class _HydropowerSearchResultTile extends ConsumerWidget {
  const _HydropowerSearchResultTile({required this.plant});

  final WaterMapPin plant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPro =
        ref.watch(fluviAccessTierProvider) == FluviAccessTier.premium;
    return FigmaSurface(
      onTap: () {
        if (hasPro) {
          ref
              .read(selectedContextProvider.notifier)
              .select(SelectedContext.fromHydropowerPin(plant));
        }
        AppNavigator.open(
          context,
          hasPro ? AppDestination.contextualMap : AppDestination.premium,
          arguments: hasPro ? hydropowerSearchMapEntry(plant) : null,
        );
      },
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.bolt_rounded,
            size: 19,
            color: FigmaFluviTokens.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    'CHE',
                    if (plant.riverName?.isNotEmpty == true) plant.riverName!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figmaBody(size: 9),
                ),
              ],
            ),
          ),
          _SearchStatusPill(
            label: hasPro ? 'HYDRO' : 'PRO',
            color: hasPro ? FigmaFluviTokens.cyan : FigmaFluviTokens.amber,
          ),
        ],
      ),
    );
  }
}

class _WaterRiverSearchResultTile extends ConsumerWidget {
  const _WaterRiverSearchResultTile({required this.river});

  final WaterRiverRef river;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPro =
        ref.watch(fluviAccessTierProvider) == FluviAccessTier.premium;
    return FigmaSurface(
      onTap: () => AppNavigator.open(
        context,
        hasPro ? AppDestination.river : AppDestination.premium,
        arguments: hasPro ? river : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.waves_rounded,
            size: 19,
            color: FigmaFluviTokens.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  river.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    'Râu',
                    if (river.basinNames.isNotEmpty) river.basinNames.first,
                    if (river.basinCode?.isNotEmpty == true) river.basinCode!,
                    '${river.damCount} baraje',
                    '${river.reservoirCount} acumulări',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figmaBody(size: 9),
                ),
              ],
            ),
          ),
          _SearchStatusPill(
            label: hasPro ? 'WATER' : 'PRO',
            color: hasPro ? FigmaFluviTokens.cyan : FigmaFluviTokens.amber,
          ),
        ],
      ),
    );
  }
}

class _SearchStatusPill extends StatelessWidget {
  const _SearchStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'IBM Plex Mono',
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _WaterAssetSearchResultTile extends ConsumerWidget {
  const _WaterAssetSearchResultTile({required this.asset});

  final WaterAssetRef asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDam = asset.type == WaterAssetType.dam;
    final hasPro =
        ref.watch(fluviAccessTierProvider) == FluviAccessTier.premium;
    return FigmaSurface(
      onTap: () => AppNavigator.open(
        context,
        hasPro ? AppDestination.reservoir : AppDestination.premium,
        arguments: hasPro ? asset : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            isDam ? Icons.account_balance_rounded : Icons.water_rounded,
            size: 19,
            color: FigmaFluviTokens.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    isDam ? 'Baraj' : 'Lac de acumulare',
                    if (asset.riverName?.isNotEmpty == true) asset.riverName!,
                    if (asset.county?.isNotEmpty == true) asset.county!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: figmaBody(size: 9),
                ),
              ],
            ),
          ),
          _SearchStatusPill(
            label: !hasPro
                ? 'PRO'
                : asset.hasOperationalData
                ? 'DATE'
                : 'CATALOG',
            color: !hasPro
                ? FigmaFluviTokens.amber
                : asset.hasOperationalData
                ? FigmaFluviTokens.green
                : FigmaFluviTokens.textMuted,
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.station});

  final Station station;

  @override
  Widget build(BuildContext context) {
    return FigmaSurface(
      onTap: () => AppNavigator.open(
        context,
        AppDestination.contextualMap,
        arguments: ContextualMapEntry.forStation(
          source: 'global-search',
          station: station,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: FigmaFluviTokens.cyan,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.river.trim().isEmpty
                      ? station.name
                      : '${station.name} · ${station.river}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  station.waterBodyType == WaterBodyType.lake
                      ? 'Lac / acumulare'
                      : 'Stație hidrometrică',
                  style: figmaBody(size: 9),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: FigmaFluviTokens.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _PlaceSearchResultTile extends StatelessWidget {
  const _PlaceSearchResultTile({required this.result});

  final MapSearchResult result;

  @override
  Widget build(BuildContext context) {
    return FigmaSurface(
      onTap: () => AppNavigator.open(
        context,
        AppDestination.contextualMap,
        arguments: ContextualMapEntry.forTarget(
          source: 'global-search',
          target: RuntimeMapCameraTarget(
            source: 'global-search',
            entityId: result.name,
            latitude: result.latitude,
            longitude: result.longitude,
            zoom: 13.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 19,
            color: FigmaFluviTokens.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (result.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    result.description!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: figmaBody(size: 9),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.map_outlined, color: FigmaFluviTokens.textSecondary),
        ],
      ),
    );
  }
}

class FigmaAlertEditorPage extends ConsumerStatefulWidget {
  const FigmaAlertEditorPage({
    super.key,
    this.station,
    this.waterAsset,
    this.waterRiver,
    this.rule,
    this.weatherTarget,
    this.repository = const AlertRuleRepository(),
    this.weatherRepository = const WeatherAlertRuleRepository(),
  });

  final Station? station;
  final WaterAssetRef? waterAsset;
  final WaterRiverRef? waterRiver;
  final AlertRule? rule;
  final WeatherAlertTarget? weatherTarget;
  final AlertRuleRepository repository;
  final WeatherAlertRuleRepository weatherRepository;

  @override
  ConsumerState<FigmaAlertEditorPage> createState() =>
      _FigmaAlertEditorPageState();
}

class _FigmaAlertEditorPageState extends ConsumerState<FigmaAlertEditorPage> {
  late AlertRuleKind _kind;
  late WeatherAlertKind _weatherKind;
  late TextEditingController _threshold;
  bool _enabled = true;
  bool _saving = false;
  String? _message;

  bool get _isWeather => widget.weatherTarget != null;
  bool get _isWaterAsset => widget.waterAsset != null;
  bool get _isWaterRiver => widget.waterRiver != null;
  bool get _supportsNumericWaterThresholds => _isWaterRiver
      ? false
      : (!_isWaterAsset || widget.waterAsset!.hasOperationalData);

  @override
  void initState() {
    super.initState();
    _kind =
        widget.rule?.kind ??
        ((_isWaterAsset || _isWaterRiver)
            ? AlertRuleKind.stateChange
            : AlertRuleKind.levelAbove);
    _weatherKind = WeatherAlertKind.strongGusts;
    _enabled = widget.rule?.enabled ?? true;
    _threshold = TextEditingController(
      text: widget.rule?.threshold?.toStringAsFixed(0) ?? '',
    );
    if (_isWeather && _threshold.text.isEmpty) {
      _threshold.text = _defaultWeatherThreshold(
        _weatherKind,
      ).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  double _defaultWeatherThreshold(WeatherAlertKind kind) => switch (kind) {
    WeatherAlertKind.strongWind => 35,
    WeatherAlertKind.strongGusts => 50,
    WeatherAlertKind.heavyRain => 8,
    WeatherAlertKind.thunderstorm => 0,
    WeatherAlertKind.extremeHeat => 35,
    WeatherAlertKind.extremeCold => 0,
  };

  String _weatherThresholdLabel(WeatherAlertKind kind) => switch (kind) {
    WeatherAlertKind.strongWind => 'Prag vânt km/h',
    WeatherAlertKind.strongGusts => 'Prag rafale km/h',
    WeatherAlertKind.heavyRain => 'Prag precipitații mm/h',
    WeatherAlertKind.thunderstorm => 'Fără prag numeric',
    WeatherAlertKind.extremeHeat ||
    WeatherAlertKind.extremeCold => 'Prag temperatură °C',
  };

  void _setWeatherKind(WeatherAlertKind kind) {
    setState(() {
      _weatherKind = kind;
      if (kind != WeatherAlertKind.thunderstorm) {
        _threshold.text = _defaultWeatherThreshold(kind).toStringAsFixed(0);
      }
    });
  }

  Future<void> _save() async {
    if (_isWeather) {
      await _saveWeather();
      return;
    }
    await _saveWaterOrCommunity();
  }

  Future<void> _saveWeather() async {
    final target = widget.weatherTarget;
    if (target == null) return;
    final needsThreshold = _weatherKind != WeatherAlertKind.thunderstorm;
    final threshold = needsThreshold
        ? double.tryParse(_threshold.text.replaceAll(',', '.'))
        : null;
    if (needsThreshold && threshold == null) {
      setState(() => _message = 'Introdu un prag numeric valid.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    final rule = WeatherAlertRule(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      target: target,
      kind: _weatherKind,
      createdAt: DateTime.now(),
      threshold: threshold,
      enabled: _enabled,
    );
    try {
      await widget.weatherRepository.save(rule);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Alerta meteo nu a putut fi salvată. Încearcă din nou.';
      });
    }
  }

  Future<void> _saveWaterOrCommunity() async {
    final selected = ref.read(selectedContextProvider);
    final station = widget.station;
    final waterAsset = widget.waterAsset;
    final waterRiver = widget.waterRiver;
    final entityId =
        widget.rule?.entityId ??
        waterRiver?.waterBodyId ??
        waterAsset?.id ??
        station?.id ??
        selected?.stationId ??
        selected?.waterId;
    final entityLabel =
        widget.rule?.entityLabel ??
        waterRiver?.name ??
        waterAsset?.name ??
        station?.name ??
        selected?.primaryLabel;
    final entityType =
        widget.rule?.entityType ??
        (waterRiver != null ? 'water_body' : null) ??
        waterAsset?.entityType ??
        (station != null || selected?.stationId != null
            ? 'station'
            : 'water_body');
    if (entityId == null || entityLabel == null) {
      setState(
        () => _message = 'Selectează mai întâi o apă sau o stație reală.',
      );
      return;
    }
    final needsThreshold =
        _kind != AlertRuleKind.communityReport &&
        _kind != AlertRuleKind.stateChange;
    final threshold = needsThreshold
        ? double.tryParse(_threshold.text.replaceAll(',', '.'))
        : null;
    if (needsThreshold && threshold == null) {
      setState(() => _message = 'Introdu un prag numeric valid.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    final rule = AlertRule(
      id: widget.rule?.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}',
      entityId: entityId,
      entityLabel: entityLabel,
      entityType: entityType,
      kind: _kind,
      createdAt: widget.rule?.createdAt ?? DateTime.now(),
      threshold: threshold,
      enabled: _enabled,
    );
    try {
      await widget.repository.save(rule);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _message = 'Alerta nu a putut fi salvată. Încearcă din nou.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedContextProvider);
    final label = _isWeather
        ? widget.weatherTarget!.label
        : widget.rule?.entityLabel ??
              widget.waterRiver?.name ??
              widget.waterAsset?.name ??
              widget.station?.name ??
              selected?.primaryLabel ??
              'Nicio entitate selectată';
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-alert-editor'),
      title: widget.rule == null ? 'Alertă nouă' : 'Editează alerta',
      eyebrow: 'ALERTĂ SINCRONIZATĂ',
      child: ListView(
        children: [
          FigmaSurface(
            child: Row(
              children: [
                Icon(
                  _isWeather ? Icons.cloud_outlined : Icons.water_rounded,
                  color: FigmaFluviTokens.cyan,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FigmaFluviTokens.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const FigmaSectionLabel('Tip alertă'),
          const SizedBox(height: 10),
          if (_isWeather) _weatherKindSelector() else _waterKindSelector(),
          if (_isWeather
              ? _weatherKind != WeatherAlertKind.thunderstorm
              : _kind != AlertRuleKind.communityReport &&
                    _kind != AlertRuleKind.stateChange) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _threshold,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: _isWeather
                    ? _weatherThresholdLabel(_weatherKind)
                    : _kind == AlertRuleKind.rapidChange
                    ? 'Prag cm/24h'
                    : 'Prag nivel cm',
              ),
            ),
          ],
          const SizedBox(height: 12),
          FigmaSurface(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Alertă activă',
                    style: TextStyle(
                      color: FigmaFluviTokens.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: figmaBody(color: FigmaFluviTokens.red, size: 11),
            ),
          ],
          const SizedBox(height: 18),
          FigmaPrimaryButton(
            label: _saving ? 'Se salvează…' : 'Salvează alerta',
            icon: Icons.notifications_active_rounded,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _waterKindSelector() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (_supportsNumericWaterThresholds) ...[
        FigmaPill(
          label: 'Nivel peste',
          active: _kind == AlertRuleKind.levelAbove,
          onTap: () => setState(() => _kind = AlertRuleKind.levelAbove),
        ),
        FigmaPill(
          label: 'Nivel sub',
          active: _kind == AlertRuleKind.levelBelow,
          onTap: () => setState(() => _kind = AlertRuleKind.levelBelow),
        ),
        FigmaPill(
          label: 'Schimbare rapidă',
          active: _kind == AlertRuleKind.rapidChange,
          onTap: () => setState(() => _kind = AlertRuleKind.rapidChange),
        ),
      ],
      FigmaPill(
        label: 'Schimbare stare',
        active: _kind == AlertRuleKind.stateChange,
        onTap: () => setState(() => _kind = AlertRuleKind.stateChange),
      ),
      FigmaPill(
        label: 'Raport în zonă',
        active: _kind == AlertRuleKind.communityReport,
        onTap: () => setState(() => _kind = AlertRuleKind.communityReport),
      ),
    ],
  );

  Widget _weatherKindSelector() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FigmaPill(
        label: 'Vânt',
        active: _weatherKind == WeatherAlertKind.strongWind,
        onTap: () => _setWeatherKind(WeatherAlertKind.strongWind),
      ),
      FigmaPill(
        label: 'Rafale',
        active: _weatherKind == WeatherAlertKind.strongGusts,
        onTap: () => _setWeatherKind(WeatherAlertKind.strongGusts),
      ),
      FigmaPill(
        label: 'Ploaie',
        active: _weatherKind == WeatherAlertKind.heavyRain,
        onTap: () => _setWeatherKind(WeatherAlertKind.heavyRain),
      ),
      FigmaPill(
        label: 'Furtună',
        active: _weatherKind == WeatherAlertKind.thunderstorm,
        onTap: () => _setWeatherKind(WeatherAlertKind.thunderstorm),
      ),
      FigmaPill(
        label: 'Căldură',
        active: _weatherKind == WeatherAlertKind.extremeHeat,
        onTap: () => _setWeatherKind(WeatherAlertKind.extremeHeat),
      ),
      FigmaPill(
        label: 'Frig',
        active: _weatherKind == WeatherAlertKind.extremeCold,
        onTap: () => _setWeatherKind(WeatherAlertKind.extremeCold),
      ),
    ],
  );
}

class FigmaRestoreResultPage extends StatelessWidget {
  const FigmaRestoreResultPage({super.key, required this.result});

  final BillingRestoreResult result;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final (icon, title, message, color) = switch (result) {
      BillingRestoreResult.restored => (
        Icons.check_circle_rounded,
        isRo ? 'Premium restaurat' : 'Premium restored',
        isRo
            ? 'Drepturile Premium au fost restaurate.'
            : 'Premium entitlement was restored for this session.',
        FigmaFluviTokens.green,
      ),
      BillingRestoreResult.nothingToRestore => (
        Icons.info_outline_rounded,
        isRo ? 'Nicio achiziție găsită' : 'No purchase found',
        isRo
            ? 'Magazinul nu a returnat o achiziție eligibilă.'
            : 'The store returned no eligible purchase.',
        FigmaFluviTokens.amber,
      ),
      BillingRestoreResult.unavailable => (
        Icons.cloud_off_rounded,
        isRo ? 'Restaurarea nu este disponibilă' : 'Restore is unavailable',
        isRo
            ? 'Repository-ul de billing nu este conectat.'
            : 'The billing repository is not connected; the plan was not changed.',
        FigmaFluviTokens.textMuted,
      ),
      BillingRestoreResult.error => (
        Icons.error_outline_rounded,
        isRo ? 'Restaurarea a eșuat' : 'Restore failed',
        isRo
            ? 'Planul nu a fost modificat.'
            : 'The plan was not changed. Try again later.',
        FigmaFluviTokens.red,
      ),
    };
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-restore-result'),
      title: isRo ? 'Rezultat restaurare' : 'Restore result',
      eyebrow: 'FLUVIAI PRO',
      child: Center(
        child: FigmaSurface(
          accent: color,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 46),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: figmaBody(size: 12),
              ),
              const SizedBox(height: 16),
              FigmaPrimaryButton(
                label: isRo ? 'Continuă la profil' : 'Continue to profile',
                onPressed: () =>
                    AppNavigator.open(context, AppDestination.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FigmaReportConfirmedPage extends StatelessWidget {
  const FigmaReportConfirmedPage({super.key, required this.stillValid});

  final bool stillValid;

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-report-confirmed'),
      title: 'Confirmare raport',
      eyebrow: 'ÎNCREDERE COMUNITATE',
      child: FigmaTruthfulEmpty(
        icon: stillValid ? Icons.verified_rounded : Icons.report_off_outlined,
        title: stillValid ? 'Raport confirmat' : 'Raport marcat ca expirat',
        message: stillValid
            ? 'Confirmarea reală a fost înregistrată.'
            : 'Marcajul real a fost înregistrat.',
        actionLabel: 'Înapoi la Comunitate',
        onAction: () => AppNavigator.open(context, AppDestination.community),
      ),
    );
  }
}

class FigmaFavoriteCollectionPage extends StatelessWidget {
  const FigmaFavoriteCollectionPage({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => FigmaCanonicalScaffold(
    key: const ValueKey('figma-favorite-collection'),
    title: label ?? 'Colecție',
    eyebrow: 'FAVORITE',
    child: const FigmaTruthfulEmpty(
      icon: Icons.folder_special_outlined,
      title: 'Colecție goală',
      message: 'Salvează entități reale din hartă pentru a construi colecția.',
    ),
  );
}
