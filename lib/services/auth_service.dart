import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_processing_service.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

class AuthService {
  const AuthService({
    SupabaseClient? client,
    MediaProcessingService mediaProcessor = const MediaProcessingService(),
  })  : _client = client,
        _mediaProcessor = mediaProcessor;

  static const _avatarBucket = 'avatars';

  final SupabaseClient? _client;
  final MediaProcessingService _mediaProcessor;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Session? get currentSession => _supabase.auth.currentSession;
  User? get currentUser => _supabase.auth.currentUser;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) => _guard(
    () => _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) => _guard(
    () => _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': name.trim()},
    ),
  );

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _supabase.auth.resetPasswordForEmail(email.trim()));

  Future<void> updatePassword(String password) => _guard(
    () => _supabase.auth.updateUser(UserAttributes(password: password)),
  );

  Future<void> updateProfile({required String name}) => _guard(
    () => _supabase.auth.updateUser(
      UserAttributes(data: {'full_name': name.trim()}),
    ),
  );

  Future<String> uploadAvatar(String imagePath) async {
    final user = currentUser;
    if (user == null) throw const AuthException('Your session has expired.');

    late final ProcessedMedia media;
    try {
      media = await _mediaProcessor.processFile(
        path: imagePath,
        purpose: MediaPurpose.avatar,
      );
    } on MediaProcessingException catch (error) {
      throw AuthException(error.message);
    }

    return _guard(() async {
      const objectName = 'avatar.jpg';
      final path = '${user.id}/$objectName';
      await _supabase.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            media.bytes,
            fileOptions: FileOptions(
              cacheControl: '31536000',
              contentType: ProcessedMedia.contentType,
              upsert: true,
              metadata: {
                'sha256': media.sha256Hex,
                'original_bytes': media.originalBytes,
                'processed_bytes': media.outputBytes,
                'dimension_limit': media.dimensionLimit,
                'quality': media.quality,
                'exif_preserved': false,
              },
            ),
          )
          .timeout(const Duration(seconds: 45));
      final publicUrl = _supabase.storage
          .from(_avatarBucket)
          .getPublicUrl(path);
      final avatarUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      await _supabase.auth.updateUser(
        UserAttributes(data: {'avatar_url': avatarUrl}),
      );
      return avatarUrl;
    });
  }

  Future<void> logout() => _guard(_supabase.auth.signOut);

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const AuthException('No internet connection. Please try again.');
    } on TimeoutException {
      throw const AuthException('The request timed out. Please try again.');
    } on AuthApiException catch (error) {
      throw AuthException(error.message);
    } on StorageException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('bucket') &&
          (message.contains('not found') ||
              message.contains('does not exist'))) {
        throw const AuthException(
          'Profile photo storage is not configured yet.',
        );
      }
      if (message.contains('row-level security') ||
          message.contains('not authorized') ||
          message.contains('unauthorized')) {
        throw const AuthException(
          'Profile photo storage permissions are not configured yet.',
        );
      }
      throw AuthException(error.message);
    } on AuthException {
      rethrow;
    } on Exception {
      throw const AuthException('Something went wrong. Please try again.');
    }
  }
}
