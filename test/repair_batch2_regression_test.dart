import 'dart:io';

import 'package:fishtrack/core/context/environmental_context.dart';
import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_account_pages.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_community_pages.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_destination_router.dart';
import 'package:fishtrack/models/catch.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/screens/map_page.dart';
import 'package:fishtrack/screens/notification_preferences_page.dart';
import 'package:fishtrack/services/auth_service.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/favorite_stations_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('report eligibility rejects expired and already-submitted reports', () {
    final active = _report(
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final expired = _report(
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    expect(canVerifyCommunityReport(active), isTrue);
    expect(canVerifyCommunityReport(active, alreadySubmitted: true), isFalse);
    expect(canVerifyCommunityReport(expired), isFalse);
  });

  testWidgets('expired report has no contradictory validity actions', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    await _pump(
      tester,
      FigmaReportDetailsPage(
        post: _report(
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        service: service,
      ),
    );

    expect(find.text('Raport expirat'), findsOneWidget);
    expect(find.text('Confirmă'), findsNothing);
    expect(find.text('Nu mai e valabil'), findsNothing);
    expect(service.verifications, isEmpty);
  });

  testWidgets('one successful report vote removes both validity actions', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    await _pump(
      tester,
      FigmaReportDetailsPage(
        post: _report(expiresAt: DateTime.now().add(const Duration(hours: 1))),
        service: service,
      ),
    );

    await tester.tap(find.text('Confirmă'));
    await tester.pumpAndSettle();

    expect(service.verifications, [ReportVerification.stillValid]);
    expect(find.text('Confirmă'), findsNothing);
    expect(find.text('Nu mai e valabil'), findsNothing);
    expect(find.textContaining('Ai confirmat'), findsOneWidget);
  });

  testWidgets('community catch opens populated canonical catch detail', (
    tester,
  ) async {
    final post = CommunityPost(
      id: 'catch-42',
      userId: 'angler',
      type: CommunityPostType.catchPost,
      title: 'Știucă',
      body: 'Captură eliberată',
      createdAt: DateTime(2026, 8, 7),
      authorName: 'Pescar',
      weight: 4.2,
      length: 81,
      latitude: 44.8,
      longitude: 21.4,
    );
    final service = _FakeCommunityService(feed: [post]);
    await _pump(
      tester,
      FigmaCommunityPage(
        service: service,
        localContext: LocalContentContext(
          latitude: 44.8,
          longitude: 21.4,
          radiusKm: 100,
          observedAt: DateTime(2026, 8, 7),
        ),
      ),
    );

    await tester.tap(find.text('Știucă').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('figma-catch-details')), findsOneWidget);
    expect(find.text('4.2 kg'), findsOneWidget);
    expect(find.text('81 cm'), findsOneWidget);
    expect(find.text('7.8.2026'), findsOneWidget);
  });

  testWidgets('real catch share gives truthful unavailable feedback', (
    tester,
  ) async {
    await _pump(
      tester,
      FigmaCatchDetailsPage(
        catchItem: Catch(
          id: 'catch-1',
          stationId: 'station-1',
          species: 'Crap',
          weight: 3.5,
          length: 64,
          date: DateTime(2026, 8, 7),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Distribuirea nu este conectată în această versiune. Nu s-a trimis nimic.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Add Report uses auth state and enforces truth validation', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    await _pump(
      tester,
      FigmaAddReportPage(
        service: service,
        authService: const _FakeAuthService(true),
      ),
      size: const Size(430, 1000),
    );

    expect(find.text('RAPORT COMUNITATE'), findsOneWidget);
    await _tapPublish(tester);
    expect(find.textContaining('Confirmă că informația'), findsOneWidget);
    expect(service.createCalls, 0);
  });

  testWidgets('Add Report exposes service failure without navigating away', (
    tester,
  ) async {
    final service = _FakeCommunityService(
      createError: const CommunityException('Publicarea nu este disponibilă.'),
    );
    await _pump(
      tester,
      FigmaAddReportPage(
        service: service,
        authService: const _FakeAuthService(true),
      ),
      size: const Size(430, 1000),
    );

    await _confirmAndPublish(tester);
    expect(find.text('Publicarea nu este disponibilă.'), findsOneWidget);
    expect(find.byKey(const ValueKey('figma-add-report')), findsOneWidget);
  });

  testWidgets('Add Report keeps coherent success state until explicit close', (
    tester,
  ) async {
    final service = _FakeCommunityService(createdId: 'report-real-7');
    await _pump(
      tester,
      FigmaAddReportPage(
        service: service,
        authService: const _FakeAuthService(true),
      ),
      size: const Size(430, 1000),
    );

    await _confirmAndPublish(tester);
    expect(
      find.text('Raport publicat cu succes. ID: report-real-7'),
      findsOneWidget,
    );
    expect(find.text('Închide'), findsWidgets);
    expect(find.byKey(const ValueKey('figma-add-report')), findsOneWidget);
  });

  testWidgets('unauthenticated Add Report does not call publish service', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    await _pump(
      tester,
      FigmaAddReportPage(
        service: service,
        authService: const _FakeAuthService(false),
      ),
      size: const Size(430, 1000),
    );

    expect(find.text('AUTENTIFICARE NECESARĂ'), findsOneWidget);
    await _tapPublish(tester);
    expect(find.textContaining('Autentifică-te'), findsOneWidget);
    expect(service.createCalls, 0);
  });

  testWidgets('Favorites shows real saved stations only under Stations', (
    tester,
  ) async {
    final favorites = _FakeFavoritesService(ids: {'station-1'});
    await _pump(
      tester,
      FigmaFavoritesPage(
        favoritesService: favorites,
        waterService: _FakeWaterService([_station()]),
      ),
    );

    expect(find.text('Baziaș · Dunărea'), findsOneWidget);
    expect(find.text('Adaugă stație din hartă'), findsOneWidget);
    await tester.tap(find.text('Ape'));
    await tester.pump();
    expect(find.text('Baziaș · Dunărea'), findsNothing);
  });

  testWidgets('pin preview reflects favorite state and calls toggle', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      Scaffold(
        body: FullMapPinPreviewCard(
          station: _station(),
          isFavorite: true,
          onClose: () {},
          onDetails: () {},
          onFavorite: () => calls++,
          onAlert: () {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Elimină din favorite'));
    expect(calls, 1);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  test('focused notification and legal destinations are registered', () {
    expect(
      AppDestinationRegistry.of(AppDestination.notificationPreferences).path,
      '/settings/notifications',
    );
    expect(
      FigmaDestinationRouter.page(AppDestination.notificationPreferences),
      isA<NotificationPreferencesPage>(),
    );
    expect(
      AppDestinationRegistry.of(AppDestination.moderation).path,
      '/legal/moderation',
    );
    expect(
      AppDestinationRegistry.of(AppDestination.aiTransparency).path,
      '/legal/ai-transparency',
    );
  });

  testWidgets('legal routes expose named focused unavailable states', (
    tester,
  ) async {
    await _pump(tester, FigmaDestinationRouter.page(AppDestination.moderation));
    expect(find.text('Comunitate și moderare'), findsOneWidget);
    expect(find.text('Conținut de moderare indisponibil'), findsOneWidget);

    await _pump(
      tester,
      FigmaDestinationRouter.page(AppDestination.aiTransparency),
    );
    expect(find.text('Transparență AI'), findsOneWidget);
    expect(
      find.text('Conținut de transparență AI indisponibil'),
      findsOneWidget,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(430, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(
          useMaterial3: true,
        ).copyWith(splashFactory: NoSplash.splashFactory),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPublish(WidgetTester tester) async {
  final button = find.text('Publică raportul');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _confirmAndPublish(WidgetTester tester) async {
  final confirmation = find.byKey(
    const ValueKey('add-report-truth-confirmation'),
  );
  await tester.ensureVisible(confirmation);
  await tester.tap(confirmation);
  await tester.pump();
  await _tapPublish(tester);
}

CommunityPost _report({required DateTime expiresAt}) => CommunityPost(
  id: 'report-1',
  userId: 'angler',
  type: CommunityPostType.report,
  title: 'Nivel ridicat',
  body: 'Observație reală',
  createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  authorName: 'Pescar',
  reportCategory: ReportCategory.highWater,
  expiresAt: expiresAt,
);

class _FakeAuthService extends AuthService {
  const _FakeAuthService(this.authenticated);

  final bool authenticated;

  @override
  bool get isAuthenticated => authenticated;
}

class _FakeCommunityService extends CommunityService {
  _FakeCommunityService({
    this.feed = const [],
    this.createdId = 'report-1',
    this.createError,
  });

  final List<CommunityPost> feed;
  final String createdId;
  final CommunityException? createError;
  int createCalls = 0;
  final List<ReportVerification> verifications = [];

  @override
  Future<List<CommunityPost>> getFeed({bool forceRefresh = false}) async =>
      feed;

  @override
  Future<String> createReport({
    required ReportCategory category,
    String? text,
    File? cameraPhoto,
    required bool useExactLocation,
  }) async {
    createCalls++;
    if (createError case final error?) throw error;
    return createdId;
  }

  @override
  Future<void> verifyReport(
    String reportId,
    ReportVerification verification,
  ) async {
    verifications.add(verification);
  }
}

class _FakeFavoritesService extends FavoriteStationsService {
  _FakeFavoritesService({required Set<String> ids}) : _ids = {...ids};

  final Set<String> _ids;

  @override
  bool get isAuthenticated => true;

  @override
  Future<Set<String>> getFavoriteIds() async => {..._ids};

  @override
  Future<bool> setFavorite(String stationId, {required bool favorite}) async {
    favorite ? _ids.add(stationId) : _ids.remove(stationId);
    return favorite;
  }
}

class _FakeWaterService extends WaterService {
  _FakeWaterService(this.stations);

  final List<Station> stations;

  @override
  Future<List<Station>> getStations({bool forceRefresh = false}) async =>
      stations;
}

Station _station() => Station(
  id: 'station-1',
  name: 'Baziaș',
  river: 'Dunărea',
  level: 548,
  trend: WaterTrend.rising,
  latitude: 44.8167,
  longitude: 21.3944,
  lastUpdate: DateTime(2026, 8, 7),
  hasWaterLevel: true,
  hasKnownTrend: true,
  waterLevelSource: 'AFDJ',
);
