import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/station.dart';
import '../../services/community_service.dart';

enum MapFeatureType {
  monitoringStation,
  river,
  branch,
  dam,
  reservoir,
  hydropower,
  fishingPlace,
  catchEntry,
  communityReport,
  pollution,
  danger,
  theft,
  obstacle,
  waterAccess,
  favorite,
  currentLocation,
  photo,
}

enum MapMarkerShape { circle, pin, diamond, warning, shield, square }

enum MapFeatureTapAction {
  openStationDetails,
  openWaterBodyDetails,
  openWaterAssetDetails,
  openFishingPlace,
  openCatchDetails,
  openReportDetails,
  toggleFavorite,
  centerCurrentLocation,
  openPhoto,
}

@immutable
class MapFeaturePresentation {
  const MapFeaturePresentation({
    required this.icon,
    required this.color,
    required this.markerShape,
    required this.label,
    required this.tapAction,
  });

  final IconData icon;
  final Color color;
  final MapMarkerShape markerShape;
  final String label;
  final MapFeatureTapAction tapAction;

  MapFeaturePresentation copyWith({
    IconData? icon,
    Color? color,
    MapMarkerShape? markerShape,
    String? label,
    MapFeatureTapAction? tapAction,
  }) => MapFeaturePresentation(
    icon: icon ?? this.icon,
    color: color ?? this.color,
    markerShape: markerShape ?? this.markerShape,
    label: label ?? this.label,
    tapAction: tapAction ?? this.tapAction,
  );
}

class MapFeatureRegistry {
  const MapFeatureRegistry._();

  static const Color stationRising = Color(0xFF2F8CFF);
  static const Color stationStable = Color(0xFF67D04B);
  static const Color stationFalling = Color(0xFFFF5A67);
  static const Color stationUnknown = Color(0xFF78909C);

  static const Color river = Color(0xFF4FC3F7);
  static const Color branch = Color(0xFF26C6DA);
  static const Color dam = Color(0xFFFF9B54);
  static const Color reservoir = Color(0xFF43D9CC);
  static const Color hydropower = Color(0xFFFFC857);
  static const Color fishingPlace = Color(0xFFFFB74D);
  static const Color catchEntry = Color(0xFF66BB6A);
  static const Color communityReport = Color(0xFFB78CFF);
  static const Color pollution = Color(0xFF8D6E63);
  static const Color danger = Color(0xFFFF7043);
  static const Color theft = Color(0xFFEF5350);
  static const Color obstacle = Color(0xFFFF8A65);
  static const Color waterAccess = Color(0xFF26C6DA);
  static const Color favorite = Color(0xFFFF75B5);
  static const Color currentLocation = Color(0xFF67D04B);
  static const Color photo = Color(0xFF90A4AE);

  static Color waterStateColor(String trend) => switch (trend) {
    'rising' => stationRising,
    'stable' => stationStable,
    'falling' => stationFalling,
    _ => stationUnknown,
  };

