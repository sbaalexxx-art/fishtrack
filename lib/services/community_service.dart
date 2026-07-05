import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_service.dart';

enum CommunityPostType { catchPost, report }

enum ReportCategory {
  fishActivity('Fish activity'),
  waterClarity('Water clarity'),
  floatingGrass('Floating grass'),
  highWater('High water'),
  lowWater('Low water'),
  strongCurrent('Strong current'),
  noCurrent('No current'),
  boats('Boats'),
  poaching('Poaching'),
  theftWarning('Theft warning'),
  accessBlocked('Access blocked'),
  parkingAvailable('Parking available'),
  goodFishing('Good fishing'),
  poorFishing('Poor fishing'),
  other('Other');

  const ReportCategory(this.label);
  final String label;

  static ReportCategory parse(Object? value) => values.firstWhere(
    (category) => category.name == value || category.label == value,
    orElse: () => other,
  );
}

enum ReportVerification { stillValid, noLongerValid }

enum ReportAbuseReason {
  falseInformation('False information'),
  wrongLocation('Wrong location'),
  spam('Spam'),
  offensiveContent('Offensive content'),
  duplicate('Duplicate'),
  other('Other');

  const ReportAbuseReason(this.label);
  final String label;

  String get databaseValue => switch (this) {
    falseInformation => 'false_information',
    wrongLocation => 'wrong_location',
    spam => 'spam',
    offensiveContent => 'offensive_content',
    duplicate => 'duplicate',
    other => 'other',
  };
}

enum CommunityReportEventType { created, verified }

class CommunityReportEvent {
  const CommunityReportEvent(this.type, this.reportId);
  final CommunityReportEventType type;
  final String reportId;
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.authorName,
    this.authorAvatar,
    this.imageUrl,
    this.weight,
    this.length,
    this.likeCount = 0,
    this.isLiked = false,
    this.reportCategory,
    this.latitude,
    this.longitude,
    this.expiresAt,
    this.stillValidCount = 0,
    this.noLongerValidCount = 0,
  });

  final String id;
  final String userId;
  final CommunityPostType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final String authorName;
  final String? authorAvatar;
  final String? imageUrl;
  final double? weight;
  final double? length;
  final int likeCount;
  final bool isLiked;
  final ReportCategory? reportCategory;
  final double? latitude;
  final double? longitude;
  final DateTime? expiresAt;
  final int stillValidCount;
  final int noLongerValidCount;

  bool get isActiveReport =>
      type == CommunityPostType.report &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  CommunityPost copyWith({int? likeCount, bool? isLiked}) => CommunityPost(
    id: id,
    userId: userId,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    authorName: authorName,
    authorAvatar: authorAvatar,
    imageUrl: imageUrl,
    weight: weight,
    length: length,
    likeCount: likeCount ?? this.likeCount,
    isLiked: isLiked ?? this.isLiked,
    reportCategory: reportCategory,
    latitude: latitude,
    longitude: longitude,
    expiresAt: expiresAt,
    stillValidCount: stillValidCount,
    noLongerValidCount: noLongerValidCount,
  );
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.authorName,
    this.authorAvatar,
  });

  final String id;
  final String userId;
  final String body;
  final DateTime createdAt;
  final String authorName;
  final String? authorAvatar;
}

