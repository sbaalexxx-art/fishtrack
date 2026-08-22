import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.now();

  test('Baziaș report is excluded from Bristol context', () {
    final local = filterFishingScoreLocalPosts(
      [_post('bazias', 44.816, 21.391, now, CommunityPostType.report)],
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(local, isEmpty);
  });

  test('Bristol report and catch use the same locality rule', () {
    final local = filterFishingScoreLocalPosts(
      [
        _post('report', 51.46, -2.58, now, CommunityPostType.report),
        _post('catch', 51.45, -2.59, now, CommunityPostType.catchPost),
        _post('distant-catch', 44.82, 21.39, now, CommunityPostType.catchPost),
      ],
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(local.map((post) => post.id), ['report', 'catch']);
    expect(local.any((post) => post.isActiveReport), isTrue);
    expect(
      local.any((post) => post.type == CommunityPostType.catchPost),
      isTrue,
    );
  });
}

CommunityPost _post(
  String id,
  double latitude,
  double longitude,
  DateTime now,
  CommunityPostType type,
) => CommunityPost(
  id: id,
  userId: 'user',
  type: type,
  title: type == CommunityPostType.report ? 'Activity' : 'Pike',
  body: 'Evidence',
  createdAt: now.subtract(const Duration(hours: 1)),
  authorName: 'Angler',
  reportCategory: type == CommunityPostType.report
      ? ReportCategory.fishActivity
      : null,
  latitude: latitude,
  longitude: longitude,
  expiresAt: type == CommunityPostType.report
      ? now.add(const Duration(hours: 8))
      : null,
);
