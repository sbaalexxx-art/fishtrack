import 'package:flutter/material.dart';

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
              _message = 'Check your email to confirm your account.';
            });
          }
        case _AuthMode.forgotPassword:
          await _authService.sendPasswordReset(_emailController.text);
          if (mounted) {
            setState(() {
              _mode = _AuthMode.login;
              _messageIsError = false;
              _message = 'Password reset instructions were sent by email.';
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
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    if ((value ?? '').length < 8) return 'Use at least 8 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _AuthMode.register;
    final isForgot = _mode == _AuthMode.forgotPassword;
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12D8D6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        textTheme: theme.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1C1C1E),
          labelStyle: TextStyle(color: Colors.white70),
          hintStyle: TextStyle(color: Colors.white60),
          prefixIconColor: Colors.white70,
          suffixIconColor: Colors.white70,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
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
                            ? 'Create account'
                            : isForgot
                            ? 'Reset password'
                            : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isForgot
                            ? 'We will send recovery instructions to your email.'
                            : 'Sign in to continue to AIFishMap.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      if (isRegister) ...[
                        TextFormField(
                          controller: _nameController,
                          enabled: !_loading,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Name',
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
                        decoration: const InputDecoration(
                          labelText: 'Email',
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
                            labelText: 'Password',
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
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? 'Passwords do not match'
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
                                    ? 'Register'
                                    : isForgot
                                    ? 'Send reset email'
                                    : 'Login',
                              ),
                      ),
                      if (_mode == _AuthMode.login) ...[
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _setMode(_AuthMode.forgotPassword),
                          child: const Text('Forgot password?'),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _setMode(_AuthMode.register),
                          child: const Text('Create an account'),
                        ),
                      ] else
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _setMode(_AuthMode.login),
                          child: const Text('Back to login'),
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
      appBar: AppBar(title: const Text('Set new password')),
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
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) => (value ?? '').length < 8
                          ? 'Use at least 8 characters'
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
                      child: Text(_loading ? 'Updating…' : 'Update password'),
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
