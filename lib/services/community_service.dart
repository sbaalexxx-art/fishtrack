import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cache/timed_cache.dart';
import 'location_service.dart';
import 'report_image_optimizer.dart';
import 'report_spam_service.dart';
import 'reputation_service.dart';
import 'diagnostics_service.dart';

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
  spam('Spam'),
  fakeInformation('Fake information'),
  offensiveContent('Offensive content'),
  dangerousIllegalActivity('Dangerous/illegal activity'),
  other('Other');

  const ReportAbuseReason(this.label);
  final String label;

  String get databaseValue => switch (this) {
    spam => 'spam',
    fakeInformation => 'fake_information',
    offensiveContent => 'offensive_content',
    dangerousIllegalActivity => 'dangerous_illegal_activity',
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
    this.speciesScientific,
    this.speciesSource,
    this.speciesConfidence,
    this.speciesModelVersion,
    this.speciesUserConfirmed = true,
    this.likeCount = 0,
    this.isLiked = false,
    this.reportCategory,
    this.latitude,
    this.longitude,
    this.expiresAt,
    this.stillValidCount = 0,
    this.noLongerValidCount = 0,
    this.spamScore = 0,
    this.isSuspicious = false,
    this.spamReason,
    this.authorTrustLevel = TrustLevel.newUser,
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
  final String? speciesScientific;
  final String? speciesSource;
  final double? speciesConfidence;
  final String? speciesModelVersion;
  final bool speciesUserConfirmed;
  final int likeCount;
  final bool isLiked;
  final ReportCategory? reportCategory;
  final double? latitude;
  final double? longitude;
  final DateTime? expiresAt;
  final int stillValidCount;
  final int noLongerValidCount;
  final int spamScore;
  final bool isSuspicious;
  final String? spamReason;
  final TrustLevel authorTrustLevel;

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
    speciesScientific: speciesScientific,
    speciesSource: speciesSource,
    speciesConfidence: speciesConfidence,
    speciesModelVersion: speciesModelVersion,
    speciesUserConfirmed: speciesUserConfirmed,
    likeCount: likeCount ?? this.likeCount,
    isLiked: isLiked ?? this.isLiked,
    reportCategory: reportCategory,
    latitude: latitude,
    longitude: longitude,
    expiresAt: expiresAt,
    stillValidCount: stillValidCount,
    noLongerValidCount: noLongerValidCount,
    spamScore: spamScore,
    isSuspicious: isSuspicious,
    spamReason: spamReason,
    authorTrustLevel: authorTrustLevel,
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
    required this.trustLevel,
    this.avatarUrl,
    this.country,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? country;
  final int reputation;
  final int catchCount;
  final TrustLevel trustLevel;
}

enum CommunityErrorCode {
  sessionExpired,
  noInternet,
  requestTimedOut,
  reportPhotoPreparationFailed,
  reportPhotoUploadFailed,
  reportPublishFailed,
  reportVerificationFailed,
  reportAbuseFailed,
  reportAlreadySubmitted,
  communityUnavailable,
}

class CommunityException implements Exception {
  const CommunityException(this.message, {this.code});

  final String message;
  final CommunityErrorCode? code;
}

class CommunityService {
  const CommunityService({SupabaseClient? client}) : _client = client;

  static const _reportPhotosBucket = 'report-photos';
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static final StreamController<CommunityReportEvent> _reportEvents =
      StreamController<CommunityReportEvent>.broadcast();
  static const cacheDuration = Duration(minutes: 3);
  static final TimedCache<List<CommunityPost>> _feedCache =
      TimedCache<List<CommunityPost>>(duration: cacheDuration);

  Stream<CommunityReportEvent> get reportEvents => _reportEvents.stream;

