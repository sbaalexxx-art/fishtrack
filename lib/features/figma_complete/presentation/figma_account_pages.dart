import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/current_location.dart';
import '../../../core/context/selected_context.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/map_entry.dart';
import '../../../core/map/pending_map_camera.dart';
import '../../../core/theme/fluviai_commercial_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../l10n/l10n.dart';
import '../../../models/station.dart';
import '../../../models/saved_item.dart';
import '../../../models/water_asset.dart';
import '../../../models/water_river.dart';
import '../../../services/alert_rule_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/billing_repository.dart';
import '../../../services/notification_service.dart';
import '../../../services/hydro_map_canonical_service.dart';
import '../../../services/community_service.dart';
import '../../../services/favorite_stations_service.dart';
import '../../../services/saved_items_service.dart';
import '../../../services/support_service.dart';
import '../../../services/reputation_service.dart';
import '../../../services/water_asset_service.dart';
import '../../../services/water_service.dart';
import '../../../services/weather_alert_rule_repository.dart';
import '../../../widgets/fluviai/draggable_ask_fluvi.dart';
import 'figma_foundation.dart';

String _countryLabel(String? countryCode) =>
    switch (countryCode?.toUpperCase()) {
      'RO' => 'România',
      'GB' || 'UK' => 'Regatul Unit',
      final code? when code.isNotEmpty => code,
      _ => 'Automat',
    };

String _countryFlag(String? countryCode) =>
    switch (countryCode?.toUpperCase()) {
      'RO' => '🇷🇴',
      'GB' || 'UK' => '🇬🇧',
      _ => '🌍',
    };

Future<void> _showFigmaInfo(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    backgroundColor: FigmaFluviTokens.surface,
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Închide'),
      ),
    ],
  ),
);

class FigmaFavoritesPage extends StatefulWidget {
  const FigmaFavoritesPage({
    super.key,
    this.favoritesService = const FavoriteStationsService(),
    this.savedItemsService = const SavedItemsService(),
    this.waterAssetService = const WaterAssetService(),
    this.waterService,
  });

  final FavoriteStationsService favoritesService;
  final SavedItemsService savedItemsService;
  final WaterAssetService waterAssetService;
  final WaterService? waterService;

  @override
  State<FigmaFavoritesPage> createState() => _FigmaFavoritesPageState();
}

class _FigmaFavoritesPageState extends State<FigmaFavoritesPage> {
  late final WaterService _waterService;
  late Future<_FigmaFavoritesData> _future;
  int _tab = 2;

  @override
  void initState() {
    super.initState();
    _waterService = widget.waterService ?? WaterService();
    _future = _load();
    FavoriteStationsService.revision.addListener(_externalRefresh);
    SavedItemsService.revision.addListener(_externalRefresh);
  }

  @override
  void dispose() {
    FavoriteStationsService.revision.removeListener(_externalRefresh);
    SavedItemsService.revision.removeListener(_externalRefresh);
    super.dispose();
  }

  void _externalRefresh() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<_FigmaFavoritesData> _load() async {
    if (!widget.favoritesService.isAuthenticated) {
      return const _FigmaFavoritesData();
    }

    // Stations are an independent canonical collection.
    // Loading Water/Places must never hide valid favorite stations.
    Set<String> favoriteIds;
    try {
      favoriteIds = await widget.favoritesService.getFavoriteIds();
    } catch (_) {
      favoriteIds = const <String>{};
    }

    List<Station> favoriteStations = const <Station>[];
    if (favoriteIds.isNotEmpty) {
      try {
        final catalog = await _waterService.getStations();
        favoriteStations = catalog
            .where((station) => favoriteIds.contains(station.id))
            .toList(growable: false);
      } catch (_) {
        favoriteStations = const <Station>[];
      }
    }

    // Water bodies / rivers / places are independent from Stations.
    List<SavedItem> savedItems;
    try {
      savedItems = await widget.savedItemsService.getItems();
    } catch (_) {
      savedItems = const <SavedItem>[];
    }

    return _FigmaFavoritesData(stations: favoriteStations, items: savedItems);
  }

  Future<void> _refresh() async {
    final next = _load();
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    try {
      await next;
    } on Exception {
      // FutureBuilder displays the real failure.
    }
  }

