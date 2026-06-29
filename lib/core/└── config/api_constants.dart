class ApiConstants {
  ApiConstants._();

  /// AFDJ - baza aplicației FishTrack
  static const String afdjBaseUrl = 'https://www.afdj.ro';

  /// OpenWeather (va fi folosit în Sprint 5)
  static const String openWeatherBaseUrl =
      'https://api.openweathermap.org/data/2.5';

  /// API Key OpenWeather
  static const String openWeatherApiKey = '';

  /// Timeout pentru request-uri
  static const Duration requestTimeout = Duration(seconds: 20);
}