class CommunityProfile {
  const CommunityProfile({
    required this.id,
    required this.name,
    required this.reputation,
    required this.catchCount,
    this.avatarUrl,
    this.country,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? country;
  final int reputation;
  final int catchCount;
}

class CommunityException implements Exception {
  const CommunityException(this.message);

  final String message;
}

class CommunityService {
  const CommunityService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static final StreamController<CommunityReportEvent> _reportEvents =
      StreamController<CommunityReportEvent>.broadcast();

  Stream<CommunityReportEvent> get reportEvents => _reportEvents.stream;

  Stream<List<CommunityPost>> watchReports() => _supabase
      .from('reports')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map(
        (rows) => rows
            .map(
              (row) => CommunityPost(
                id: _text(row['id']) ?? '',
                userId: _text(row['user_id']) ?? '',
                type: CommunityPostType.report,
                title: _text(row['type']) ?? 'Fishing report',
                body: _text(row['description']) ?? '',
                imageUrl: _text(row['photo_url'] ?? row['image_url']),
                createdAt: _date(row['created_at'] ?? row['timestamp']),
                authorName: 'Angler',
                reportCategory: ReportCategory.parse(
                  row['category'] ?? row['type'],
                ),
                latitude: _number(row['latitude']),
                longitude: _number(row['longitude']),
                expiresAt: _nullableDate(row['expires_at']),
                stillValidCount: _integer(row['still_valid_count']),
                noLongerValidCount: _integer(row['no_longer_valid_count']),
              ),
            )
            .where((report) => report.id.isNotEmpty)
            .toList(growable: false),
      );

  Future<List<CommunityPost>> getFeed() => _guard(() async {
    final responses = await Future.wait([
      _supabase
          .from('catches')
          .select()
          .order('timestamp', ascending: false)
          .limit(50),
      _supabase
          .from('reports')
          .select()
          .order('created_at', ascending: false)
          .limit(50),
    ]);
    final catches = _maps(responses[0]);
    final reports = _maps(responses[1]);
    developer.log(
      'Fetched report count: ${reports.length}',
      name: 'AIFishMap.Community',
    );
    final userIds = <String>{
      ...catches.map((row) => _text(row['user_id'])).whereType<String>(),
      ...reports.map((row) => _text(row['user_id'])).whereType<String>(),
    };
    final profiles = await _profiles(userIds);
    final catchIds = catches
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toList();
    final likes = await _likes(catchIds);
    final currentUserId = _supabase.auth.currentUser?.id;

    final posts = <CommunityPost>[
      for (final row in catches)
        if (_text(row['id']) case final String id)
          CommunityPost(
            id: id,
            userId: _text(row['user_id']) ?? '',
            type: CommunityPostType.catchPost,
            title: _text(row['species']) ?? 'Catch',
            body: _text(row['notes']) ?? '',
            imageUrl: _text(row['image']),
            weight: _number(row['weight']),
            length: _number(row['length']),
            createdAt: _date(row['timestamp']),
            authorName: _profileName(profiles, _text(row['user_id'])),
            authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
            likeCount: likes.where((like) => like.catchId == id).length,
            isLiked: likes.any(
              (like) => like.catchId == id && like.userId == currentUserId,
            ),
          ),
      for (final row in reports)
        if (_text(row['id']) case final String id)
          CommunityPost(
            id: id,
            userId: _text(row['user_id']) ?? '',
            type: CommunityPostType.report,
            title: _text(row['type']) ?? 'Fishing report',
            body: _text(row['description']) ?? '',
            imageUrl: _text(row['photo_url'] ?? row['image_url']),
            createdAt: _date(row['created_at'] ?? row['timestamp']),
            reportCategory: ReportCategory.parse(
              row['category'] ?? row['type'],
            ),
            latitude: _number(row['latitude']),
            longitude: _number(row['longitude']),
            expiresAt: _nullableDate(row['expires_at']),
            stillValidCount: _integer(row['still_valid_count']),
            noLongerValidCount: _integer(row['no_longer_valid_count']),
            authorName: _profileName(profiles, _text(row['user_id'])),
            authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
          ),
    ];
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  });

  Future<List<CommunityPost>> getReportsArchive(Duration period) => _guard(
    () async {
      final since = DateTime.now().toUtc().subtract(period);
      final reports = _maps(
        await _supabase
            .from('reports')
            .select()
            .gte('created_at', since.toIso8601String())
            .order('created_at', ascending: false),
      );
      final profiles = await _profiles(
        reports.map((row) => _text(row['user_id'])).whereType<String>().toSet(),
      );
      final archive = <CommunityPost>[
        for (final row in reports)
          if (_text(row['id']) case final String id)
            CommunityPost(
              id: id,
              userId: _text(row['user_id']) ?? '',
              type: CommunityPostType.report,
              title: _text(row['type']) ?? 'Fishing report',
              body: _text(row['description']) ?? '',
              imageUrl: _text(row['photo_url'] ?? row['image_url']),
              createdAt: _date(row['created_at'] ?? row['timestamp']),
              reportCategory: ReportCategory.parse(
                row['category'] ?? row['type'],
              ),
              latitude: _number(row['latitude']),
              longitude: _number(row['longitude']),
              expiresAt: _nullableDate(row['expires_at']),
              stillValidCount: _integer(row['still_valid_count']),
              noLongerValidCount: _integer(row['no_longer_valid_count']),
              authorName: _profileName(profiles, _text(row['user_id'])),
              authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
            ),
      ];
      developer.log(
        'Fetched archive report count: ${archive.length}; '
        'period: ${period.inHours}h',
        name: 'AIFishMap.Community',
      );
      return archive;
    },
    debugLabel: 'fetch reports archive',
  );

  Future<String> createReport({
    required ReportCategory category,
    String? text,
    File? cameraPhoto,
    required bool useExactLocation,
  }) => _guard(() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const CommunityException('Your session has expired.');
    }
    final position = await const LocationService().determinePosition();
    final latitude = useExactLocation
        ? position.latitude
        : (position.latitude * 100).round() / 100;
    final longitude = useExactLocation
        ? position.longitude
        : (position.longitude * 100).round() / 100;
    final now = DateTime.now().toUtc();
    String? imageUrl;
    if (cameraPhoto != null) {
      final path = '${user.id}/${now.microsecondsSinceEpoch}.jpg';
      await _supabase.storage.from('report-photos').upload(path, cameraPhoto);
      imageUrl = _supabase.storage.from('report-photos').getPublicUrl(path);
    }
    final inserted = Map<String, dynamic>.from(
      await _supabase
          .from('reports')
          .insert({
            'user_id': user.id,
            'type': category.label,
            'category': category.name,
            'description': text?.trim(),
            'image_url': imageUrl,
            'latitude': latitude,
            'longitude': longitude,
            'created_at': now.toIso8601String(),
            'expires_at': now.add(const Duration(hours: 12)).toIso8601String(),
          })
          .select('id')
          .single(),
    );
    final id = _text(inserted['id']);
    if (id == null) {
      throw const CommunityException(
        'The report was saved without a valid identifier.',
      );
    }
    developer.log(
      'Community report insert success',
      name: 'AIFishMap.Community',
    );
    developer.log('Inserted report id: $id', name: 'AIFishMap.Community');
    _reportEvents.add(
      CommunityReportEvent(CommunityReportEventType.created, id),
    );
    return id;
  }, debugLabel: 'publish community report');

