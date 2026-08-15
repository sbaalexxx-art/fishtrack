import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/commercial_home/data/commercial_home_data_source.dart';
import '../../models/station.dart';
import '../../services/firebase_observability_service.dart';
import '../map/map_runtime_provenance.dart';
import '../../features/figma_complete/presentation/figma_destination_router.dart';
import 'app_destination.dart';
import 'map_entry.dart';

typedef MainTabSelector = void Function(int index);
typedef MainTabRouteSelector = void Function(int index, {Object? arguments});

abstract final class AppNavigator {
  static MainTabSelector? _mainTabSelector;
  static MainTabRouteSelector? _mainTabRouteSelector;
  static GlobalKey<NavigatorState>? _shellNavigatorKey;

  static ValueKey<String> destinationKey(AppDestination destination) =>
      ValueKey<String>('app-destination-${destination.name}');

  static void attachMainTabSelector(MainTabSelector selector) {
    _mainTabSelector = selector;
  }

  static void attachMainTabRouteSelector(MainTabRouteSelector selector) {
    _mainTabRouteSelector = selector;
  }

  static void detachMainTabSelector() {
    _mainTabSelector = null;
    _mainTabRouteSelector = null;
  }

  static void attachShellNavigator(GlobalKey<NavigatorState> navigatorKey) {
    _shellNavigatorKey = navigatorKey;
  }

  static void detachShellNavigator(GlobalKey<NavigatorState> navigatorKey) {
    if (identical(_shellNavigatorKey, navigatorKey)) {
      _shellNavigatorKey = null;
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _mainTabSelector = null;
    _mainTabRouteSelector = null;
    _shellNavigatorKey = null;
  }

  static Future<T?> open<T>(
    BuildContext context,
    AppDestination destination, {
    Object? arguments,
    MainTabSelector? selectMainTab,
    CommercialHomeDataSource? dataSource,
  }) {
    return _open<T>(
      context,
      destination,
      arguments: arguments,
      selectMainTab: selectMainTab,
      dataSource: dataSource,
      routeName: AppDestinationRegistry.of(destination).path,
    );
  }

  static Future<T?> openPath<T>(
    BuildContext context,
    String path, {
    Object? arguments,
    MainTabSelector? selectMainTab,
    CommercialHomeDataSource? dataSource,
  }) {
    final definition = AppDestinationRegistry.fromPath(path);
    if (definition == null) {
      throw ArgumentError.value(path, 'path', 'Unknown FluviAI route');
    }
    return _open<T>(
      context,
      definition.destination,
      arguments: arguments,
      selectMainTab: selectMainTab,
      dataSource: dataSource,
      routeName: path,
    );
  }

  static Future<T?> _open<T>(
    BuildContext context,
    AppDestination destination, {
    required String routeName,
    Object? arguments,
    MainTabSelector? selectMainTab,
    CommercialHomeDataSource? dataSource,
  }) {
    unawaited(
      FirebaseObservabilityService.instance.logEvent(
        'destination_opened',
        parameters: <String, Object>{
          'destination': destination.name,
          'route': routeName,
        },
      ),
    );
    // Contextual map routes are aliases into the one persistent Mapbox runtime
    // whenever the authenticated shell is available. The pushed wrapper stays
    // as a safe fallback for isolated/deep-link contexts outside that shell.
    if (destination == AppDestination.contextualMap &&
        (selectMainTab != null ||
            _mainTabRouteSelector != null ||
            _mainTabSelector != null)) {
      final entry = arguments is ContextualMapEntry ? arguments : null;
      final payload = entry?.station ?? entry?.cameraTarget;
      if (_mainTabRouteSelector != null) {
        _mainTabRouteSelector!(1, arguments: payload);
      } else if (selectMainTab != null) {
        selectMainTab(1);
      } else {
        _mainTabSelector!(1);
      }
      return Future<T?>.value();
    }
    final tab = switch (destination) {
      AppDestination.home => 0,
      AppDestination.map => 1,
      AppDestination.activity => 2,
      AppDestination.utilities => 3,
      _ => null,
    };
    if (tab != null) {
      if (selectMainTab != null ||
          _mainTabRouteSelector != null ||
          _mainTabSelector != null) {
        if (destination == AppDestination.map && arguments is Station) {
          logMapRuntime('navigator.map-payload', station: arguments);
        }
        if (selectMainTab != null) {
          if (_mainTabRouteSelector != null) {
            _mainTabRouteSelector!(tab, arguments: arguments);
          } else {
            selectMainTab(tab);
          }
        } else if (_mainTabRouteSelector != null) {
          _mainTabRouteSelector!(tab, arguments: arguments);
        } else {
          _mainTabSelector!(tab);
        }
        return Future<T?>.value();
      }
    }

    final navigator = _shellNavigatorKey?.currentState ?? Navigator.of(context);
    return navigator.push<T>(
      MaterialPageRoute<T>(
        settings: RouteSettings(name: routeName, arguments: arguments),
        builder: (routeContext) => KeyedSubtree(
          key: destinationKey(destination),
          child: FigmaDestinationRouter.page(
            destination,
            arguments: arguments,
            dataSource: dataSource,
          ),
        ),
      ),
    );
  }
}

bool destinationShowsShellNavigation(AppDestination destination) =>
    switch (destination) {
      AppDestination.home ||
      AppDestination.map ||
      AppDestination.activity ||
      AppDestination.utilities => true,
      _ => false,
    };
