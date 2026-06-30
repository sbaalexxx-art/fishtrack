import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static final instance = SupabaseService._();

  final SupabaseClient client = Supabase.instance.client;
}
