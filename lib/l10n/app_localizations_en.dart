// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FluviAI';

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
  String get fishingInsights => 'FluviAI Radar';

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
  String get homeTagline => 'Smart fishing • Live reports • Trusted community';

  @override
  String get communityEmptyMessage => 'Quiet on the water in this area.';

  @override
  String get communityEmptyCta => 'Be the first to report!';

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
  String get notEnoughData => 'Not enough data yet';

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
  String get signInForNotificationPreferences =>
      'Please sign in to manage notification preferences.';

  @override
  String get categories => 'Categories';

  @override
  String get priority => 'Priority';

  @override
  String get clearReadNotifications => 'Clear read notifications';

  @override
  String get notificationsUnavailable => 'Notifications are unavailable.';

  @override
  String get noNotifications => 'No notifications yet.';

  @override
  String get communityUnavailable => 'Community feed is unavailable.';

  @override
  String get noCommunityActivity => 'No community activity yet.';

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
  String get mapSearchHint => 'Search station or location…';

  @override
  String get noMapSearchResult => 'No station or location found.';

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

  @override
  String get fluviAiRadar => 'FluviAI Radar';

  @override
  String get askFluviAI => 'Ask FluviAI';

  @override
  String get areaCheck => 'Area Check';

  @override
  String get verifyArea => 'Check area';

  @override
  String get trusted => 'Trusted';

  @override
  String get clearSky => 'Clear sky';

  @override
  String get lowWater => 'Low water';

  @override
  String get notAccurate => 'Not accurate';

  @override
  String get currentLocation => 'Current Location';

  @override
  String get liveActivity => 'Live activity';

  @override
  String get goodFishing => 'Good fishing';

  @override
  String get poorFishing => 'Poor fishing';

  @override
  String get scoreExcellent => 'Excellent';

  @override
  String get scoreGood => 'Good';

  @override
  String get scoreFair => 'Fair';

  @override
  String get scorePoor => 'Poor';

  @override
  String get low => 'Low';

  @override
  String get high => 'High';

  @override
  String reportsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports today',
      one: '1 report today',
      zero: '0 reports today',
    );
    return '$_temp0';
  }

  @override
  String get noCommunityUpdate => 'No community update yet.';

  @override
  String get confirm => 'Confirm';

  @override
  String get underReview => 'Under review';

  @override
  String get takeLivePhoto => 'Take live photo';

  @override
  String get retakeLivePhoto => 'Retake live photo';

  @override
  String get communityTrustTitle => '🤝 Respect anglers. Respect nature.';

  @override
  String get communityTrustBody =>
      'The FluviAI community is based on trust.\nOnly publish real, current information to help other anglers make better decisions on the water.';

  @override
  String get reportTruthConfirmation =>
      'I confirm this report is real and reflects the current conditions.';

  @override
  String get misleadingReportsWarning =>
      'False or misleading reports may be removed and can affect your Community Reputation.';

  @override
  String get publishing => 'Publishing…';

  @override
  String get publish => 'Publish';

  @override
  String get reportCategoryFishActivity => 'Fish activity';

  @override
  String get reportCategoryWaterClarity => 'Water clarity';

  @override
  String get reportCategoryFloatingGrass => 'Floating grass';

  @override
  String get reportCategoryHighWater => 'High water';

  @override
  String get reportCategoryLowWater => 'Low water';

  @override
  String get reportCategoryStrongCurrent => 'Strong current';

  @override
  String get reportCategoryNoCurrent => 'No current';

  @override
  String get reportCategoryBoats => 'Boats';

  @override
  String get reportCategoryPoaching => 'Poaching';

  @override
  String get reportCategoryTheftWarning => 'Theft warning';

  @override
  String get reportCategoryAccessBlocked => 'Access blocked';

  @override
  String get reportCategoryParkingAvailable => 'Parking available';

  @override
  String get reportCategoryGoodFishing => 'Good fishing';

  @override
  String get reportCategoryPoorFishing => 'Poor fishing';

  @override
  String get reportCategoryOther => 'Other';

  @override
  String get abuseReasonSpam => 'Spam';

  @override
  String get abuseReasonFakeInformation => 'Fake information';

  @override
  String get abuseReasonOffensiveContent => 'Offensive content';

  @override
  String get abuseReasonDangerousIllegalActivity =>
      'Dangerous/illegal activity';

  @override
  String get abuseReasonOther => 'Other';

  @override
  String get mainSection => 'Main';

  @override
  String get myFishing => 'My Fishing';

  @override
  String get useful => 'Useful';

  @override
  String get account => 'Account';

  @override
  String get support => 'Support';

  @override
  String get developer => 'Developer';

  @override
  String get aiFishingInsights => 'FluviAI Radar';

  @override
  String get myCatches => 'My Catches';

  @override
  String get fishingDiary => 'Fishing Diary';

  @override
  String get fishingPermit => 'Fishing Permit';

  @override
  String get regulations => 'Regulations';

  @override
  String get closedSeason => 'Closed Season / Prohibition';

  @override
  String get minimumLegalSizes => 'Minimum Legal Sizes';

  @override
  String get protectedSpecies => 'Protected Species';

  @override
  String get dailyCatchLimits => 'Daily Catch Limits';

  @override
  String get protectedAreas => 'Protected Areas';

  @override
  String get reportPoaching => 'Report Poaching';

  @override
  String get solunar => 'Solunar';

  @override
  String get fishingCalendar => 'Fishing Calendar';

  @override
  String get knots => 'Knots';

  @override
  String get unitConversions => 'Unit Conversions';

  @override
  String get authorityContacts => 'Authority Contacts';

  @override
  String get premium => 'Premium';

  @override
  String get helpFaq => 'Help & FAQ';

  @override
  String get contactSupport => 'Contact Support';

  @override
  String get feedback => 'Feedback';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get terms => 'Terms';

  @override
  String get aboutApp => 'About FluviAI';

  @override
  String get developerMode => 'Developer Mode';

  @override
  String get featureComingSoon => 'This feature is coming soon.';

  @override
  String get liveWaterLevels => 'Live Water Levels';

  @override
  String get monitoredStationsTitle => 'Monitored stations';

  @override
  String get updateTimeUnavailable => 'Update time unavailable';

  @override
  String get updatedNow => 'Updated just now';

  @override
  String updatedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return 'Updated $_temp0 ago';
  }

  @override
  String updatedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return 'Updated $_temp0 ago';
  }

  @override
  String updatedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Updated $_temp0 ago';
  }

  @override
  String feelsLike(int temperature) {
    return 'Feels like $temperature°C';
  }

  @override
  String get humidity => 'Humidity';

  @override
  String get windSpeed => 'Wind speed';

  @override
  String get windDirection => 'Wind direction';

  @override
  String get windGusts => 'Wind gusts';

  @override
  String get precipitationProbability => 'Precipitation probability';

  @override
  String get cloudCover => 'Cloud cover';

  @override
  String get pressure => 'Pressure';

  @override
  String get lastUpdated => 'Last updated';

  @override
  String get next24Hours => 'Next 24 hours';

  @override
  String get temperature => 'Temperature';

  @override
  String get wind => 'Wind';

  @override
  String get direction => 'Direction';

  @override
  String get precipitation => 'Precipitation';

  @override
  String get threeDayForecast => '3-day forecast';

  @override
  String get sunrise => 'Sunrise';

  @override
  String get sunset => 'Sunset';

  @override
  String get illuminated => 'illuminated';

  @override
  String moonAge(String value) {
    return 'Moon age: $value days';
  }

  @override
  String get locationRequired => 'Location required';

  @override
  String get notAvailable => 'Not available';

  @override
  String get or => 'or';

  @override
  String get mondayShort => 'Mon';

  @override
  String get tuesdayShort => 'Tue';

  @override
  String get wednesdayShort => 'Wed';

  @override
  String get thursdayShort => 'Thu';

  @override
  String get fridayShort => 'Fri';

  @override
  String get saturdayShort => 'Sat';

  @override
  String get sundayShort => 'Sun';

  @override
  String get savingCatch => 'Saving catch…';

  @override
  String get saveCatch => 'Save Catch';

  @override
  String get catchLocationRequired =>
      'Use GPS or enter a place name for this catch.';

  @override
  String get noCatchesYet => 'No catches yet.';

  @override
  String get loadingEllipsis => 'Loading…';

  @override
  String get waterUnavailable => 'Water unavailable';

  @override
  String get noStationAvailable => 'No station available';

  @override
  String get updateFailed => 'Update failed';

  @override
  String get waitingForData => 'Waiting for data';

  @override
  String get unknown => 'Unknown';

  @override
  String get noSource => 'No source';

  @override
  String get rising => 'Rising';

  @override
  String get stable => 'Stable';

  @override
  String get falling => 'Falling';

  @override
  String get weatherUnavailableShort => 'Weather unavailable';

  @override
  String get mapLayers => 'Map layers';

  @override
  String get waterStations => 'Water stations';

  @override
  String get communityReports => 'Community reports';

  @override
  String get favoriteStations => 'Favourite stations';

  @override
  String get signInForFavoriteStations =>
      'Please sign in to filter favourite stations.';

  @override
  String get retryLoadingReports => 'Retry loading reports';

  @override
  String get loadingFishingReports => 'Loading live fishing reports…';

  @override
  String get fishingFilters => 'Fishing filters';

  @override
  String get photoCaptureFailed => 'The photo could not be captured.';

  @override
  String get cameraPhotoRequired => 'Take a photo with the camera.';

  @override
  String get catchSaved => 'Catch saved successfully.';

  @override
  String get requiredField => 'Required';

  @override
  String get positiveValueRequired => 'Enter a value above 0';

  @override
  String get exactLocation => 'Exact location';

  @override
  String get approximateLocation => 'Approximate location';

  @override
  String get hiddenLocation => 'Hidden location';

  @override
  String get reservoir => 'Reservoir';

  @override
  String get canal => 'Canal';

  @override
  String get danube => 'Danube';

  @override
  String get other => 'Other';

  @override
  String get checkEmailConfirmation =>
      'Check your email to confirm your account.';

  @override
  String get passwordResetSent =>
      'Password reset instructions were sent by email.';

  @override
  String get validEmailRequired => 'Enter a valid email address';

  @override
  String get minimumEightCharacters => 'Use at least 8 characters';

  @override
  String get createAccountTitle => 'Create account';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get recoveryInstructionsHint =>
      'We will send recovery instructions to your email.';

  @override
  String get signInToContinue => 'Sign in to continue to FluviAI.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get register => 'Register';

  @override
  String get sendResetEmail => 'Send reset email';

  @override
  String get login => 'Login';

  @override
  String get signInForFavorites =>
      'Please sign in to view your favourite stations.';

  @override
  String get favoritesUnavailable => 'Favourite stations are unavailable.';

  @override
  String get waterLevelUnavailable => 'Water level unavailable';

  @override
  String get nameRequired => 'Name is required.';

  @override
  String get profileUpdated => 'Profile updated.';

  @override
  String get saving => 'Saving…';

  @override
  String get saveProfile => 'Save Profile';

  @override
  String reputationValue(int value) {
    return 'Reputation $value/100';
  }

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0 ago';
  }

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0 ago';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0 ago';
  }

  @override
  String get catches => 'Catches';

  @override
  String get reputation => 'Reputation';

  @override
  String get cachedDataFallback => 'Showing the latest locally saved data.';
}