  Stream<List<CommunityPost>> watchReports() => _supabase
      .from('reports')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) {
        _feedCache.clear();
        return rows
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
                spamScore: _integer(row['spam_score']),
                isSuspicious: row['is_suspicious'] == true,
                spamReason: _text(row['spam_reason']),
              ),
            )
            .where((report) => report.id.isNotEmpty)
            .toList(growable: false);
      });

  Future<List<CommunityPost>> getFeed({bool forceRefresh = false}) async =>
      (await getFeedResult(forceRefresh: forceRefresh)).value;

  Future<CacheResult<List<CommunityPost>>> getFeedResult({
    bool forceRefresh = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = await _feedCache.get(
      () => _fetchFeed(),
      forceRefresh: forceRefresh,
    );
    if (result.value.isEmpty) {
      _feedCache.clear();
      if (result.isStaleFallback) {
        throw const CommunityException(
          'Community data is unavailable.',
          code: CommunityErrorCode.communityUnavailable,
        );
      }
    }
    stopwatch.stop();
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.community,
      operation: 'feed_load',
      message: result.isStaleFallback ? 'stale_fallback' : 'available',
      duration: stopwatch.elapsed,
      metadata: <String, Object?>{
        'items': result.value.length,
        'force_refresh': forceRefresh,
      },
    );
    return result;
  }

  Future<List<CommunityPost>> _fetchFeed() => _guard(() async {
    final reports = _maps(
      await _supabase
          .from('reports')
          .select()
          .order('created_at', ascending: false)
          .limit(50),
    );
    final catches = await _fetchOptionalCatches();
    developer.log(
      'Fetched report count: ${reports.length}',
      name: 'AIFishMap.Community',
    );
    final userIds = <String>{
      ...catches.map((row) => _text(row['user_id'])).whereType<String>(),
      ...reports.map((row) => _text(row['user_id'])).whereType<String>(),
    };
    Map<String, Map<String, dynamic>> profiles = const {};
    try {
      profiles = await _profiles(userIds);
    } on Exception catch (error, stackTrace) {
      _logOptionalFeedFailure('profiles', error, stackTrace);
    }
    Map<String, ReputationMetrics> reputations = const {};
    try {
      reputations = await ReputationService(
        client: _supabase,
      ).getReputations(userIds);
    } on Exception catch (error, stackTrace) {
      _logOptionalFeedFailure('reputations', error, stackTrace);
    }
    final catchIds = catches
        .map((row) => _text(row['id']))
        .whereType<String>()
        .toList();
    List<_Like> likes = const [];
    try {
      likes = await _likes(catchIds);
    } on Exception catch (error, stackTrace) {
      _logOptionalFeedFailure('likes', error, stackTrace);
    }
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
            speciesScientific: _text(row['species_scientific']),
            speciesSource: _text(row['species_source']),
            speciesConfidence: _number(row['species_confidence']),
            speciesModelVersion: _text(row['species_model_version']),
            speciesUserConfirmed: row['species_user_confirmed'] != false,
            latitude: _number(row['latitude']),
            longitude: _number(row['longitude']),
            createdAt: _date(row['timestamp']),
            authorName: _profileName(profiles, _text(row['user_id'])),
            authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
            authorTrustLevel: _trustLevel(reputations, _text(row['user_id'])),
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
            spamScore: _integer(row['spam_score']),
            isSuspicious: row['is_suspicious'] == true,
            spamReason: _text(row['spam_reason']),
            authorName: _profileName(profiles, _text(row['user_id'])),
            authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
            authorTrustLevel: _trustLevel(reputations, _text(row['user_id'])),
          ),
    ];
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  });

  Future<List<Map<String, dynamic>>> _fetchOptionalCatches() async {
    if (_supabase.auth.currentUser == null) return const [];
    try {
      return _maps(
        await _supabase.rpc(
          'get_public_catches_v2',
          params: const {'p_limit': 50},
        ),
      );
    } on Exception catch (error, stackTrace) {
      _logOptionalFeedFailure('public catches', error, stackTrace);
      return const [];
    }
  }

  static void _logOptionalFeedFailure(
    String source,
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      'Optional community feed $source unavailable',
      name: 'AIFishMap.Community',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<List<CommunityPost>> getReportsArchive(
    Duration period, {
    DateTime? end,
  }) => _guard(() async {
    final rangeEnd = (end ?? DateTime.now()).toUtc();
    final since = rangeEnd.subtract(period);
    final reports = _maps(
      await _supabase
          .from('reports')
          .select()
          .gte('created_at', since.toIso8601String())
          .lt('created_at', rangeEnd.toIso8601String())
          .order('created_at', ascending: false),
    );
    final profiles = await _profiles(
      reports.map((row) => _text(row['user_id'])).whereType<String>().toSet(),
    );
    final reputations = await ReputationService(client: _supabase)
        .getReputations(
          reports.map((row) => _text(row['user_id'])).whereType<String>(),
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
            spamScore: _integer(row['spam_score']),
            isSuspicious: row['is_suspicious'] == true,
            spamReason: _text(row['spam_reason']),
            authorName: _profileName(profiles, _text(row['user_id'])),
            authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
            authorTrustLevel: _trustLevel(reputations, _text(row['user_id'])),
          ),
    ];
    developer.log(
      'Fetched archive report count: ${archive.length}; '
      'range: ${since.toIso8601String()}–${rangeEnd.toIso8601String()}',
      name: 'AIFishMap.Community',
    );
    return archive;
  }, debugLabel: 'fetch reports archive');

  Future<String> createReport({
    required ReportCategory category,
    String? text,
    File? cameraPhoto,
    required bool useExactLocation,
  }) => _guard(
    () async {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw const CommunityException(
          'Your session has expired.',
          code: CommunityErrorCode.sessionExpired,
        );
      }
      final position = await const LocationService().determinePosition();
      final latitude = useExactLocation
          ? position.latitude
          : (position.latitude * 100).round() / 100;
      final longitude = useExactLocation
          ? position.longitude
          : (position.longitude * 100).round() / 100;
      final now = DateTime.now().toUtc();
      final description = text?.trim() ?? '';
      final moderation = const ReportSpamService();
      OptimizedReportImage? optimizedImage;
      String? storagePath;
      var reportSaved = false;
      try {
        if (cameraPhoto != null) {
          try {
            optimizedImage = await const ReportImageOptimizer().optimize(
              cameraPhoto,
            );
          } on ReportImageOptimizationException {
            throw const CommunityException(
              'The report photo could not be prepared. Please try another photo.',
              code: CommunityErrorCode.reportPhotoPreparationFailed,
            );
          }
        }
        final reportPhoto = optimizedImage?.file;
        final hash = await moderation.imageHash(reportPhoto);
        final previousRows = _maps(
          await _supabase
              .from('reports')
              .select(
                'category,description,latitude,longitude,created_at,image_hash',
              )
              .eq('user_id', user.id)
              .gte(
                'created_at',
                now.subtract(const Duration(hours: 24)).toIso8601String(),
              )
              .order('created_at', ascending: false)
              .limit(50),
        );
        final assessment = moderation.assess(
          category: category.name,
          description: description,
          latitude: latitude,
          longitude: longitude,
          now: now,
          imageHash: hash,
          history: [
            for (final row in previousRows)
              SpamReportHistory(
                category: _text(row['category']) ?? '',
                description: _text(row['description']) ?? '',
                latitude: _number(row['latitude']),
                longitude: _number(row['longitude']),
                createdAt: _date(row['created_at']).toUtc(),
                imageHash: _text(row['image_hash']),
              ),
          ],
        );
        String? imageUrl;
        if (reportPhoto != null) {
          final uploadedPath = '${user.id}/${now.microsecondsSinceEpoch}.jpg';
          await _supabase.storage
              .from(_reportPhotosBucket)
              .upload(
                uploadedPath,
                reportPhoto,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          storagePath = uploadedPath;
          imageUrl = _supabase.storage
              .from(_reportPhotosBucket)
              .getPublicUrl(uploadedPath);
        }
        late final Map<String, Object?> inserted;
        inserted = Map<String, Object?>.from(
          await _supabase
              .from('reports')
              .insert({
                'user_id': user.id,
                'type': category.label,
                'category': category.name,
                'description': description.isEmpty ? null : description,
                'image_url': imageUrl,
                'latitude': latitude,
                'longitude': longitude,
                'use_exact_location': useExactLocation,
                'created_at': now.toIso8601String(),
                'expires_at': now
                    .add(const Duration(hours: 12))
                    .toIso8601String(),
                'spam_score': assessment.score,
                'is_suspicious': assessment.isSuspicious,
                'spam_reason': assessment.reason,
                'image_hash': hash,
              })
              .select('id')
              .single(),
        );
        final id = _text(inserted['id']);
        if (id == null) {
          throw const CommunityException(
            'The report was saved without a valid identifier.',
            code: CommunityErrorCode.reportPublishFailed,
          );
        }
        reportSaved = true;
        developer.log(
          'Community report insert success',
          name: 'AIFishMap.Community',
        );
        developer.log('Inserted report id: $id', name: 'AIFishMap.Community');
        _feedCache.clear();
        _reportEvents.add(
          CommunityReportEvent(CommunityReportEventType.created, id),
        );
        return id;
      } finally {
        if (storagePath != null && !reportSaved) {
          await _removeReportPhoto(storagePath);
        }
        await optimizedImage?.dispose();
      }
    },
    debugLabel: 'publish community report',
    storageErrorCode: CommunityErrorCode.reportPhotoUploadFailed,
    databaseErrorCode: CommunityErrorCode.reportPublishFailed,
  );

  Future<bool> attachReportWaterContext({
    required String reportId,
    required String entityType,
    required String entityId,
  }) => _guard(
    () async {
      final response = await _supabase.rpc(
        'attach_report_water_context_v1',
        params: {
          'p_report_id': reportId,
          'p_entity_type': entityType,
          'p_entity_id': entityId,
        },
      );
      return response == true;
    },
    debugLabel: 'attach report Water context',
    databaseErrorCode: CommunityErrorCode.reportPublishFailed,
  );

  Future<void> _removeReportPhoto(String path) async {
    try {
      await _supabase.storage.from(_reportPhotosBucket).remove([path]);
    } catch (_) {
      // Cleanup is best-effort; preserve the original report insert failure.
    }
  }

  Future<List<CommunityPost>> getActiveReports() async => (await getFeed())
      .where(
        (post) =>
            post.isActiveReport &&
            post.latitude != null &&
            post.longitude != null,
      )
      .toList(growable: false);

  Future<void> verifyReport(String reportId, ReportVerification verification) =>
      _guard(
        () async {
          final user = _supabase.auth.currentUser;
          if (user == null) {
            throw const CommunityException(
              'Your session has expired.',
              code: CommunityErrorCode.sessionExpired,
            );
          }
          await _supabase.rpc(
            'submit_report_verification',
            params: {
              'p_report_id': reportId,
              'p_is_valid': verification == ReportVerification.stillValid,
            },
          );
          _reportEvents.add(
            CommunityReportEvent(CommunityReportEventType.verified, reportId),
          );
          developer.log(
            verification == ReportVerification.stillValid
                ? 'Confirm reaction: $reportId'
                : 'Not accurate reaction: $reportId',
            name: 'AIFishMap.Community',
          );
        },
        debugLabel: 'react to community report',
        databaseErrorCode: CommunityErrorCode.reportVerificationFailed,
      );

  Future<void> reportAbuse(String reportId, ReportAbuseReason reason) => _guard(
    () async {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw const CommunityException(
          'Your session has expired.',
          code: CommunityErrorCode.sessionExpired,
        );
      }
      final existing = await _supabase
          .from('report_abuse')
          .select('id')
          .eq('report_id', reportId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) {
        throw const CommunityException(
          'You have already reported this report.',
          code: CommunityErrorCode.reportAlreadySubmitted,
        );
      }
      await _supabase.from('report_abuse').insert({
        'report_id': reportId,
        'user_id': user.id,
        'reason': reason.databaseValue,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      developer.log(
        'Report abuse: $reportId (${reason.databaseValue})',
        name: 'AIFishMap.Community',
      );
    },
    debugLabel: 'report community abuse',
    databaseErrorCode: CommunityErrorCode.reportAbuseFailed,
  );

  Future<bool> toggleLike(CommunityPost post) => _guard(() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const CommunityException(
        'Your session has expired.',
        code: CommunityErrorCode.sessionExpired,
      );
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
          throw const CommunityException(
            'Your session has expired.',
            code: CommunityErrorCode.sessionExpired,
          );
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
    final reputation = await ReputationService(
      client: _supabase,
    ).getReputation(userId);
    return CommunityProfile(
      id: userId,
      name: _text(row['username'] ?? row['full_name']) ?? 'Angler',
      avatarUrl: _text(row['avatar'] ?? row['avatar_url']),
      country: _text(row['country']),
      reputation: reputation.reputationScore,
      catchCount: reputation.catchesCount,
      trustLevel: reputation.trustLevel,
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

  TrustLevel _trustLevel(
    Map<String, ReputationMetrics> reputations,
    String? id,
  ) => reputations[id]?.trustLevel ?? TrustLevel.newUser;

  Future<T> _guard<T>(
    Future<T> Function() operation, {
    String? debugLabel,
    CommunityErrorCode socketErrorCode = CommunityErrorCode.noInternet,
    CommunityErrorCode timeoutErrorCode = CommunityErrorCode.requestTimedOut,
    CommunityErrorCode? storageErrorCode,
    CommunityErrorCode? databaseErrorCode,
    CommunityErrorCode fallbackErrorCode =
        CommunityErrorCode.communityUnavailable,
  }) async {
    try {
      return await operation().timeout(const Duration(seconds: 30));
    } on CommunityException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      rethrow;
    } on SocketException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw CommunityException(
        'No internet connection.',
        code: socketErrorCode,
      );
    } on TimeoutException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw CommunityException(
        'The request timed out. Please retry.',
        code: timeoutErrorCode,
      );
    } on StorageException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw CommunityException(
        'The report photo could not be uploaded. Please try again.',
        code: storageErrorCode,
      );
    } on PostgrestException catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw CommunityException(switch (databaseErrorCode) {
        CommunityErrorCode.reportVerificationFailed =>
          'The report verification could not be saved.',
        CommunityErrorCode.reportAbuseFailed =>
          'The abuse report could not be submitted. Please try again.',
        _ => 'The report could not be published. Please try again.',
      }, code: databaseErrorCode);
    } on Exception catch (error, stackTrace) {
      _logFailure(debugLabel, error, stackTrace);
      throw CommunityException(
        'Community data is unavailable.',
        code: fallbackErrorCode,
      );
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
