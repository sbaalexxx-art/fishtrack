import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/context/selected_context.dart';
import '../services/saved_items_service.dart';
import '../core/map/map_runtime_provenance.dart';
import '../core/map/pending_map_camera.dart';
import '../core/theme/fluviai_commercial_tokens.dart';
import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../core/runtime/app_runtime.dart';
import '../services/community_service.dart';
import '../services/firebase_observability_service.dart';
import '../services/firebase_push_service.dart';
import '../services/water_asset_service.dart';
import '../models/station.dart';
import '../features/commercial_home/data/commercial_home_data_source.dart';
import '../widgets/navigation/fluviai_navigation.dart';
import '../features/commercial_home/presentation/commercial_home_page.dart';
import '../features/shell/presentation/activity_hub_page.dart';
import '../features/shell/presentation/utilities_hub_page.dart';
import 'map_page.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({
    super.key,
    this.homeDataSource,
    this.homeMapOverride,
    this.mapPageOverride,
    this.communityPageOverride,
    this.favoritesPageOverride,
  });

  final CommercialHomeDataSource? homeDataSource;
  final Widget? homeMapOverride;
  final Widget? mapPageOverride;
  final Widget? communityPageOverride;
  final Widget? favoritesPageOverride;

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  late final ValueNotifier<int> _selectedIndexListenable;
  late final NavigatorObserver _shellNavigatorObserver;
  StreamSubscription<RemoteMessage>? _pushOpenSubscription;

  late final ValueNotifier<bool> _fullMapActive;
  late final MapFocusController _mapFocusController;
  late final List<Widget> _pages;
  bool _fullMapInitialized = false;
  bool _shellNavigationVisible = true;
  bool _contentCanPop = false;
  bool _hydroMapRedirectRunning = false;
  String? _lastHydroMapRedirectPlantId;
  ProviderSubscription<SelectedContext?>? _hydroSelectionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNavigator.attachMainTabRouteSelector(_selectPage);
    AppNavigator.attachShellNavigator(_contentNavigatorKey);
    _hydroSelectionSubscription = ref.listenManual<SelectedContext?>(
      selectedContextProvider,
      (_, next) => _handleHydroMapCheSelection(next),
    );
    _shellNavigatorObserver = _ShellNavigatorObserver(
      onRouteChanged: _handleShellRouteChanged,
    );
    _selectedIndexListenable = ValueNotifier<int>(0);
    _fullMapActive = ValueNotifier<bool>(false);
    _mapFocusController = MapFocusController();
    _pushOpenSubscription = FirebasePushService.instance.openedMessages.listen(
      _handlePushOpened,
    );
    final pendingPush = FirebasePushService.instance.takePendingOpenedMessage();
    if (pendingPush != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handlePushOpened(pendingPush);
      });
    }
    _pages = [
      KeyedSubtree(
        key: AppNavigator.destinationKey(AppDestination.home),
        child: _HomeTierBridge(
          onNavigate: _selectPage,
          onCreateReport: () => _openReportFromMap(ReportCategory.fishActivity),
          dataSource: widget.homeDataSource,
          mapOverride: widget.homeMapOverride,
        ),
      ),
      const SizedBox.shrink(),
      KeyedSubtree(
        key: AppNavigator.destinationKey(AppDestination.activity),
        child: widget.communityPageOverride ?? const FluviAIActivityHubPage(),
      ),
      KeyedSubtree(
        key: AppNavigator.destinationKey(AppDestination.utilities),
        child:
            widget.favoritesPageOverride ??
            FluviAIUtilitiesHubPage(
              onSelectMainTab: _selectPage,
              dataSource: widget.homeDataSource,
            ),
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(appRuntimeProvider.notifier)
            .start(languageCode: _runtimeLanguageCode),
      );
    });
  }

  void _handleHydroMapCheSelection(SelectedContext? selected) {
    if (!mounted ||
        _selectedIndex != 1 ||
        _contentCanPop ||
        _hydroMapRedirectRunning ||
        ref.read(fluviAccessTierProvider) != FluviAccessTier.premium) {
      return;
    }

    final plantId = selected?.hydropowerPlantId?.trim();
    if (plantId == null || plantId.isEmpty) return;
    if (_lastHydroMapRedirectPlantId == plantId) return;

    _lastHydroMapRedirectPlantId = plantId;
    _hydroMapRedirectRunning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedIndex != 1 || _contentCanPop) {
        _hydroMapRedirectRunning = false;
        _lastHydroMapRedirectPlantId = null;
        return;
      }

      final label = selected?.locationName ?? selected?.primaryLabel;
      unawaited(
        AppNavigator.open<void>(
          context,
          AppDestination.hydropower,
          arguments: label,
          selectMainTab: _selectPage,
        ).whenComplete(() {
          if (!mounted) return;
          _hydroMapRedirectRunning = false;
          _lastHydroMapRedirectPlantId = null;
        }),
      );
    });
  }

  void _handlePushOpened(RemoteMessage message) {
    if (!mounted) return;
    unawaited(_routePushOpened(message));
  }

  Future<void> _routePushOpened(RemoteMessage message) async {
    final eventType =
        (message.data['type'] ?? message.data['event_type'] ?? 'unknown')
            .toString();
    final entityType = message.data['entity_type']?.toString().trim() ?? '';
    final entityId = message.data['entity_id']?.toString().trim() ?? '';

    await FirebaseObservabilityService.instance.logEvent(
      'push_deep_link_opened',
      parameters: <String, Object>{
        'event_type': eventType,
        'entity_type': entityType.isEmpty ? 'none' : entityType,
      },
    );
    if (!mounted) return;

    if (entityType == 'hydropower_plant' && entityId.isNotEmpty) {
      try {
        final state = await const WaterAssetService().getHydropowerPlantState(
          entityId,
        );
        if (!mounted) return;
        if (state != null) {
          ref
              .read(selectedContextProvider.notifier)
              .select(
                SelectedContext(
                  countryCode: state.countryCode,
                  locationName: state.name,
                  latitude: state.latitude,
                  longitude: state.longitude,
                  waterId: state.waterBodyId,
                  damId: state.damId,
                  reservoirId: state.reservoirId,
                  hydropowerPlantId: state.plantId,
                  source: state.evidenceSource,
                  observedAt: state.evidenceObservedAt,
                ),
              );
          await AppNavigator.open<void>(
            context,
            AppDestination.hydropower,
            arguments: state.name,
            selectMainTab: _selectPage,
          );
          return;
        }
      } on Exception {
        // The notification inbox remains a truthful fallback when the target
        // entity cannot be resolved (offline, stale auth, or backend error).
      }
    }

    if (!mounted) return;
    await AppNavigator.open<void>(
      context,
      AppDestination.notifications,
      selectMainTab: _selectPage,
    );
  }

  String get _runtimeLanguageCode =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      ref
          .read(appRuntimeProvider.notifier)
          .refreshIfStale(languageCode: _runtimeLanguageCode),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigator.detachMainTabSelector();
    AppNavigator.detachShellNavigator(_contentNavigatorKey);
    _hydroSelectionSubscription?.close();
    _fullMapActive.dispose();
    _mapFocusController.dispose();
    unawaited(_pushOpenSubscription?.cancel());
    _selectedIndexListenable.dispose();
    super.dispose();
  }

  void _handleShellRouteChanged(Route<dynamic>? route) {
    final path = route?.settings.name;
    // Modal routes (bottom sheets/dialogs) are intentionally unnamed. Using
    // only the route name made the shell believe it could not pop them and
    // allowed Android Back to escape the app instead of dismissing the modal.
    final contentCanPop = route != null && !route.isFirst;
    final destination = path == null
        ? null
        : AppDestinationRegistry.fromPath(path);
    final visible = destination == null
        ? route?.isFirst == true
              ? true
              : _shellNavigationVisible
        : destinationShowsShellNavigation(destination.destination);
    if (!mounted ||
        (visible == _shellNavigationVisible &&
            contentCanPop == _contentCanPop)) {
      return;
    }
    setState(() {
      _shellNavigationVisible = visible;
      _contentCanPop = contentCanPop;
    });
  }

  void _selectPage(int index, {Object? arguments}) {
    _contentNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (index == 1 && arguments is Station) {
      final container = ProviderScope.containerOf(context);
      final selected = container.read(selectedContextProvider);
      if (selected?.stationId != arguments.id ||
          selected?.latitude != arguments.latitude ||
          selected?.longitude != arguments.longitude) {
        container
            .read(selectedContextProvider.notifier)
            .selectStation(arguments);
      }
      _mapFocusController.requestStation(arguments);
      logMapRuntime('shell.map-focus-requested', station: arguments);
    } else if (index == 1 && arguments is RuntimeMapCameraTarget) {
      _mapFocusController.requestTarget(arguments);
      logMapRuntime(
        'shell.map-camera-requested',
        fields: {'source': arguments.source, 'entityId': arguments.entityId},
      );
    }
    setState(() {
      if (index == 1 && !_fullMapInitialized) {
        _pages[1] = KeyedSubtree(
          key: AppNavigator.destinationKey(AppDestination.map),
          child:
              widget.mapPageOverride ??
              MapPage(
                isActiveListenable: _fullMapActive,
                focusController: _mapFocusController,
                includeBottomSafeArea: false,
                onAddCatch: _openAddCatchPage,
                onCreateReport: _openReportFromMap,
              ),
        );
        _fullMapInitialized = true;
      }
      _selectedIndex = index;
      _selectedIndexListenable.value = index;
    });
    _fullMapActive.value = index == 1;
    unawaited(
      FirebaseObservabilityService.instance.logEvent(
        'main_tab_selected',
        parameters: <String, Object>{'tab_index': index},
      ),
    );
  }

  Future<void> _openAddCatchPage() async {
    final added = await AppNavigator.open<bool>(
      context,
      AppDestination.addCatch,
      selectMainTab: _selectPage,
    );
    if (added == true && mounted) {
      await AppNavigator.open<void>(
        context,
        AppDestination.myCatches,
        selectMainTab: _selectPage,
      );
    }
  }

  void _openReportFromMap(ReportCategory initialCategory) {
    AppNavigator.open<void>(
      context,
      AppDestination.addReport,
      arguments: initialCategory,
      selectMainTab: _selectPage,
    );
  }

  Future<void> _openAddMenu() async {
    final destination = await showModalBottomSheet<FluviAIQuickAddSelection>(
      context: _contentNavigatorKey.currentContext ?? context,
      useSafeArea: true,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: FluviAIThemeColors.of(context).surface,
      barrierColor: Colors.black.withValues(alpha: .70),
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => MainAddActionSheet(
        onAddReport: () =>
            Navigator.of(sheetContext).pop(FluviAIQuickAddSelection.report),
        onAddCatch: () =>
            Navigator.of(sheetContext).pop(FluviAIQuickAddSelection.catchEntry),
        onSavePlace: () =>
            Navigator.of(sheetContext).pop(FluviAIQuickAddSelection.savePlace),
      ),
    );

    if (!mounted || destination == null) return;
    switch (destination) {
      case FluviAIQuickAddSelection.report:
        _openReportFromMap(ReportCategory.fishActivity);
      case FluviAIQuickAddSelection.catchEntry:
        await _openAddCatchPage();
      case FluviAIQuickAddSelection.savePlace:
        await _saveSelectedPlace();
    }
  }

  Future<void> _saveSelectedPlace() async {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final selected = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(selectedContextProvider);
    if (selected == null || !selected.hasCoordinates) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRomanian
                ? 'Selectează mai întâi un loc, o apă sau o stație.'
                : 'Select a place, water or station first.',
          ),
        ),
      );
      return;
    }
    final lat = selected.latitude!;
    final lng = selected.longitude!;
    final referenceId =
        selected.hydropowerPlantId ??
        selected.placeId ??
        selected.waterId ??
        selected.stationId ??
        'coord:${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final title =
        selected.primaryLabel ?? (isRomanian ? 'Loc salvat' : 'Saved place');
    final itemType = selected.hydropowerPlantId != null
        ? 'hydropower_plant'
        : selected.reservoirId != null
        ? 'reservoir'
        : selected.damId != null
        ? 'dam'
        : selected.waterId != null
        ? 'water_body'
        : 'place';
    try {
      await const SavedItemsService().save(
        type: itemType,
        referenceId: referenceId,
        title: title,
        subtitle: selected.riverName ?? selected.region,
        latitude: lat,
        longitude: lng,
        metadata: <String, Object?>{
          if (selected.countryCode != null)
            'country_code': selected.countryCode,
          if (selected.region != null) 'region': selected.region,
          if (selected.stationId != null) 'station_id': selected.stationId,
          if (selected.waterId != null) 'water_id': selected.waterId,
          if (selected.hydropowerPlantId != null)
            'hydropower_plant_id': selected.hydropowerPlantId,
          if (selected.source != null) 'source': selected.source,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRomanian
                ? 'Loc salvat în Apele mele.'
                : 'Place saved to My Waters.',
          ),
        ),
      );
    } on SavedItemsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appRuntimeProvider);
    final themeColors = FluviAIThemeColors.of(context);
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final keyboardIsOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isFullMapSelected = _selectedIndex == 1;
    final showBottomNavigation =
        routeIsCurrent && !keyboardIsOpen && _shellNavigationVisible;

    return PopScope<Object?>(
      canPop: !_contentCanPop && !isFullMapSelected,
      onPopInvokedWithResult: (didPop, result) {
        logMapRuntime(
          'shell.system-back',
          fields: {
            'didPop': didPop,
            'contentCanPop': _contentCanPop,
            'selectedIndex': _selectedIndex,
          },
        );
        if (didPop) return;
        if (_contentCanPop) {
          _contentNavigatorKey.currentState?.pop();
        } else if (isFullMapSelected) {
          _selectPage(0);
        }
      },
      child: Scaffold(
        backgroundColor: themeColors.background,
        body: Navigator(
          key: _contentNavigatorKey,
          observers: [_shellNavigatorObserver],
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/shell'),
            builder: (_) => ValueListenableBuilder<int>(
              valueListenable: _selectedIndexListenable,
              builder: (context, index, child) =>
                  IndexedStack(index: index, children: _pages),
            ),
          ),
        ),
        bottomNavigationBar: showBottomNavigation
            ? FluviAIBottomNavigationBar(
                selectedIndex: _selectedIndex,
                onSelect: _selectPage,
                onAdd: _openAddMenu,
              )
            : null,
      ),
    );
  }
}

