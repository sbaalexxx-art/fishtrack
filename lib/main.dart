import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/localization/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/fluviai_commercial_tokens.dart';
import 'core/theme/theme_controller.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_page.dart';
import 'screens/main_navigation.dart';
import 'services/auth_service.dart';
import 'services/build_mode_service.dart';
import 'services/diagnostics_service.dart';
import 'services/firebase_observability_service.dart';
import 'services/firebase_push_service.dart';

const _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installInternalDiagnostics();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  if (_mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(_mapboxAccessToken);
  }

  DiagnosticsService.instance.record(
    category: DiagnosticCategory.app,
    operation: 'startup',
    message: 'Flutter bootstrap started',
    metadata: <String, Object?>{
      'mapbox_configured': _mapboxAccessToken.isNotEmpty,
    },
  );

  runApp(
    ProviderScope(child: AppBootstrap(initialize: _initializeApplication)),
  );
}

void _installInternalDiagnostics() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    DiagnosticsService.instance.recordError(
      category: DiagnosticCategory.app,
      operation: 'flutter_error',
      error: details.exception,
      stackTrace: details.stack,
      fatal: true,
    );
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final previousPlatformError = dispatcher.onError;
  dispatcher.onError = (error, stackTrace) {
    DiagnosticsService.instance.recordError(
      category: DiagnosticCategory.app,
      operation: 'platform_error',
      error: error,
      stackTrace: stackTrace,
      fatal: true,
    );
    return previousPlatformError?.call(error, stackTrace) ?? false;
  };
}

Future<ApplicationControllers> _initializeApplication() async {
  final stopwatch = Stopwatch()..start();
  await _initializeFirebaseIfConfigured();
  await Supabase.initialize(
    url: 'https://rbymtavrfreweyfydkjl.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJieW10YXZyZnJld2V5Znlka2psIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MTMxNTIsImV4cCI6MjA5ODM4OTE1Mn0.4PS1M079y5chpYV7XU_5xxuO6i9tc4nOAF3XcCS0rzo',
  );

  await BuildModeService.refreshInternalAccess();

  final preferences = await SharedPreferences.getInstance();
  await DiagnosticsService.instance.initialize(preferences);
  await FirebaseObservabilityService.instance.setUserIdentifier(
    Supabase.instance.client.auth.currentSession?.user.id,
  );
  await FirebasePushService.instance.initialize();
  stopwatch.stop();
  DiagnosticsService.instance.record(
    category: DiagnosticCategory.supabase,
    operation: 'initialize',
    message: 'Supabase and local controllers initialized',
    duration: stopwatch.elapsed,
    metadata: <String, Object?>{
      'authenticated': Supabase.instance.client.auth.currentSession != null,
    },
  );
  return ApplicationControllers(
    locale: LocaleController(preferences),
    theme: ThemeController(preferences),
  );
}

Future<void> _initializeFirebaseIfConfigured() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await FirebaseObservabilityService.instance.initialize();
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.app,
      operation: 'firebase_initialize',
      message: 'Firebase observability transport initialized',
      metadata: <String, Object?>{
        'project_id': Firebase.app().options.projectId,
      },
    );
  } on Object catch (error, stackTrace) {
    DiagnosticsService.instance.recordError(
      category: DiagnosticCategory.app,
      operation: 'firebase_initialize',
      error: error,
      stackTrace: stackTrace,
    );
    // Firebase telemetry/push must never prevent Water, Weather, Map or
    // Supabase-backed product functionality from starting.
  }
}

class ApplicationControllers {
  const ApplicationControllers({required this.locale, required this.theme});

  final LocaleController locale;
  final ThemeController theme;
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, required this.initialize});

  final Future<ApplicationControllers> Function() initialize;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  ApplicationControllers? _controllers;
  Object? _startupFailure;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _finishStartup());
  }

  Future<void> _finishStartup() async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
    });
    try {
      final controllers = await widget.initialize();
      if (!mounted) return;
      setState(() => _controllers = controllers);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _startupFailure = error);
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllers = _controllers;
    if (controllers == null) {
      if (_startupFailure != null) {
        return _StartupFailureSurface(
          isRetrying: _isInitializing,
          onRetry: _finishStartup,
        );
      }
      return const _StartupSurface();
    }
    return LocaleScope(
      controller: controllers.locale,
      child: ThemeScope(
        controller: controllers.theme,
        child: AIFishMapApp(
          localeController: controllers.locale,
          themeController: controllers.theme,
        ),
      ),
    );
  }
}

class _StartupFailureSurface extends StatelessWidget {
  const _StartupFailureSurface({
    required this.isRetrying,
    required this.onRetry,
  });

  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        splashFactory: NoSplash.splashFactory,
      ),
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF0F1115),
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF0F1115),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 32),
                    const SizedBox(height: 14),
                    const Text(
                      'FluviAI could not start',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const ValueKey('startup-retry'),
                      onPressed: isRetrying ? null : onRetry,
                      icon: isRetrying
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(isRetrying ? 'Retrying...' : 'Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupSurface extends StatelessWidget {
  const _StartupSurface();

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Color(0xFF0F1115),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0F1115),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Color(0xFF0F1115),
        systemNavigationBarContrastEnforced: false,
      ),
      child: SizedBox.expand(child: ColoredBox(color: Color(0xFF0F1115))),
    );
  }
}

class AIFishMapApp extends StatelessWidget {
  const AIFishMapApp({
    super.key,
    required this.localeController,
    required this.themeController,
  });

  final LocaleController localeController;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final analyticsObserver =
        FirebaseObservabilityService.instance.navigatorObserver;
    return ListenableBuilder(
      listenable: Listenable.merge([localeController, themeController]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: analyticsObserver == null
            ? const <NavigatorObserver>[]
            : <NavigatorObserver>[analyticsObserver],
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
        themeMode: themeController.themeMode,
        builder: (context, child) {
          final theme = Theme.of(context);
          final colors = FluviAIThemeColors.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: colors.background,
              statusBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: colors.background,
              systemNavigationBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
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
        if (session == null) {
          BuildModeService.clearInternalAccess();
          return const AuthPage();
        }
        return _InternalAccessGate(userId: session.user.id);
      },
    );
  }
}

class _InternalAccessGate extends StatefulWidget {
  const _InternalAccessGate({required this.userId});

  final String userId;

  @override
  State<_InternalAccessGate> createState() => _InternalAccessGateState();
}

class _InternalAccessGateState extends State<_InternalAccessGate> {
  late Future<void> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = BuildModeService.refreshInternalAccess();
  }

  @override
  void didUpdateWidget(covariant _InternalAccessGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      BuildModeService.clearInternalAccess();
      _accessFuture = BuildModeService.refreshInternalAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupSurface();
        }
        return const MainNavigation();
      },
    );
  }
}
