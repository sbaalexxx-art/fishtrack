import 'package:fishtrack/services/notification_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overnight quiet hours span midnight', () {
    const preferences = NotificationPreferences(quietHoursEnabled: true);

    expect(preferences.isQuietAt(DateTime(2026, 7, 6, 23)), isTrue);
    expect(preferences.isQuietAt(DateTime(2026, 7, 7, 6, 59)), isTrue);
    expect(preferences.isQuietAt(DateTime(2026, 7, 7, 12)), isFalse);
  });

  test('categories can be independently disabled', () {
    final categories = {...NotificationCategory.values}
      ..remove(NotificationCategory.communityReports);
    final preferences = const NotificationPreferences().copyWith(
      enabledCategories: categories,
    );

    expect(
      preferences.isCategoryEnabled(NotificationCategory.communityReports),
      isFalse,
    );
    expect(
      preferences.isCategoryEnabled(NotificationCategory.dangerousReports),
      isTrue,
    );
  });

  test('preferences serialize future-ready settings', () {
    const preferences = NotificationPreferences(
      quietHoursEnabled: true,
      groupingEnabled: false,
      cooldown: Duration(minutes: 30),
    );
    final json = preferences.toJson();

    expect(json['quiet_hours_enabled'], isTrue);
    expect(json['grouping_enabled'], isFalse);
    expect(json['cooldown_minutes'], 30);
  });
}
