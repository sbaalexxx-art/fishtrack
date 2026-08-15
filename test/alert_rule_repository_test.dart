import 'package:fishtrack/services/alert_rule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('alert rules persist, update and delete locally', () async {
    const repository = AlertRuleRepository();
    final createdAt = DateTime.utc(2026, 8, 1, 12);
    final rule = AlertRule(
      id: 'rule-1',
      entityId: 'station-1',
      entityLabel: 'Test station',
      kind: AlertRuleKind.rapidChange,
      createdAt: createdAt,
    );

    await repository.save(rule);
    var loaded = await repository.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.entityId, 'station-1');
    expect(loaded.single.enabled, isTrue);

    await repository.save(rule.copyWith(enabled: false));
    loaded = await repository.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.enabled, isFalse);

    await repository.remove(rule.id);
    expect(await repository.load(), isEmpty);
  });
}
