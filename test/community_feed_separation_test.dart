import 'package:fishtrack/core/cache/timed_cache.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/screens/reports_page.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/widgets/home_premium/home_premium_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'separates the feed and matches the real community shell geometry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var loadCount = 0;
      final textScale = ValueNotifier<double>(1.4);
      final shellInsets = ValueNotifier<EdgeInsets>(
        const EdgeInsets.only(top: 24, bottom: 24),
      );
      addTearDown(textScale.dispose);
      addTearDown(shellInsets.dispose);

      final l10n = await AppLocalizations.delegate.load(const Locale('ro'));
      final reportNoun = l10n.createReport.trim().split(' ').last;
      final compactReportLabel =
          '${reportNoun[0].toUpperCase()}${reportNoun.substring(1)}';
      final catchNoun = l10n.addCatch.trim().split(' ').last;
      final compactCatchLabel =
          '${catchNoun[0].toUpperCase()}${catchNoun.substring(1)}';
      final posts = <CommunityPost>[
        _post(
          id: 'catch-1',
          type: CommunityPostType.catchPost,
          title: 'CATCH_ONLY_MARKER',
          body: 'CATCH_BODY_MARKER',
          weight: 2.4,
          length: 58,
          likeCount: 12,
        ),
        _post(
          id: 'report-1',
          type: CommunityPostType.report,
          title: ReportCategory.highWater.label,
          body: 'REPORT_ONLY_MARKER',
          reportCategory: ReportCategory.highWater,
          latitude: 44.1234,
          longitude: 22.5678,
          stillValidCount: 7,
          noLongerValidCount: 2,
        ),
        _post(
          id: 'report-2',
          type: CommunityPostType.report,
          title: ReportCategory.lowWater.label,
          body: 'SECOND_REPORT_MARKER',
          reportCategory: ReportCategory.lowWater,
        ),
        _post(
          id: 'report-3',
          type: CommunityPostType.report,
          title: ReportCategory.strongCurrent.label,
          body: 'THIRD_REPORT_MARKER',
          reportCategory: ReportCategory.strongCurrent,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          locale: const Locale('ro'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ValueListenableBuilder<double>(
            valueListenable: textScale,
            builder: (context, scale, _) => ValueListenableBuilder<EdgeInsets>(
              valueListenable: shellInsets,
              builder: (context, insets, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: insets,
                  viewPadding: insets,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
          home: _ProductionCommunityShell(
            feedLoader: ({required forceRefresh}) async {
              loadCount += 1;
              return CacheResult<List<CommunityPost>>(posts);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstReportCard = find.byKey(
        const ValueKey('report-card-report-1'),
      );
      final secondReportCard = find.byKey(
        const ValueKey('report-card-report-2'),
      );
      final thirdReportCard = find.byKey(
        const ValueKey('report-card-report-3'),
      );
      final catchCard = find.byKey(const ValueKey('catch-card-catch-1'));
      final reportAppBarAction = find.byKey(
        const Key('community-report-appbar-action'),
      );
      final catchAppBarAction = find.byKey(
        const Key('community-catch-appbar-action'),
      );
      final bottomNavigationShell = find.byKey(
        const Key('test-bottom-navigation-shell'),
      );
      final confirmAction = find.descendant(
        of: firstReportCard,
        matching: find.byKey(const Key('report-confirm-action')),
      );
      final notAccurateAction = find.descendant(
        of: firstReportCard,
        matching: find.byKey(const Key('report-not-accurate-action')),
      );

      expect(find.text('REPORT_ONLY_MARKER'), findsOneWidget);
      expect(find.text('CATCH_ONLY_MARKER'), findsNothing);
      expect(firstReportCard, findsOneWidget);
      expect(secondReportCard, findsOneWidget);
      expect(thirdReportCard, findsOneWidget);
      expect(reportAppBarAction, findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text(l10n.reportCategoryHighWater), findsOneWidget);
      expect(find.text(l10n.approximateLocation), findsOneWidget);
      expect(find.textContaining('44.123'), findsNothing);
      expect(find.textContaining('22.568'), findsNothing);

      final reportTooltip = tester.widget<Tooltip>(
        find.ancestor(of: reportAppBarAction, matching: find.byType(Tooltip)),
      );
      expect(reportTooltip.message, l10n.createReport);
      expect(
        find.descendant(
          of: reportAppBarAction,
          matching: find.text(compactReportLabel),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(reportAppBarAction).height, 48);
      expect(
        tester
            .getRect(
              find.byKey(const Key('community-report-appbar-action-surface')),
            )
            .height,
        40,
      );

      final portraitFirstRect = tester.getRect(firstReportCard);
      final portraitSecondRect = tester.getRect(secondReportCard);
      final portraitThirdRect = tester.getRect(thirdReportCard);
      final portraitNavigationTop = tester.getRect(bottomNavigationShell).top;
      expect(portraitFirstRect.height, lessThanOrEqualTo(180));
      expect(portraitSecondRect.height, lessThanOrEqualTo(180));
      expect(portraitThirdRect.height, lessThanOrEqualTo(180));
      expect(
        portraitSecondRect.bottom,
        lessThanOrEqualTo(portraitNavigationTop),
      );
      final visibleThirdBottom =
          portraitThirdRect.bottom < portraitNavigationTop
          ? portraitThirdRect.bottom
          : portraitNavigationTop;
      expect(
        visibleThirdBottom - portraitThirdRect.top,
        greaterThanOrEqualTo(portraitThirdRect.height * .8),
      );
      expect(
        tester.getRect(find.byKey(const Key('community-feed-selector'))).height,
        lessThanOrEqualTo(52),
      );

      final portraitDescription = tester.widget<Text>(
        find.text('REPORT_ONLY_MARKER'),
      );
      expect(portraitDescription.maxLines, 2);
      expect(portraitDescription.overflow, TextOverflow.ellipsis);
      expect(tester.getRect(confirmAction).height, 48);
      expect(tester.getRect(notAccurateAction).height, 48);
      expect(
        tester.getRect(confirmAction).right,
        lessThanOrEqualTo(tester.getRect(notAccurateAction).left),
      );
      expect(tester.takeException(), isNull);
      expect(loadCount, 1);

      await tester.tap(
        find.descendant(
          of: firstReportCard,
          matching: find.byKey(const Key('report-overflow-action')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.reportAbuse), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.catches));
      await tester.pumpAndSettle();
      expect(find.text('CATCH_ONLY_MARKER'), findsOneWidget);
      expect(find.text('REPORT_ONLY_MARKER'), findsNothing);
      expect(catchCard, findsOneWidget);
      expect(catchAppBarAction, findsOneWidget);
      expect(
        find.descendant(
          of: catchAppBarAction,
          matching: find.text(compactCatchLabel),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(catchAppBarAction).height, 48);
      expect(
        tester
            .getRect(
              find.byKey(const Key('community-catch-appbar-action-surface')),
            )
            .height,
        40,
      );
      final portraitAppBarRect = tester.getRect(
        find.byKey(const Key('community-app-bar')),
      );
      expect(
        tester.getRect(catchAppBarAction).bottom,
        lessThanOrEqualTo(portraitAppBarRect.bottom),
      );
      expect(
        tester
            .getRect(catchAppBarAction)
            .overlaps(tester.getRect(bottomNavigationShell)),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      expect(loadCount, 1);

      Future<void> verifyLandscape({
        required Size size,
        required EdgeInsets insets,
        required double scale,
      }) async {
        tester.view.physicalSize = size;
        shellInsets.value = insets;
        textScale.value = scale;
        await tester.pumpAndSettle();

        if (find.text('CATCH_ONLY_MARKER').evaluate().isNotEmpty) {
          await tester.tap(find.text(l10n.reports));
          await tester.pumpAndSettle();
        }

        expect(find.text('REPORT_ONLY_MARKER'), findsOneWidget);
        expect(find.text('CATCH_ONLY_MARKER'), findsNothing);
        expect(reportAppBarAction, findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);

        final firstRect = tester.getRect(firstReportCard);
        final secondRect = tester.getRect(secondReportCard);
        final actionRect = tester.getRect(reportAppBarAction);
        final navigationRect = tester.getRect(bottomNavigationShell);
        final listRect = tester.getRect(
          find.byKey(const Key('community-feed-list')),
        );
        final selectorRect = tester.getRect(
          find.byKey(const Key('community-feed-selector')),
        );
        final appBarRect = tester.getRect(
          find.byKey(const Key('community-app-bar')),
        );

        expect(firstRect.height, closeTo(98, .1));
        expect(secondRect.height, closeTo(98, .1));
        if (scale <= 1) {
          expect(firstRect.height, lessThanOrEqualTo(104));
          expect(secondRect.height, lessThanOrEqualTo(104));
        }
        expect(firstRect.top, greaterThanOrEqualTo(listRect.top));
        expect(
          secondRect.bottom,
          lessThanOrEqualTo(listRect.bottom),
          reason:
              'Cardul doi trebuie să se termine în viewport: '
              '$secondRect versus $listRect.',
        );
        expect(secondRect.bottom, lessThanOrEqualTo(navigationRect.top));
        expect(firstRect.overlaps(navigationRect), isFalse);
        expect(secondRect.overlaps(navigationRect), isFalse);

        expect(selectorRect.height, closeTo(48, .1));
        expect(appBarRect.height, closeTo(insets.top + 48, .1));
        expect(selectorRect.right, lessThanOrEqualTo(actionRect.left));
        final usableWidth = size.width - insets.horizontal;
        final reportActionLabel = find.descendant(
          of: reportAppBarAction,
          matching: find.text(compactReportLabel),
        );
        expect(
          reportActionLabel,
          usableWidth >= 680 ? findsOneWidget : findsNothing,
        );
        expect(actionRect.height, 48);
        expect(
          tester
              .getRect(
                find.byKey(const Key('community-report-appbar-action-surface')),
              )
              .height,
          40,
        );
        expect(actionRect.bottom, lessThanOrEqualTo(appBarRect.bottom));
        final titleSemantics = tester.widget<Semantics>(
          find.byKey(const Key('community-landscape-title-semantics')),
        );
        expect(titleSemantics.properties.label, l10n.community);

        expect(
          tester.getRect(find.text(l10n.approximateLocation)).bottom,
          lessThanOrEqualTo(firstRect.bottom),
        );
        expect(
          tester.getRect(confirmAction).right,
          lessThanOrEqualTo(tester.getRect(notAccurateAction).left),
        );
        expect(tester.getRect(confirmAction).height, 48);
        expect(tester.getRect(notAccurateAction).height, 48);
        expect(
          tester.getRect(notAccurateAction).bottom,
          lessThanOrEqualTo(firstRect.bottom),
        );
        final description = tester.widget<Text>(
          find.text('REPORT_ONLY_MARKER'),
        );
        expect(description.maxLines, 1);
        expect(description.overflow, TextOverflow.ellipsis);

        final overflow = find.descendant(
          of: firstReportCard,
          matching: find.byKey(const Key('report-overflow-action')),
        );
        expect(overflow, findsOneWidget);
        expect(firstRect.contains(tester.getCenter(overflow)), isTrue);
        expect(actionRect.overlaps(navigationRect), isFalse);
        expect(tester.takeException(), isNull);
        expect(loadCount, 1);

        await tester.tap(find.text(l10n.catches));
        await tester.pumpAndSettle();

        expect(find.text('CATCH_ONLY_MARKER'), findsOneWidget);
        expect(find.text('CATCH_BODY_MARKER'), findsOneWidget);
        expect(find.text('REPORT_ONLY_MARKER'), findsNothing);
        expect(catchCard, findsOneWidget);
        expect(catchAppBarAction, findsOneWidget);

        final catchRect = tester.getRect(catchCard);
        final catchListRect = tester.getRect(
          find.byKey(const Key('community-feed-list')),
        );
        final catchActionRect = tester.getRect(catchAppBarAction);
        final catchSelectorRect = tester.getRect(
          find.byKey(const Key('community-feed-selector')),
        );
        final thumbnailRect = tester.getRect(
          find.byKey(const ValueKey('catch-card-thumbnail-catch-1')),
        );
        final catchTitleRect = tester.getRect(
          find.byKey(const ValueKey('catch-card-title-catch-1')),
        );

        expect(catchRect.height, inInclusiveRange(110, 140));
        expect(catchRect.top, greaterThanOrEqualTo(catchListRect.top));
        expect(catchRect.bottom, lessThanOrEqualTo(catchListRect.bottom));
        expect(catchRect.bottom, lessThanOrEqualTo(navigationRect.top));
        expect(catchRect.overlaps(navigationRect), isFalse);
        expect(thumbnailRect.left, closeTo(catchRect.left, .1));
        expect(thumbnailRect.right, lessThanOrEqualTo(catchTitleRect.left));
        expect(
          find.descendant(
            of: catchCard,
            matching: find.byIcon(Icons.favorite_border_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: catchCard,
            matching: find.byIcon(Icons.chat_bubble_outline_rounded),
          ),
          findsOneWidget,
        );
        final catchActionLabel = find.descendant(
          of: catchAppBarAction,
          matching: find.text(compactCatchLabel),
        );
        expect(
          catchActionLabel,
          usableWidth >= 680 ? findsOneWidget : findsNothing,
        );
        expect(catchActionRect.height, 48);
        expect(
          tester
              .getRect(
                find.byKey(const Key('community-catch-appbar-action-surface')),
              )
              .height,
          40,
        );
        expect(
          catchSelectorRect.right,
          lessThanOrEqualTo(catchActionRect.left),
        );
        expect(catchActionRect.bottom, lessThanOrEqualTo(appBarRect.bottom));
        expect(catchActionRect.overlaps(navigationRect), isFalse);
        expect(tester.takeException(), isNull);
        expect(loadCount, 1);
      }

      const samsungSideInsets = EdgeInsets.fromLTRB(34.13, 29.87, 48, 0);
      await verifyLandscape(
        size: const Size(832, 384),
        insets: samsungSideInsets,
        scale: 1.4,
      );
      await verifyLandscape(
        size: const Size(844, 390),
        insets: samsungSideInsets,
        scale: 1.4,
      );
      await verifyLandscape(
        size: const Size(844, 390),
        insets: samsungSideInsets,
        scale: 1,
      );
      await verifyLandscape(
        size: const Size(720, 360),
        insets: samsungSideInsets,
        scale: 1.4,
      );
      await verifyLandscape(
        size: const Size(960, 440),
        insets: samsungSideInsets,
        scale: 1,
      );
      await verifyLandscape(
        size: const Size(844, 390),
        insets: const EdgeInsets.fromLTRB(34.13, 29.87, 0, 48),
        scale: 1.4,
      );
      await verifyLandscape(
        size: const Size(1024, 768),
        insets: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        scale: 1.4,
      );
    },
  );
}

class _ProductionCommunityShell extends StatelessWidget {
  const _ProductionCommunityShell({required this.feedLoader});

  final CommunityFeedLoader feedLoader;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final navigationHeight = layout.bottomNavHeight * .86;
    return Scaffold(
      body: IndexedStack(
        index: 0,
        children: [ReportsPage(feedLoader: feedLoader)],
      ),
      bottomNavigationBar: SafeArea(
        key: const Key('test-bottom-navigation-shell'),
        minimum: EdgeInsets.symmetric(
          horizontal: layout.horizontalPadding * .50,
        ),
        child: SizedBox(
          key: const Key('test-bottom-navigation'),
          height: navigationHeight,
        ),
      ),
    );
  }
}

CommunityPost _post({
  required String id,
  required CommunityPostType type,
  required String title,
  String body = '',
  ReportCategory? reportCategory,
  double? latitude,
  double? longitude,
  double? weight,
  double? length,
  int likeCount = 0,
  int stillValidCount = 0,
  int noLongerValidCount = 0,
}) => CommunityPost(
  id: id,
  userId: 'user-$id',
  type: type,
  title: title,
  body: body,
  createdAt: DateTime(2026, 7, 24, 10),
  authorName: 'Test Angler',
  weight: weight,
  length: length,
  likeCount: likeCount,
  reportCategory: reportCategory,
  latitude: latitude,
  longitude: longitude,
  stillValidCount: stillValidCount,
  noLongerValidCount: noLongerValidCount,
);
