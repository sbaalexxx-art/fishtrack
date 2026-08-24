import '../../models/station.dart';

enum WaterHubEntryMode { overview, selectStation }

/// Optional canonical Water Hub section requested by an upstream surface.
enum WaterHubSection { danube, dams, rivers }

class WaterHubRequest {
  const WaterHubRequest({
    this.initialStation,
    this.entryMode = WaterHubEntryMode.overview,
    this.initialSection,
  });

  final Station? initialStation;
  final WaterHubEntryMode entryMode;
  final WaterHubSection? initialSection;
}
