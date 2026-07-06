// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AIFishMap';

  @override
  String get home => 'Home';

  @override
  String get map => 'Map';

  @override
  String get fishingMap => 'Fishing Map';

  @override
  String get waterLevel => 'Water Level';

  @override
  String get waterLevels => 'Water Levels';

  @override
  String get stationDetails => 'Station Details';

  @override
  String get weather => 'Weather';

  @override
  String get fishingInsights => 'Fishing Insights';

  @override
  String get reports => 'Reports';

  @override
  String get reportsArchive => 'Reports Archive';

  @override
  String get recentCatches => 'Recent Catches';

  @override
  String get favorites => 'Favorites';

  @override
  String get favouriteStations => 'Favourite Stations';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationPreferences => 'Notification Preferences';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get community => 'Community';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get cancel => 'Cancel';

  @override
  String get apply => 'Apply';

  @override
  String get reset => 'Reset';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get loading => 'Loading…';

  @override
  String get noData => 'No data';

  @override
  String get errorGeneric => 'Something went wrong. Try again.';

  @override
  String get unavailable => 'Currently unavailable.';

  @override
  String get noFavouriteStations => 'No favourite stations yet.';

  @override
  String get waterProviderUnavailable =>
      'Water provider is currently unavailable.';

  @override
  String get noWaterData => 'No water data is currently available.';

  @override
  String get weatherUnavailable => 'Weather is currently unavailable.';

  @override
  String get noRecentCatches => 'No recent catches.';

  @override
  String get recentCatchesLoadError => 'Recent catches could not be loaded.';

  @override
  String get noComments => 'No comments yet.';

  @override
  String get commentsUnavailable => 'Comments are currently unavailable.';

  @override
  String get report => 'Report';

  @override
  String get reportAbuse => 'Report Abuse';

  @override
  String get createReport => 'Create Report';

  @override
  String get reportSubmitted => 'Report submitted for review.';

  @override
  String get noReports => 'No reports for this period.';

  @override
  String get noCategoryData => 'No category data for this period.';

  @override
  String get reportCategory => 'Report category';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get useExactLocation => 'Use exact location';

  @override
  String get approximateLocationHint =>
      'Disable to share an approximate location';

  @override
  String get positiveFactors => 'Positive factors';

  @override
  String get negativeFactors => 'Negative factors';

  @override
  String get bestTimeWindow => 'Best time window';

  @override
  String get missingData => 'Missing data';

  @override
  String get noSignificantFactors => 'No significant factors available.';

  @override
  String confidence(int value) {
    return 'Confidence: $value%';
  }

  @override
  String get goldenHour => 'Golden hour';

  @override
  String goldenHourValue(String value) {
    return 'Golden hour: $value';
  }

  @override
  String get coordinates => 'Coordinates';

  @override
  String get waterLevelHistory => 'Water level history';

  @override
  String get aiWaterInsight => 'AI water insight';

  @override
  String monitoredStations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count monitored stations',
      one: '1 monitored station',
    );
    return '$_temp0';
  }

  @override
  String days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String reportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports',
      one: '1 report',
    );
    return '$_temp0';
  }

  @override
  String likes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count likes',
      one: '1 like',
    );
    return '$_temp0';
  }

  @override
  String get comments => 'Comments';

  @override
  String get addComment => 'Add a comment';

  @override
  String get catchDetails => 'Catch Details';

  @override
  String get anglerProfile => 'Angler Profile';

  @override
  String get profileUnavailable => 'Profile is unavailable.';

  @override
  String get addCatch => 'Add Catch';

  @override
  String get species => 'Species';

  @override
  String get weight => 'Weight';

  @override
  String get weightUnit => 'Weight unit';

  @override
  String get lengthCm => 'Length (cm)';

  @override
  String get notes => 'Notes';

  @override
  String get placeNameOptional => 'Place name (optional with GPS)';

  @override
  String get placeHint => 'Lake, river, reservoir, canal…';

  @override
  String get waterType => 'Water type';

  @override
  String get locationPrivacy => 'Location privacy';

  @override
  String get camera => 'Camera';

  @override
  String get name => 'Name';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get createAccount => 'Create an account';

  @override
  String get backToLogin => 'Back to login';

  @override
  String get setNewPassword => 'Set new password';

  @override
  String get newPassword => 'New password';

  @override
  String get updating => 'Updating…';

  @override
  String get updatePassword => 'Update password';

  @override
  String get logout => 'Logout';

  @override
  String get changeAvatar => 'Change avatar';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get startTime => 'Start time';

  @override
  String get endTime => 'End time';

  @override
  String get groupSimilarNotifications => 'Group similar notifications';

  @override
  String get duplicateCooldown => 'Duplicate cooldown';

  @override
  String get notificationPreferencesTooltip => 'Notification preferences';

  @override
  String get clearReadNotifications => 'Clear read notifications';

  @override
  String get standard => 'Standard';

  @override
  String get satellite => 'Satellite';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get fishingMode => 'Fishing Mode';

  @override
  String get riverAndLake => 'River & lake';

  @override
  String get river => 'River';

  @override
  String get lake => 'Lake';

  @override
  String get allSpecies => 'All species';

  @override
  String get gpsRadius => 'GPS radius';

  @override
  String get anyDistance => 'Any distance';

  @override
  String get filterByWaterLevel => 'Filter by water level';

  @override
  String get waterTrend => 'Water trend';

  @override
  String get difficulty => 'Difficulty';

  @override
  String get anyDifficulty => 'Any difficulty';

  @override
  String get easy => 'Easy';

  @override
  String get moderate => 'Moderate';

  @override
  String get hard => 'Hard';

  @override
  String get favoritesOnly => 'Favorites only';

  @override
  String get searchStation => 'Search station name…';

  @override
  String get noStationFound => 'No station found.';

  @override
  String get stationSearchUnavailable => 'Station search is unavailable.';

  @override
  String get viewAll => 'View all';

  @override
  String get retryRecentCatches => 'Retry recent catches';

  @override
  String get youAreHere => 'You are here';
}
