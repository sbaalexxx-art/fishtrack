import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { automatic, light, dark }

class ThemeController extends ChangeNotifier {
  ThemeController(this._preferences) {
    final saved = _preferences.getString(preferenceKey);
    _preference = AppThemePreference.values.firstWhere(
      (value) => value.name == saved,
      orElse: () => AppThemePreference.automatic,
    );
  }

  static const preferenceKey = 'fluviai_theme_preference';

  final SharedPreferences _preferences;
  late AppThemePreference _preference;

  AppThemePreference get preference => _preference;

  ThemeMode get themeMode => switch (_preference) {
    AppThemePreference.automatic => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  Brightness effectiveBrightness(Brightness platformBrightness) =>
      switch (_preference) {
        AppThemePreference.automatic => platformBrightness,
        AppThemePreference.light => Brightness.light,
        AppThemePreference.dark => Brightness.dark,
      };

  Future<void> setPreference(AppThemePreference preference) async {
    if (preference == _preference) return;
    final saved = await _preferences.setString(preferenceKey, preference.name);
    if (!saved) return;
    _preference = preference;
    notifyListeners();
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller != null) return controller;
    throw FlutterError('ThemeScope.of() called without a ThemeScope ancestor.');
  }

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}
