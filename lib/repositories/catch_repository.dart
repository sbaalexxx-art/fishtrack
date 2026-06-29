import '../models/catch.dart';

class CatchRepository {
  const CatchRepository();

  Future<List<Catch>> getCatchesForStation(String stationId) async {
    final catches = [
      Catch(
        id: '1',
        stationId: '1',
        species: 'Crap',
        weight: 6.4,
        length: 72,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Catch(
        id: '2',
        stationId: '1',
        species: 'Șalău',
        weight: 3.1,
        length: 61,
        date: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Catch(
        id: '3',
        stationId: '2',
        species: 'Somn',
        weight: 18.7,
        length: 145,
        date: DateTime.now().subtract(const Duration(days: 3)),
      ),
      Catch(
        id: '4',
        stationId: '2',
        species: 'Avat',
        weight: 2.6,
        length: 58,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Catch(
        id: '5',
        stationId: '3',
        species: 'Crap',
        weight: 8.2,
        length: 79,
        date: DateTime.now().subtract(const Duration(days: 4)),
      ),
      Catch(
        id: '6',
        stationId: '3',
        species: 'Știucă',
        weight: 5.8,
        length: 92,
        date: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];

    return catches
        .where((catchItem) => catchItem.stationId == stationId)
        .toList();
  }
}