  Future<List<CommunityPost>> getActiveReports() async => (await getFeed())
      .where(
        (post) =>
            post.isActiveReport &&
            post.latitude != null &&
            post.longitude != null,
      )
      .toList(growable: false);

  Future<void> verifyReport(String reportId, ReportVerification verification) =>
      _guard(() async {
        final user = _supabase.auth.currentUser;
        if (user == null) {
          throw const CommunityException('Your session has expired.');
        }
        await _supabase.from('report_verifications').upsert({
          'report_id': reportId,
          'user_id': user.id,
          'is_valid': verification == ReportVerification.stillValid,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'report_id,user_id');
        _reportEvents.add(
          CommunityReportEvent(CommunityReportEventType.verified, reportId),
        );
        developer.log(
          verification == ReportVerification.stillValid
              ? 'Confirm reaction: $reportId'
              : 'Not accurate reaction: $reportId',
          name: 'AIFishMap.Community',
        );
      }, debugLabel: 'react to community report');

  Future<void> reportAbuse(String reportId, ReportAbuseReason reason) =>
      _guard(() async {
        final user = _supabase.auth.currentUser;
        if (user == null) {
          throw const CommunityException('Your session has expired.');
        }
        await _supabase.from('report_abuse').upsert({
          'report_id': reportId,
          'user_id': user.id,
          'reason': reason.databaseValue,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'report_id,user_id');
        developer.log(
          'Report abuse: $reportId (${reason.databaseValue})',
          name: 'AIFishMap.Community',
        );
      }, debugLabel: 'report community abuse');

  Future<bool> toggleLike(CommunityPost post) => _guard(() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const CommunityException('Your session has expired.');
    }
    if (post.isLiked) {
      await _supabase
          .from('catch_likes')
          .delete()
          .eq('catch_id', post.id)
          .eq('user_id', user.id);
      return false;
    }
    await _supabase.from('catch_likes').insert({
      'catch_id': post.id,
      'user_id': user.id,
    });
    return true;
  });

