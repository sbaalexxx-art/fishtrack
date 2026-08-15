import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../screens/weather_page.dart';
import '../../services/weather_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

enum _WeatherHomeDisplayState { offline, stale, unavailable, error }

_WeatherHomeDisplayState? _resolveWeatherHomeDisplayState(
  WeatherHomeResult? result, {
  required bool isLoading,
  required bool hasSnapshotError,
  required bool isDefinitelyOffline,
}) {
  if (isDefinitelyOffline) return _WeatherHomeDisplayState.offline;
  if (hasSnapshotError) return _WeatherHomeDisplayState.error;
  if (result == null) {
    return isLoading ? null : _WeatherHomeDisplayState.unavailable;
  }
  return switch (result.status) {
    WeatherHomeStatus.available => null,
    WeatherHomeStatus.staleFallback => _WeatherHomeDisplayState.stale,
    WeatherHomeStatus.providerError => _WeatherHomeDisplayState.error,
    WeatherHomeStatus.locationUnavailable ||
    WeatherHomeStatus.unavailable => _WeatherHomeDisplayState.unavailable,
  };
}

class WeatherCardPremium extends StatefulWidget {
  const WeatherCardPremium({
    super.key,
    required this.layout,
    this.fallbackStation,
    this.onMetricPressed,
  });

  final HomePremiumLayout layout;
  final Station? fallbackStation;
  final ValueChanged<WeatherPageSection>? onMetricPressed;

  @override
  State<WeatherCardPremium> createState() => _WeatherCardPremiumState();
}

class _WeatherCardPremiumState extends State<WeatherCardPremium> {
  static const _missingValue = '\u2014';

  final Connectivity _connectivity = Connectivity();
  final WeatherService _weatherService = WeatherService();
  late Future<WeatherHomeResult> _weatherFuture;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _connectivityKnown = false;
  bool _isDefinitelyOffline = false;

