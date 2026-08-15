import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/core/context/environmental_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('explicit country context is independent from GPS fallback', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(contentRegionProvider), isNull);

    await container
        .read(contentRegionProvider.notifier)
        .selectCountry(countryCode: 'ro', region: 'Romania');

    final explicit = container.read(contentRegionProvider);

    expect(explicit?.countryCode, 'RO');
    expect(explicit?.region, 'Romania');
    expect(explicit?.source, ContentRegionSource.explicitSelection);
    expect(explicit?.isExplicit, isTrue);

    await container.read(contentRegionProvider.notifier).useDeviceLocation();

    expect(container.read(contentRegionProvider), isNull);
  });

  test(
    'explicit country context persists across provider recreation',
    () async {
      final first = ProviderContainer();

      await first
          .read(contentRegionProvider.notifier)
          .selectCountry(countryCode: 'GB', region: 'England');

      expect(first.read(contentRegionProvider)?.countryCode, 'GB');
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);

      // Reading starts persisted-region restoration.
      second.read(contentRegionProvider);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final restored = second.read(contentRegionProvider);

      expect(restored?.countryCode, 'GB');
      expect(restored?.region, 'England');
      expect(restored?.source, ContentRegionSource.explicitSelection);
    },
  );
}