class _ShellNavigatorObserver extends NavigatorObserver {
  _ShellNavigatorObserver({required this.onRouteChanged});

  final ValueChanged<Route<dynamic>?> onRouteChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onRouteChanged(newRoute);
  }
}

class _HomeTierBridge extends ConsumerWidget {
  const _HomeTierBridge({
    required this.onNavigate,
    required this.onCreateReport,
    this.dataSource,
    this.mapOverride,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onCreateReport;
  final CommercialHomeDataSource? dataSource;
  final Widget? mapOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CommercialHomePage(
    onNavigate: onNavigate,
    onCreateReport: onCreateReport,
    accessTier: ref.watch(fluviAccessTierProvider),
    dataSource: dataSource,
    mapOverride: mapOverride,
  );
}

class MainAddActionSheet extends StatelessWidget {
  const MainAddActionSheet({
    super.key,
    required this.onAddReport,
    required this.onAddCatch,
    required this.onSavePlace,
  });

  final VoidCallback onAddReport;
  final VoidCallback onAddCatch;
  final VoidCallback onSavePlace;

  @override
  Widget build(BuildContext context) => FluviAIQuickAddSheet(
    onAddReport: onAddReport,
    onAddCatch: onAddCatch,
    onSavePlace: onSavePlace,
  );
}