  Future<void> _remove(Station station) async {
    try {
      await widget.favoritesService.setFavorite(station.id, favorite: false);
      await _refresh();
    } on FavoriteException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _removeSaved(SavedItem item) async {
    try {
      await widget.savedItemsService.remove(
        type: item.type,
        referenceId: item.referenceId,
      );
      await _refresh();
    } on SavedItemsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openSaved(SavedItem item) async {
    if (item.type == 'river') {
      try {
        final candidates = await widget.waterAssetService.searchRivers(
          item.title,
          limit: 50,
        );
        final storedRiverKey =
            item.metadata['river_key']?.toString() ?? item.referenceId;
        final storedWaterBodyId = item.metadata['water_body_id']?.toString();
        WaterRiverRef? river;
        for (final candidate in candidates) {
          if (candidate.key == storedRiverKey ||
              (storedWaterBodyId != null &&
                  candidate.waterBodyId == storedWaterBodyId)) {
            river = candidate;
            break;
          }
        }
        if (river == null) {
          throw const WaterAssetException(
            'Râul salvat nu mai este disponibil în catalogul canonic.',
          );
        }
        if (!mounted) return;
        await AppNavigator.open(
          context,
          AppDestination.river,
          arguments: river,
        );
        return;
      } on Exception {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Râul salvat nu este disponibil momentan.'),
          ),
        );
        return;
      }
    }

    if (item.type == 'dam' || item.type == 'reservoir') {
      final lat = item.latitude;
      final lng = item.longitude;
      if (lat == null || lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coordonatele entității Water nu sunt disponibile.'),
          ),
        );
        return;
      }
      final asset = WaterAssetRef(
        type: item.type == 'dam'
            ? WaterAssetType.dam
            : WaterAssetType.reservoir,
        id: item.referenceId,
        name: item.title,
        latitude: lat,
        longitude: lng,
        subtitle: item.subtitle,
        basinName: item.metadata['basin_name']?.toString(),
        waterBodyId: item.metadata['water_body_id']?.toString(),
      );
      await AppNavigator.open(
        context,
        AppDestination.reservoir,
        arguments: asset,
      );
      return;
    }

    final lat = item.latitude;
    final lng = item.longitude;
    if (lat == null || lng == null) return;
    try {
      ProviderScope.containerOf(context, listen: false)
          .read(selectedContextProvider.notifier)
          .select(
            SelectedContext(
              locationName: item.title,
              latitude: lat,
              longitude: lng,
              waterId: item.type == 'water_body' ? item.referenceId : null,
              waterName: item.type == 'water_body' ? item.title : null,
              placeId: item.type == 'place' ? item.referenceId : null,
            ),
          );
    } on StateError {
      // Isolated widget tests may omit ProviderScope.
    }
    if (!mounted) return;
    await AppNavigator.open(context, AppDestination.map);
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-favorites-page'),
      title: 'Favorite',
      eyebrow: 'APELE ȘI LOCURILE TALE',
      showBack: true,
      action: FigmaRoundButton(
        icon: Icons.edit_outlined,
        tooltip: 'Editează',
        onPressed: () => _showFigmaInfo(
          context,
          title: 'Editează favoritele',
          message:
              'Folosește steaua fiecărei stații pentru a o elimina. Nicio modificare nu este aplicată fără acțiunea ta.',
        ),
      ),
      padding: EdgeInsets.zero,
      child: FutureBuilder<_FigmaFavoritesData>(
        future: _future,
        builder: (context, state) {
          final data = state.data ?? const _FigmaFavoritesData();
          final stations = data.stations;
          final savedItems = switch (_tab) {
            0 =>
              data.items
                  .where(
                    (item) => const {
                      'water_body',
                      'river',
                      'dam',
                      'reservoir',
                    }.contains(item.type),
                  )
                  .toList(growable: false),
            1 =>
              data.items
                  .where(
                    (item) => !const {
                      'water_body',
                      'river',
                      'dam',
                      'reservoir',
                    }.contains(item.type),
                  )
                  .toList(growable: false),
            _ => const <SavedItem>[],
          };
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    FigmaPill(
                      label: 'Ape',
                      active: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    const SizedBox(width: 8),
                    FigmaPill(
                      label: 'Locuri',
                      active: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                    const SizedBox(width: 8),
                    FigmaPill(
                      label: 'Stații',
                      active: _tab == 2,
                      onTap: () => setState(() => _tab = 2),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.connectionState == ConnectionState.waiting &&
                    !state.hasData)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (state.hasError)
                  FigmaTruthfulEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Favorite indisponibile',
                    message: 'Verifică sesiunea și conexiunea.',
                    actionLabel: 'Reîncearcă',
                    onAction: _refresh,
                  )
                else if (_tab == 2 && stations.isEmpty)
                  FigmaTruthfulEmpty(
                    icon: Icons.star_border_rounded,
                    title: 'Nicio stație favorită',
                    message: widget.favoritesService.isAuthenticated
                        ? 'Salvează o stație reală din harta completă.'
                        : 'Autentificarea este necesară pentru favorite.',
                    actionLabel: 'Deschide harta',
                    onAction: () => AppNavigator.open(
                      context,
                      AppDestination.contextualMap,
                      arguments: ContextualMapEntry.browse(
                        source: 'favorites-empty',
                      ),
                    ),
                    minHeight: 270,
                  )
                else if (_tab != 2 && savedItems.isEmpty)
                  FigmaTruthfulEmpty(
                    icon: Icons.bookmark_border_rounded,
                    title: _tab == 0
                        ? 'Nicio apă salvată'
                        : 'Niciun loc salvat',
                    message: _tab == 0
                        ? 'Salvează o apă reală din contextul hărții.'
                        : 'Folosește „Salvează locul” după ce selectezi un context real.',
                    actionLabel: 'Deschide harta',
                    onAction: () =>
                        AppNavigator.open(context, AppDestination.map),
                    minHeight: 270,
                  )
                else if (_tab == 2)
                  for (var index = 0; index < stations.length; index++) ...[
                    _FavoriteStationCard(
                      station: stations[index],
                      onRemove: () => _remove(stations[index]),
                    ),
                    if (index != stations.length - 1)
                      const SizedBox(height: 10),
                  ]
                else
                  for (var index = 0; index < savedItems.length; index++) ...[
                    _FigmaSavedItemCard(
                      item: savedItems[index],
                      onOpen: () => _openSaved(savedItems[index]),
                      onRemove: () => _removeSaved(savedItems[index]),
                    ),
                    if (index != savedItems.length - 1)
                      const SizedBox(height: 10),
                  ],
                const SizedBox(height: 14),
                Center(
                  child: TextButton.icon(
                    onPressed: _tab == 2
                        ? () => AppNavigator.open(
                            context,
                            AppDestination.contextualMap,
                            arguments: ContextualMapEntry.browse(
                              source: 'favorites-add-station',
                            ),
                          )
                        : () => AppNavigator.open(context, AppDestination.map),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      _tab == 2
                          ? 'Adaugă stație din hartă'
                          : _tab == 0
                          ? 'Favorite pentru ape'
                          : 'Locuri salvate',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FigmaFavoritesData {
  const _FigmaFavoritesData({
    this.stations = const <Station>[],
    this.items = const <SavedItem>[],
  });
  final List<Station> stations;
  final List<SavedItem> items;
}

class _FigmaSavedItemCard extends StatelessWidget {
  const _FigmaSavedItemCard({
    required this.item,
    required this.onOpen,
    required this.onRemove,
  });
  final SavedItem item;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => FigmaSurface(
    onTap: onOpen,
    child: Row(
      children: [
        const Icon(Icons.place_rounded, color: FigmaFluviTokens.cyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (item.subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  item.subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: FigmaFluviTokens.textMuted),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Elimină',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}

class _FavoriteStationCard extends StatelessWidget {
  const _FavoriteStationCard({required this.station, required this.onRemove});

  final Station station;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasLevel = station.hasWaterLevel && station.level.isFinite;
    final trendColor = !station.hasKnownTrend
        ? FigmaFluviTokens.textMuted
        : switch (station.trend) {
            WaterTrend.rising => const Color(0xFF29B6F6),
            WaterTrend.falling => FigmaFluviTokens.red,
            WaterTrend.stable => FigmaFluviTokens.green,
          };
    return FigmaSurface(
      onTap: () =>
          AppNavigator.open(context, AppDestination.water, arguments: station),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  station.river.trim().isEmpty
                      ? station.name
                      : '${station.name} · ${station.river}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Elimină din favorite',
                onPressed: onRemove,
                icon: const Icon(
                  Icons.star_rounded,
                  color: FigmaFluviTokens.cyan,
                  size: 20,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasLevel
                    ? '${station.level.toStringAsFixed(0)} ${station.waterLevelUnit}'
                    : 'Date indisponibile',
                style: TextStyle(
                  color: hasLevel
                      ? FigmaFluviTokens.white
                      : FigmaFluviTokens.textMuted,
                  fontSize: hasLevel ? 24 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              FigmaStatusDot(
                label: station.hasKnownTrend
                    ? station.trendText
                    : 'TREND NECUNOSCUT',
                color: trendColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => AppNavigator.open(
                  context,
                  AppDestination.contextualMap,
                  arguments: ContextualMapEntry.forStation(
                    source: 'favorite-station',
                    station: station,
                  ),
                ),
                icon: const Icon(Icons.location_on_outlined, size: 16),
                label: const Text('Vezi harta'),
              ),
              const Spacer(),
              Text(
                station.waterLevelSource,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: figmaBody(size: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FigmaAlertsPage extends StatefulWidget {
  const FigmaAlertsPage({
    super.key,
    this.repository = const AlertRuleRepository(),
    this.weatherRepository = const WeatherAlertRuleRepository(),
  });

  final AlertRuleRepository repository;
  final WeatherAlertRuleRepository weatherRepository;

  @override
  State<FigmaAlertsPage> createState() => _FigmaAlertsPageState();
}

class _FigmaAlertsPageState extends State<FigmaAlertsPage> {
  late Future<_FigmaAlertsData> _future;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_FigmaAlertsData> _loadData() async {
    final results = await Future.wait<Object>([
      widget.repository.load(),
      widget.weatherRepository.load(),
      NotificationService().getNotifications(),
    ]);
    return _FigmaAlertsData(
      waterRules: results[0] as List<AlertRule>,
      weatherRules: results[1] as List<WeatherAlertRule>,
      notifications: results[2] as List<AppNotification>,
    );
  }

  Future<void> _reload() async {
    final next = _loadData();
    if (!mounted) return;
    setState(() => _future = next);
    try {
      await next;
    } on Exception {
      // FutureBuilder renders the repository failure.
    }
  }

  Future<void> _toggleWater(AlertRule rule, bool enabled) async {
    await widget.repository.save(rule.copyWith(enabled: enabled));
    if (!mounted) return;
    await _reload();
  }

  Future<void> _toggleWeather(WeatherAlertRule rule, bool enabled) async {
    await widget.weatherRepository.save(rule.copyWith(enabled: enabled));
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-alerts-page'),
      title: 'Alerte și notificări',
      eyebrow: 'MONITORIZARE',
      action: FigmaRoundButton(
        key: const ValueKey('alerts-open-settings'),
        icon: Icons.settings_outlined,
        tooltip: 'Setări notificări',
        onPressed: () =>
            AppNavigator.open(context, AppDestination.notificationPreferences),
      ),
      padding: EdgeInsets.zero,
      child: FutureBuilder<_FigmaAlertsData>(
        future: _future,
        builder: (context, state) {
          final data = state.data ?? const _FigmaAlertsData();
          final activeWater = data.waterRules.where((rule) => rule.enabled);
          final activeWeather = data.weatherRules.where((rule) => rule.enabled);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FigmaPill(
                      label: 'Active',
                      active: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    FigmaPill(
                      label: 'Regulile mele',
                      active: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                    FigmaPill(
                      label: 'Istoric',
                      active: _tab == 2,
                      onTap: () => setState(() => _tab = 2),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FigmaSectionLabel(
                  _tab == 2 ? 'Istoric real' : 'Reguli sincronizate',
                ),
                const SizedBox(height: 10),
                if (state.connectionState == ConnectionState.waiting &&
                    !state.hasData)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (state.hasError)
                  FigmaTruthfulEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Alertele nu pot fi încărcate',
                    message: 'Verifică conexiunea și încearcă din nou.',
                    actionLabel: 'Reîncearcă',
                    onAction: _reload,
                  )
                else if (_tab == 2)
                  _AlertHistory(notifications: data.notifications)
                else ...[
                  if ((_tab == 0 ? activeWater : data.waterRules).isEmpty &&
                      (_tab == 0 ? activeWeather : data.weatherRules).isEmpty)
                    FigmaTruthfulEmpty(
                      icon: Icons.notifications_active_outlined,
                      title: 'Nicio regulă creată',
                      message:
                          'Creează o alertă din Water sau Weather pentru contextul real urmărit.',
                    )
                  else ...[
                    for (final rule
                        in (_tab == 0 ? activeWater : data.waterRules)) ...[
                      _AlertRuleCard(
                        rule: rule,
                        onChanged: (value) => _toggleWater(rule, value),
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final rule
                        in (_tab == 0 ? activeWeather : data.weatherRules)) ...[
                      _WeatherAlertRuleCard(
                        rule: rule,
                        onChanged: (value) => _toggleWeather(rule, value),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
                const SizedBox(height: 18),
                FigmaPrimaryButton(
                  label: 'Alertă Water / Community',
                  icon: Icons.add_alert_rounded,
                  secondary: true,
                  onPressed: () =>
                      AppNavigator.open(context, AppDestination.newAlert),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FigmaAlertsData {
  const _FigmaAlertsData({
    this.waterRules = const [],
    this.weatherRules = const [],
    this.notifications = const [],
  });

  final List<AlertRule> waterRules;
  final List<WeatherAlertRule> weatherRules;
  final List<AppNotification> notifications;
}

class _AlertRuleCard extends StatelessWidget {
  const _AlertRuleCard({required this.rule, required this.onChanged});

  final AlertRule rule;
  final ValueChanged<bool> onChanged;

  String get _description => switch (rule.kind) {
    AlertRuleKind.levelAbove =>
      'Nivel peste ${rule.threshold?.toStringAsFixed(0) ?? '—'} cm',
    AlertRuleKind.levelBelow =>
      'Nivel sub ${rule.threshold?.toStringAsFixed(0) ?? '—'} cm',
    AlertRuleKind.rapidChange =>
      'Schimbare rapidă ${rule.threshold?.toStringAsFixed(0) ?? '—'} cm/24h',
    AlertRuleKind.stateChange => 'Schimbare observată a stării apei',
    AlertRuleKind.communityReport => 'Raport comunitate în zonă',
  };

  @override
  Widget build(BuildContext context) => FigmaSurface(
    accent: rule.enabled ? FigmaFluviTokens.cyan : FigmaFluviTokens.textMuted,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: FigmaFluviTokens.cyan.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.water_rounded, color: FigmaFluviTokens.cyan),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rule.entityLabel,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(_description, style: figmaBody(size: 10)),
            ],
          ),
        ),
        Switch(value: rule.enabled, onChanged: onChanged),
      ],
    ),
  );
}

class _WeatherAlertRuleCard extends StatelessWidget {
  const _WeatherAlertRuleCard({required this.rule, required this.onChanged});

  final WeatherAlertRule rule;
  final ValueChanged<bool> onChanged;

  String get _description => switch (rule.kind) {
    WeatherAlertKind.strongWind =>
      'Vânt ≥ ${rule.threshold?.toStringAsFixed(0) ?? '—'} km/h',
    WeatherAlertKind.strongGusts =>
      'Rafale ≥ ${rule.threshold?.toStringAsFixed(0) ?? '—'} km/h',
    WeatherAlertKind.heavyRain =>
      'Ploaie ≥ ${rule.threshold?.toStringAsFixed(1) ?? '—'} mm/h',
    WeatherAlertKind.thunderstorm => 'Furtună în prognoza apropiată',
    WeatherAlertKind.extremeHeat =>
      'Temperatură ≥ ${rule.threshold?.toStringAsFixed(0) ?? '—'}°C',
    WeatherAlertKind.extremeCold =>
      'Temperatură ≤ ${rule.threshold?.toStringAsFixed(0) ?? '—'}°C',
  };

  @override
  Widget build(BuildContext context) => FigmaSurface(
    accent: rule.enabled ? FigmaFluviTokens.amber : FigmaFluviTokens.textMuted,
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: FigmaFluviTokens.amber.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.cloud_outlined,
            color: FigmaFluviTokens.amber,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rule.target.label,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(_description, style: figmaBody(size: 10)),
            ],
          ),
        ),
        Switch(value: rule.enabled, onChanged: onChanged),
      ],
    ),
  );
}

class _AlertHistory extends StatelessWidget {
  const _AlertHistory({required this.notifications});

  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context) {
    final alerts = notifications
        .where(
          (item) => switch (item.type) {
            AppNotificationType.waterLevelChanged ||
            AppNotificationType.waterTrendChanged ||
            AppNotificationType.waterStateObserved ||
            AppNotificationType.newReportNearFavoriteStation ||
            AppNotificationType.dangerousReport ||
            AppNotificationType.newCatchNearSavedArea ||
            AppNotificationType.weatherAlert ||
            AppNotificationType.reportVerificationChanged ||
            AppNotificationType.catchLiked ||
            AppNotificationType.hydroDispatchForecast ||
            AppNotificationType.hydroDispatchWindowApproaching ||
            AppNotificationType.hydroDispatchObserved => true,
            _ => false,
          },
        )
        .take(30)
        .toList(growable: false);
    if (alerts.isEmpty) {
      return const FigmaTruthfulEmpty(
        icon: Icons.history_rounded,
        title: 'Nicio alertă încă',
        message:
            'Evenimentele reale Water, Weather și Community vor apărea aici.',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < alerts.length; index++) ...[
          FigmaSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  alerts[index].type == AppNotificationType.weatherAlert
                      ? Icons.cloud_outlined
                      : Icons.notifications_active_outlined,
                  color: alerts[index].priority == NotificationPriority.critical
                      ? FigmaFluviTokens.red
                      : FigmaFluviTokens.cyan,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alerts[index].title,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(alerts[index].message, style: figmaBody(size: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (index != alerts.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class FigmaNotificationCenterPage extends StatefulWidget {
  const FigmaNotificationCenterPage({super.key});

  @override
  State<FigmaNotificationCenterPage> createState() =>
      _FigmaNotificationCenterPageState();
}

class _FigmaNotificationCenterPageState
    extends State<FigmaNotificationCenterPage> {
  final NotificationService _service = NotificationService();
  final CommunityService _communityService = const CommunityService();
  late final Stream<List<AppNotification>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _service.watchNotifications();
    unawaited(_service.getNotifications());
  }

  Future<void> _open(AppNotification notification) async {
    try {
      if (!notification.isRead) {
        await _service.markAsRead(notification.id);
      }
      if (!mounted) return;

      final reportId = notification.relatedReport;
      final catchId = notification.relatedCatch;
      if (reportId != null || catchId != null) {
        final posts = await _communityService.getFeed(forceRefresh: true);
        CommunityPost? target;
        final id = reportId ?? catchId;
        for (final post in posts) {
          if (post.id == id) {
            target = post;
            break;
          }
        }
        if (!mounted) return;
        if (target != null) {
          await AppNavigator.open(
            context,
            target.type == CommunityPostType.report
                ? AppDestination.reportDetail
                : AppDestination.catchDetail,
            arguments: target,
          );
          return;
        }
      }

      final notificationEntityId = notification.entityId;
      if (notification.entityType == 'hydropower_plant' &&
          notificationEntityId != null &&
          notificationEntityId.isNotEmpty) {
        final sites = await const HydroMapCanonicalService().getVerifiedSites(
          countryCode: 'RO',
        );
        HydroCanonicalMapSite? site;
        for (final candidate in sites) {
          if (candidate.plantId == notificationEntityId) {
            site = candidate;
            break;
          }
        }
        if (!mounted) return;
        if (site != null) {
          await AppNavigator.open<void>(
            context,
            AppDestination.contextualMap,
            arguments: ContextualMapEntry.forTarget(
              source: 'notification-hydro-dispatch',
              target: RuntimeMapCameraTarget(
                source: 'notification-hydro-dispatch',
                entityId: site.plantId!,
                latitude: site.latitude,
                longitude: site.longitude,
                zoom: 13.4,
              ),
            ),
          );
          return;
        }
      }

      final stationId = notification.relatedStation;
      if (stationId != null) {
        final stations = await WaterService().getStations();
        Station? station;
        for (final candidate in stations) {
          if (candidate.id == stationId) {
            station = candidate;
            break;
          }
        }
        if (!mounted) return;
        if (station != null) {
          await AppNavigator.open(
            context,
            AppDestination.water,
            arguments: station,
          );
          return;
        }
      }

      if (notification.entityType == 'profile') {
        await AppNavigator.open(context, AppDestination.profile);
      }
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Detaliul notificării nu este disponibil momentan.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-notification-center'),
      title: 'Notificări',
      eyebrow: 'CENTRU',
      action: FigmaRoundButton(
        icon: Icons.tune_rounded,
        tooltip: 'Preferințe',
        onPressed: () =>
            AppNavigator.open(context, AppDestination.notificationPreferences),
      ),
      child: StreamBuilder<List<AppNotification>>(
        stream: _stream,
        initialData: _service.cachedNotifications(),
        builder: (context, snapshot) {
          final notifications = snapshot.data ?? const <AppNotification>[];
          if (snapshot.hasError && notifications.isEmpty) {
            return FigmaTruthfulEmpty(
              icon: Icons.cloud_off_rounded,
              title: 'Notificările nu pot fi încărcate',
              message:
                  'Verifică conexiunea. Ultimele notificări salvate reapar automat când serviciul revine.',
            );
          }
          if (notifications.isEmpty) {
            return FigmaTruthfulEmpty(
              icon: Icons.notifications_none_rounded,
              title: 'Nicio notificare disponibilă',
              message:
                  'Alertele pentru ape, rapoarte, capturi și zone urmărite vor apărea aici.',
              actionLabel: context.l10n.notificationEmptyAction,
              onAction: () => AppNavigator.open(
                context,
                AppDestination.notificationPreferences,
              ),
              minHeight: 280,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = notifications[index];
              return FigmaSurface(
                onTap: () => _open(item),
                accent: _notificationAccent(item.priority),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _notificationAccent(
                          item.priority,
                        ).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _notificationIcon(item.type),
                        color: _notificationAccent(item.priority),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    color: FigmaFluviTokens.white,
                                    fontSize: 13,
                                    fontWeight: item.isRead
                                        ? FontWeight.w700
                                        : FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (!item.isRead)
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: FigmaFluviTokens.cyan,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(item.message, style: figmaBody(size: 10.5)),
                          const SizedBox(height: 7),
                          Text(
                            _notificationAge(item.createdAt),
                            style: figmaBody(
                              size: 9,
                              color: FigmaFluviTokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static IconData _notificationIcon(AppNotificationType type) => switch (type) {
    AppNotificationType.waterLevelChanged => Icons.water_rounded,
    AppNotificationType.waterTrendChanged => Icons.trending_down_rounded,
    AppNotificationType.waterStateObserved => Icons.water_drop_outlined,
    AppNotificationType.newReportNearFavoriteStation => Icons.campaign_outlined,
    AppNotificationType.dangerousReport => Icons.warning_amber_rounded,
    AppNotificationType.newCatchNearSavedArea => Icons.set_meal_rounded,
    AppNotificationType.reputationIncreased => Icons.insights_rounded,
    AppNotificationType.trustBadgeUpgraded => Icons.verified_rounded,
    AppNotificationType.favoriteStationUpdate => Icons.favorite_rounded,
    AppNotificationType.weatherAlert => Icons.cloud_outlined,
    AppNotificationType.reportVerificationChanged => Icons.fact_check_outlined,
    AppNotificationType.catchLiked => Icons.favorite_border_rounded,
    AppNotificationType.hydroDispatchForecast ||
    AppNotificationType.hydroDispatchWindowApproaching ||
    AppNotificationType.hydroDispatchObserved => Icons.bolt_rounded,
  };

  static Color _notificationAccent(NotificationPriority priority) =>
      switch (priority) {
        NotificationPriority.silent => FigmaFluviTokens.textMuted,
        NotificationPriority.important => FigmaFluviTokens.cyan,
        NotificationPriority.critical => FigmaFluviTokens.red,
      };

  static String _notificationAge(DateTime createdAt) {
    final delta = DateTime.now().difference(createdAt.toLocal());
    if (delta.isNegative || delta.inMinutes < 1) return 'acum';
    if (delta.inHours < 1) return 'acum ${delta.inMinutes} min';
    if (delta.inDays < 1) return 'acum ${delta.inHours} h';
    if (delta.inDays < 7) return 'acum ${delta.inDays} zile';
    final local = createdAt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }
}

class FigmaRegulationsPage extends StatefulWidget {
  const FigmaRegulationsPage({super.key, this.initialTab = 1});

  final int initialTab;

  @override
  State<FigmaRegulationsPage> createState() => _FigmaRegulationsPageState();
}

class _FigmaRegulationsPageState extends State<FigmaRegulationsPage> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_tab) {
      0 => 'Permis',
      1 => 'Reglementări',
      _ => 'Siguranță',
    };
    final selected = ProviderScope.containerOf(
      context,
    ).read(selectedContextProvider);
    final countryLabel = _countryLabel(selected?.countryCode);
    final countryFlag = _countryFlag(selected?.countryCode);
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-regulations-page'),
      title: 'Permis, reguli și siguranță',
      eyebrow: countryLabel.toUpperCase(),
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          FigmaSurface(
            onTap: () => _showFigmaInfo(
              context,
              title: 'Țara conținutului',
              message:
                  'Pachetul de conținut este selectat din contextul aplicației. Schimbarea țării se face din Setări.',
            ),
            child: Row(
              children: [
                Text(countryFlag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    countryLabel,
                    style: const TextStyle(
                      color: FigmaFluviTokens.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: FigmaFluviTokens.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FigmaPill(
                  label: 'Permis',
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FigmaPill(
                  label: 'Reglementări',
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FigmaPill(
                  label: 'Siguranță',
                  active: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FigmaSurface(
            accent: FigmaFluviTokens.amber,
            child: Text(
              'Verifică întotdeauna sursa oficială înainte de pescuit. FluviAI nu afișează date juridice neverificate.',
              style: figmaBody(
                color: FigmaFluviTokens.amber,
                size: 10,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FigmaSectionLabel(title),
          const SizedBox(height: 10),
          if (_tab == 0)
            const _PermitContent()
          else if (_tab == 1)
            const _RegulationsContent()
          else
            const _SafetyContent(),
        ],
      ),
    );
  }
}

class _PermitContent extends StatelessWidget {
  const _PermitContent();

  @override
  Widget build(BuildContext context) => const FigmaTruthfulEmpty(
    icon: Icons.badge_outlined,
    title: 'Permisul nu este conectat',
    message:
        'Valabilitatea și emitentul vor fi afișate numai din sursa oficială.',
  );
}

class _RegulationsContent extends StatelessWidget {
  const _RegulationsContent();

  @override
  Widget build(BuildContext context) {
    const species = ['Știucă', 'Șalău', 'Crap', 'Somn', 'Clean'];
    return FigmaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: FigmaFluviTokens.amber,
                  size: 18,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Datele oficiale de prohibiție și limite sunt indisponibile.',
                    style: TextStyle(
                      color: FigmaFluviTokens.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const FigmaDivider(),
          for (final item in species) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const FigmaPill(label: 'LUNGIME —'),
                  const SizedBox(width: 6),
                  const FigmaPill(label: 'LIMITĂ —', active: true),
                ],
              ),
            ),
            if (item != species.last) const FigmaDivider(),
          ],
        ],
      ),
    );
  }
}

class _SafetyContent extends StatelessWidget {
  const _SafetyContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SafetyRow(
          icon: Icons.phone_rounded,
          color: FigmaFluviTokens.red,
          title: '112 · Urgențe',
          subtitle: 'Număr național unic',
        ),
        const SizedBox(height: 10),
        const _SafetyRow(
          icon: Icons.support_agent_rounded,
          color: FigmaFluviTokens.textSecondary,
          title: 'Contact oficial în integrare',
          subtitle: 'Nu afișăm numere neverificate',
        ),
        const SizedBox(height: 10),
        _SafetyRow(
          icon: Icons.warning_amber_rounded,
          color: FigmaFluviTokens.cyan,
          title: 'Raportează braconaj',
          subtitle: 'Deschide fișa de sesizare rapidă',
          onTap: () => AppNavigator.open(context, AppDestination.addReport),
        ),
      ],
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FigmaSurface(
    accent: color,
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: figmaBody(size: 10)),
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

class FigmaToolkitPage extends StatelessWidget {
  const FigmaToolkitPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-toolkit-page'),
      title: 'Instrumente pescar',
      eyebrow: 'PREGĂTIRE',
      child: ListView(
        children: [
          _ToolkitTile(
            icon: Icons.badge_outlined,
            title: 'Permis de pescuit',
            subtitle: 'Stare și valabilitate din sursă oficială',
            destination: AppDestination.permit,
          ),
          const SizedBox(height: 10),
          _ToolkitTile(
            icon: Icons.rule_rounded,
            title: 'Reglementări',
            subtitle: 'Prohibiții, dimensiuni și limite verificate',
            destination: AppDestination.regulations,
          ),
          const SizedBox(height: 10),
          _ToolkitTile(
            icon: Icons.health_and_safety_outlined,
            title: 'Siguranță',
            subtitle: 'Contacte și acțiuni pentru situații de risc',
            destination: AppDestination.safety,
          ),
          const SizedBox(height: 10),
          _ToolkitTile(
            icon: Icons.notifications_active_outlined,
            title: 'Alerte',
            subtitle: 'Reguli pentru ape și stații reale',
            destination: AppDestination.alerts,
          ),
        ],
      ),
    );
  }
}

class _ToolkitTile extends StatelessWidget {
  const _ToolkitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppDestination destination;

  @override
  Widget build(BuildContext context) => FigmaSurface(
    onTap: () => AppNavigator.open(context, destination),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: FigmaFluviTokens.cyan.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: FigmaFluviTokens.cyan, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: figmaBody(size: 10)),
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

class FigmaProfilePage extends ConsumerStatefulWidget {
  const FigmaProfilePage({super.key});

  @override
  ConsumerState<FigmaProfilePage> createState() => _FigmaProfilePageState();
}

class _FigmaProfilePageState extends ConsumerState<FigmaProfilePage> {
  final _auth = const AuthService();
  late final Future<ReputationMetrics> _reputation;

  @override
  void initState() {
    super.initState();
    _reputation = const ReputationService().getCurrentUserReputation();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final metadata = user?.userMetadata;
    final name = metadata?['full_name']?.toString().trim();
    final avatarUrl = metadata?['avatar_url']?.toString();
    final tier = ref.watch(fluviAccessTierProvider);
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-profile-page'),
      title: 'Profil',
      eyebrow: user == null ? 'NEAUTENTIFICAT' : 'CONT',
      action: FigmaRoundButton(
        icon: Icons.settings_outlined,
        tooltip: 'Setări',
        onPressed: () => AppNavigator.open(context, AppDestination.settings),
      ),
      child: user == null
          ? FigmaTruthfulEmpty(
              icon: Icons.person_outline_rounded,
              title: 'Autentificare necesară',
              message: 'Profilul personal apare după autentificare.',
              actionLabel: 'Deschide autentificarea',
              onAction: () =>
                  AppNavigator.open(context, AppDestination.accountSecurity),
            )
          : ListView(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: FigmaFluviTokens.surfaceRaised,
                      backgroundImage: avatarUrl == null || avatarUrl.isEmpty
                          ? null
                          : NetworkImage(avatarUrl),
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person_rounded,
                              color: FigmaFluviTokens.cyan,
                              size: 34,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name == null || name.isEmpty
                                      ? 'Pescar FluviAI'
                                      : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: FigmaFluviTokens.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FigmaPill(
                                label: tier == FluviAccessTier.premium
                                    ? 'PRO'
                                    : 'FREE',
                                color: tier == FluviAccessTier.premium
                                    ? FigmaFluviTokens.amber
                                    : FigmaFluviTokens.cyan,
                                active: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email ?? 'Email indisponibil',
                            style: figmaBody(size: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<ReputationMetrics>(
                  future: _reputation,
                  builder: (context, state) {
                    final metrics = state.data;
                    return FigmaSurface(
                      child: Row(
                        children: [
                          Expanded(
                            child: FigmaMetric(
                              value: metrics?.reputationScore.toString() ?? '—',
                              label: 'reputație',
                            ),
                          ),
                          Expanded(
                            child: FigmaMetric(
                              value: metrics?.trustLevel.label ?? '—',
                              label: 'încredere',
                              alignment: CrossAxisAlignment.center,
                            ),
                          ),
                          Expanded(
                            child: FigmaMetric(
                              value: metrics?.catchesCount.toString() ?? '—',
                              label: 'capturi',
                              alignment: CrossAxisAlignment.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                FigmaSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ProfileRow(
                        label: 'Capturile mele',
                        destination: AppDestination.myCatches,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Jurnalul meu',
                        destination: AppDestination.journal,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Rapoartele mele',
                        destination: AppDestination.myReports,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Permis de pescuit',
                        destination: AppDestination.permit,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Cont și securitate',
                        destination: AppDestination.accountSecurity,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Premium',
                        destination: AppDestination.premium,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Ajutor și feedback',
                        destination: AppDestination.support,
                      ),
                      const FigmaDivider(),
                      _ProfileRow(
                        label: 'Legal',
                        destination: AppDestination.legal,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.destination});

  final String label;
  final AppDestination destination;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => AppNavigator.open(context, destination),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: FigmaFluviTokens.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: FigmaFluviTokens.textSecondary,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class FigmaSettingsPage extends ConsumerStatefulWidget {
  const FigmaSettingsPage({super.key});

  @override
  ConsumerState<FigmaSettingsPage> createState() => _FigmaSettingsPageState();
}

class _FigmaSettingsPageState extends ConsumerState<FigmaSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final localeScope = LocaleScope.of(context);
    final themeController = ThemeScope.of(context);
    final contentRegion = ref.watch(contentRegionProvider);
    final countryLabel = _countryLabel(contentRegion?.countryCode);
    final languageCode = localeScope.languageCode;

    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-settings-page'),
      title: 'Setări aplicație & ajutor',
      subtitle: 'Preferințe · date · legal · suport',
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          const _SettingsReviewSectionLabel('PREFERINȚE'),
          const SizedBox(height: 8),
          _SettingsAppearanceCard(
            preference: themeController.preference,
            onChanged: (value) async {
              await themeController.setPreference(value);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 10),
          _SettingsReviewRow(
            title: 'Limbă',
            subtitle: languageCode == 'ro'
                ? 'Română · English'
                : 'English · Română',
            onTap: () async {
              await localeScope.setLanguageCode(
                languageCode == 'ro' ? 'en' : 'ro',
              );
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Regiune și unități',
            subtitle: '$countryLabel · unități după preferința aplicației',
            onTap: () => _showFigmaInfo(
              context,
              title: 'Regiune și unități',
              message:
                  'Regiunea de conținut este rezolvată separat de limba interfeței. Selectorul complet de unități se conectează la setarea persistentă existentă în etapa de utilități reale.',
            ),
          ),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: languageCode == 'ro'
                ? 'Resetează poziția Întreabă Fluvi'
                : 'Reset Ask Fluvi position',
            subtitle: languageCode == 'ro'
                ? 'Restabilește pozițiile implicite pe Acasă și Hartă'
                : 'Restore the default Home and Map positions',
            onTap: () async {
              await AskFluviPlacementStore.resetAll();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    languageCode == 'ro'
                        ? 'Poziția Întreabă Fluvi a fost resetată.'
                        : 'Ask Fluvi position was reset.',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          const _SettingsReviewSectionLabel('CONFIDENȚIALITATE & DATE'),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Confidențialitate și date',
            subtitle: 'Privacy notice · export · ștergere cont',
            onTap: () =>
                AppNavigator.open<void>(context, AppDestination.privacy),
          ),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Permisiuni și analytics',
            subtitle: 'Locație · cameră · notificări · opțiuni analytics',
            onTap: () => _showFigmaInfo(
              context,
              title: 'Permisiuni și analytics',
              message:
                  'Permisiunile sunt controlate de sistem și de fluxurile care le folosesc. Nu schimbăm permisiuni fără o acțiune explicită a utilizatorului.',
            ),
          ),
          const SizedBox(height: 18),
          const _SettingsReviewSectionLabel('LEGAL & SIGURANȚĂ'),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Termeni & condiții',
            subtitle: 'UE · România · UK',
            onTap: () => AppNavigator.open<void>(context, AppDestination.terms),
          ),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Comunitate & moderare',
            subtitle: 'Raportare · moderare · conținut ilegal',
            onTap: () =>
                AppNavigator.open<void>(context, AppDestination.moderation),
          ),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Fluvi & transparență AI',
            subtitle: 'Asistent AI · surse · limite · etichetare',
            badge: 'AI',
            onTap: () =>
                AppNavigator.open<void>(context, AppDestination.aiTransparency),
          ),
          const SizedBox(height: 8),
          _SettingsReviewRow(
            title: 'Abonament & facturare',
            subtitle: 'Trial · preț · reînnoire · anulare',
            badge: 'PRO',
            onTap: () =>
                AppNavigator.open<void>(context, AppDestination.premium),
          ),
          const SizedBox(height: 10),
          _SettingsReviewRow(
            title: 'Ajutor · contact · companie · licențe · versiune',
            compact: true,
            onTap: () =>
                AppNavigator.open<void>(context, AppDestination.support),
          ),
          const SizedBox(height: 86),
        ],
      ),
    );
  }
}

class _SettingsReviewSectionLabel extends StatelessWidget {
  const _SettingsReviewSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: FluviAIThemeColors.of(context).textSecondary,
      fontFamily: FluviAICommercialTokens.monoFontFamily,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _SettingsAppearanceCard extends StatelessWidget {
  const _SettingsAppearanceCard({
    required this.preference,
    required this.onChanged,
  });

  final AppThemePreference preference;
  final ValueChanged<AppThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final colors = FluviAIThemeColors.of(context);
    final selector = _ThemePreferenceSelector(
      preference: preference,
      onChanged: onChanged,
    );
    return Material(
      key: const ValueKey('settings-appearance-surface'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AppearanceCopy(),
                  const SizedBox(height: 10),
                  selector,
                ],
              )
            : Row(
                children: [
                  const Expanded(child: _AppearanceCopy()),
                  const SizedBox(width: 12),
                  selector,
                ],
              ),
      ),
    );
  }
}

class _AppearanceCopy extends StatelessWidget {
  const _AppearanceCopy();

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Aspect',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Automat urmează sistemul',
          style: TextStyle(color: colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}

class _ThemePreferenceSelector extends StatelessWidget {
  const _ThemePreferenceSelector({
    required this.preference,
    required this.onChanged,
  });

  final AppThemePreference preference;
  final ValueChanged<AppThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSoft),
      ),
      child: SegmentedButton<AppThemePreference>(
        key: const ValueKey('settings-theme-selector'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: AppThemePreference.automatic,
            label: Text('Auto'),
          ),
          ButtonSegment(value: AppThemePreference.light, label: Text('Zi')),
          ButtonSegment(value: AppThemePreference.dark, label: Text('Noapte')),
        ],
        selected: {preference},
        onSelectionChanged: (values) => onChanged(values.first),
      ),
    );
  }
}

class _SettingsReviewRow extends StatelessWidget {
  const _SettingsReviewRow({
    required this.title,
    this.subtitle,
    this.badge,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: compact ? colors.surfaceRaised : colors.surface,
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          border: Border.all(color: colors.borderSoft),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: compact ? 12 : 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: compact ? 10.5 : 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 9.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    badge!,
                    style: const TextStyle(
                      color: FigmaFluviTokens.cyan,
                      fontFamily: FluviAICommercialTokens.monoFontFamily,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FigmaPremiumPage extends ConsumerStatefulWidget {
  const FigmaPremiumPage({
    super.key,
    this.billingRepository = const UnavailableBillingRepository(),
  });

  final BillingRepository billingRepository;

  @override
  ConsumerState<FigmaPremiumPage> createState() => _FigmaPremiumPageState();
}

class _FigmaPremiumPageState extends ConsumerState<FigmaPremiumPage> {
  bool _restoring = false;
  String? _result;

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _result = null;
    });
    BillingRestoreResult result;
    try {
      result = await widget.billingRepository.restorePurchases();
    } on Exception {
      result = BillingRestoreResult.error;
    }
    if (!mounted) return;
    if (result == BillingRestoreResult.restored) {
      ref
          .read(fluviAccessTierProvider.notifier)
          .setTier(FluviAccessTier.premium);
    }
    setState(() {
      _restoring = false;
      _result = switch (result) {
        BillingRestoreResult.restored => 'Premium a fost restaurat.',
        BillingRestoreResult.nothingToRestore =>
          'Nu a fost găsită o achiziție eligibilă.',
        BillingRestoreResult.unavailable =>
          'Magazinul nu este conectat în această versiune.',
        BillingRestoreResult.error =>
          'Restaurarea a eșuat. Planul nu a fost modificat.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPremium =
        ref.watch(fluviAccessTierProvider) == FluviAccessTier.premium;
    const features = [
      'Râuri interioare, baraje și acumulări',
      'Istoric Water și grafice extinse',
      'Prognoze, alerte și planificare avansată',
      'FluviScore, Insight și Ask Fluvi avansate',
      'Hărți și date salvate pentru teren',
      'Statistici personale și jurnal extins',
      'Comparații între stații și ape',
      'Experiență fără reclame',
    ];
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-premium-page'),
      title: 'FluviAI Pro',
      eyebrow: isPremium ? 'PLAN ACTIV' : 'UPGRADE',
      background: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [
            Color(0xFF123D57),
            FigmaFluviTokens.background,
            Color(0xFF000000),
          ],
          stops: [0, .48, 1],
        ),
      ),
      child: ListView(
        children: [
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'FluviAI',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FigmaPill(
                      label: 'PRO',
                      color: FigmaFluviTokens.amber,
                      active: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Descoperă mai mult din fiecare partidă',
                  style: figmaBody(size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FigmaSurface(
            accent: FigmaFluviTokens.amber,
            child: Column(
              children: [
                for (final feature in features)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          color: FigmaFluviTokens.cyanSoft,
                          size: 17,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              color: FigmaFluviTokens.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FigmaSurface(
            accent: FigmaFluviTokens.green,
            child: Text(
              'Funcțiile esențiale și alertele de siguranță rămân disponibile Free.',
              textAlign: TextAlign.center,
              style: figmaBody(
                color: FigmaFluviTokens.cyanSoft,
                size: 10,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FigmaSurface(
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LUNAR',
                        style: TextStyle(
                          color: FigmaFluviTokens.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Preț în Store',
                        style: TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'monedă locală / lună',
                        style: TextStyle(
                          color: FigmaFluviTokens.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FigmaSurface(
                  accent: FigmaFluviTokens.cyan,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ANUAL · RECOMANDAT',
                        style: TextStyle(
                          color: FigmaFluviTokens.cyan,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Preț în Store',
                        style: TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'monedă locală / an',
                        style: TextStyle(
                          color: FigmaFluviTokens.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FigmaPrimaryButton(
            label: isPremium ? 'Plan Pro activ' : 'Continuă cu FluviAI Pro',
            icon: Icons.workspace_premium_rounded,
            onPressed: isPremium
                ? null
                : () => setState(
                    () => _result =
                        'Magazinul nu este conectat. Nu s-a inițiat nicio plată.',
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _restoring ? null : _restore,
            child: Text(_restoring ? 'Se verifică…' : 'Restaurează achiziția'),
          ),
          if (_result != null)
            Text(
              _result!,
              textAlign: TextAlign.center,
              style: figmaBody(size: 10),
            ),
          const SizedBox(height: 8),
          Text(
            'Prețul și perioada sunt afișate de App Store sau Google Play înainte de confirmare.',
            textAlign: TextAlign.center,
            style: figmaBody(size: 9),
          ),
        ],
      ),
    );
  }
}

Future<void> _openSupportTicketComposer(BuildContext context) async {
  final subject = TextEditingController();
  final message = TextEditingController();
  var category = 'support';
  String? errorMessage;
  var working = false;
  final created = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: FigmaFluviTokens.surface,
        title: const Text('Trimite solicitare'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                items: const [
                  DropdownMenuItem(value: 'support', child: Text('Ajutor')),
                  DropdownMenuItem(
                    value: 'bug',
                    child: Text('Problemă tehnică'),
                  ),
                  DropdownMenuItem(value: 'feedback', child: Text('Feedback')),
                  DropdownMenuItem(
                    value: 'billing',
                    child: Text('Plată / Premium'),
                  ),
                  DropdownMenuItem(
                    value: 'privacy',
                    child: Text('Confidențialitate'),
                  ),
                ],
                onChanged: working
                    ? null
                    : (value) =>
                          setDialogState(() => category = value ?? 'support'),
                decoration: const InputDecoration(labelText: 'Categorie'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subject,
                enabled: !working,
                decoration: const InputDecoration(labelText: 'Subiect'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: message,
                enabled: !working,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(labelText: 'Descriere'),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: const TextStyle(
                    color: FigmaFluviTokens.red,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: working
                ? null
                : () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: working
                ? null
                : () async {
                    setDialogState(() {
                      working = true;
                      errorMessage = null;
                    });
                    try {
                      await const SupportService().createTicket(
                        category: category,
                        subject: subject.text,
                        message: message.text,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    } on SupportException catch (error) {
                      setDialogState(() {
                        working = false;
                        errorMessage = error.message;
                      });
                    }
                  },
            child: Text(working ? 'Se trimite…' : 'Trimite'),
          ),
        ],
      ),
    ),
  );
  subject.dispose();
  message.dispose();
  if (created == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitarea a fost înregistrată.')),
    );
  }
}

Future<void> _showMySupportTickets(BuildContext context) async {
  try {
    final tickets = await const SupportService().getMyTickets();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FigmaFluviTokens.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: tickets.isEmpty
              ? const FigmaTruthfulEmpty(
                  icon: Icons.support_agent_rounded,
                  title: 'Nicio solicitare',
                  message:
                      'Solicitările trimise din aplicație vor apărea aici.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: tickets.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: FigmaFluviTokens.border),
                  itemBuilder: (_, index) {
                    final ticket = tickets[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        ticket.subject,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${ticket.category} · ${ticket.status} · ${ticket.createdAt.toString().substring(0, 16)}',
                        style: const TextStyle(
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      trailing: Text(
                        '#${ticket.id.substring(0, 8)}',
                        style: const TextStyle(
                          color: FigmaFluviTokens.cyan,
                          fontSize: 9,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  } on SupportException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class FigmaLegalSupportPage extends StatelessWidget {
  const FigmaLegalSupportPage({super.key, this.focus});

  final AppDestination? focus;

  @override
  Widget build(BuildContext context) {
    final pageTitle = switch (focus) {
      AppDestination.support => 'Ajutor și suport',
      AppDestination.privacy => 'Politica de confidențialitate',
      AppDestination.terms => 'Termeni și condiții',
      AppDestination.licences => 'Licențe open-source',
      AppDestination.about => 'Despre FluviAI',
      AppDestination.moderation => 'Comunitate și moderare',
      AppDestination.aiTransparency => 'Transparență AI',
      _ => 'Legal și suport',
    };
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-legal-support-page'),
      title: pageTitle,
      eyebrow: 'TRANSPARENȚĂ',
      child: ListView(
        children: [
          if (focus == AppDestination.moderation)
            const FigmaTruthfulEmpty(
              icon: Icons.policy_outlined,
              title: 'Conținut de moderare indisponibil',
              message:
                  'Politica de moderare nu este publicată în sursa curentă.',
            )
          else if (focus == AppDestination.aiTransparency)
            const FigmaTruthfulEmpty(
              icon: Icons.auto_awesome_outlined,
              title: 'Conținut de transparență AI indisponibil',
              message:
                  'Documentul de transparență AI nu este publicat în sursa curentă.',
            )
          else if (focus == AppDestination.about)
            const FigmaTruthfulEmpty(
              icon: Icons.info_outline_rounded,
              title: 'Conținut despre aplicație indisponibil',
              message:
                  'Pagina editorială Despre FluviAI nu este publicată în sursa curentă.',
            ),
          if (focus == null || focus == AppDestination.terms) ...[
            _LegalSection(
              title: 'Termeni și condiții',
              body: 'Conținut juridic în curs de revizuire',
              onTap: focus == AppDestination.terms
                  ? null
                  : () => AppNavigator.open(context, AppDestination.terms),
            ),
            const SizedBox(height: 12),
          ],
          if (focus == null || focus == AppDestination.privacy) ...[
            _LegalSection(
              title: 'Politica de confidențialitate',
              body: 'Conținut juridic în curs de revizuire',
              onTap: focus == AppDestination.privacy
                  ? null
                  : () => AppNavigator.open(context, AppDestination.privacy),
            ),
            const SizedBox(height: 12),
          ],
          if (focus == null || focus == AppDestination.licences) ...[
            const _LegalSection(
              title: 'Licențe open-source',
              body: 'Mapbox GL · fl_chart · Riverpod · Supabase',
            ),
            const SizedBox(height: 12),
          ],
          if (focus == null || focus == AppDestination.support) ...[
            FigmaSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FigmaSectionLabel('Contact suport'),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(
                        Icons.mail_outline_rounded,
                        color: FigmaFluviTokens.cyan,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Suport în aplicație',
                          style: TextStyle(
                            color: FigmaFluviTokens.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: FigmaFluviTokens.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Solicitările sunt salvate în cont și pot fi urmărite din această pagină.',
                          style: figmaBody(size: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FigmaSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SupportRow(
                    label: 'Trimite solicitare',
                    onTap: () => _openSupportTicketComposer(context),
                  ),
                  const FigmaDivider(),
                  _SupportRow(
                    label: 'Solicitările mele',
                    onTap: () => _showMySupportTickets(context),
                  ),
                  if (focus == null) ...[
                    const FigmaDivider(),
                    _SupportRow(
                      label: 'Despre FluviAI',
                      onTap: () =>
                          AppNavigator.open(context, AppDestination.about),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, required this.body, this.onTap});

  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FigmaSurface(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FigmaSectionLabel(title),
        const SizedBox(height: 10),
        Text(body, style: figmaBody(size: 12)),
        if (onTap != null) ...[
          const SizedBox(height: 8),
          const Text(
            'Stare document  ›',
            style: TextStyle(
              color: FigmaFluviTokens.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: FigmaFluviTokens.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              color: FigmaFluviTokens.cyan,
              size: 18,
            ),
        ],
      ),
    ),
  );
}

class FigmaAccountSecurityPage extends StatefulWidget {
  const FigmaAccountSecurityPage({super.key});

  @override
  State<FigmaAccountSecurityPage> createState() =>
      _FigmaAccountSecurityPageState();
}

class _FigmaAccountSecurityPageState extends State<FigmaAccountSecurityPage> {
  final _auth = const AuthService();
  bool _loggingOut = false;
  bool _privacyWorking = false;
  String? _message;

  Future<void> _sendRecovery() async {
    final email = _auth.currentUser?.email;
    if (email == null || email.isEmpty) return;
    setState(() {
      _message = null;
    });
    try {
      await _auth.sendPasswordReset(email);
      if (mounted) {
        setState(
          () => _message =
              'Instrucțiunile de recuperare au fost trimise la emailul contului.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _exportData() async {
    if (_privacyWorking) return;
    setState(() {
      _privacyWorking = true;
      _message = null;
    });
    try {
      final payload = await _auth.exportMyData();
      final formatted = const JsonEncoder.withIndent('  ').convert(payload);
      await Clipboard.setData(ClipboardData(text: formatted));
      if (mounted) {
        setState(
          () =>
              _message = 'Exportul JSON al datelor a fost copiat în clipboard.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _privacyWorking = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_privacyWorking || _auth.currentUser == null) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FigmaFluviTokens.surface,
        title: const Text('Ștergere definitivă'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contul, capturile, rapoartele, favoritele, jurnalul, regulile și notificările vor fi șterse definitiv. Scrie ȘTERGE pentru confirmare.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'ȘTERGE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim().toUpperCase();
              Navigator.of(
                dialogContext,
              ).pop(value == 'ȘTERGE' || value == 'STERGE');
            },
            child: const Text('Șterge definitiv'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() {
      _privacyWorking = true;
      _message = null;
    });
    try {
      await _auth.deleteAccount();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _privacyWorking = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _loggingOut = true;
      _message = null;
    });
    try {
      await _auth.logout();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-account-security'),
      title: 'Cont și securitate',
      eyebrow: user == null ? 'NEAUTENTIFICAT' : 'AUTENTIFICAT',
      child: ListView(
        children: [
          const FigmaSectionLabel('Autentificare'),
          const SizedBox(height: 8),
          FigmaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _AccountRow(
                  label: 'Email',
                  value: user?.email ?? 'Neautentificat',
                ),
                const FigmaDivider(),
                _AccountRow(
                  label: 'Parolă și recuperare',
                  value: 'Gestionează  ›',
                  onTap: user?.email == null ? null : _sendRecovery,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const FigmaSectionLabel('Securitate'),
          const SizedBox(height: 8),
          FigmaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _AccountRow(
                  label: 'Dispozitive conectate',
                  value: 'Vezi sesiunile  ›',
                  onTap: () => _showFigmaInfo(
                    context,
                    title: 'Dispozitive conectate',
                    message:
                        'Lista sesiunilor va apărea după conectarea endpointului securizat. Nu afișăm dispozitive inventate.',
                  ),
                ),
                const FigmaDivider(),
                _AccountRow(
                  label: 'Activitate recentă',
                  value: 'Verifică  ›',
                  onTap: () => _showFigmaInfo(
                    context,
                    title: 'Activitate recentă',
                    message:
                        'Istoricul de securitate nu este disponibil în sursa curentă.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const FigmaSectionLabel('Date și cont'),
          const SizedBox(height: 8),
          FigmaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _AccountRow(
                  label: 'Exportă datele mele',
                  value: _privacyWorking ? 'Se procesează…' : 'Export JSON  ›',
                  onTap: user == null || _privacyWorking ? null : _exportData,
                ),
                const FigmaDivider(),
                _AccountRow(
                  label: 'Șterge contul',
                  value: _privacyWorking
                      ? 'Se procesează…'
                      : 'Proces protejat  ›',
                  destructive: true,
                  onTap: user == null || _privacyWorking
                      ? null
                      : _deleteAccount,
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
            label: _loggingOut ? 'Se deconectează…' : 'Deconectare',
            secondary: true,
            onPressed: user == null || _loggingOut ? null : _logout,
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.label,
    required this.value,
    this.destructive = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: destructive
                    ? FigmaFluviTokens.red
                    : FigmaFluviTokens.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: destructive
                    ? FigmaFluviTokens.red
                    : FigmaFluviTokens.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
