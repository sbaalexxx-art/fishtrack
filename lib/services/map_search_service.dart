import '../core/network/api_client.dart';

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