  static MapFeaturePresentation forFeature(
    MapFeatureType type,
    AppLocalizations l10n,
  ) {
    final isRomanian = l10n.localeName.startsWith('ro');

    return switch (type) {
      MapFeatureType.monitoringStation => MapFeaturePresentation(
        icon: Icons.water_drop_rounded,
        color: stationUnknown,
        markerShape: MapMarkerShape.pin,
        label: l10n.waterStations,
        tapAction: MapFeatureTapAction.openStationDetails,
      ),
      MapFeatureType.river => MapFeaturePresentation(
        icon: Icons.waves_rounded,
        color: river,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Râu' : 'River',
        tapAction: MapFeatureTapAction.openWaterBodyDetails,
      ),
      MapFeatureType.branch => MapFeaturePresentation(
        icon: Icons.alt_route_rounded,
        color: branch,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Braț' : 'Branch',
        tapAction: MapFeatureTapAction.openWaterBodyDetails,
      ),
      MapFeatureType.dam => MapFeaturePresentation(
        icon: Icons.account_balance_rounded,
        color: dam,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Baraj' : 'Dam',
        tapAction: MapFeatureTapAction.openWaterAssetDetails,
      ),
      MapFeatureType.reservoir => MapFeaturePresentation(
        icon: Icons.water_rounded,
        color: reservoir,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Lac de acumulare' : 'Reservoir',
        tapAction: MapFeatureTapAction.openWaterAssetDetails,
      ),
      MapFeatureType.hydropower => MapFeaturePresentation(
        icon: Icons.bolt_rounded,
        color: hydropower,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Hidrocentrală' : 'Hydropower',
        tapAction: MapFeatureTapAction.openWaterAssetDetails,
      ),
      MapFeatureType.fishingPlace => MapFeaturePresentation(
        icon: Icons.location_on_rounded,
        color: fishingPlace,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Loc de pescuit' : 'Fishing spot',
        tapAction: MapFeatureTapAction.openFishingPlace,
      ),
      MapFeatureType.catchEntry => MapFeaturePresentation(
        icon: Icons.set_meal_rounded,
        color: catchEntry,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Captură' : 'Catch',
        tapAction: MapFeatureTapAction.openCatchDetails,
      ),
      MapFeatureType.communityReport => MapFeaturePresentation(
        icon: Icons.campaign_rounded,
        color: communityReport,
        markerShape: MapMarkerShape.diamond,
        label: l10n.report,
        tapAction: MapFeatureTapAction.openReportDetails,
      ),
      MapFeatureType.pollution => MapFeaturePresentation(
        icon: Icons.factory_rounded,
        color: pollution,
        markerShape: MapMarkerShape.warning,
        label: isRomanian ? 'Poluare' : 'Pollution',
        tapAction: MapFeatureTapAction.openReportDetails,
      ),
      MapFeatureType.danger => MapFeaturePresentation(
        icon: Icons.warning_amber_rounded,
        color: danger,
        markerShape: MapMarkerShape.warning,
        label: isRomanian ? 'Pericol' : 'Danger',
        tapAction: MapFeatureTapAction.openReportDetails,
      ),
      MapFeatureType.theft => MapFeaturePresentation(
        icon: Icons.shield_rounded,
        color: theft,
        markerShape: MapMarkerShape.shield,
        label: isRomanian ? 'Alertă de furt' : 'Theft alert',
        tapAction: MapFeatureTapAction.openReportDetails,
      ),
      MapFeatureType.obstacle => MapFeaturePresentation(
        icon: Icons.block_rounded,
        color: obstacle,
        markerShape: MapMarkerShape.warning,
        label: isRomanian ? 'Obstacol' : 'Obstacle',
        tapAction: MapFeatureTapAction.openReportDetails,
      ),
      MapFeatureType.waterAccess => MapFeaturePresentation(
        icon: Icons.route_rounded,
        color: waterAccess,
        markerShape: MapMarkerShape.pin,
        label: isRomanian ? 'Acces la apă' : 'Water access',
        tapAction: MapFeatureTapAction.openFishingPlace,
      ),
      MapFeatureType.favorite => MapFeaturePresentation(
        icon: Icons.bookmark_rounded,
        color: favorite,
        markerShape: MapMarkerShape.square,
        label: l10n.favorites,
        tapAction: MapFeatureTapAction.toggleFavorite,
      ),
      MapFeatureType.currentLocation => MapFeaturePresentation(
        icon: Icons.my_location_rounded,
        color: currentLocation,
        markerShape: MapMarkerShape.circle,
        label: l10n.youAreHere,
        tapAction: MapFeatureTapAction.centerCurrentLocation,
      ),
      MapFeatureType.photo => MapFeaturePresentation(
        icon: Icons.photo_camera_rounded,
        color: photo,
        markerShape: MapMarkerShape.square,
        label: isRomanian ? 'Fotografie' : 'Photo',
        tapAction: MapFeatureTapAction.openPhoto,
      ),
    };
  }

  static MapFeaturePresentation forStation(
    Station station,
    AppLocalizations l10n,
  ) {
    return MapFeaturePresentation(
      icon: Icons.water_drop_rounded,
      color: stationTrendColor(station),
      markerShape: MapMarkerShape.pin,
      label: l10n.waterStations,
      tapAction: MapFeatureTapAction.openStationDetails,
    );
  }

  static Color stationTrendColor(Station station) {
    if (!station.hasKnownTrend) return stationUnknown;

    return switch (station.trend) {
      WaterTrend.rising => stationRising,
      WaterTrend.stable => stationStable,
      WaterTrend.falling => stationFalling,
    };
  }

