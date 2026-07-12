import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/localization/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_page.dart';
import 'screens/main_navigation.dart';
import 'services/auth_service.dart';

const _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(_mapboxAccessToken);
  }

  await Supabase.initialize(
    url: 'https://rbymtavrfreweyfydkjl.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJieW10YXZyZnJld2V5Znlka2psIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MTMxNTIsImV4cCI6MjA5ODM4OTE1Mn0.4PS1M079y5chpYV7XU_5xxuO6i9tc4nOAF3XcCS0rzo',
  );

  final preferences = await SharedPreferences.getInstance();
  final localeController = LocaleController(preferences);

  runApp(
    LocaleScope(
      controller: localeController,
      child: AIFishMapApp(localeController: localeController),
    ),
  );
}

class AIFishMapApp extends StatelessWidget {
  const AIFishMapApp({super.key, required this.localeController});

  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        locale: localeController.locale,
        supportedLocales: const [Locale('ro'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const _AuthGate(),
      ),
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
