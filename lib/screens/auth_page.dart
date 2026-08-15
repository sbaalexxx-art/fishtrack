import 'package:flutter/material.dart';

import '../features/figma_complete/presentation/figma_foundation.dart';
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
            ? 'Completează numele, emailul și o parolă de minimum 6 caractere.'
            : 'Completează emailul și o parolă de minimum 6 caractere.',
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
          setState(
            () => _message =
                'Contul a fost creat. Verifică emailul dacă este necesară confirmarea.',
          );
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
      setState(() => _message = 'Introdu emailul contului.');
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.authService.sendPasswordReset(email);
      if (mounted) {
        setState(
          () => _message = 'Instrucțiunile de recuperare au fost trimise.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FigmaFluviTokens.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: FigmaFluviTokens.pageGradient,
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _showAccess
                ? _buildAccess(context)
                : _buildOnboarding(context),
          ),
        ),
      ),
    );
  }

  Widget _buildOnboarding(BuildContext context) {
    return ListView(
      key: const ValueKey('figma-auth-onboarding'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      children: [
        const Text(
          'FluviAI',
          style: TextStyle(
            color: FigmaFluviTokens.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Apele, vremea și comunitatea într-un singur loc',
          style: figmaBody(size: 14),
        ),
        const SizedBox(height: 18),
        FigmaSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: FigmaFluviTokens.cyan.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(
                    color: FigmaFluviTokens.cyan.withValues(alpha: .24),
                  ),
                ),
                child: const Center(
                  child: Text(
                    '≈',
                    style: TextStyle(
                      color: FigmaFluviTokens.cyan,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Planifică mai bine. Pescuiește mai sigur.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const _OnboardingPoint(label: 'Niveluri și trenduri Water'),
              const _OnboardingPoint(label: 'Weather, Solunar și FluviScore'),
              const _OnboardingPoint(
                label: 'Rapoarte, capturi și locuri salvate',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const FigmaSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FigmaSectionLabel('Experiența ta locală'),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Limba interfeței',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Română  ›',
                    style: TextStyle(
                      color: FigmaFluviTokens.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Țara conținutului',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'România  ›',
                    style: TextStyle(
                      color: FigmaFluviTokens.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FigmaPrimaryButton(
          label: 'Continuă',
          onPressed: () => setState(() => _showAccess = true),
        ),
        const SizedBox(height: 10),
        FigmaPrimaryButton(
          label: 'Am deja cont',
          secondary: true,
          onPressed: () => setState(() => _showAccess = true),
        ),
        const SizedBox(height: 14),
        Text(
          'Continuând, accepți Termenii și confirmi că ai citit Politica de confidențialitate.',
          textAlign: TextAlign.center,
          style: figmaBody(size: 9),
        ),
      ],
    );
  }

  Widget _buildAccess(BuildContext context) {
    return ListView(
      key: const ValueKey('figma-auth-access'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          children: [
            FigmaRoundButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Înapoi',
              onPressed: () => setState(() => _showAccess = false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _register ? 'Creează cont' : 'Bine ai revenit',
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _register
              ? 'Salvează capturi, favorite și alerte personale.'
              : 'Conectează-te la contul tău FluviAI.',
          style: figmaBody(size: 12),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: FigmaPill(
                label: 'Autentificare',
                active: !_register,
                onTap: () => setState(() => _register = false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FigmaPill(
                label: 'Cont nou',
                active: _register,
                onTap: () => setState(() => _register = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FigmaSurface(
          child: Column(
            children: [
              if (_register) ...[
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nume'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Parolă',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Afișează parola' : 'Ascunde parola',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: figmaBody(color: FigmaFluviTokens.amber, size: 11),
          ),
        ],
        const SizedBox(height: 18),
        FigmaPrimaryButton(
          label: _working
              ? 'Se procesează…'
              : (_register ? 'Creează contul' : 'Autentificare'),
          onPressed: _working ? null : _submit,
        ),
        if (!_register) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _working ? null : _resetPassword,
            child: const Text('Am uitat parola'),
          ),
        ],
      ],
    );
  }
}

class _OnboardingPoint extends StatelessWidget {
  const _OnboardingPoint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: FigmaFluviTokens.cyanSoft,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: figmaBody(size: 11))),
      ],
    ),
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
      setState(() => _message = 'Parola trebuie să aibă minimum 6 caractere.');
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.authService.updatePassword(_password.text);
      if (mounted) setState(() => _message = 'Parola a fost actualizată.');
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-update-password'),
      title: 'Recuperare cont',
      eyebrow: 'SECURITATE',
      showBack: false,
      child: ListView(
        children: [
          const FigmaTruthfulEmpty(
            icon: Icons.lock_reset_rounded,
            title: 'Alege o parolă nouă',
            message: 'Linkul de recuperare a deschis o sesiune protejată.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Parolă nouă'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: figmaBody(size: 11),
            ),
          ],
          const SizedBox(height: 18),
          FigmaPrimaryButton(
            label: _working ? 'Se actualizează…' : 'Actualizează parola',
            onPressed: _working ? null : _update,
          ),
        ],
      ),
    );
  }
}
