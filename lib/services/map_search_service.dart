import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../core/network/api_client.dart';
import '../models/station.dart';

typedef MapboxAccessTokenProvider = Future<String> Function();

Future<String> _runtimeMapboxAccessToken() async {
  const dartDefinedToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  if (dartDefinedToken.isNotEmpty) return dartDefinedToken;

  try {
    return (await MapboxOptions.getAccessToken()).trim();
  } on Exception {
    return '';
  }
}

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
  const MapSearchService({
    this.apiClient = const ApiClient(),
    this.accessTokenProvider = _runtimeMapboxAccessToken,
  });

  final ApiClient apiClient;
  final MapboxAccessTokenProvider accessTokenProvider;

  List<MapSearchResult> searchStations(
    String query,
    Iterable<Station> stations,
  ) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return const [];

    return stations
        .where((station) {
          final name = normalize(station.name);
          final river = normalize(station.river);
          final id = normalize(station.id);
          return name.contains(normalized) ||
              river.contains(normalized) ||
              id.contains(normalized);
        })
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

  Future<List<MapSearchResult>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];

    final mapboxAccessToken = (await accessTokenProvider()).trim();
    if (mapboxAccessToken.isNotEmpty) {
      final mapboxResults = await _searchMapbox(
        normalized,
        accessToken: mapboxAccessToken,
      );
      if (mapboxResults.isNotEmpty) return mapboxResults;
    }

    return _searchPhoton(normalized);
  }

  Future<List<MapSearchResult>> _searchMapbox(
    String query, {
    required String accessToken,
  }) async {
    final v6Results = await _searchMapboxV6(query, accessToken: accessToken);
    if (v6Results.isNotEmpty) return v6Results;
    return _searchMapboxV5(query, accessToken: accessToken);
  }

  Future<List<MapSearchResult>> _searchMapboxV6(
    String query, {
    required String accessToken,
  }) async {
    final uri = Uri.https('api.mapbox.com', '/search/geocode/v6/forward', {
      'q': query,
      'limit': '8',
      'language': 'ro,en',
      'autocomplete': 'true',
      'access_token': accessToken,
    });

    try {
      final payload = await apiClient
          .get(uri.toString())
          .timeout(const Duration(seconds: 10));
      if (payload is! Map || payload['features'] is! List) return const [];

      return (payload['features'] as List)
          .whereType<Map>()
          .map(_mapboxFeatureResult)
          .whereType<MapSearchResult>()
          .toList(growable: false);
    } on Exception {
      return const [];
    }
  }

  Future<List<MapSearchResult>> _searchMapboxV5(
    String query, {
    required String accessToken,
  }) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.mapbox.com',
      pathSegments: ['geocoding', 'v5', 'mapbox.places', '$query.json'],
      queryParameters: {
        'access_token': accessToken,
        'limit': '8',
        'language': 'ro,en',
        'autocomplete': 'true',
      },
    );

    try {
      final payload = await apiClient
          .get(uri.toString())
          .timeout(const Duration(seconds: 10));
      if (payload is! Map || payload['features'] is! List) return const [];

      return (payload['features'] as List)
          .whereType<Map>()
          .map(_mapboxFeatureResult)
          .whereType<MapSearchResult>()
          .toList(growable: false);
    } on Exception {
      return const [];
    }
  }

  Future<List<MapSearchResult>> _searchPhoton(String query) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '8',
      'lang': 'en',
    });

    try {
      final payload = await apiClient
          .get(uri.toString())
          .timeout(const Duration(seconds: 10));
      if (payload is! Map || payload['features'] is! List) return const [];

      return (payload['features'] as List)
          .whereType<Map>()
          .map(_photonFeatureResult)
          .whereType<MapSearchResult>()
          .toList(growable: false);
    } on Exception {
      return const [];
    }
  }

  static MapSearchResult? _mapboxFeatureResult(Map feature) {
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map || geometry['coordinates'] is! List) return null;

    final coordinates = geometry['coordinates'] as List;
    if (coordinates.length < 2) return null;

    final longitude = _number(coordinates[0]);
    final latitude = _number(coordinates[1]);
    if (latitude == null || longitude == null) return null;

    final nameCandidates = <Object?>[
      if (properties is Map) properties['name'],
      if (properties is Map) properties['full_address'],
      if (properties is Map) properties['place_formatted'],
      feature['place_name'],
      feature['text'],
    ];
    final name = _firstText(nameCandidates);
    if (name == null) return null;

    final descriptionCandidates = <Object?>[
      if (properties is Map) properties['full_address'],
      if (properties is Map) properties['place_formatted'],
      feature['place_name'],
    ];
    final description = _firstText(
      descriptionCandidates.where((value) => value?.toString() != name),
    );

    return MapSearchResult(
      name: name,
      description: description,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static MapSearchResult? _photonFeatureResult(Map feature) {
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
    final name = _firstText([properties['name']]);
    if (latitude == null || longitude == null || name == null) return null;

    final place = _firstText([
      properties['city'],
      properties['county'],
      properties['state'],
      properties['country'],
    ]);

    return MapSearchResult(
      name: name,
      description: place,
      latitude: latitude,
      longitude: longitude,
    );
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

  static String? _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
