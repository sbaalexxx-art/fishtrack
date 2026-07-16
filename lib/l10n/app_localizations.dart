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
  /// **'FluviAI'**
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
  /// **'FluviAI Radar'**
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

  /// No description provided for @notificationWaterAlerts.
  ///
  /// In ro, this message translates to:
  /// **'Alerte nivel apă'**
  String get notificationWaterAlerts;

  /// No description provided for @notificationFavouriteStations.
  ///
  /// In ro, this message translates to:
  /// **'Stații favorite'**
  String get notificationFavouriteStations;

  /// No description provided for @notificationCommunityReports.
  ///
  /// In ro, this message translates to:
  /// **'Rapoarte comunitate'**
  String get notificationCommunityReports;

  /// No description provided for @notificationDangerousReports.
  ///
  /// In ro, this message translates to:
  /// **'Alerte de pericol'**
  String get notificationDangerousReports;

  /// No description provided for @notificationFluviAiRadar.
  ///
  /// In ro, this message translates to:
  /// **'Indice FluviAI'**
  String get notificationFluviAiRadar;

  /// No description provided for @notificationReputationTrust.
  ///
  /// In ro, this message translates to:
  /// **'Reputație și încredere'**
  String get notificationReputationTrust;

  /// No description provided for @notificationAchievements.
  ///
  /// In ro, this message translates to:
  /// **'Realizări'**
  String get notificationAchievements;

  /// No description provided for @notificationCatchActivity.
  ///
  /// In ro, this message translates to:
  /// **'Activitate capturi'**
  String get notificationCatchActivity;

  /// No description provided for @notificationPrioritySilent.
  ///
  /// In ro, this message translates to:
  /// **'Silențios'**
  String get notificationPrioritySilent;

  /// No description provided for @notificationPrioritySilentDescription.
  ///
  /// In ro, this message translates to:
  /// **'Salvată doar în aplicație, fără notificare pop-up.'**
  String get notificationPrioritySilentDescription;

  /// No description provided for @notificationPriorityImportant.
  ///
  /// In ro, this message translates to:
  /// **'Important'**
  String get notificationPriorityImportant;

  /// No description provided for @notificationPriorityImportantDescription.
  ///
  /// In ro, this message translates to:
  /// **'Livrare normală, respectând intervalul silențios.'**
  String get notificationPriorityImportantDescription;

  /// No description provided for @notificationPriorityCritical.
  ///
  /// In ro, this message translates to:
  /// **'Critic'**
  String get notificationPriorityCritical;

  /// No description provided for @notificationPriorityCriticalDescription.
  ///
  /// In ro, this message translates to:
  /// **'Livrată imediat, inclusiv în intervalul silențios.'**
  String get notificationPriorityCriticalDescription;

  /// No description provided for @notificationGroupingDescription.
  ///
  /// In ro, this message translates to:
  /// **'Grupează aceeași stație și același tip de eveniment în 30 de minute.'**
  String get notificationGroupingDescription;

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

  /// No description provided for @homeTagline.
  ///
  /// In ro, this message translates to:
  /// **'Acolo unde pasiunea întâlnește firul apei.'**
  String get homeTagline;

  /// No description provided for @weatherHomeDegrees.
  ///
  /// In ro, this message translates to:
  /// **'Grade'**
  String get weatherHomeDegrees;

  /// No description provided for @weatherHomeRain.
  ///
  /// In ro, this message translates to:
  /// **'Ploaie'**
  String get weatherHomeRain;

  /// No description provided for @communityEmptyMessage.
  ///
  /// In ro, this message translates to:
  /// **'Liniște pe ape în această zonă.'**
  String get communityEmptyMessage;

  /// No description provided for @communityEmptyCta.
  ///
  /// In ro, this message translates to:
  /// **'Fii primul care raportează!'**
  String get communityEmptyCta;

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

  /// No description provided for @mapSearchHint.
  ///
  /// In ro, this message translates to:
  /// **'Caută stație sau locație…'**
  String get mapSearchHint;

  /// No description provided for @noMapSearchResult.
  ///
  /// In ro, this message translates to:
  /// **'Nu a fost găsită nicio stație sau locație.'**
  String get noMapSearchResult;

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
  /// **'Locația ta'**
  String get youAreHere;

  /// No description provided for @fluviAiRadar.
  ///
  /// In ro, this message translates to:
  /// **'FluviAI Radar'**
  String get fluviAiRadar;

  /// No description provided for @askFluviAI.
  ///
  /// In ro, this message translates to:
  /// **'Întreabă FluviAI'**
  String get askFluviAI;

  /// No description provided for @areaCheck.
  ///
  /// In ro, this message translates to:
  /// **'Verificare zonă'**
  String get areaCheck;

  /// No description provided for @verifyArea.
  ///
  /// In ro, this message translates to:
  /// **'Verifică zona'**
  String get verifyArea;

  /// No description provided for @trusted.
  ///
  /// In ro, this message translates to:
  /// **'De încredere'**
  String get trusted;

  /// No description provided for @clearSky.
  ///
  /// In ro, this message translates to:
  /// **'Cer senin'**
  String get clearSky;

  /// No description provided for @lowWater.
  ///
  /// In ro, this message translates to:
  /// **'Nivel scăzut'**
  String get lowWater;

  /// No description provided for @notAccurate.
  ///
  /// In ro, this message translates to:
  /// **'Nu este corect'**
  String get notAccurate;

  /// No description provided for @currentLocation.
  ///
  /// In ro, this message translates to:
  /// **'Locația curentă'**
  String get currentLocation;

  /// No description provided for @liveActivity.
  ///
  /// In ro, this message translates to:
  /// **'Activitate live'**
  String get liveActivity;

  /// No description provided for @goodFishing.
  ///
  /// In ro, this message translates to:
  /// **'Activitate bună'**
  String get goodFishing;

  /// No description provided for @poorFishing.
  ///
  /// In ro, this message translates to:
  /// **'Activitate slabă'**
  String get poorFishing;

  /// No description provided for @scoreExcellent.
  ///
  /// In ro, this message translates to:
  /// **'Excelent'**
  String get scoreExcellent;

  /// No description provided for @scoreGood.
  ///
  /// In ro, this message translates to:
  /// **'Bun'**
  String get scoreGood;

  /// No description provided for @scoreFair.
  ///
  /// In ro, this message translates to:
  /// **'Acceptabil'**
  String get scoreFair;

  /// No description provided for @scorePoor.
  ///
  /// In ro, this message translates to:
  /// **'Slab'**
  String get scorePoor;

  /// No description provided for @low.
  ///
  /// In ro, this message translates to:
  /// **'Scăzut'**
  String get low;

  /// No description provided for @high.
  ///
  /// In ro, this message translates to:
  /// **'Ridicat'**
  String get high;

  /// No description provided for @reportsToday.
  ///
  /// In ro, this message translates to:
  /// **'{count, plural, =0{0 rapoarte astăzi} =1{1 raport astăzi} other{{count} rapoarte astăzi}}'**
  String reportsToday(int count);

  /// No description provided for @noCommunityUpdate.
  ///
  /// In ro, this message translates to:
  /// **'Nicio actualizare din comunitate.'**
  String get noCommunityUpdate;

  /// No description provided for @confirm.
  ///
  /// In ro, this message translates to:
  /// **'Confirmă'**
  String get confirm;

  /// No description provided for @underReview.
  ///
  /// In ro, this message translates to:
  /// **'În verificare'**
  String get underReview;

  /// No description provided for @takeLivePhoto.
  ///
  /// In ro, this message translates to:
  /// **'Fă poză live'**
  String get takeLivePhoto;

  /// No description provided for @retakeLivePhoto.
  ///
  /// In ro, this message translates to:
  /// **'Refă poza live'**
  String get retakeLivePhoto;

  /// No description provided for @communityTrustTitle.
  ///
  /// In ro, this message translates to:
  /// **'🤝 Respectă pescarii. Respectă natura.'**
  String get communityTrustTitle;

  /// No description provided for @communityTrustBody.
  ///
  /// In ro, this message translates to:
  /// **'Comunitatea FluviAI se bazează pe încredere.\nPublică doar informații reale și actuale pentru a-i ajuta pe ceilalți pescari să ia cele mai bune decizii pe apă.'**
  String get communityTrustBody;

  /// No description provided for @reportTruthConfirmation.
  ///
  /// In ro, this message translates to:
  /// **'Confirm că acest raport este real și reflectă condițiile din acest moment.'**
  String get reportTruthConfirmation;

  /// No description provided for @misleadingReportsWarning.
  ///
  /// In ro, this message translates to:
  /// **'Rapoartele false sau înșelătoare pot fi eliminate și îți pot afecta reputația în comunitate.'**
  String get misleadingReportsWarning;

  /// No description provided for @publishing.
  ///
  /// In ro, this message translates to:
  /// **'Se publică…'**
  String get publishing;

  /// No description provided for @publish.
  ///
  /// In ro, this message translates to:
  /// **'Publică'**
  String get publish;

  /// No description provided for @reportCategoryFishActivity.
  ///
  /// In ro, this message translates to:
  /// **'Activitate pești'**
  String get reportCategoryFishActivity;

  /// No description provided for @reportCategoryWaterClarity.
  ///
  /// In ro, this message translates to:
  /// **'Claritatea apei'**
  String get reportCategoryWaterClarity;

  /// No description provided for @reportCategoryFloatingGrass.
  ///
  /// In ro, this message translates to:
  /// **'Iarbă pe apă'**
  String get reportCategoryFloatingGrass;

  /// No description provided for @reportCategoryHighWater.
  ///
  /// In ro, this message translates to:
  /// **'Nivel ridicat'**
  String get reportCategoryHighWater;

  /// No description provided for @reportCategoryLowWater.
  ///
  /// In ro, this message translates to:
  /// **'Nivel scăzut'**
  String get reportCategoryLowWater;

  /// No description provided for @reportCategoryStrongCurrent.
  ///
  /// In ro, this message translates to:
  /// **'Curent puternic'**
  String get reportCategoryStrongCurrent;

  /// No description provided for @reportCategoryNoCurrent.
  ///
  /// In ro, this message translates to:
  /// **'Fără curent'**
  String get reportCategoryNoCurrent;

  /// No description provided for @reportCategoryBoats.
  ///
  /// In ro, this message translates to:
  /// **'Bărci'**
  String get reportCategoryBoats;

  /// No description provided for @reportCategoryPoaching.
  ///
  /// In ro, this message translates to:
  /// **'Braconaj'**
  String get reportCategoryPoaching;

  /// No description provided for @reportCategoryTheftWarning.
  ///
  /// In ro, this message translates to:
  /// **'Avertizare furt'**
  String get reportCategoryTheftWarning;

  /// No description provided for @reportCategoryAccessBlocked.
  ///
  /// In ro, this message translates to:
  /// **'Acces blocat'**
  String get reportCategoryAccessBlocked;

  /// No description provided for @reportCategoryParkingAvailable.
  ///
  /// In ro, this message translates to:
  /// **'Parcare disponibilă'**
  String get reportCategoryParkingAvailable;

  /// No description provided for @reportCategoryGoodFishing.
  ///
  /// In ro, this message translates to:
  /// **'Activitate bună'**
  String get reportCategoryGoodFishing;

  /// No description provided for @reportCategoryPoorFishing.
  ///
  /// In ro, this message translates to:
  /// **'Activitate slabă'**
  String get reportCategoryPoorFishing;

  /// No description provided for @reportCategoryOther.
  ///
  /// In ro, this message translates to:
  /// **'Altul'**
  String get reportCategoryOther;

  /// No description provided for @abuseReasonSpam.
  ///
  /// In ro, this message translates to:
  /// **'Spam'**
  String get abuseReasonSpam;

  /// No description provided for @abuseReasonFakeInformation.
  ///
  /// In ro, this message translates to:
  /// **'Informație falsă'**
  String get abuseReasonFakeInformation;

  /// No description provided for @abuseReasonOffensiveContent.
  ///
  /// In ro, this message translates to:
  /// **'Conținut ofensator'**
  String get abuseReasonOffensiveContent;

  /// No description provided for @abuseReasonDangerousIllegalActivity.
  ///
  /// In ro, this message translates to:
  /// **'Activitate periculoasă/ilegală'**
  String get abuseReasonDangerousIllegalActivity;

  /// No description provided for @abuseReasonOther.
  ///
  /// In ro, this message translates to:
  /// **'Altul'**
  String get abuseReasonOther;

  /// No description provided for @mainSection.
  ///
  /// In ro, this message translates to:
  /// **'Principal'**
  String get mainSection;

  /// No description provided for @myFishing.
  ///
  /// In ro, this message translates to:
  /// **'Pescuitul meu'**
  String get myFishing;

  /// No description provided for @useful.
  ///
  /// In ro, this message translates to:
  /// **'Utile'**
  String get useful;

  /// No description provided for @account.
  ///
  /// In ro, this message translates to:
  /// **'Cont'**
  String get account;

  /// No description provided for @support.
  ///
  /// In ro, this message translates to:
  /// **'Asistență'**
  String get support;

  /// No description provided for @developer.
  ///
  /// In ro, this message translates to:
  /// **'Dezvoltator'**
  String get developer;

  /// No description provided for @aiFishingInsights.
  ///
  /// In ro, this message translates to:
  /// **'FluviAI Radar'**
  String get aiFishingInsights;

  /// No description provided for @myCatches.
  ///
  /// In ro, this message translates to:
  /// **'Capturile mele'**
  String get myCatches;

  /// No description provided for @fishingDiary.
  ///
  /// In ro, this message translates to:
  /// **'Jurnal de pescuit'**
  String get fishingDiary;

  /// No description provided for @fishingPermit.
  ///
  /// In ro, this message translates to:
  /// **'Permis de pescuit'**
  String get fishingPermit;

  /// No description provided for @regulations.
  ///
  /// In ro, this message translates to:
  /// **'Reglementări'**
  String get regulations;

  /// No description provided for @closedSeason.
  ///
  /// In ro, this message translates to:
  /// **'Perioadă de prohibiție'**
  String get closedSeason;

  /// No description provided for @minimumLegalSizes.
  ///
  /// In ro, this message translates to:
  /// **'Dimensiuni minime legale'**
  String get minimumLegalSizes;

  /// No description provided for @protectedSpecies.
  ///
  /// In ro, this message translates to:
  /// **'Specii protejate'**
  String get protectedSpecies;

  /// No description provided for @dailyCatchLimits.
  ///
  /// In ro, this message translates to:
  /// **'Limite zilnice de captură'**
  String get dailyCatchLimits;

  /// No description provided for @protectedAreas.
  ///
  /// In ro, this message translates to:
  /// **'Zone protejate'**
  String get protectedAreas;

  /// No description provided for @reportPoaching.
  ///
  /// In ro, this message translates to:
  /// **'Raportează braconajul'**
  String get reportPoaching;

  /// No description provided for @solunar.
  ///
  /// In ro, this message translates to:
  /// **'Solunar'**
  String get solunar;

  /// No description provided for @fishingCalendar.
  ///
  /// In ro, this message translates to:
  /// **'Calendar de pescuit'**
  String get fishingCalendar;

  /// No description provided for @knots.
  ///
  /// In ro, this message translates to:
  /// **'Noduri'**
  String get knots;

  /// No description provided for @unitConversions.
  ///
  /// In ro, this message translates to:
  /// **'Conversii de unități'**
  String get unitConversions;

  /// No description provided for @authorityContacts.
  ///
  /// In ro, this message translates to:
  /// **'Contacte autorități'**
  String get authorityContacts;

  /// No description provided for @premium.
  ///
  /// In ro, this message translates to:
  /// **'Premium'**
  String get premium;

  /// No description provided for @helpFaq.
  ///
  /// In ro, this message translates to:
  /// **'Ajutor și întrebări frecvente'**
  String get helpFaq;

  /// No description provided for @contactSupport.
  ///
  /// In ro, this message translates to:
  /// **'Contactează asistența'**
  String get contactSupport;

  /// No description provided for @feedback.
  ///
  /// In ro, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @privacyPolicy.
  ///
  /// In ro, this message translates to:
  /// **'Politica de confidențialitate'**
  String get privacyPolicy;

  /// No description provided for @terms.
  ///
  /// In ro, this message translates to:
  /// **'Termeni și condiții'**
  String get terms;

  /// No description provided for @aboutApp.
  ///
  /// In ro, this message translates to:
  /// **'Despre FluviAI'**
  String get aboutApp;

  /// No description provided for @developerMode.
  ///
  /// In ro, this message translates to:
  /// **'Mod dezvoltator'**
  String get developerMode;

  /// No description provided for @featureComingSoon.
  ///
  /// In ro, this message translates to:
  /// **'Această funcție va fi disponibilă în curând.'**
  String get featureComingSoon;

  /// No description provided for @liveWaterLevels.
  ///
  /// In ro, this message translates to:
  /// **'Niveluri ale apei în timp real'**
  String get liveWaterLevels;

  /// No description provided for @monitoredStationsTitle.
  ///
  /// In ro, this message translates to:
  /// **'Stații monitorizate'**
  String get monitoredStationsTitle;

  /// No description provided for @updateTimeUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Ora actualizării nu este disponibilă'**
  String get updateTimeUnavailable;

  /// No description provided for @updatedNow.
  ///
  /// In ro, this message translates to:
  /// **'Actualizat chiar acum'**
  String get updatedNow;

  /// No description provided for @updatedMinutesAgo.
  ///
  /// In ro, this message translates to:
  /// **'Actualizat acum {count, plural, =1{1 minut} other{{count} minute}}'**
  String updatedMinutesAgo(int count);

  /// No description provided for @updatedHoursAgo.
  ///
  /// In ro, this message translates to:
  /// **'Actualizat acum {count, plural, =1{1 oră} other{{count} ore}}'**
  String updatedHoursAgo(int count);

  /// No description provided for @updatedDaysAgo.
  ///
  /// In ro, this message translates to:
  /// **'Actualizat acum {count, plural, =1{1 zi} other{{count} zile}}'**
  String updatedDaysAgo(int count);

  /// No description provided for @feelsLike.
  ///
  /// In ro, this message translates to:
  /// **'Se simte ca {temperature}°C'**
  String feelsLike(int temperature);

  /// No description provided for @humidity.
  ///
  /// In ro, this message translates to:
  /// **'Umiditate'**
  String get humidity;

  /// No description provided for @windSpeed.
  ///
  /// In ro, this message translates to:
  /// **'Viteza vântului'**
  String get windSpeed;

  /// No description provided for @windDirection.
  ///
  /// In ro, this message translates to:
  /// **'Direcția vântului'**
  String get windDirection;

  /// No description provided for @windGusts.
  ///
  /// In ro, this message translates to:
  /// **'Rafale de vânt'**
  String get windGusts;

  /// No description provided for @precipitationProbability.
  ///
  /// In ro, this message translates to:
  /// **'Probabilitate de precipitații'**
  String get precipitationProbability;

  /// No description provided for @cloudCover.
  ///
  /// In ro, this message translates to:
  /// **'Nebulozitate'**
  String get cloudCover;

  /// No description provided for @pressure.
  ///
  /// In ro, this message translates to:
  /// **'Presiune'**
  String get pressure;

  /// No description provided for @lastUpdated.
  ///
  /// In ro, this message translates to:
  /// **'Ultima actualizare'**
  String get lastUpdated;

  /// No description provided for @next24Hours.
  ///
  /// In ro, this message translates to:
  /// **'Următoarele 24 de ore'**
  String get next24Hours;

  /// No description provided for @temperature.
  ///
  /// In ro, this message translates to:
  /// **'Temperatură'**
  String get temperature;

  /// No description provided for @wind.
  ///
  /// In ro, this message translates to:
  /// **'Vânt'**
  String get wind;

  /// No description provided for @direction.
  ///
  /// In ro, this message translates to:
  /// **'Direcție'**
  String get direction;

  /// No description provided for @precipitation.
  ///
  /// In ro, this message translates to:
  /// **'Precipitații'**
  String get precipitation;

  /// No description provided for @threeDayForecast.
  ///
  /// In ro, this message translates to:
  /// **'Prognoză pe 3 zile'**
  String get threeDayForecast;

  /// No description provided for @sunrise.
  ///
  /// In ro, this message translates to:
  /// **'Răsărit'**
  String get sunrise;

  /// No description provided for @sunset.
  ///
  /// In ro, this message translates to:
  /// **'Apus'**
  String get sunset;

  /// No description provided for @illuminated.
  ///
  /// In ro, this message translates to:
  /// **'iluminată'**
  String get illuminated;

  /// No description provided for @moonAge.
  ///
  /// In ro, this message translates to:
  /// **'Vârsta Lunii: {value} zile'**
  String moonAge(String value);

  /// No description provided for @locationRequired.
  ///
  /// In ro, this message translates to:
  /// **'Locația este necesară'**
  String get locationRequired;

  /// No description provided for @notAvailable.
  ///
  /// In ro, this message translates to:
  /// **'Nu este disponibil'**
  String get notAvailable;

  /// No description provided for @or.
  ///
  /// In ro, this message translates to:
  /// **'sau'**
  String get or;

  /// No description provided for @mondayShort.
  ///
  /// In ro, this message translates to:
  /// **'Lun'**
  String get mondayShort;

  /// No description provided for @tuesdayShort.
  ///
  /// In ro, this message translates to:
  /// **'Mar'**
  String get tuesdayShort;

  /// No description provided for @wednesdayShort.
  ///
  /// In ro, this message translates to:
  /// **'Mie'**
  String get wednesdayShort;

  /// No description provided for @thursdayShort.
  ///
  /// In ro, this message translates to:
  /// **'Joi'**
  String get thursdayShort;

  /// No description provided for @fridayShort.
  ///
  /// In ro, this message translates to:
  /// **'Vin'**
  String get fridayShort;

  /// No description provided for @saturdayShort.
  ///
  /// In ro, this message translates to:
  /// **'Sâm'**
  String get saturdayShort;

  /// No description provided for @sundayShort.
  ///
  /// In ro, this message translates to:
  /// **'Dum'**
  String get sundayShort;

  /// No description provided for @savingCatch.
  ///
  /// In ro, this message translates to:
  /// **'Se salvează captura…'**
  String get savingCatch;

  /// No description provided for @saveCatch.
  ///
  /// In ro, this message translates to:
  /// **'Salvează captura'**
  String get saveCatch;

  /// No description provided for @catchLocationRequired.
  ///
  /// In ro, this message translates to:
  /// **'Folosește GPS-ul sau introdu numele locului capturii.'**
  String get catchLocationRequired;

  /// No description provided for @noCatchesYet.
  ///
  /// In ro, this message translates to:
  /// **'Nu există încă nicio captură.'**
  String get noCatchesYet;

  /// No description provided for @loadingEllipsis.
  ///
  /// In ro, this message translates to:
  /// **'Se încarcă…'**
  String get loadingEllipsis;

  /// No description provided for @waterUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Datele despre apă sunt indisponibile'**
  String get waterUnavailable;

  /// No description provided for @noStationAvailable.
  ///
  /// In ro, this message translates to:
  /// **'Nu există nicio stație disponibilă'**
  String get noStationAvailable;

  /// No description provided for @updateFailed.
  ///
  /// In ro, this message translates to:
  /// **'Actualizarea a eșuat'**
  String get updateFailed;

  /// No description provided for @waitingForData.
  ///
  /// In ro, this message translates to:
  /// **'Se așteaptă date'**
  String get waitingForData;

  /// No description provided for @unknown.
  ///
  /// In ro, this message translates to:
  /// **'Necunoscut'**
  String get unknown;

  /// No description provided for @noSource.
  ///
  /// In ro, this message translates to:
  /// **'Fără sursă'**
  String get noSource;

  /// No description provided for @rising.
  ///
  /// In ro, this message translates to:
  /// **'În creștere'**
  String get rising;

  /// No description provided for @stable.
  ///
  /// In ro, this message translates to:
  /// **'Stabil'**
  String get stable;

  /// No description provided for @falling.
  ///
  /// In ro, this message translates to:
  /// **'În scădere'**
  String get falling;

  /// No description provided for @weatherUnavailableShort.
  ///
  /// In ro, this message translates to:
  /// **'Date meteo indisponibile'**
  String get weatherUnavailableShort;

  /// No description provided for @mapLayers.
  ///
  /// In ro, this message translates to:
  /// **'Straturi hartă'**
  String get mapLayers;

  /// No description provided for @waterStations.
  ///
  /// In ro, this message translates to:
  /// **'Stații hidrometrice'**
  String get waterStations;

  /// No description provided for @communityReports.
  ///
  /// In ro, this message translates to:
  /// **'Rapoarte comunitare'**
  String get communityReports;

  /// No description provided for @favoriteStations.
  ///
  /// In ro, this message translates to:
  /// **'Stații favorite'**
  String get favoriteStations;

  /// No description provided for @signInForFavoriteStations.
  ///
  /// In ro, this message translates to:
  /// **'Autentifică-te pentru a filtra stațiile favorite.'**
  String get signInForFavoriteStations;

  /// No description provided for @retryLoadingReports.
  ///
  /// In ro, this message translates to:
  /// **'Reîncearcă încărcarea rapoartelor'**
  String get retryLoadingReports;

  /// No description provided for @loadingFishingReports.
  ///
  /// In ro, this message translates to:
  /// **'Se încarcă rapoartele de pescuit…'**
  String get loadingFishingReports;

  /// No description provided for @fishingFilters.
  ///
  /// In ro, this message translates to:
  /// **'Filtre de pescuit'**
  String get fishingFilters;

  /// No description provided for @photoCaptureFailed.
  ///
  /// In ro, this message translates to:
  /// **'Fotografia nu a putut fi realizată.'**
  String get photoCaptureFailed;

  /// No description provided for @cameraPhotoRequired.
  ///
  /// In ro, this message translates to:
  /// **'Realizează o fotografie cu camera.'**
  String get cameraPhotoRequired;

  /// No description provided for @catchSaved.
  ///
  /// In ro, this message translates to:
  /// **'Captura a fost salvată.'**
  String get catchSaved;

  /// No description provided for @requiredField.
  ///
  /// In ro, this message translates to:
  /// **'Câmp obligatoriu'**
  String get requiredField;

  /// No description provided for @positiveValueRequired.
  ///
  /// In ro, this message translates to:
  /// **'Introdu o valoare mai mare decât 0'**
  String get positiveValueRequired;

  /// No description provided for @exactLocation.
  ///
  /// In ro, this message translates to:
  /// **'Locație exactă'**
  String get exactLocation;

  /// No description provided for @approximateLocation.
  ///
  /// In ro, this message translates to:
  /// **'Locație aproximativă'**
  String get approximateLocation;

  /// No description provided for @hiddenLocation.
  ///
  /// In ro, this message translates to:
  /// **'Locație ascunsă'**
  String get hiddenLocation;

  /// No description provided for @reservoir.
  ///
  /// In ro, this message translates to:
  /// **'Lac de acumulare'**
  String get reservoir;

  /// No description provided for @canal.
  ///
  /// In ro, this message translates to:
  /// **'Canal'**
  String get canal;

  /// No description provided for @danube.
  ///
  /// In ro, this message translates to:
  /// **'Dunăre'**
  String get danube;

  /// No description provided for @other.
  ///
  /// In ro, this message translates to:
  /// **'Altul'**
  String get other;

  /// No description provided for @checkEmailConfirmation.
  ///
  /// In ro, this message translates to:
  /// **'Verifică e-mailul pentru a confirma contul.'**
  String get checkEmailConfirmation;

  /// No description provided for @passwordResetSent.
  ///
  /// In ro, this message translates to:
  /// **'Instrucțiunile pentru resetarea parolei au fost trimise prin e-mail.'**
  String get passwordResetSent;

  /// No description provided for @validEmailRequired.
  ///
  /// In ro, this message translates to:
  /// **'Introdu o adresă de e-mail validă'**
  String get validEmailRequired;

  /// No description provided for @minimumEightCharacters.
  ///
  /// In ro, this message translates to:
  /// **'Folosește cel puțin 8 caractere'**
  String get minimumEightCharacters;

  /// No description provided for @createAccountTitle.
  ///
  /// In ro, this message translates to:
  /// **'Creează cont'**
  String get createAccountTitle;

  /// No description provided for @resetPassword.
  ///
  /// In ro, this message translates to:
  /// **'Resetează parola'**
  String get resetPassword;

  /// No description provided for @welcomeBack.
  ///
  /// In ro, this message translates to:
  /// **'Bine ai revenit'**
  String get welcomeBack;

  /// No description provided for @recoveryInstructionsHint.
  ///
  /// In ro, this message translates to:
  /// **'Vom trimite instrucțiunile de recuperare la adresa ta de e-mail.'**
  String get recoveryInstructionsHint;

  /// No description provided for @signInToContinue.
  ///
  /// In ro, this message translates to:
  /// **'Autentifică-te pentru a continua în FluviAI.'**
  String get signInToContinue;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In ro, this message translates to:
  /// **'Parolele nu coincid'**
  String get passwordsDoNotMatch;

  /// No description provided for @register.
  ///
  /// In ro, this message translates to:
  /// **'Înregistrare'**
  String get register;

  /// No description provided for @sendResetEmail.
  ///
  /// In ro, this message translates to:
  /// **'Trimite e-mailul de resetare'**
  String get sendResetEmail;

  /// No description provided for @login.
  ///
  /// In ro, this message translates to:
  /// **'Autentificare'**
  String get login;

  /// No description provided for @signInForFavorites.
  ///
  /// In ro, this message translates to:
  /// **'Autentifică-te pentru a vedea stațiile favorite.'**
  String get signInForFavorites;

  /// No description provided for @favoritesUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Stațiile favorite sunt indisponibile.'**
  String get favoritesUnavailable;

  /// No description provided for @waterLevelUnavailable.
  ///
  /// In ro, this message translates to:
  /// **'Nivelul apei este indisponibil'**
  String get waterLevelUnavailable;

  /// No description provided for @nameRequired.
  ///
  /// In ro, this message translates to:
  /// **'Numele este obligatoriu.'**
  String get nameRequired;

  /// No description provided for @profileUpdated.
  ///
  /// In ro, this message translates to:
  /// **'Profilul a fost actualizat.'**
  String get profileUpdated;

  /// No description provided for @saving.
  ///
  /// In ro, this message translates to:
  /// **'Se salvează…'**
  String get saving;

  /// No description provided for @saveProfile.
  ///
  /// In ro, this message translates to:
  /// **'Salvează profilul'**
  String get saveProfile;

  /// No description provided for @reputationValue.
  ///
  /// In ro, this message translates to:
  /// **'Reputație {value}/100'**
  String reputationValue(int value);

  /// No description provided for @justNow.
  ///
  /// In ro, this message translates to:
  /// **'Chiar acum'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In ro, this message translates to:
  /// **'Acum {count, plural, =1{1 minut} other{{count} minute}}'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In ro, this message translates to:
  /// **'Acum {count, plural, =1{1 oră} other{{count} ore}}'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In ro, this message translates to:
  /// **'Acum {count, plural, =1{1 zi} other{{count} zile}}'**
  String daysAgo(int count);

  /// No description provided for @catches.
  ///
  /// In ro, this message translates to:
  /// **'Capturi'**
  String get catches;

  /// No description provided for @reputation.
  ///
  /// In ro, this message translates to:
  /// **'Reputație'**
  String get reputation;

  /// No description provided for @cachedDataFallback.
  ///
  /// In ro, this message translates to:
  /// **'Afișăm ultimele date salvate local.'**
  String get cachedDataFallback;
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