  static MapFeaturePresentation forReportCategory(
    ReportCategory category,
    AppLocalizations l10n,
  ) {
    return MapFeaturePresentation(
      icon: _reportCategoryIcon(category),
      color: _reportCategoryColor(category),
      markerShape: _reportCategoryMarkerShape(category),
      label: _reportCategoryLabel(category, l10n),
      tapAction: MapFeatureTapAction.openReportDetails,
    );
  }

  static IconData _reportCategoryIcon(ReportCategory category) =>
      switch (category) {
        ReportCategory.fishActivity => Icons.set_meal_rounded,
        ReportCategory.waterClarity => Icons.visibility_rounded,
        ReportCategory.floatingGrass => Icons.grass_rounded,
        ReportCategory.highWater => Icons.water_rounded,
        ReportCategory.lowWater => Icons.water_drop_outlined,
        ReportCategory.strongCurrent => Icons.waves_rounded,
        ReportCategory.noCurrent => Icons.horizontal_rule_rounded,
        ReportCategory.boats => Icons.directions_boat_rounded,
        ReportCategory.poaching => Icons.policy_rounded,
        ReportCategory.theftWarning => Icons.shield_rounded,
        ReportCategory.accessBlocked => Icons.block_rounded,
        ReportCategory.parkingAvailable => Icons.local_parking_rounded,
        ReportCategory.goodFishing => Icons.phishing_rounded,
        ReportCategory.poorFishing => Icons.sentiment_dissatisfied_rounded,
        ReportCategory.other => Icons.more_horiz_rounded,
      };

  static Color _reportCategoryColor(ReportCategory category) =>
      switch (category) {
        ReportCategory.fishActivity => const Color(0xFF37D6A3),
        ReportCategory.waterClarity => const Color(0xFF4FC3F7),
        ReportCategory.floatingGrass => const Color(0xFF7CB342),
        ReportCategory.highWater => stationRising,
        ReportCategory.lowWater => const Color(0xFF64B5F6),
        ReportCategory.strongCurrent => const Color(0xFFFF8A3D),
        ReportCategory.noCurrent => const Color(0xFF90A4AE),
        ReportCategory.boats => const Color(0xFF26C6DA),
        ReportCategory.poaching => danger,
        ReportCategory.theftWarning => theft,
        ReportCategory.accessBlocked => obstacle,
        ReportCategory.parkingAvailable => const Color(0xFF66BB6A),
        ReportCategory.goodFishing => stationStable,
        ReportCategory.poorFishing => const Color(0xFFFFB74D),
        ReportCategory.other => stationUnknown,
      };

  static MapMarkerShape _reportCategoryMarkerShape(ReportCategory category) =>
      switch (category) {
        ReportCategory.poaching ||
        ReportCategory.accessBlocked => MapMarkerShape.warning,
        ReportCategory.theftWarning => MapMarkerShape.shield,
        ReportCategory.boats => MapMarkerShape.diamond,
        ReportCategory.parkingAvailable ||
        ReportCategory.goodFishing ||
        ReportCategory.poorFishing => MapMarkerShape.pin,
        ReportCategory.other => MapMarkerShape.square,
        _ => MapMarkerShape.circle,
      };

  static String _reportCategoryLabel(
    ReportCategory category,
    AppLocalizations l10n,
  ) => switch (category) {
    ReportCategory.fishActivity => l10n.reportCategoryFishActivity,
    ReportCategory.waterClarity => l10n.reportCategoryWaterClarity,
    ReportCategory.floatingGrass => l10n.reportCategoryFloatingGrass,
    ReportCategory.highWater => l10n.reportCategoryHighWater,
    ReportCategory.lowWater => l10n.reportCategoryLowWater,
    ReportCategory.strongCurrent => l10n.reportCategoryStrongCurrent,
    ReportCategory.noCurrent => l10n.reportCategoryNoCurrent,
    ReportCategory.boats => l10n.reportCategoryBoats,
    ReportCategory.poaching => l10n.reportCategoryPoaching,
    ReportCategory.theftWarning => l10n.reportCategoryTheftWarning,
    ReportCategory.accessBlocked => l10n.reportCategoryAccessBlocked,
    ReportCategory.parkingAvailable => l10n.reportCategoryParkingAvailable,
    ReportCategory.goodFishing => l10n.reportCategoryGoodFishing,
    ReportCategory.poorFishing => l10n.reportCategoryPoorFishing,
    ReportCategory.other => l10n.reportCategoryOther,
  };
}
