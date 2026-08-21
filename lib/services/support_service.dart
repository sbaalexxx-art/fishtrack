import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.subject,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String category;
  final String subject;
  final String message;
  final String status;
  final DateTime createdAt;
}

class SupportException implements Exception {
  const SupportException(this.message);
  final String message;
}

class SupportService {
  const SupportService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<String> createTicket({
    required String category,
    required String subject,
    required String message,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw const SupportException('Sesiunea a expirat.');
    final cleanSubject = subject.trim();
    final cleanMessage = message.trim();
    if (cleanSubject.length < 3) {
      throw const SupportException('Subiectul este prea scurt.');
    }
    if (cleanMessage.length < 10) {
      throw const SupportException(
        'Descrie problema în cel puțin 10 caractere.',
      );
    }

    try {
      final row = await _supabase
          .from('support_tickets')
          .insert({
            'user_id': user.id,
            'category': category,
            'subject': cleanSubject,
            'message': cleanMessage,
          })
          .select('id')
          .single()
          .timeout(const Duration(seconds: 20));
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) {
        throw const SupportException(
          'Solicitarea nu a primit un identificator valid.',
        );
      }
      return id;
    } on SocketException {
      throw const SupportException('Nu există conexiune la internet.');
    } on TimeoutException {
      throw const SupportException('Trimiterea a expirat. Încearcă din nou.');
    } on PostgrestException catch (error) {
      throw SupportException(error.message);
    }
  }

  Future<List<SupportTicket>> getMyTickets() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return const <SupportTicket>[];
    try {
      final rows = await _supabase
          .from('support_tickets')
          .select('id,category,subject,message,status,created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 15));
      return rows
          .map((row) {
            return SupportTicket(
              id: row['id'].toString(),
              category: row['category']?.toString() ?? 'support',
              subject: row['subject']?.toString() ?? '',
              message: row['message']?.toString() ?? '',
              status: row['status']?.toString() ?? 'open',
              createdAt:
                  DateTime.tryParse(
                    row['created_at']?.toString() ?? '',
                  )?.toLocal() ??
                  DateTime.now(),
            );
          })
          .toList(growable: false);
    } on Exception {
      throw const SupportException('Solicitările nu au putut fi încărcate.');
    }
  }
}
