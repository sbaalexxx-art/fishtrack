import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth_page.dart';
import 'screens/main_navigation.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rbymtavrfreweyfydkjl.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJieW10YXZyZnJld2V5Znlka2psIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MTMxNTIsImV4cCI6MjA5ODM4OTE1Mn0.4PS1M079y5chpYV7XU_5xxuO6i9tc4nOAF3XcCS0rzo',
  );

  runApp(const FishTrackApp());
}

class FishTrackApp extends StatelessWidget {
  const FishTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FishTrack',
      theme: AppTheme.lightTheme,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    const authService = AuthService();
    return StreamBuilder<AuthState>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        final authState = snapshot.data;
        if (authState?.event == AuthChangeEvent.passwordRecovery) {
          return const UpdatePasswordPage();
        }
        final session = authState?.session ?? authService.currentSession;
        return session == null ? const AuthPage() : const MainNavigation();
      },
    );
  }
}
