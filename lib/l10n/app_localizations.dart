import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ro.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ro'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ro, this message translates to:
  /// **'AIFishMap'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In ro, this message translates to:
  /// **'Acasă'**
  String get home;

  /// No description provided for @map.
  ///
  /// In ro, this message translates to:
  /// **'Hartă'**
  String get map;

  /// No description provided for @fishingMap.
  ///
  /// In ro, this message translates to:
  /// **'Hartă de pescuit'**
  String get fishingMap;

  /// No description provided for @waterLevel.
  ///
  /// In ro, this message translates to:
  /// **'Nivelul apei'**
  String get waterLevel;

  /// No description provided for @waterLevels.
  ///
  /// In ro, this message translates to:
  /// **'Nivelurile apei'**
  String get waterLevels;

  /// No description provided for @stationDetails.
  ///
  /// In ro, this message translates to:
  /// **'Detalii stație'**
  String get stationDetails;

  /// No description provided for @weather.
  ///
  /// In ro, this message translates to:
  /// **'Vreme'**
  String get weather;

  /// No description provided for @fishingInsights.
  ///
  /// In ro, this message translates to:
  /// **'Informații pentru pescuit'**
  String get fishingInsights;

  /// No description provided for @reports.
  ///
  /// In ro, this message translates to:
  /// **'Rapoarte'**
  String get reports;

  /// No description provided for @reportsArchive.
  ///
  /// In ro, this message translates to:
  /// **'Arhiva rapoartelor'**
  String get reportsArchive;

  /// No description provided for @recentCatches.
  ///
  /// In ro, this message translates to:
  /// **'Capturi recente'**
  String get recentCatches;

  /// No description provided for @favorites.
  ///
  /// In ro, this message translates to:
  /// **'Favorite'**
  String get favorites;

  /// No description provided for @favouriteStations.
  ///
  /// In ro, this message translates to:
  /// **'Stații favorite'**
  String get favouriteStations;

  /// No description provided for @notifications.
  ///
  /// In ro, this message translates to:
  /// **'Notificări'**
  String get notifications;

  /// No description provided for @notificationPreferences.
  ///
  /// In ro, this message translates to:
  /// **'Preferințe notificări'**
  String get notificationPreferences;

  /// No description provided for @profile.
  ///
  /// In ro, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In ro, this message translates to:
  /// **'Setări'**
  String get settings;

  /// No description provided for @community.
  ///
  /// In ro, this message translates to:
  /// **'Comunitate'**
  String get community;

  /// No description provided for @retry.
  ///
  /// In ro, this message translates to:
  /// **'Reîncearcă'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In ro, this message translates to:
  /// **'Reîmprospătează'**
  String get refresh;

  /// No description provided for @cancel.
  ///
  /// In ro, this message translates to:
  /// **'Anulează'**
  String get cancel;

  /// No description provided for @apply.
  ///
  /// In ro, this message translates to:
  /// **'Aplică'**
  String get apply;

  /// No description provided for @reset.
  ///
  /// In ro, this message translates to:
  /// **'Resetează'**
  String get reset;

  /// No description provided for @save.
  ///
  /// In ro, this message translates to:
  /// **'Salvează'**
  String get save;

  /// No description provided for @close.
  ///
  /// In ro, this message translates to:
  /// **'Închide'**
  String get close;

  /// No description provided for @loading.
  ///
  /// In ro, this message translates to:
  /// **'Se încarcă…'**
  String get loading;

  /// No description provided for @noData.
  ///
  /// In ro, this message translates to:
  /// **'Nu există date'**
  String get noData;

  /// No description provided for @errorGeneric.
  ///
  /// In ro, this message translates to:
  /// **'A apărut o eroare. Încearcă din nou.'**
  String get errorGeneric;

  /// No description provided for @unavailable.
  ///
  /// In ro, this message translates to:
  /// **'Indisponibil momentan.'**
  String get unavailable;

  /// No description provided for @noFavouriteStations.
  ///
  /// In ro, this message translates to:
  /// **'Nu ai încă stații favorite.'**
  String get noFavouriteStations;

  /// No description provided for @waterProviderUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Furnizorul de date despre apă este momentan indisponibil.'**
  String get waterProviderUnavailable;

  /// No description provided for @noWaterData.
  ///
  /// In ro, this message translates to:
  /// **'Momentan nu există date despre apă.'**
  String get noWaterData;

  /// No description provided for @weatherUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Datele meteo sunt momentan indisponibile.'**
  String get weatherUnavailable;

  /// No description provided for @noRecentCatches.
  ///
  /// In ro, this message translates to:
  /// **'Nu există capturi recente.'**
  String get noRecentCatches;

  /// No description provided for @recentCatchesLoadError.
  ///
  /// In ro, this message translates to:
  /// **'Capturile recente nu au putut fi încărcate.'**
  String get recentCatchesLoadError;

  /// No description provided for @noComments.
  ///
  /// In ro, this message translates to:
  /// **'Nu există încă niciun comentariu.'**
  String get noComments;

  /// No description provided for @commentsUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Comentariile sunt momentan indisponibile.'**
  String get commentsUnavailable;

  /// No description provided for @report.
  ///
  /// In ro, this message translates to:
  /// **'Raportează'**
  String get report;

  /// No description provided for @reportAbuse.
  ///
  /// In ro, this message translates to:
  /// **'Raportează abuz'**
  String get reportAbuse;

  /// No description provided for @createReport.
  ///
  /// In ro, this message translates to:
  /// **'Creează raport'**
  String get createReport;

  /// No description provided for @reportSubmitted.
  ///
  /// In ro, this message translates to:
  /// **'Raportul a fost trimis pentru verificare.'**
  String get reportSubmitted;

  /// No description provided for @noReports.
  ///
  /// In ro, this message translates to:
  /// **'Nu există rapoarte pentru această perioadă.'**
  String get noReports;

  /// No description provided for @noCategoryData.
  ///
  /// In ro, this message translates to:
  /// **'Nu există date pe categorii pentru această perioadă.'**
  String get noCategoryData;

  /// No description provided for @reportCategory.
  ///
  /// In ro, this message translates to:
  /// **'Categoria raportului'**
  String get reportCategory;

  /// No description provided for @descriptionOptional.
  ///
  /// In ro, this message translates to:
  /// **'Descriere (opțional)'**
  String get descriptionOptional;

  /// No description provided for @useExactLocation.
  ///
  /// In ro, this message translates to:
  /// **'Folosește locația exactă'**
  String get useExactLocation;

  /// No description provided for @approximateLocationHint.
  ///
  /// In ro, this message translates to:
  /// **'Dezactivează pentru a partaja o locație aproximativă'**
  String get approximateLocationHint;

  /// No description provided for @positiveFactors.
  ///
  /// In ro, this message translates to:
  /// **'Factori pozitivi'**
  String get positiveFactors;

  /// No description provided for @negativeFactors.
  ///
  /// In ro, this message translates to:
  /// **'Factori negativi'**
  String get negativeFactors;

  /// No description provided for @bestTimeWindow.
  ///
  /// In ro, this message translates to:
  /// **'Cel mai bun interval'**
  String get bestTimeWindow;

  /// No description provided for @missingData.
  ///
  /// In ro, this message translates to:
  /// **'Date lipsă'**
  String get missingData;

  /// No description provided for @noSignificantFactors.
  ///
  /// In ro, this message translates to:
  /// **'Nu există factori semnificativi.'**
  String get noSignificantFactors;

  /// No description provided for @notEnoughData.
  ///
  /// In ro, this message translates to:
  /// **'Nu există încă suficiente date'**
  String get notEnoughData;

  /// No description provided for @confidence.
  ///
  /// In ro, this message translates to:
  /// **'Încredere: {value}%'**
  String confidence(int value);

  /// No description provided for @goldenHour.
  ///
  /// In ro, this message translates to:
  /// **'Ora de aur'**
  String get goldenHour;

  /// No description provided for @goldenHourValue.
  ///
  /// In ro, this message translates to:
  /// **'Ora de aur: {value}'**
  String goldenHourValue(String value);

  /// No description provided for @coordinates.
  ///
  /// In ro, this message translates to:
  /// **'Coordonate'**
  String get coordinates;

  /// No description provided for @waterLevelHistory.
  ///
  /// In ro, this message translates to:
  /// **'Istoricul nivelului apei'**
  String get waterLevelHistory;

  /// No description provided for @aiWaterInsight.
  ///
  /// In ro, this message translates to:
  /// **'Analiză AI a apei'**
  String get aiWaterInsight;

  /// No description provided for @monitoredStations.
  ///
  /// In ro, this message translates to:
  /// **'{count, plural, =1{1 stație monitorizată} other{{count} stații monitorizate}}'**
  String monitoredStations(int count);

  /// No description provided for @days.
  ///
  /// In ro, this message translates to:
  /// **'{count, plural, =1{1 zi} other{{count} zile}}'**
  String days(int count);

  /// No description provided for @reportCount.
  ///
  /// In ro, this message translates to:
  /// **'{count, plural, =1{1 raport} other{{count} rapoarte}}'**
  String reportCount(int count);

  /// No description provided for @likes.
  ///
  /// In ro, this message translates to:
  /// **'{count, plural, =1{1 apreciere} other{{count} aprecieri}}'**
  String likes(int count);

  /// No description provided for @comments.
  ///
  /// In ro, this message translates to:
  /// **'Comentarii'**
  String get comments;

  /// No description provided for @addComment.
  ///
  /// In ro, this message translates to:
  /// **'Adaugă un comentariu'**
  String get addComment;

  /// No description provided for @catchDetails.
  ///
  /// In ro, this message translates to:
  /// **'Detalii captură'**
  String get catchDetails;

  /// No description provided for @anglerProfile.
  ///
  /// In ro, this message translates to:
  /// **'Profil pescar'**
  String get anglerProfile;

  /// No description provided for @profileUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Profilul este indisponibil.'**
  String get profileUnavailable;

  /// No description provided for @addCatch.
  ///
  /// In ro, this message translates to:
  /// **'Adaugă captură'**
  String get addCatch;

  /// No description provided for @species.
  ///
  /// In ro, this message translates to:
  /// **'Specie'**
  String get species;

  /// No description provided for @weight.
  ///
  /// In ro, this message translates to:
  /// **'Greutate'**
  String get weight;

  /// No description provided for @weightUnit.
  ///
  /// In ro, this message translates to:
  /// **'Unitatea greutății'**
  String get weightUnit;

  /// No description provided for @lengthCm.
  ///
  /// In ro, this message translates to:
  /// **'Lungime (cm)'**
  String get lengthCm;

  /// No description provided for @notes.
  ///
  /// In ro, this message translates to:
  /// **'Notițe'**
  String get notes;

  /// No description provided for @placeNameOptional.
  ///
  /// In ro, this message translates to:
  /// **'Numele locului (opțional cu GPS)'**
  String get placeNameOptional;

  /// No description provided for @placeHint.
  ///
  /// In ro, this message translates to:
  /// **'Lac, râu, acumulare, canal…'**
  String get placeHint;

  /// No description provided for @waterType.
  ///
  /// In ro, this message translates to:
  /// **'Tipul apei'**
  String get waterType;

  /// No description provided for @locationPrivacy.
  ///
  /// In ro, this message translates to:
  /// **'Confidențialitatea locației'**
  String get locationPrivacy;

  /// No description provided for @camera.
  ///
  /// In ro, this message translates to:
  /// **'Cameră'**
  String get camera;

  /// No description provided for @name.
  ///
  /// In ro, this message translates to:
  /// **'Nume'**
  String get name;

  /// No description provided for @email.
  ///
  /// In ro, this message translates to:
  /// **'E-mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In ro, this message translates to:
  /// **'Parolă'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In ro, this message translates to:
  /// **'Confirmă parola'**
  String get confirmPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In ro, this message translates to:
  /// **'Ai uitat parola?'**
  String get forgotPassword;

  /// No description provided for @createAccount.
  ///
  /// In ro, this message translates to:
  /// **'Creează un cont'**
  String get createAccount;

  /// No description provided for @backToLogin.
  ///
  /// In ro, this message translates to:
  /// **'Înapoi la autentificare'**
  String get backToLogin;

  /// No description provided for @setNewPassword.
  ///
  /// In ro, this message translates to:
  /// **'Setează o parolă nouă'**
  String get setNewPassword;

  /// No description provided for @newPassword.
  ///
  /// In ro, this message translates to:
  /// **'Parolă nouă'**
  String get newPassword;

  /// No description provided for @updating.
  ///
  /// In ro, this message translates to:
  /// **'Se actualizează…'**
  String get updating;

  /// No description provided for @updatePassword.
  ///
  /// In ro, this message translates to:
  /// **'Actualizează parola'**
  String get updatePassword;

  /// No description provided for @logout.
  ///
  /// In ro, this message translates to:
  /// **'Deconectare'**
  String get logout;

  /// No description provided for @changeAvatar.
  ///
  /// In ro, this message translates to:
  /// **'Schimbă avatarul'**
  String get changeAvatar;

  /// No description provided for @quietHours.
  ///
  /// In ro, this message translates to:
  /// **'Interval silențios'**
  String get quietHours;

  /// No description provided for @startTime.
  ///
  /// In ro, this message translates to:
  /// **'Ora de început'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In ro, this message translates to:
  /// **'Ora de sfârșit'**
  String get endTime;

  /// No description provided for @groupSimilarNotifications.
  ///
  /// In ro, this message translates to:
  /// **'Grupează notificările similare'**
  String get groupSimilarNotifications;

  /// No description provided for @duplicateCooldown.
  ///
  /// In ro, this message translates to:
  /// **'Interval pentru duplicate'**
  String get duplicateCooldown;

  /// No description provided for @notificationPreferencesTooltip.
  ///
  /// In ro, this message translates to:
  /// **'Preferințe notificări'**
  String get notificationPreferencesTooltip;

  /// No description provided for @signInForNotificationPreferences.
  ///
  /// In ro, this message translates to:
  /// **'Autentifică-te pentru a gestiona preferințele notificărilor.'**
  String get signInForNotificationPreferences;

  /// No description provided for @categories.
  ///
  /// In ro, this message translates to:
  /// **'Categorii'**
  String get categories;

  /// No description provided for @priority.
  ///
  /// In ro, this message translates to:
  /// **'Prioritate'**
  String get priority;

  /// No description provided for @clearReadNotifications.
  ///
  /// In ro, this message translates to:
  /// **'Șterge notificările citite'**
  String get clearReadNotifications;

  /// No description provided for @notificationsUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Notificările sunt indisponibile.'**
  String get notificationsUnavailable;

  /// No description provided for @noNotifications.
  ///
  /// In ro, this message translates to:
  /// **'Nu există încă notificări.'**
  String get noNotifications;

  /// No description provided for @communityUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Fluxul comunității este indisponibil.'**
  String get communityUnavailable;

  /// No description provided for @noCommunityActivity.
  ///
  /// In ro, this message translates to:
  /// **'Nu există încă activitate în comunitate.'**
  String get noCommunityActivity;

  /// No description provided for @standard.
  ///
  /// In ro, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @satellite.
  ///
  /// In ro, this message translates to:
  /// **'Satelit'**
  String get satellite;

  /// No description provided for @comingSoon.
  ///
  /// In ro, this message translates to:
  /// **'În curând'**
  String get comingSoon;

  /// No description provided for @fishingMode.
  ///
  /// In ro, this message translates to:
  /// **'Mod pescuit'**
  String get fishingMode;

  /// No description provided for @riverAndLake.
  ///
  /// In ro, this message translates to:
  /// **'Râu și lac'**
  String get riverAndLake;

  /// No description provided for @river.
  ///
  /// In ro, this message translates to:
  /// **'Râu'**
  String get river;

  /// No description provided for @lake.
  ///
  /// In ro, this message translates to:
  /// **'Lac'**
  String get lake;

  /// No description provided for @allSpecies.
  ///
  /// In ro, this message translates to:
  /// **'Toate speciile'**
  String get allSpecies;

  /// No description provided for @gpsRadius.
  ///
  /// In ro, this message translates to:
  /// **'Rază GPS'**
  String get gpsRadius;

  /// No description provided for @anyDistance.
  ///
  /// In ro, this message translates to:
  /// **'Orice distanță'**
  String get anyDistance;

  /// No description provided for @filterByWaterLevel.
  ///
  /// In ro, this message translates to:
  /// **'Filtrează după nivelul apei'**
  String get filterByWaterLevel;

  /// No description provided for @waterTrend.
  ///
  /// In ro, this message translates to:
  /// **'Tendința apei'**
  String get waterTrend;

  /// No description provided for @difficulty.
  ///
  /// In ro, this message translates to:
  /// **'Dificultate'**
  String get difficulty;

  /// No description provided for @anyDifficulty.
  ///
  /// In ro, this message translates to:
  /// **'Orice dificultate'**
  String get anyDifficulty;

  /// No description provided for @easy.
  ///
  /// In ro, this message translates to:
  /// **'Ușor'**
  String get easy;

  /// No description provided for @moderate.
  ///
  /// In ro, this message translates to:
  /// **'Moderat'**
  String get moderate;

  /// No description provided for @hard.
  ///
  /// In ro, this message translates to:
  /// **'Dificil'**
  String get hard;

  /// No description provided for @favoritesOnly.
  ///
  /// In ro, this message translates to:
  /// **'Doar favorite'**
  String get favoritesOnly;

  /// No description provided for @searchStation.
  ///
  /// In ro, this message translates to:
  /// **'Caută numele stației…'**
  String get searchStation;

  /// No description provided for @noStationFound.
  ///
  /// In ro, this message translates to:
  /// **'Nu a fost găsită nicio stație.'**
  String get noStationFound;

  /// No description provided for @stationSearchUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Căutarea stațiilor este indisponibilă.'**
  String get stationSearchUnavailable;

  /// No description provided for @viewAll.
  ///
  /// In ro, this message translates to:
  /// **'Vezi toate'**
  String get viewAll;

  /// No description provided for @retryRecentCatches.
  ///
  /// In ro, this message translates to:
  /// **'Reîncearcă încărcarea capturilor recente'**
  String get retryRecentCatches;

  /// No description provided for @youAreHere.
  ///
  /// In ro, this message translates to:
  /// **'Ești aici'**
  String get youAreHere;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ro'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ro':
      return AppLocalizationsRo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
