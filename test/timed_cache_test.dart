import 'package:fishtrack/core/cache/timed_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns fresh value until duration expires', () async {
    var now = DateTime(2026);
    var calls = 0;
    final cache = TimedCache<int>(
      duration: const Duration(minutes: 5),
      clock: () => now,
    );

    expect((await cache.get(() async => ++calls)).value, 1);
    now = now.add(const Duration(minutes: 4));
    expect((await cache.get(() async => ++calls)).value, 1);
    now = now.add(const Duration(minutes: 2));
    expect((await cache.get(() async => ++calls)).value, 2);
  });

  test('force refresh bypasses fresh cache', () async {
    var calls = 0;
    final cache = TimedCache<int>(duration: const Duration(hours: 1));
    await cache.get(() async => ++calls);
    final result = await cache.get(() async => ++calls, forceRefresh: true);
    expect(result.value, 2);
  });

  test('returns stale cached value after loader failure', () async {
    final cache = TimedCache<int>(duration: Duration.zero);
    await cache.get(() async => 7);
    final result = await cache.get(() async => throw Exception('offline'));
    expect(result.value, 7);
    expect(result.isStaleFallback, isTrue);
  });
}