  @override
  void initState() {
    super.initState();
    _weatherFuture = _loadWeather();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );
    unawaited(_checkInitialConnectivity());
  }

  @override
  void didUpdateWidget(covariant WeatherCardPremium oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fallbackStation?.id != widget.fallbackStation?.id) {
      _weatherFuture = _loadWeather();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<WeatherHomeResult> _loadWeather({bool forceRefresh = false}) {
    return _weatherService.getHomeWeatherResult(
      fallbackStation: widget.fallbackStation,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      _updateConnectivity(await _connectivity.checkConnectivity());
    } on Exception {
      // Keep the provider-derived state until connectivity is known.
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final isDefinitelyOffline =
        results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
    if (_connectivityKnown && _isDefinitelyOffline == isDefinitelyOffline) {
      return;
    }
    final reconnected =
        _connectivityKnown && _isDefinitelyOffline && !isDefinitelyOffline;
    setState(() {
      _connectivityKnown = true;
      _isDefinitelyOffline = isDefinitelyOffline;
      if (reconnected) {
        _weatherFuture = _loadWeather(forceRefresh: true);
      }
    });
  }

  void _retryWeather() {
    setState(() => _weatherFuture = _loadWeather(forceRefresh: true));
  }

  String _localizedCondition(BuildContext context, String? condition) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';

    final value = condition?.trim();
    if (value == null || value.isEmpty) {
      return context.l10n.loadingEllipsis;
    }

    if (!isRo) {
      return value;
    }

    switch (value.toLowerCase()) {
      case 'clear sky':
        return 'Cer senin';
      case 'partly cloudy':
        return 'Parțial înnorat';
      case 'overcast':
        return 'Cer acoperit';
      case 'fog':
        return 'Ceață';
      case 'drizzle':
        return 'Burniță';
      case 'rain':
        return 'Ploaie';
      case 'snow':
        return 'Ninsoare';
      case 'rain showers':
        return 'Averse de ploaie';
      case 'snow showers':
        return 'Averse de ninsoare';
      case 'thunderstorm':
        return 'Furtună';
      case 'unknown':
        return 'Necunoscut';
      default:
        return value;
    }
  }

  String _localizedWindDirection(BuildContext context, String value) {
    if (Localizations.localeOf(context).languageCode != 'ro') return value;
    return switch (value.trim().toUpperCase()) {
      'SW' => 'SV',
      'W' => 'V',
      'NW' => 'NV',
      _ => value,
    };
  }

  String _pressureLabel(double? pressure) {
    if (pressure == null || !pressure.isFinite) {
      return _missingValue;
    }
    return '${pressure.round()} hPa';
  }

  String? _contextLabel(BuildContext context, WeatherHomeResult result) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    if (result.locationSource == WeatherLocationSource.stationFallback ||
        result.locationSource == WeatherLocationSource.defaultFallback) {
      return isRo ? 'Loca\u021bie estimat\u0103' : 'Estimated location';
    }
    return null;
  }

  VoidCallback? _metricAction(WeatherPageSection section) {
    final onMetricPressed = widget.onMetricPressed;
    if (onMetricPressed == null) return null;
    return () => onMetricPressed(section);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherHomeResult>(
      future: _weatherFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final weather = result?.data;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            result == null;
        final displayState = _resolveWeatherHomeDisplayState(
          result,
          isLoading: isLoading,
          hasSnapshotError: snapshot.hasError,
          isDefinitelyOffline: _connectivityKnown && _isDefinitelyOffline,
        );
        final temperature = weather == null
            ? null
            : '${weather.temperature.round()}\u00b0';
        final neutralValue = isLoading
            ? context.l10n.loadingEllipsis
            : _missingValue;
        final conditionLabel = isLoading
            ? context.l10n.loadingEllipsis
            : weather != null
            ? _localizedCondition(context, weather.condition)
            : context.l10n.weatherUnavailableShort;
        final contextLabel = weather == null || result == null
            ? null
            : _contextLabel(context, result);
        final condition = contextLabel == null
            ? conditionLabel
            : '$conditionLabel \u00b7 $contextLabel';
        final windSpeed = weather == null
            ? null
            : '${weather.windSpeed.toStringAsFixed(1)} km/h';
        final windDirection = weather == null
            ? null
            : _localizedWindDirection(context, weather.windDirectionLabel);
        final wind = windSpeed == null || windDirection == null
            ? neutralValue
            : '$windSpeed $windDirection';
        final pressure = weather == null
            ? neutralValue
            : _pressureLabel(weather.pressure);
        final precipitation = weather == null
            ? neutralValue
            : weather.precipitationProbability.isFinite
            ? '${weather.precipitationProbability.round()}%'
            : _missingValue;
        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = widget.layout;
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final dense =
                  constraints.maxWidth < 360 ||
                  constraints.maxHeight <= 132 ||
                  textScale >= 1.2;
              final accessibilityLayout =
                  textScale >= 1.3 || constraints.maxWidth < 330;
              final exposeMetricDeepLinks = !accessibilityLayout;
              final cardPadding = layout.isSmallPhone
                  ? 8.0
                  : (layout.isTablet ? 11.0 : 9.0);
              final primaryMetrics = [
                _WeatherReading(
                  icon: Icons.air_rounded,
                  label: context.l10n.wind,
                  value: wind,
                  accentColor: const Color(0xFF62D7F5),
                  dense: dense,
                  horizontal: accessibilityLayout,
                  onTap: exposeMetricDeepLinks
                      ? _metricAction(WeatherPageSection.wind)
                      : null,
                ),
                _WeatherReading(
                  icon: Icons.speed_rounded,
                  label: context.l10n.pressure,
                  value: pressure,
                  accentColor: const Color(0xFFA4D96C),
                  dense: dense,
                  horizontal: accessibilityLayout,
                  onTap: exposeMetricDeepLinks
                      ? _metricAction(WeatherPageSection.pressure)
                      : null,
                ),
                _WeatherReading(
                  icon: Icons.umbrella_outlined,
                  label: context.l10n.weatherHomeRain,
                  value: precipitation,
                  accentColor: const Color(0xFF7EA8FF),
                  dense: dense,
                  horizontal: accessibilityLayout,
                  onTap: exposeMetricDeepLinks
                      ? _metricAction(WeatherPageSection.precipitation)
                      : null,
                ),
              ];

              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: cardPadding,
                  vertical: cardPadding * .76,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF102630), Color(0xFF071821)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF39C6E6).withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF12D8D6).withValues(alpha: 0.06),
                      blurRadius: 18,
                      spreadRadius: -8,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: dense ? 24 : 28,
                          height: dense ? 24 : 28,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFC84A,
                            ).withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFFFFC84A,
                              ).withValues(alpha: 0.46),
                            ),
                          ),
                          child: Icon(
                            Icons.wb_sunny_rounded,
                            color: const Color(0xFFFFC84A),
                            size: (dense ? 14 : 16) * layout.iconScale,
                          ),
                        ),
                        SizedBox(width: dense ? 6 : 8),
                        Expanded(
                          child: Text(
                            context.l10n.weather.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFFF4FCFF),
                              fontWeight: FontWeight.w800,
                              fontSize:
                                  (dense ? 13.5 : 15.5) * layout.titleFontScale,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        SizedBox(width: dense ? 4 : 8),
                        if (isLoading)
                          SizedBox.square(
                            dimension: dense ? 16 : 18,
                            child: const CircularProgressIndicator(
                              strokeWidth: 1.8,
                            ),
                          )
                        else if (displayState != null)
                          _WeatherStatusBadge(
                            state: displayState,
                            compact: dense,
                            onRetry:
                                displayState ==
                                        _WeatherHomeDisplayState.error ||
                                    displayState ==
                                        _WeatherHomeDisplayState.unavailable
                                ? _retryWeather
                                : null,
                          ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white54,
                          size: 18 * layout.iconScale,
                        ),
                      ],
                    ),
                    SizedBox(height: dense ? 4 : 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: dense ? 4 : 5,
                            child: _TemperaturePreview(
                              value: temperature ?? neutralValue,
                              condition: condition,
                              dense: dense,
                              onTap: exposeMetricDeepLinks
                                  ? _metricAction(
                                      WeatherPageSection.temperature,
                                    )
                                  : null,
                            ),
                          ),
                          Container(
                            width: 1,
                            margin: EdgeInsets.symmetric(
                              horizontal: dense ? 6 : 10,
                              vertical: dense ? 3 : 5,
                            ),
                            color: const Color(
                              0xFF62D7F5,
                            ).withValues(alpha: 0.20),
                          ),
                          if (accessibilityLayout)
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < primaryMetrics.length;
                                    index++
                                  ) ...[
                                    Expanded(child: primaryMetrics[index]),
                                    if (index != primaryMetrics.length - 1)
                                      Container(
                                        height: 1,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 1,
                                        ),
                                        color: const Color(
                                          0xFFBFE9F4,
                                        ).withValues(alpha: 0.10),
                                      ),
                                  ],
                                ],
                              ),
                            )
                          else
                            for (
                              var index = 0;
                              index < primaryMetrics.length;
                              index++
                            ) ...[
                              Expanded(flex: 3, child: primaryMetrics[index]),
                              if (index != primaryMetrics.length - 1)
                                Container(
                                  width: 1,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: dense ? 3 : 6,
                                    vertical: dense ? 8 : 10,
                                  ),
                                  color: const Color(
                                    0xFFBFE9F4,
                                  ).withValues(alpha: 0.10),
                                ),
                            ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TemperaturePreview extends StatelessWidget {
  const _TemperaturePreview({
    required this.value,
    required this.condition,
    required this.dense,
    this.onTap,
  });

  final String value;
  final String condition;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);

    return Semantics(
      button: onTap != null,
      label: context.l10n.weatherHomeDegrees,
      value: '$value, $condition',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: dense ? 3 : 4,
              margin: EdgeInsets.symmetric(vertical: dense ? 5 : 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC84A),
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFC84A).withValues(alpha: 0.28),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            SizedBox(width: dense ? 7 : 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        color: const Color(0xFFFFFFFF),
                        fontSize: (dense ? 28 : 34) * layout.titleFontScale,
                        height: .95,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  SizedBox(height: dense ? 1 : 3),
                  Text(
                    condition,
                    maxLines: dense ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: const Color(0xFFDCECF1),
                      fontSize: (dense ? 10.5 : 12) * layout.bodyFontScale,
                      height: 1.08,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherReading extends StatelessWidget {
  const _WeatherReading({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.dense,
    required this.horizontal,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final bool dense;
  final bool horizontal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);

    return Semantics(
      button: onTap != null,
      label: label,
      value: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: horizontal
            ? Row(
                children: [
                  Icon(icon, color: accentColor, size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: Color.lerp(
                          const Color(0xFFDCECF1),
                          accentColor,
                          0.18,
                        ),
                        fontSize: 9.5 * layout.bodyFontScale,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 3,
                    child: FittedBox(
                      alignment: Alignment.centerRight,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: TextStyle(
                          color: const Color(0xFFFFFFFF),
                          fontSize: 12.5 * layout.bodyFontScale,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: accentColor, size: dense ? 13 : 15),
                      SizedBox(width: dense ? 3 : 5),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: Color.lerp(
                              const Color(0xFFDCECF1),
                              accentColor,
                              0.18,
                            ),
                            fontSize: (dense ? 9.5 : 11) * layout.bodyFontScale,
                            height: 1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: dense ? 3 : 5),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: TextStyle(
                          color: const Color(0xFFFFFFFF),
                          fontSize: (dense ? 15.5 : 18) * layout.bodyFontScale,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _WeatherStatusBadge extends StatelessWidget {
  const _WeatherStatusBadge({
    required this.state,
    required this.compact,
    this.onRetry,
  });

  final _WeatherHomeDisplayState state;
  final bool compact;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final (label, color, icon) = switch (state) {
      _WeatherHomeDisplayState.offline => (
        'OFFLINE',
        const Color(0xFF9AA7B2),
        Icons.cloud_off_rounded,
      ),
      _WeatherHomeDisplayState.stale => (
        isRo ? 'DATE VECHI' : 'STALE',
        const Color(0xFFFFA24A),
        Icons.schedule_rounded,
      ),
      _WeatherHomeDisplayState.unavailable => (
        isRo ? 'INDISPONIBIL' : 'UNAVAILABLE',
        const Color(0xFF9AA7B2),
        Icons.cloud_off_outlined,
      ),
      _WeatherHomeDisplayState.error => (
        isRo ? 'EROARE' : 'ERROR',
        const Color(0xFFFF6B6B),
        Icons.error_outline_rounded,
      ),
    };

    final badge = Container(
      constraints: BoxConstraints(maxWidth: compact ? 86 : 104),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: compact ? 11 : 12),
            const SizedBox(width: 3),
            Text(
              label,
              maxLines: 1,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontSize: compact ? 8.5 : 9.5,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: .34,
              ),
            ),
          ],
        ),
      ),
    );

    final retry = onRetry;
    if (retry == null) {
      return Semantics(
        label: label,
        child: Tooltip(message: label, child: badge),
      );
    }
    return Semantics(
      label: '$label. ${context.l10n.retry}',
      button: true,
      onTap: retry,
      child: Tooltip(
        message: context.l10n.retry,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: retry,
            child: Center(child: badge),
          ),
        ),
      ),
    );
  }
}
