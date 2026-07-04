import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

class AuthService {
  const AuthService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
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
    final image = File(imagePath);
    if (!await image.exists()) {
      throw const AuthException('The selected image is no longer available.');
    }

    return _guard(() async {
      const objectName = 'avatar.jpg';
      final path = '${user.id}/$objectName';
      await _supabase.storage
          .from('avatars')
          .upload(path, image, fileOptions: const FileOptions(upsert: true))
          .timeout(const Duration(seconds: 45));
      final publicUrl = _supabase.storage.from('avatars').getPublicUrl(path);
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
      throw AuthException(error.message);
    } on AuthException {
      rethrow;
    } on Exception {
      throw const AuthException('Something went wrong. Please try again.');
    }
  }
}