  Future<List<CommunityComment>> getComments(String catchId) =>
      _guard(() async {
        final rows = _maps(
          await _supabase
              .from('catch_comments')
              .select()
              .eq('catch_id', catchId)
              .order('created_at'),
        );
        final profiles = await _profiles(
          rows.map((row) => _text(row['user_id'])).whereType<String>().toSet(),
        );
        return [
          for (final row in rows)
            if (_text(row['id']) case final String id)
              CommunityComment(
                id: id,
                userId: _text(row['user_id']) ?? '',
                body: _text(row['body']) ?? '',
                createdAt: _date(row['created_at']),
                authorName: _profileName(profiles, _text(row['user_id'])),
                authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
              ),
        ];
      });

  Future<void> addComment({required String catchId, required String body}) =>
      _guard(() async {
        final user = _supabase.auth.currentUser;
        if (user == null) {
          throw const CommunityException('Your session has expired.');
        }
        await _supabase.from('catch_comments').insert({
          'catch_id': catchId,
          'user_id': user.id,
          'body': body.trim(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      });

  Future<CommunityProfile> getProfile(String userId) => _guard(() async {
    final row = Map<String, dynamic>.from(
      await _supabase.from('profiles').select().eq('id', userId).single(),
    );
    final catches = _maps(
      await _supabase.from('catches').select('id').eq('user_id', userId),
    );
    return CommunityProfile(
      id: userId,
      name: _text(row['username'] ?? row['full_name']) ?? 'Angler',
      avatarUrl: _text(row['avatar'] ?? row['avatar_url']),
      country: _text(row['country']),
      reputation: _integer(row['reputation']),
      catchCount: catches.length,
    );
  });

  Future<Map<String, Map<String, dynamic>>> _profiles(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = _maps(
      await _supabase.from('profiles').select().inFilter('id', ids.toList()),
    );
    return {
      for (final row in rows)
        if (_text(row['id']) case final String id) id: row,
    };
  }

  Future<List<_Like>> _likes(List<String> catchIds) async {
    if (catchIds.isEmpty) return const [];
    final rows = _maps(
      await _supabase
          .from('catch_likes')
          .select()
          .inFilter('catch_id', catchIds),
    );
    return [
      for (final row in rows)
        if (_text(row['catch_id']) case final String catchId)
          _Like(catchId, _text(row['user_id']) ?? ''),
    ];
  }

  String _profileName(Map<String, Map<String, dynamic>> profiles, String? id) {
    final profile = profiles[id];
    return _text(profile?['username'] ?? profile?['full_name']) ?? 'Angler';
  }

  String? _profileAvatar(
    Map<String, Map<String, dynamic>> profiles,
    String? id,
  ) {
    final profile = profiles[id];
    return _text(profile?['avatar'] ?? profile?['avatar_url']);
  }

  Future<T> _guard<T>(
    Future<T> Function() operation, {
    String? debugLabel,
  }) async {
    try {
      return await operation().timeout(const Duration(seconds: 30));
    } on CommunityException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      rethrow;
    } on SocketException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw const CommunityException('No internet connection.');
    } on TimeoutException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw const CommunityException('The request timed out. Please retry.');
    } on StorageException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw const CommunityException(
        'The report photo could not be uploaded. Please try again.',
      );
    } on PostgrestException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw const CommunityException(
        'The report could not be published. Please try again.',
      );
    } on Exception catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw const CommunityException('Community data is unavailable.');
    }
  }

  static void _logFailure(String? label, Object error, StackTrace stackTrace) {
    if (label == null) return;
    developer.log(
      '$label failed',
      name: 'AIFishMap.Community',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : const [];
  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();
  static DateTime? _nullableDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal();
}

class _Like {
  const _Like(this.catchId, this.userId);
  final String catchId;
  final String userId;
}
