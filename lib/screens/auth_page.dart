import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/auth_service.dart';

enum _AuthMode { login, register, forgotPassword }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = const AuthService();

  _AuthMode _mode = _AuthMode.login;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _message = null;
      _messageIsError = false;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      switch (_mode) {
        case _AuthMode.login:
          await _authService.login(
            email: _emailController.text,
            password: _passwordController.text,
          );
        case _AuthMode.register:
          final response = await _authService.register(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          );
          if (response.session == null && mounted) {
            setState(() {
              _mode = _AuthMode.login;
              _messageIsError = false;
              _message = context.l10n.checkEmailConfirmation;
            });
          }
        case _AuthMode.forgotPassword:
          await _authService.sendPasswordReset(_emailController.text);
          if (mounted) {
            setState(() {
              _mode = _AuthMode.login;
              _messageIsError = false;
              _message = context.l10n.passwordResetSent;
            });
          }
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? context.l10n.requiredField : null;

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return context.l10n.validEmailRequired;
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    if ((value ?? '').length < 8) return context.l10n.minimumEightCharacters;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _AuthMode.register;
    final isForgot = _mode == _AuthMode.forgotPassword;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Theme(
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12D8D6),
          brightness: theme.brightness,
        ),
        scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
        textTheme: theme.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          labelStyle: TextStyle(color: scheme.onSurfaceVariant),
          hintStyle: TextStyle(color: scheme.onSurfaceVariant),
          prefixIconColor: scheme.onSurfaceVariant,
          suffixIconColor: scheme.onSurfaceVariant,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: scheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF12D8D6), width: 2),
          ),
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.phishing_rounded, size: 54),
                      const SizedBox(height: 16),
                      Text(
                        isRegister
                            ? context.l10n.createAccountTitle
                            : isForgot
                            ? context.l10n.resetPassword
                            : context.l10n.welcomeBack,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isForgot
                            ? context.l10n.recoveryInstructionsHint
                            : context.l10n.signInToContinue,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      if (isRegister) ...[
                        TextFormField(
                          controller: _nameController,
                          enabled: !_loading,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.l10n.name,
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _emailController,
                        enabled: !_loading,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: isForgot
                            ? TextInputAction.done
                            : TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.l10n.email,
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: _emailValidator,
                      ),
                      if (!isForgot) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !_loading,
                          obscureText: _obscurePassword,
                          textInputAction: isRegister
                              ? TextInputAction.next
                              : TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: context.l10n.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: _passwordValidator,
                          onFieldSubmitted: isRegister
                              ? null
                              : (_) => _submit(),
                        ),
                      ],
                      if (isRegister) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          enabled: !_loading,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: context.l10n.confirmPassword,
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? context.l10n.passwordsDoNotMatch
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _messageIsError
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isRegister
                                    ? context.l10n.register
                                    : isForgot
                                    ? context.l10n.sendResetEmail
                                    : context.l10n.login,
                              ),
                      ),
                      if (_mode == _AuthMode.login) ...[
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _setMode(_AuthMode.forgotPassword),
                          child: Text(context.l10n.forgotPassword),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _setMode(_AuthMode.register),
                          child: Text(context.l10n.createAccount),
                        ),
                      ] else
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _setMode(_AuthMode.login),
                          child: Text(context.l10n.backToLogin),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UpdatePasswordPage extends StatefulWidget {
  const UpdatePasswordPage({super.key});

  @override
  State<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends State<UpdatePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _authService = const AuthService();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _authService.updatePassword(_passwordController.text);
      await _authService.logout();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.setNewPassword)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        labelText: context.l10n.newPassword,
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) => (value ?? '').length < 8
                          ? context.l10n.minimumEightCharacters
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _save,
                      child: Text(
                        _loading
                            ? context.l10n.updating
                            : context.l10n.updatePassword,
                      ),
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
