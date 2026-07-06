import 'package:geolocator/geolocator.dart';

import '../models/station.dart';
import 'community_service.dart';
import 'favorite_stations_service.dart';
import 'water_service.dart';

enum WaterAlertType {
  waterLevelRising('Water level rising'),
  waterLevelFalling('Water level falling'),
  rapidChange('Rapid change'),
  newCommunityReport('New community report'),
  dangerousReport('Dangerous report');

  const WaterAlertType(this.label);
  final String label;
}

class WaterAlert {
  const WaterAlert({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.type,
    required this.timestamp,
    this.isRead = false,
  });

  final String id;
  final String stationId;
  final String stationName;
  final WaterAlertType type;
  final DateTime timestamp;
  final bool isRead;

  WaterAlert copyWith({bool? isRead}) => WaterAlert(
    id: id,
    stationId: stationId,
    stationName: stationName,
    type: type,
    timestamp: timestamp,
    isRead: isRead ?? this.isRead,
  );
}

abstract interface class WaterAlertHistoryStore {
  List<WaterAlert> get alerts;
  WaterTrend? trendFor(String stationId);
  void rememberTrend(String stationId, WaterTrend trend);
  bool contains(String eventId);
  void add(WaterAlert alert);
  void markRead(String alertId);
}

class MemoryWaterAlertHistoryStore implements WaterAlertHistoryStore {
  MemoryWaterAlertHistoryStore({this.maximumAlerts = 50});

  final int maximumAlerts;
  final List<WaterAlert> _alerts = [];
  final Map<String, WaterTrend> _trends = {};
  final Set<String> _eventIds = {};

  @override
  List<WaterAlert> get alerts => List.unmodifiable(_alerts);

  @override
  WaterTrend? trendFor(String stationId) => _trends[stationId];

  @override
  void rememberTrend(String stationId, WaterTrend trend) {
    _trends[stationId] = trend;
  }

  @override
  bool contains(String eventId) => _eventIds.contains(eventId);

  @override
  void add(WaterAlert alert) {
    if (!_eventIds.add(alert.id)) return;
    _alerts.insert(0, alert);
    if (_alerts.length > maximumAlerts) {
      final removed = _alerts.removeLast();
      _eventIds.remove(removed.id);
    }
  }

  @override
  void markRead(String alertId) {
    final index = _alerts.indexWhere((alert) => alert.id == alertId);
    if (index >= 0) _alerts[index] = _alerts[index].copyWith(isRead: true);
  }
}

class WaterAlertService {
  WaterAlertService({
    FavoriteStationsService? favoriteStationsService,
    WaterService? waterService,
    CommunityService? communityService,
    WaterAlertHistoryStore? history,
  }) : _favoriteStationsService =
           favoriteStationsService ?? const FavoriteStationsService(),
       _waterService = waterService ?? WaterService(),
       _communityService = communityService ?? const CommunityService(),
       history = history ?? _sharedHistory;

  static final MemoryWaterAlertHistoryStore _sharedHistory =
      MemoryWaterAlertHistoryStore();
  static const reportRadiusMeters = 10000.0;

  final FavoriteStationsService _favoriteStationsService;
  final WaterService _waterService;
  final CommunityService _communityService;
  final WaterAlertHistoryStore history;

  bool get isAuthenticated => _favoriteStationsService.isAuthenticated;

  Future<List<WaterAlert>> refresh() async {
    final favoriteIds = await _favoriteStationsService.getFavoriteIds();
    if (favoriteIds.isEmpty) return history.alerts;
    final results = await Future.wait([
      _waterService.getStations(),
      _communityService.getFeed(),
    ]);
    final stations = (results[0] as List<Station>)
        .where((station) => favoriteIds.contains(station.id))
        .toList(growable: false);
    final posts = results[1] as List<CommunityPost>;
    for (final station in stations) {
      _evaluateTrend(station);
      await _evaluateRapidChange(station);
      _evaluateReports(station, posts);
    }
    return history.alerts;
  }

  void markRead(String alertId) => history.markRead(alertId);

  void _evaluateTrend(Station station) {
    if (!station.hasKnownTrend) return;
    final previous = history.trendFor(station.id);
    history.rememberTrend(station.id, station.trend);
    if (previous == null || previous == station.trend) return;
    final type = switch (station.trend) {
      WaterTrend.rising => WaterAlertType.waterLevelRising,
      WaterTrend.falling => WaterAlertType.waterLevelFalling,
      WaterTrend.stable => null,
    };
    if (type != null) {
      _add(
        station,
        type,
        station.lastUpdate,
        'trend:${station.trend.name}:${station.lastUpdate.toUtc()}',
      );
    }
  }

  Future<void> _evaluateRapidChange(Station station) async {
    if (!station.hasWaterLevel) return;
    try {
      final readings = await _waterService.getHistory(
        station.id,
        stationName: station.name,
        limit: 2,
      );
      if (readings.length < 2) return;
      final ordered = [...readings]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final latest = ordered[0];
      final previous = ordered[1];
      if (latest.unit != previous.unit ||
          latest.timestamp.difference(previous.timestamp).abs() >
              const Duration(hours: 24)) {
        return;
      }
      final delta = (latest.value - previous.value).abs();
      final threshold = (previous.value.abs() * .20).clamp(10, 50);
      if (delta < threshold) return;
      _add(
        station,
        WaterAlertType.rapidChange,
        latest.timestamp,
        'rapid:${latest.timestamp.toUtc()}:${latest.value}',
      );
    } on Exception {
      // A missing history source must not invent or infer water readings.
    }
  }

  void _evaluateReports(Station station, List<CommunityPost> posts) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    for (final report in posts.where(
      (post) =>
          post.type == CommunityPostType.report &&
          post.createdAt.isAfter(cutoff) &&
          post.latitude != null &&
          post.longitude != null,
    )) {
      final distance = Geolocator.distanceBetween(
        station.latitude,
        station.longitude,
        report.latitude!,
        report.longitude!,
      );
      if (distance > reportRadiusMeters) continue;
      _add(
        station,
        WaterAlertType.newCommunityReport,
        report.createdAt,
        'report:${report.id}',
      );
      if (_isDangerous(report.reportCategory)) {
        _add(
          station,
          WaterAlertType.dangerousReport,
          report.createdAt,
          'danger:${report.id}',
        );
      }
    }
  }

  static bool _isDangerous(ReportCategory? category) => switch (category) {
    ReportCategory.strongCurrent ||
    ReportCategory.poaching ||
    ReportCategory.theftWarning ||
    ReportCategory.accessBlocked => true,
    _ => false,
  };

  void _add(
    Station station,
    WaterAlertType type,
    DateTime timestamp,
    String sourceKey,
  ) {
    final id = '${station.id}:${type.name}:$sourceKey';
    if (history.contains(id)) return;
    history.add(
      WaterAlert(
        id: id,
        stationId: station.id,
        stationName: station.name,
        type: type,
        timestamp: timestamp,
      ),
    );
  }
}
