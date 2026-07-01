import '../models/station.dart';
import '../repositories/water_repository.dart';

class MapService {
  MapService();

  final WaterRepository _repository = const WaterRepository();

  Future<List<Station>> getStations() async {
    return await _repository.getStations();
  }
}
