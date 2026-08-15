import '../../models/station.dart';

enum WaterHubEntryMode { overview, selectStation }

class WaterHubRequest {
  const WaterHubRequest({
    this.initialStation,
    this.entryMode = WaterHubEntryMode.overview,
  });

  final Station? initialStation;
  final WaterHubEntryMode entryMode;
}
