import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends ChangeNotifier {
  LocaleController(this._preferences) {
    final savedLanguageCode = _preferences.getString(_preferenceKey);
    _languageCode = _supportedLanguageCodes.contains(savedLanguageCode)
        ? savedLanguageCode!
        : _defaultLanguageCode;
  }

  static const _preferenceKey = 'fluviai_language_code';
  static const _defaultLanguageCode = 'ro';
  static const _supportedLanguageCodes = {'ro', 'en'};

  final SharedPreferences _preferences;
  late String _languageCode;

  Locale get locale => Locale(_languageCode);

  String get languageCode => _languageCode;

  Future<void> setLanguageCode(String languageCode) async {
    if (!_supportedLanguageCodes.contains(languageCode) ||
        languageCode == _languageCode) {
      return;
    }

    final saved = await _preferences.setString(_preferenceKey, languageCode);
    if (!saved) return;

    _languageCode = languageCode;
    notifyListeners();
  }
}

class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller != null) return controller;

    throw FlutterError(
      'LocaleScope.of() called with a context that does not contain a '
      'LocaleScope. Wrap the application with LocaleScope before accessing '
      'the locale controller.',
    );
  }

  static LocaleController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LocaleScope>()
        ?.notifier;
  }
}
