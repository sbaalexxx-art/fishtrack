class SavedItem {
  const SavedItem({
    required this.id,
    required this.type,
    required this.referenceId,
    required this.title,
    required this.createdAt,
    this.subtitle,
    this.latitude,
    this.longitude,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String type;
  final String referenceId;
  final String title;
  final String? subtitle;
  final double? latitude;
  final double? longitude;
  final Map<String, Object?> metadata;
  final DateTime createdAt;

  factory SavedItem.fromJson(Map<String, dynamic> json) => SavedItem(
    id: json['id']?.toString() ?? '',
    type: json['item_type']?.toString() ?? '',
    referenceId: json['reference_id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    subtitle: json['subtitle']?.toString(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    metadata: json['metadata'] is Map
        ? Map<String, Object?>.from(json['metadata'] as Map)
        : const <String, Object?>{},
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
