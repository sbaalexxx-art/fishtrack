import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

enum CommunityPostType { catchPost, report }

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
            createdAt: _date(row['created_at'] ?? row['timestamp']),
            authorName: _profileName(profiles, _text(row['user_id'])),
            authorAvatar: _profileAvatar(profiles, _text(row['user_id'])),
          ),
    ];
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  });

  Future<void> createReport({
    required String type,
    required String description,
  }) => _guard(() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const CommunityException('Your session has expired.');
    }
    await _supabase.from('reports').insert({
      'user_id': user.id,
      'type': type,
      'description': description.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  });

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

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 30));
    } on CommunityException {
      rethrow;
    } on SocketException {
      throw const CommunityException('No internet connection.');
    } on TimeoutException {
      throw const CommunityException('The request timed out. Please retry.');
    } on PostgrestException catch (error) {
      throw CommunityException(error.message);
    } on Exception {
      throw const CommunityException('Community data is unavailable.');
    }
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
}

class _Like {
  const _Like(this.catchId, this.userId);
  final String catchId;
  final String userId;
}
