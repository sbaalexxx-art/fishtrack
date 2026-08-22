import 'dart:async';

import 'package:fishtrack/core/localization/locale_controller.dart';
import 'package:fishtrack/core/theme/app_theme.dart';
import 'package:fishtrack/core/theme/fluviai_commercial_tokens.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/screens/auth_page.dart';
import 'package:fishtrack/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AuthPage renders the canonical welcome state', (tester) async {
    await _pumpAuth(tester);

    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-welcome-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-continue-email')), findsOneWidget);
  });

  testWidgets('hero slot remains independent from the Flutter overlay', (
    tester,
  ) async {
    await _pumpAuth(tester);

    expect(find.byKey(const ValueKey('auth-hero-background')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-hero-image-slot')), findsOneWidget);
    final heroImage = tester.widget<Image>(
      find.byKey(const ValueKey('auth-hero-image')),
    );
    expect(heroImage.image, isA<AssetImage>());
    expect(
      (heroImage.image as AssetImage).assetName,
      'assets/images/auth/fluviai_login_hero.webp',
    );
    expect(heroImage.fit, BoxFit.cover);
    expect(find.byKey(const ValueKey('auth-welcome-scroll')), findsOneWidget);
  });

  testWidgets('hero focal crop adapts between portrait and landscape', (
    tester,
  ) async {
    await _pumpAuth(tester, size: const Size(390, 844));
    final portraitAlignment = tester
        .widget<Image>(find.byKey(const ValueKey('auth-hero-image')))
        .alignment;

    await _pumpAuth(tester, size: const Size(844, 390));
    final landscapeAlignment = tester
        .widget<Image>(find.byKey(const ValueKey('auth-hero-image')))
        .alignment;

    expect(portraitAlignment, isNot(equals(landscapeAlignment)));
  });

  testWidgets('Login and Welcome use the wordmark without the legacy logo', (
    tester,
  ) async {
    await _pumpAuth(tester);

    expect(find.byKey(const ValueKey('auth-brand-wordmark')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/fluviai_logo.png',
      ),
      findsNothing,
    );

    await _openAccess(tester);
    expect(find.byKey(const ValueKey('auth-brand-wordmark')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/fluviai_logo.png',
      ),
      findsNothing,
    );
  });

  testWidgets('welcome reveals one continuous auth panel over the same hero', (
    tester,
  ) async {
    await _pumpAuth(tester);
    expect(find.byKey(const ValueKey('auth-hero-background')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth-continue-email')));
    await tester.pump(const Duration(milliseconds: 140));

    expect(find.byKey(const ValueKey('auth-hero-background')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-panel')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('Login headline remains quieter than Welcome', (tester) async {
    await _pumpAuth(tester);
    final welcomeHeadline = tester.widget<Text>(
      find.byKey(const ValueKey('auth-hero-title')),
    );

    await _openAccess(tester);
    final loginHeadline = tester.widget<Text>(
      find.byKey(const ValueKey('auth-hero-title')),
    );

    expect(
      loginHeadline.style!.fontSize,
      lessThan(welcomeHeadline.style!.fontSize!),
    );
    expect(_accentSpan(loginHeadline, 'apei'), isNotNull);
  });

  testWidgets('compact language selector updates LocaleScope from RO to EN', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {
      'fluviai_language_code': 'ro',
    });
    final preferences = await SharedPreferences.getInstance();
    final localeController = LocaleController(preferences);
    await _pumpAuth(tester, localeController: localeController);

    final selector = find.byKey(const ValueKey('auth-language-selector'));
    expect(selector, findsOneWidget);
    expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(selector).width, lessThanOrEqualTo(112));

    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-language-en')));
    await tester.pumpAndSettle();

    expect(localeController.languageCode, 'en');
    expect(find.text('Continue with email'), findsOneWidget);
  });

  testWidgets('login mode remains available', (tester) async {
    await _pumpAuth(tester);
    await _openAccess(tester);

    expect(find.byKey(const ValueKey('auth-login-tab')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-password-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-reset-password')), findsOneWidget);
  });

  testWidgets('register mode remains available', (tester) async {
    await _pumpAuth(tester);
    await _openAccess(tester);
    await tester.tap(find.byKey(const ValueKey('auth-register-tab')));
    await tester.pump();

    expect(find.byKey(const ValueKey('auth-name-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-password-field')), findsOneWidget);
  });

  testWidgets('login submit still reaches AuthService injection', (
    tester,
  ) async {
    final service = _RecordingAuthService();
    await _pumpAuth(tester, authService: service);
    await _openAccess(tester);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'angler@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'secret1',
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    expect(service.loginCalls, 1);
    expect(service.lastEmail, 'angler@example.com');
    expect(service.lastPassword, 'secret1');
  });

  testWidgets('register submit still reaches AuthService injection', (
    tester,
  ) async {
    final service = _RecordingAuthService();
    await _pumpAuth(tester, authService: service);
    await _openAccess(tester);
    await tester.tap(find.byKey(const ValueKey('auth-register-tab')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('auth-name-field')),
      'Ana Pescar',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'ana@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'secret1',
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    expect(service.registerCalls, 1);
    expect(service.lastName, 'Ana Pescar');
    expect(service.lastEmail, 'ana@example.com');
    expect(service.lastPassword, 'secret1');
  });

  testWidgets('forgot-password action remains wired', (tester) async {
    final service = _RecordingAuthService();
    await _pumpAuth(tester, authService: service);
    await _openAccess(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'angler@example.com',
    );

    await tester.tap(find.byKey(const ValueKey('auth-reset-password')));
    await tester.pumpAndSettle();

    expect(service.resetCalls, 1);
    expect(service.lastEmail, 'angler@example.com');
  });

  testWidgets('loading state prevents duplicate submission', (tester) async {
    final gate = Completer<AuthResponse>();
    final service = _RecordingAuthService(loginGate: gate);
    await _pumpAuth(tester, authService: service);
    await _openAccess(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'angler@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'secret1',
    );

    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pump();

    expect(service.loginCalls, 1);
    final submit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('auth-submit')),
    );
    expect(submit.onPressed, isNull);

    gate.completeError(const AuthException('Test auth error'));
    await tester.pumpAndSettle();
  });

  testWidgets('auth errors are presented in a live region', (tester) async {
    final service = _RecordingAuthService();
    await _pumpAuth(tester, authService: service);
    await _openAccess(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'angler@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'secret1',
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Test auth error'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('auth-message')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.liveRegion, isTrue);
  });

  testWidgets('Romanian welcome copy renders', (tester) async {
    await _pumpAuth(tester, locale: const Locale('ro'));

    expect(
      find.text('Acolo unde pasiunea întâlnește firul apei.'),
      findsOneWidget,
    );
    final headline = tester.widget<Text>(
      find.byKey(const ValueKey('auth-hero-title')),
    );
    expect(
      _accentSpan(headline, 'apei').style?.color,
      FluviAICommercialTokens.accent.withValues(alpha: 0.84),
    );
    final supportingLine = tester.widget<Text>(
      find.byKey(const ValueKey('auth-hero-subtitle')),
    );
    expect(supportingLine.style?.fontSize, 14);
    expect(supportingLine.style?.fontWeight, FontWeight.w600);
    expect(
      find.text('Date reale. Decizii mai bune. Capturi memorabile.'),
      findsOneWidget,
    );
    expect(find.text('Continuă cu e-mail'), findsOneWidget);
  });

  testWidgets('English welcome copy renders', (tester) async {
    await _pumpAuth(tester, locale: const Locale('en'));

    expect(find.text('Where passion meets the waterline.'), findsOneWidget);
    final headline = tester.widget<Text>(
      find.byKey(const ValueKey('auth-hero-title')),
    );
    expect(
      _accentSpan(headline, 'waterline').style?.color,
      FluviAICommercialTokens.accent.withValues(alpha: 0.84),
    );
    expect(
      find.text('Real data. Better decisions. Memorable catches.'),
      findsOneWidget,
    );
    expect(find.text('Continue with email'), findsOneWidget);
  });

  testWidgets('welcome treatment adapts between light and dark themes', (
    tester,
  ) async {
    await _pumpAuth(tester, brightness: Brightness.light);
    final lightDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey('auth-hero-background')),
        )
        .decoration;

    await _pumpAuth(tester, brightness: Brightness.dark);
    await tester.pumpAndSettle();
    final darkDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(const ValueKey('auth-hero-background')),
        )
        .decoration;

    expect(lightDecoration, isNot(equals(darkDecoration)));
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 360, 390, 430]) {
    testWidgets('$width px portrait remains overflow-free', (tester) async {
      await _pumpAuth(tester, size: Size(width, 720));
      expect(tester.takeException(), isNull);

      await _openAccess(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
    });
  }

  testWidgets('landscape remains overflow-free', (tester) async {
    await _pumpAuth(tester, size: const Size(844, 390));
    expect(tester.takeException(), isNull);

    await _openAccess(tester);
    expect(tester.takeException(), isNull);
  });

  for (final scale in <double>[1.3, 1.5, 2]) {
    testWidgets('text scale $scale remains overflow-free', (tester) async {
      await _pumpAuth(tester, size: const Size(320, 640), textScale: scale);
      expect(tester.takeException(), isNull);

      await _openAccess(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard inset keeps the form scrollable', (tester) async {
    await _pumpAuth(
      tester,
      size: const Size(390, 844),
      viewInsets: const EdgeInsets.only(bottom: 320),
    );
    await _openAccess(tester);

    expect(find.byKey(const ValueKey('auth-access-scroll')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('auth-password-field')),
    );
    await tester.tap(find.byKey(const ValueKey('auth-password-field')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary actions satisfy the 48 px touch contract', (
    tester,
  ) async {
    await _pumpAuth(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-continue-email'))).height,
      greaterThanOrEqualTo(48),
    );

    await _openAccess(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-submit'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-login-tab'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-register-tab'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('UpdatePasswordPage still reaches AuthService injection', (
    tester,
  ) async {
    final service = _RecordingAuthService();
    await _pumpPasswordRecovery(tester, service);

    await tester.enterText(find.byType(TextField), 'new-secret');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(service.updatePasswordCalls, 1);
    expect(service.lastPassword, 'new-secret');
  });
}

TextSpan _accentSpan(Text headline, String accent) {
  final root = headline.textSpan! as TextSpan;
  return root.children!.cast<TextSpan>().singleWhere(
    (span) => span.text == accent,
  );
}

Future<void> _pumpAuth(
  WidgetTester tester, {
  AuthService? authService,
  Locale locale = const Locale('ro'),
  Brightness brightness = Brightness.dark,
  Size size = const Size(390, 844),
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  LocaleController? localeController,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  Widget buildApp(Locale activeLocale) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: activeLocale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.lightTheme.copyWith(splashFactory: InkRipple.splashFactory),
    darkTheme: AppTheme.darkTheme.copyWith(
      splashFactory: InkRipple.splashFactory,
    ),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: viewInsets,
      ),
      child: child!,
    ),
    home: AuthPage(authService: authService ?? _RecordingAuthService()),
  );

  await tester.pumpWidget(
    localeController == null
        ? buildApp(locale)
        : LocaleScope(
            controller: localeController,
            child: ListenableBuilder(
              listenable: localeController,
              builder: (context, child) => buildApp(localeController.locale),
            ),
          ),
  );
  await tester.pump();
}

Future<void> _openAccess(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('auth-continue-email'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _pumpPasswordRecovery(
  WidgetTester tester,
  AuthService authService,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ro'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      themeMode: ThemeMode.dark,
      home: UpdatePasswordPage(authService: authService),
    ),
  );
  await tester.pump();
}

class _RecordingAuthService extends AuthService {
  _RecordingAuthService({this.loginGate});

  final Completer<AuthResponse>? loginGate;
  int loginCalls = 0;
  int registerCalls = 0;
  int resetCalls = 0;
  int updatePasswordCalls = 0;
  String? lastName;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) {
    loginCalls += 1;
    lastEmail = email;
    lastPassword = password;
    return loginGate?.future ??
        Future<AuthResponse>.error(const AuthException('Test auth error'));
  }

  @override
  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) {
    registerCalls += 1;
    lastName = name;
    lastEmail = email;
    lastPassword = password;
    return Future<AuthResponse>.error(const AuthException('Test auth error'));
  }

  @override
  Future<void> sendPasswordReset(String email) {
    resetCalls += 1;
    lastEmail = email;
    return Future<void>.error(const AuthException('Test reset error'));
  }

  @override
  Future<void> updatePassword(String password) {
    updatePasswordCalls += 1;
    lastPassword = password;
    return Future<void>.error(const AuthException('Test update error'));
  }
}
