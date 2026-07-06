import 'package:fishtrack/services/report_spam_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ReportSpamService();
  final now = DateTime.utc(2026, 7, 6, 12);

  SpamReportHistory history({
    String category = 'highWater',
    String description = 'River is high',
    double latitude = 44.1,
    double longitude = 22.2,
    String? imageHash,
    int minutesAgo = 10,
  }) => SpamReportHistory(
    category: category,
    description: description,
    latitude: latitude,
    longitude: longitude,
    createdAt: now.subtract(Duration(minutes: minutesAgo)),
    imageHash: imageHash,
  );

  test('ordinary report remains normal', () {
    final result = service.assess(
      category: 'waterClarity',
      description: 'Visibility is about one metre near the bank',
      latitude: 44,
      longitude: 22,
      now: now,
      history: const [],
    );

    expect(result.score, 0);
    expect(result.isSuspicious, isFalse);
  });

  test('repeated content and rapid publishing are suspicious', () {
    final result = service.assess(
      category: 'highWater',
      description: 'River is high',
      latitude: 44,
      longitude: 22,
      now: now,
      history: List.generate(4, (index) => history(minutesAgo: index + 1)),
    );

    expect(result.score, 75);
    expect(result.isSuspicious, isTrue);
    expect(result.reason, contains('Repeated description'));
  });

  test('score is capped at 100', () {
    final result = service.assess(
      category: 'highWater',
      description: '!!!',
      latitude: 44.1,
      longitude: 22.2,
      imageHash: 'same',
      now: now,
      history: List.generate(
        8,
        (index) => history(imageHash: 'same', minutesAgo: index + 1),
      ),
    );

    expect(result.score, 100);
    expect(result.isSuspicious, isTrue);
  });
}
