import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/localization/locale_controller.dart';
import '../core/theme/fluviai_commercial_tokens.dart';
import '../l10n/l10n.dart';
import '../services/auth_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.authService = const AuthService()});

  final AuthService authService;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showAccess = false;
  bool _register = false;
  bool _working = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    if (email.isEmpty || password.length < 6 || (_register && name.isEmpty)) {
      setState(
        () => _message = _register
            ? context.l10n.authRegisterValidation
            : context.l10n.authLoginValidation,
      );
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      if (_register) {
        await widget.authService.register(
          name: name,
          email: email,
          password: password,
        );
        if (mounted && widget.authService.currentSession == null) {
          setState(() => _message = context.l10n.authAccountCreated);
        }
      } else {
        await widget.authService.login(email: email, password: password);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = context.l10n.authEnterAccountEmail);
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.authService.sendPasswordReset(email);
      if (mounted) setState(() => _message = context.l10n.passwordResetSent);
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      key: const ValueKey('auth-scaffold'),
      resizeToAvoidBottomInset: true,
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AuthHeroBackground(
            imageAsset: 'assets/images/auth/fluviai_login_hero.webp',
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                if (reduceMotion) return child;
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.045),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: _showAccess
                  ? _buildAccess(context)
                  : _buildWelcome(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final l10n = context.l10n;
    final colors = FluviAIThemeColors.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      key: const ValueKey('auth-welcome-layout'),
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 650;
        final splitLayout =
            constraints.maxWidth >= 680 &&
            constraints.maxWidth > constraints.maxHeight &&
            textScale < 1.5;
        final verticalPadding = compactHeight ? 14.0 : 20.0;
        final minimumHeight = math.max(
          0.0,
          constraints.maxHeight - (verticalPadding * 2),
        );
        return SingleChildScrollView(
          key: const ValueKey('auth-welcome-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            verticalPadding,
            20,
            verticalPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: splitLayout ? 980 : 540),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumHeight),
                child: IntrinsicHeight(
                  child: splitLayout
                      ? Row(
                          children: [
                            const Expanded(
                              flex: 6,
                              child: _HeroIdentity(
                                compact: true,
                                showSubtitle: true,
                              ),
                            ),
                            const SizedBox(width: 44),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: _LanguageSelector(colors: colors),
                                  ),
                                  const Spacer(),
                                  _GradientAuthButton(
                                    key: const ValueKey('auth-continue-email'),
                                    label: l10n.continueWithEmail,
                                    icon: Icons.mail_outline_rounded,
                                    onPressed: () =>
                                        setState(() => _showAccess = true),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: _LanguageSelector(colors: colors),
                            ),
                            SizedBox(height: compactHeight ? 12 : 24),
                            const _HeroIdentity(
                              compact: false,
                              showSubtitle: true,
                            ),
                            SizedBox(height: compactHeight ? 20 : 32),
                            const Spacer(),
                            _GradientAuthButton(
                              key: const ValueKey('auth-continue-email'),
                              label: l10n.continueWithEmail,
                              icon: Icons.mail_outline_rounded,
                              onPressed: () =>
                                  setState(() => _showAccess = true),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccess(BuildContext context) {
    final l10n = context.l10n;
    final colors = FluviAIThemeColors.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      key: const ValueKey('auth-access-layout'),
      builder: (context, constraints) {
        final splitLayout =
            constraints.maxWidth >= 700 &&
            constraints.maxWidth > constraints.maxHeight &&
            textScale < 1.5;
        return SingleChildScrollView(
          key: const ValueKey('auth-access-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            splitLayout ? 28 : 16,
            10,
            splitLayout ? 28 : 16,
            20,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: splitLayout ? 980 : 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _BackButton(
                        label: l10n.authBack,
                        onPressed: () => setState(() => _showAccess = false),
                      ),
                      const Spacer(),
                      _LanguageSelector(colors: colors),
                    ],
                  ),
                  SizedBox(height: splitLayout ? 8 : 12),
                  if (splitLayout)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          flex: 5,
                          child: _HeroIdentity(
                            compact: true,
                            showSubtitle: false,
                            functionalFocus: true,
                          ),
                        ),
                        const SizedBox(width: 36),
                        Expanded(flex: 5, child: _buildAuthPanel(context)),
                      ],
                    )
                  else ...[
                    const _HeroIdentity(
                      compact: true,
                      showSubtitle: false,
                      functionalFocus: true,
                    ),
                    const SizedBox(height: 14),
                    _buildAuthPanel(context),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAuthPanel(BuildContext context) {
    final l10n = context.l10n;
    final activeColors = FluviAIThemeColors.of(context);
    const panelColors = FluviAIThemeColors.dark;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final panelColor = Color.alphaBlend(
      activeColors.background.withValues(alpha: isDark ? 0.18 : 0.1),
      FluviAICommercialTokens.backgroundRaised,
    ).withValues(alpha: isDark ? 0.9 : 0.86);

    return DecoratedBox(
      key: const ValueKey('auth-panel'),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: FluviAICommercialTokens.accent.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: activeColors.background.withValues(
              alpha: isDark ? 0.42 : 0.26,
            ),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(_register ? 'register-heading' : 'login-heading'),
                children: [
                  Text(
                    _register ? l10n.createAccountTitle : l10n.welcomeBack,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF7FAFC),
                      fontSize: 24,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.55,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _register
                        ? l10n.authCreateAccountSubtitle
                        : l10n.signInToContinue,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: panelColors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 17),
            AutofillGroup(
              child: Column(
                children: [
                  if (_register) ...[
                    TextField(
                      key: const ValueKey('auth-name-field'),
                      controller: _name,
                      autofillHints: const [AutofillHints.name],
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: panelColors.textPrimary),
                      decoration: _panelInputDecoration(
                        label: l10n.name,
                        icon: Icons.person_outline_rounded,
                        colors: panelColors,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    key: const ValueKey('auth-email-field'),
                    controller: _email,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    style: TextStyle(color: panelColors.textPrimary),
                    decoration: _panelInputDecoration(
                      label: l10n.email,
                      icon: Icons.mail_outline_rounded,
                      colors: panelColors,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('auth-password-field'),
                    controller: _password,
                    autofillHints: [
                      _register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    enableSuggestions: false,
                    autocorrect: false,
                    style: TextStyle(color: panelColors.textPrimary),
                    onSubmitted: (_) => _submit(),
                    decoration:
                        _panelInputDecoration(
                          label: l10n.password,
                          icon: Icons.lock_outline_rounded,
                          colors: panelColors,
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? l10n.authShowPassword
                                : l10n.authHidePassword,
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 160),
                              child: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                key: ValueKey(_obscure),
                                color: panelColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                container: true,
                child: Text(
                  _message!,
                  key: const ValueKey('auth-message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: FluviAICommercialTokens.waterFalling,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Semantics(
              selected: true,
              child: SizedBox(
                key: ValueKey(
                  _register ? 'auth-register-primary' : 'auth-login-tab',
                ),
                height: 50,
                child: _AuthSubmitButton(
                  buttonKey: const ValueKey('auth-submit'),
                  label: _working
                      ? l10n.authProcessing
                      : (_register ? l10n.createAccountTitle : l10n.authSignIn),
                  working: _working,
                  register: _register,
                  onPressed: _working ? null : _submit,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: ValueKey(_register ? 'auth-login-tab' : 'auth-register-tab'),
              onPressed: _working
                  ? null
                  : () => setState(() => _register = !_register),
              style: OutlinedButton.styleFrom(
                foregroundColor: FluviAICommercialTokens.accent,
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: FluviAICommercialTokens.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: Icon(
                _register
                    ? Icons.login_rounded
                    : Icons.person_add_alt_1_rounded,
              ),
              label: Text(
                _register ? l10n.backToLogin : l10n.createAccountTitle,
              ),
            ),
            if (!_register) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                key: const ValueKey('auth-reset-password'),
                onPressed: _working ? null : _resetPassword,
                style: TextButton.styleFrom(
                  foregroundColor: panelColors.textSecondary,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.lock_reset_rounded, size: 19),
                label: Text(l10n.forgotPassword),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _panelInputDecoration({
    required String label,
    required IconData icon,
    required FluviAIThemeColors colors,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colors.border),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: colors.textSecondary),
      floatingLabelStyle: const TextStyle(
        color: FluviAICommercialTokens.accent,
      ),
      prefixIcon: Icon(icon, color: colors.textSecondary),
      filled: true,
      fillColor: colors.surfaceRaised.withValues(alpha: 0.74),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      prefixIconConstraints: const BoxConstraints(
        minWidth: FluviAICommercialTokens.minimumTouchTarget,
        minHeight: FluviAICommercialTokens.minimumTouchTarget,
      ),
      suffixIconConstraints: const BoxConstraints(
        minWidth: FluviAICommercialTokens.minimumTouchTarget,
        minHeight: FluviAICommercialTokens.minimumTouchTarget,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: FluviAICommercialTokens.accent,
          width: 1.5,
        ),
      ),
    );
  }
}

class _AuthHeroBackground extends StatelessWidget {
  const _AuthHeroBackground({this.imageAsset});

  final String? imageAsset;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final focalAlignment = landscape
            ? const Alignment(0.05, -0.18)
            : const Alignment(0.08, -0.02);
        return DecoratedBox(
          key: const ValueKey('auth-hero-background'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.backgroundRaised, colors.background],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              KeyedSubtree(
                key: const ValueKey('auth-hero-image-slot'),
                child: imageAsset == null
                    ? const SizedBox.expand()
                    : Image.asset(
                        imageAsset!,
                        key: const ValueKey('auth-hero-image'),
                        fit: BoxFit.cover,
                        alignment: focalAlignment,
                        filterQuality: FilterQuality.high,
                      ),
              ),
              DecoratedBox(
                key: const ValueKey('auth-hero-scrim'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [
                            const Color(0xFF03111D).withValues(alpha: 0.28),
                            const Color(0xFF041521).withValues(alpha: 0.34),
                            const Color(0xFF03111D).withValues(alpha: 0.76),
                          ]
                        : [
                            const Color(0xFF041725).withValues(alpha: 0.16),
                            const Color(0xFF062033).withValues(alpha: 0.24),
                            const Color(0xFF041725).withValues(alpha: 0.64),
                          ],
                    stops: const [0, 0.54, 1],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroIdentity extends StatelessWidget {
  const _HeroIdentity({
    required this.compact,
    required this.showSubtitle,
    this.functionalFocus = false,
  });

  final bool compact;
  final bool showSubtitle;
  final bool functionalFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    const heroColors = FluviAIThemeColors.dark;
    final headlineSize = largeText
        ? (functionalFocus ? 19.5 : 20.0)
        : compact
        ? (functionalFocus ? 21.5 : 22.5)
        : 27.0;
    final fullTitle = l10n.authHeroTitle;
    final accent = l10n.authHeroTitleAccent;
    final accentStart = fullTitle.lastIndexOf(accent);
    final hasLocalizedAccent = accent.isNotEmpty && accentStart >= 0;
    final headlineColor = heroColors.textPrimary.withValues(
      alpha: functionalFocus ? 0.9 : 1,
    );
    final accentColor = FluviAICommercialTokens.accent.withValues(alpha: 0.84);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FluviAIBrandLockup(compact: compact),
        SizedBox(height: compact ? 12 : 20),
        Text.rich(
          hasLocalizedAccent
              ? TextSpan(
                  children: [
                    TextSpan(text: fullTitle.substring(0, accentStart)),
                    TextSpan(
                      text: accent,
                      style: TextStyle(color: accentColor),
                    ),
                    TextSpan(
                      text: fullTitle.substring(accentStart + accent.length),
                    ),
                  ],
                )
              : TextSpan(text: fullTitle),
          key: const ValueKey('auth-hero-title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: headlineColor,
            fontSize: headlineSize,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.45,
            shadows: const [Shadow(color: Color(0x99000000), blurRadius: 12)],
          ),
        ),
        if (showSubtitle) ...[
          const SizedBox(height: 8),
          Text(
            l10n.authHeroSubtitle,
            key: const ValueKey('auth-hero-subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: heroColors.textPrimary.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 8)],
            ),
          ),
        ],
      ],
    );
  }
}

class _FluviAIBrandLockup extends StatelessWidget {
  const _FluviAIBrandLockup({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    const colors = FluviAIThemeColors.dark;
    return Semantics(
      label: 'FluviAI',
      image: true,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'FLUVI',
                style: TextStyle(color: colors.textPrimary),
              ),
              const TextSpan(
                text: 'AI',
                style: TextStyle(color: FluviAICommercialTokens.accent),
              ),
            ],
          ),
          key: const ValueKey('auth-brand-wordmark'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: largeText ? 28 : (compact ? 32 : 40),
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 3.2 : 4.2,
            height: 1,
            shadows: const [Shadow(color: Color(0xB0000000), blurRadius: 14)],
          ),
        ),
      ),
    );
  }
}

class _GradientAuthButton extends StatelessWidget {
  const _GradientAuthButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    child: SizedBox(
      height: 58,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [FluviAICommercialTokens.accent, Color(0xFF10B8E8)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: FluviAICommercialTokens.accent.withValues(alpha: 0.75),
            ),
            boxShadow: [
              BoxShadow(
                color: FluviAICommercialTokens.accent.withValues(alpha: 0.2),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF062631)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF062631),
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF062631),
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

class _AuthSubmitButton extends StatelessWidget {
  const _AuthSubmitButton({
    required this.buttonKey,
    required this.label,
    required this.working,
    required this.register,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool working;
  final bool register;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enabled
              ? const [FluviAICommercialTokens.accent, Color(0xFF10B8E8)]
              : const [Color(0xFF66838A), Color(0xFF526C78)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: FluviAICommercialTokens.accent.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFF062631),
          disabledForegroundColor: const Color(0xFF17343D),
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey('$working-$register'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (working)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF062631),
                  ),
                )
              else
                Icon(
                  register
                      ? Icons.person_add_alt_1_rounded
                      : Icons.login_rounded,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (!working) ...[
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.colors});

  final FluviAIThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final activeCode = Localizations.localeOf(context).languageCode;
    final controller = LocaleScope.maybeOf(context);
    const overlayColors = FluviAIThemeColors.dark;
    return Semantics(
      button: true,
      label: activeCode.toUpperCase(),
      child: SizedBox(
        key: const ValueKey('auth-language-selector'),
        width: 100,
        height: 48,
        child: PopupMenuButton<String>(
          enabled: controller != null,
          tooltip: activeCode.toUpperCase(),
          offset: const Offset(0, 44),
          color: overlayColors.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: overlayColors.border),
          ),
          onSelected: controller == null
              ? null
              : (languageCode) async {
                  await controller.setLanguageCode(languageCode);
                },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              key: const ValueKey('auth-language-ro'),
              value: 'ro',
              child: const Text('Română'),
            ),
            PopupMenuItem<String>(
              key: const ValueKey('auth-language-en'),
              value: 'en',
              child: const Text('English'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colors.background.withValues(alpha: 0.12),
                  FluviAICommercialTokens.backgroundRaised.withValues(
                    alpha: 0.82,
                  ),
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: overlayColors.borderSoft),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.language_rounded,
                    color: overlayColors.textPrimary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    activeCode.toUpperCase(),
                    style: TextStyle(
                      color: overlayColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: overlayColors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    const overlayColors = FluviAIThemeColors.dark;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: FluviAICommercialTokens.minimumTouchTarget,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    colors.background.withValues(alpha: 0.12),
                    FluviAICommercialTokens.backgroundRaised.withValues(
                      alpha: 0.82,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: overlayColors.borderSoft),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFFF7FAFC),
                  size: 19,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthFormSurface extends StatelessWidget {
  const _AuthFormSurface({required this.colors, required this.child});

  final FluviAIThemeColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: colors.borderSoft),
      boxShadow: [
        BoxShadow(
          color: colors.background.withValues(alpha: 0.2),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class UpdatePasswordPage extends StatefulWidget {
  const UpdatePasswordPage({super.key, this.authService = const AuthService()});

  final AuthService authService;

  @override
  State<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends State<UpdatePasswordPage> {
  final _password = TextEditingController();
  bool _working = false;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (_password.text.length < 6) {
      setState(() => _message = context.l10n.authPasswordMinimumSix);
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.authService.updatePassword(_password.text);
      if (mounted) {
        setState(() => _message = context.l10n.authPasswordUpdated);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = FluviAIThemeColors.of(context);
    return Scaffold(
      key: const ValueKey('figma-update-password'),
      resizeToAvoidBottomInset: true,
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AuthHeroBackground(imageAsset: null),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.authSecurity.toUpperCase(),
                        style: const TextStyle(
                          color: FluviAICommercialTokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.authRecoveryTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _AuthFormSurface(
                        colors: colors,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.lock_reset_rounded,
                              color: FluviAICommercialTokens.accent,
                              size: 38,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.authChooseNewPassword,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.authRecoverySessionMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _password,
                              obscureText: true,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _update(),
                              decoration: InputDecoration(
                                labelText: l10n.newPassword,
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _working ? null : _update,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(
                          _working
                              ? l10n.authUpdatingPassword
                              : l10n.updatePassword,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
