import 'package:flutter/material.dart';

import '../../../core/navigation/app_destination.dart';
import '../../commercial_home/data/commercial_home_data_source.dart';
import '../../hydro_dispatch/presentation/hydro_dispatch_canonical_route.dart';
import '../../../models/catch.dart';
import '../../../models/station.dart';
import '../../../models/water_asset.dart';
import '../../../models/water_river.dart';
import '../../../services/alert_rule_repository.dart';
import '../../../services/billing_repository.dart';
import '../../../services/community_service.dart';
import '../../../services/weather_alert_rule_repository.dart';
import '../../../screens/notification_preferences_page.dart';
import '../../../screens/map_page.dart';
import '../../../core/navigation/map_entry.dart';
import '../../../core/navigation/water_entry.dart';
import 'figma_account_pages.dart';
import 'figma_community_pages.dart';
import 'figma_environment_pages.dart';
import 'figma_misc_pages.dart';

abstract final class FigmaDestinationRouter {
  static Widget page(
    AppDestination destination, {
    Object? arguments,
    CommercialHomeDataSource? dataSource,
  }) => switch (destination) {
    AppDestination.search => const FigmaGlobalSearchPage(),
    AppDestination.contextualMap => ContextualMapPage(
      entry: arguments is ContextualMapEntry ? arguments : null,
    ),
    AppDestination.notifications => const FigmaNotificationCenterPage(),
    AppDestination.notificationPreferences =>
      const NotificationPreferencesPage(),
    AppDestination.water => FigmaWaterHubPage(
      initialStation: arguments is WaterHubRequest
          ? arguments.initialStation
          : arguments is Station
          ? arguments
          : null,
      entryMode: arguments is WaterHubRequest
          ? arguments.entryMode
          : WaterHubEntryMode.overview,
      dataSource: dataSource,
    ),
    AppDestination.station => FigmaStationPage(
      station: arguments is Station ? arguments : null,
    ),
    AppDestination.river => FigmaRiverPage(
      river: arguments is WaterRiverRef ? arguments : null,
    ),
    AppDestination.reservoir => FigmaReservoirPage(
      asset: arguments is WaterAssetRef ? arguments : null,
      label: arguments is String ? arguments : null,
    ),
    AppDestination.hydropower => HydroDispatchCanonicalRoute(
      plantLabel: arguments is String ? arguments : null,
      child: FigmaHydropowerPage(label: arguments is String ? arguments : null),
    ),
    AppDestination.weather => FigmaWeatherHubPage(
      initialStation: arguments is Station ? arguments : null,
      dataSource: dataSource,
    ),
    AppDestination.fluvi => FigmaFluviHubPage(
      initialStation: arguments is Station ? arguments : null,
      dataSource: dataSource,
    ),
    AppDestination.askFluvi => FigmaAskFluviPage(dataSource: dataSource),
    AppDestination.community => const FigmaCommunityPage(),
    AppDestination.reportDetail => FigmaReportDetailsPage(
      post: arguments is CommunityPost ? arguments : null,
    ),
    AppDestination.reportConfirmed => FigmaReportConfirmedPage(
      stillValid: arguments is bool ? arguments : true,
    ),
    AppDestination.addReport => FigmaAddReportPage(
      initialCategory: arguments is ReportCategory ? arguments : null,
    ),
    AppDestination.myReports => const FigmaReportsArchivePage(),
    AppDestination.catches ||
    AppDestination.myCatches => const FigmaCatchesPage(),
    AppDestination.addCatch => const FigmaAddCatchPage(),
    AppDestination.catchDetail => FigmaCatchDetailsPage(
      catchItem: arguments is Catch ? arguments : null,
      communityCatch:
          arguments is CommunityPost &&
              arguments.type == CommunityPostType.catchPost
          ? arguments
          : null,
      label: arguments is String ? arguments : null,
    ),
    AppDestination.journal => const FigmaJournalPage(),
    AppDestination.favorites => const FigmaFavoritesPage(),
    AppDestination.favoriteCollection => FigmaFavoriteCollectionPage(
      label: arguments is String ? arguments : null,
    ),
    AppDestination.alerts => const FigmaAlertsPage(),
    AppDestination.newAlert => FigmaAlertEditorPage(
      station: arguments is Station ? arguments : null,
      waterAsset: arguments is WaterAssetRef ? arguments : null,
      waterRiver: arguments is WaterRiverRef ? arguments : null,
      weatherTarget: arguments is WeatherAlertTarget ? arguments : null,
    ),
    AppDestination.editAlert => FigmaAlertEditorPage(
      rule: arguments is AlertRule ? arguments : null,
    ),
    AppDestination.toolkit => const FigmaToolkitPage(),
    AppDestination.permit => const FigmaRegulationsPage(initialTab: 0),
    AppDestination.regulations => const FigmaRegulationsPage(initialTab: 1),
    AppDestination.safety => const FigmaRegulationsPage(initialTab: 2),
    AppDestination.profile => const FigmaProfilePage(),
    AppDestination.accountSecurity => const FigmaAccountSecurityPage(),
    AppDestination.premium ||
    AppDestination.restore => const FigmaPremiumPage(),
    AppDestination.premiumRestored => FigmaRestoreResultPage(
      result: arguments is BillingRestoreResult
          ? arguments
          : BillingRestoreResult.unavailable,
    ),
    AppDestination.support => const FigmaLegalSupportPage(
      focus: AppDestination.support,
    ),
    AppDestination.privacy => const FigmaLegalSupportPage(
      focus: AppDestination.privacy,
    ),
    AppDestination.terms => const FigmaLegalSupportPage(
      focus: AppDestination.terms,
    ),
    AppDestination.licences => const FigmaLegalSupportPage(
      focus: AppDestination.licences,
    ),
    AppDestination.about => const FigmaLegalSupportPage(
      focus: AppDestination.about,
    ),
    AppDestination.moderation => const FigmaLegalSupportPage(
      focus: AppDestination.moderation,
    ),
    AppDestination.aiTransparency => const FigmaLegalSupportPage(
      focus: AppDestination.aiTransparency,
    ),
    AppDestination.legal => const FigmaLegalSupportPage(),
    AppDestination.settings => const FigmaSettingsPage(),
    AppDestination.recovery => const FigmaAccountSecurityPage(),
    AppDestination.home ||
    AppDestination.map ||
    AppDestination.activity ||
    AppDestination.utilities => const SizedBox.shrink(),
  };
}
