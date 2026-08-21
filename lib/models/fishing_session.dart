class FishingSession {
  const FishingSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.title,
    this.notes,
    this.latitude,
    this.longitude,
    this.placeName,
    this.stationId,
    this.waterId,
    this.waterName,
    this.countryCode,
    this.region,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? title;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final String? placeName;
  final String? stationId;
  final String? waterId;
  final String? waterName;
  final String? countryCode;
  final String? region;

  bool get isOpen => endedAt == null;
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  factory FishingSession.fromJson(Map<String, dynamic> json) => FishingSession(
    id: json['id']?.toString() ?? '',
    startedAt:
        DateTime.tryParse(json['started_at']?.toString() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? '')?.toLocal(),
    title: json['title']?.toString(),
    notes: json['notes']?.toString(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    placeName: json['place_name']?.toString(),
    stationId: json['station_id']?.toString(),
    waterId: json['water_id']?.toString(),
    waterName: json['water_name']?.toString(),
    countryCode: json['country_code']?.toString(),
    region: json['region']?.toString(),
  );
}
