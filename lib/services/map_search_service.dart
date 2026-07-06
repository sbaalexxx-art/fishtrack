import '../core/network/api_client.dart';
import '../models/station.dart';

class MapSearchResult {
  const MapSearchResult({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.description,
  });

  final String name;
  final String? description;
  final double latitude;
  final double longitude;
}

class MapSearchService {
  const MapSearchService({this.apiClient = const ApiClient()});

  final ApiClient apiClient;

  List<MapSearchResult> searchStations(
    String query,
    Iterable<Station> stations,
  ) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return const [];
    return stations
        .where((station) => normalize(station.name).contains(normalized))
        .map(
          (station) => MapSearchResult(
            name: station.name,
            description: station.river.isEmpty ? null : station.river,
            latitude: station.latitude,
            longitude: station.longitude,
          ),
        )
        .toList(growable: false);
  }

  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[ăâáàäãå]'), 'a')
      .replaceAll(RegExp(r'[îíìï]'), 'i')
      .replaceAll(RegExp(r'[șş]'), 's')
      .replaceAll(RegExp(r'[țţ]'), 't')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[óòöõ]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll(RegExp(r'\s+'), ' ');

  Future<List<MapSearchResult>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];

    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': normalized,
      'limit': '8',
      'lang': 'en',
    });
    final payload = await apiClient
        .get(uri.toString())
        .timeout(const Duration(seconds: 12));
    if (payload is! Map || payload['features'] is! List) return const [];

    return (payload['features'] as List)
        .whereType<Map>()
        .map((feature) {
          final geometry = feature['geometry'];
          final properties = feature['properties'];
          if (geometry is! Map ||
              properties is! Map ||
              geometry['coordinates'] is! List) {
            return null;
          }
          final coordinates = geometry['coordinates'] as List;
          if (coordinates.length < 2) return null;
          final longitude = _number(coordinates[0]);
          final latitude = _number(coordinates[1]);
          final name = properties['name']?.toString().trim();
          if (latitude == null ||
              longitude == null ||
              name == null ||
              name.isEmpty) {
            return null;
          }
          final place =
              properties['city'] ?? properties['county'] ?? properties['state'];
          return MapSearchResult(
            name: name,
            description: place?.toString(),
            latitude: latitude,
            longitude: longitude,
          );
        })
        .whereType<MapSearchResult>()
        .toList(growable: false);
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
