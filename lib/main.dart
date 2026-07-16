import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const _minimumPremiumSplashDuration = Duration(milliseconds: 800);
const _premiumSplashFadeDuration = Duration(milliseconds: 180);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (_mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(_mapboxAccessToken);
  }

  runApp(_AppBootstrap(initialization: _initializeApplication()));
}

Future<LocaleController> _initializeApplication() async {
  await Supabase.initialize(
    url: 'https://rbymtavrfreweyfydkjl.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJieW10YXZyZnJld2V5Znlka2psIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MTMxNTIsImV4cCI6MjA5ODM4OTE1Mn0.4PS1M079y5chpYV7XU_5xxuO6i9tc4nOAF3XcCS0rzo',
  );

  final preferences = await SharedPreferences.getInstance();
  return LocaleController(preferences);
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({required this.initialization});

  final Future<LocaleController> initialization;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  LocaleController? _localeController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _finishStartup());
  }

  Future<void> _finishStartup() async {
    final minimumDisplay = Future<void>.delayed(_minimumPremiumSplashDuration);
    final localeController = await widget.initialization;
    await minimumDisplay;

    if (!mounted) return;
    setState(() => _localeController = localeController);
  }

  @override
  Widget build(BuildContext context) {
    final localeController = _localeController;
    return AnimatedSwitcher(
      duration: _premiumSplashFadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: localeController == null
          ? const _PremiumSplash(key: ValueKey('premium-splash'))
          : KeyedSubtree(
              key: const ValueKey('application'),
              child: LocaleScope(
                controller: localeController,
                child: AIFishMapApp(localeController: localeController),
              ),
            ),
    );
  }
}

class _PremiumSplash extends StatelessWidget {
  const _PremiumSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0F1115),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Color(0xFF0F1115),
        systemNavigationBarContrastEnforced: false,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        color: const Color(0xFF0F1115),
        home: Scaffold(
          backgroundColor: const Color(0xFF0F1115),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;
              if (!isLandscape) {
                return SizedBox.expand(
                  child: Image.asset(
                    'assets/branding/fluvi_ai_splash_final.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Image.asset(
                      'assets/branding/fluvi_ai_splash_final.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                  const ColoredBox(color: Color(0xB30F1115)),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, safeAreaConstraints) {
                        final contentWidth = safeAreaConstraints.maxWidth;
                        final contentHeight = safeAreaConstraints.maxHeight;

                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: contentWidth * .18,
                                height: contentHeight * .38,
                                child: Image.asset(
                                  'assets/branding/fluviai_logo.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                              SizedBox(height: contentHeight * .035),
                              SizedBox(
                                width: contentWidth * .58,
                                height: contentHeight * .22,
                                child: Image.asset(
                                  'assets/branding/fluviai_wordmark.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
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
