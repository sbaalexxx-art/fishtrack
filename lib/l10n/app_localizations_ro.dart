// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'AIFishMap';

  @override
  String get home => 'Acasă';

  @override
  String get map => 'Hartă';

  @override
  String get fishingMap => 'Hartă de pescuit';

  @override
  String get waterLevel => 'Nivelul apei';

  @override
  String get waterLevels => 'Nivelurile apei';

  @override
  String get stationDetails => 'Detalii stație';

  @override
  String get weather => 'Vreme';

  @override
  String get fishingInsights => 'Informații pentru pescuit';

  @override
  String get reports => 'Rapoarte';

  @override
  String get reportsArchive => 'Arhiva rapoartelor';

  @override
  String get recentCatches => 'Capturi recente';

  @override
  String get favorites => 'Favorite';

  @override
  String get favouriteStations => 'Stații favorite';

  @override
  String get notifications => 'Notificări';

  @override
  String get notificationPreferences => 'Preferințe notificări';

  @override
  String get profile => 'Profil';

  @override
  String get settings => 'Setări';

  @override
  String get community => 'Comunitate';

  @override
  String get retry => 'Reîncearcă';

  @override
  String get refresh => 'Reîmprospătează';

  @override
  String get cancel => 'Anulează';

  @override
  String get apply => 'Aplică';

  @override
  String get reset => 'Resetează';

  @override
  String get save => 'Salvează';

  @override
  String get close => 'Închide';

  @override
  String get loading => 'Se încarcă…';

  @override
  String get noData => 'Nu există date';

  @override
  String get errorGeneric => 'A apărut o eroare. Încearcă din nou.';

  @override
  String get unavailable => 'Indisponibil momentan.';

  @override
  String get noFavouriteStations => 'Nu ai încă stații favorite.';

  @override
  String get waterProviderUnavailable =>
      'Furnizorul de date despre apă este momentan indisponibil.';

  @override
  String get noWaterData => 'Momentan nu există date despre apă.';

  @override
  String get weatherUnavailable => 'Datele meteo sunt momentan indisponibile.';

  @override
  String get noRecentCatches => 'Nu există capturi recente.';

  @override
  String get recentCatchesLoadError =>
      'Capturile recente nu au putut fi încărcate.';

  @override
  String get noComments => 'Nu există încă niciun comentariu.';

  @override
  String get commentsUnavailable => 'Comentariile sunt momentan indisponibile.';

  @override
  String get report => 'Raportează';

  @override
  String get reportAbuse => 'Raportează abuz';

  @override
  String get createReport => 'Creează raport';

  @override
  String get reportSubmitted => 'Raportul a fost trimis pentru verificare.';

  @override
  String get noReports => 'Nu există rapoarte pentru această perioadă.';

  @override
  String get noCategoryData =>
      'Nu există date pe categorii pentru această perioadă.';

  @override
  String get reportCategory => 'Categoria raportului';

  @override
  String get descriptionOptional => 'Descriere (opțional)';

  @override
  String get useExactLocation => 'Folosește locația exactă';

  @override
  String get approximateLocationHint =>
      'Dezactivează pentru a partaja o locație aproximativă';

  @override
  String get positiveFactors => 'Factori pozitivi';

  @override
  String get negativeFactors => 'Factori negativi';

  @override
  String get bestTimeWindow => 'Cel mai bun interval';

  @override
  String get missingData => 'Date lipsă';

  @override
  String get noSignificantFactors => 'Nu există factori semnificativi.';

  @override
  String get notEnoughData => 'Nu există încă suficiente date';

  @override
  String confidence(int value) {
    return 'Încredere: $value%';
  }

  @override
  String get goldenHour => 'Ora de aur';

  @override
  String goldenHourValue(String value) {
    return 'Ora de aur: $value';
  }

  @override
  String get coordinates => 'Coordonate';

  @override
  String get waterLevelHistory => 'Istoricul nivelului apei';

  @override
  String get aiWaterInsight => 'Analiză AI a apei';

  @override
  String monitoredStations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stații monitorizate',
      one: '1 stație monitorizată',
    );
    return '$_temp0';
  }

  @override
  String days(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zile',
      one: '1 zi',
    );
    return '$_temp0';
  }

  @override
  String reportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rapoarte',
      one: '1 raport',
    );
    return '$_temp0';
  }

  @override
  String likes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aprecieri',
      one: '1 apreciere',
    );
    return '$_temp0';
  }

  @override
  String get comments => 'Comentarii';

  @override
  String get addComment => 'Adaugă un comentariu';

  @override
  String get catchDetails => 'Detalii captură';

  @override
  String get anglerProfile => 'Profil pescar';

  @override
  String get profileUnavailable => 'Profilul este indisponibil.';

  @override
  String get addCatch => 'Adaugă captură';

  @override
  String get species => 'Specie';

  @override
  String get weight => 'Greutate';

  @override
  String get weightUnit => 'Unitatea greutății';

  @override
  String get lengthCm => 'Lungime (cm)';

  @override
  String get notes => 'Notițe';

  @override
  String get placeNameOptional => 'Numele locului (opțional cu GPS)';

  @override
  String get placeHint => 'Lac, râu, acumulare, canal…';

  @override
  String get waterType => 'Tipul apei';

  @override
  String get locationPrivacy => 'Confidențialitatea locației';

  @override
  String get camera => 'Cameră';

  @override
  String get name => 'Nume';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Parolă';

  @override
  String get confirmPassword => 'Confirmă parola';

  @override
  String get forgotPassword => 'Ai uitat parola?';

  @override
  String get createAccount => 'Creează un cont';

  @override
  String get backToLogin => 'Înapoi la autentificare';

  @override
  String get setNewPassword => 'Setează o parolă nouă';

  @override
  String get newPassword => 'Parolă nouă';

  @override
  String get updating => 'Se actualizează…';

  @override
  String get updatePassword => 'Actualizează parola';

  @override
  String get logout => 'Deconectare';

  @override
  String get changeAvatar => 'Schimbă avatarul';

  @override
  String get quietHours => 'Interval silențios';

  @override
  String get startTime => 'Ora de început';

  @override
  String get endTime => 'Ora de sfârșit';

  @override
  String get groupSimilarNotifications => 'Grupează notificările similare';

  @override
  String get duplicateCooldown => 'Interval pentru duplicate';

  @override
  String get notificationPreferencesTooltip => 'Preferințe notificări';

  @override
  String get signInForNotificationPreferences =>
      'Autentifică-te pentru a gestiona preferințele notificărilor.';

  @override
  String get categories => 'Categorii';

  @override
  String get priority => 'Prioritate';

  @override
  String get clearReadNotifications => 'Șterge notificările citite';

  @override
  String get notificationsUnavailable => 'Notificările sunt indisponibile.';

  @override
  String get noNotifications => 'Nu există încă notificări.';

  @override
  String get communityUnavailable => 'Fluxul comunității este indisponibil.';

  @override
  String get noCommunityActivity => 'Nu există încă activitate în comunitate.';

  @override
  String get standard => 'Standard';

  @override
  String get satellite => 'Satelit';

  @override
  String get comingSoon => 'În curând';

  @override
  String get fishingMode => 'Mod pescuit';

  @override
  String get riverAndLake => 'Râu și lac';

  @override
  String get river => 'Râu';

  @override
  String get lake => 'Lac';

  @override
  String get allSpecies => 'Toate speciile';

  @override
  String get gpsRadius => 'Rază GPS';

  @override
  String get anyDistance => 'Orice distanță';

  @override
  String get filterByWaterLevel => 'Filtrează după nivelul apei';

  @override
  String get waterTrend => 'Tendința apei';

  @override
  String get difficulty => 'Dificultate';

  @override
  String get anyDifficulty => 'Orice dificultate';

  @override
  String get easy => 'Ușor';

  @override
  String get moderate => 'Moderat';

  @override
  String get hard => 'Dificil';

  @override
  String get favoritesOnly => 'Doar favorite';

  @override
  String get searchStation => 'Caută numele stației…';

  @override
  String get noStationFound => 'Nu a fost găsită nicio stație.';

  @override
  String get stationSearchUnavailable =>
      'Căutarea stațiilor este indisponibilă.';

  @override
  String get viewAll => 'Vezi toate';

  @override
  String get retryRecentCatches => 'Reîncearcă încărcarea capturilor recente';

  @override
  String get youAreHere => 'Ești aici';
}
