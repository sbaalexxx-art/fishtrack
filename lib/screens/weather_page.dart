import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../l10n/l10n.dart';
import '../models/weather.dart';
import '../services/astronomy_service.dart';
import '../services/weather_service.dart';
import '../widgets/weather/weather_visuals.dart';

enum WeatherPageSection {
  temperature,
  wind,
  pressure,
  humidity,
  precipitation,
  solunar,
}

WeatherPageSection weatherPageInitialSection(WeatherPageSection? section) =>
    section ?? WeatherPageSection.temperature;

class WeatherPageSectionSelection {
  WeatherPageSectionSelection(WeatherPageSection? initialSection)
    : selected = weatherPageInitialSection(initialSection);

  WeatherPageSection selected;

  bool select(WeatherPageSection section) {
    if (selected == section) return false;
    selected = section;
    return true;
  }
}

double normalizedMoonIllumination(double illuminationPercent) {
  if (!illuminationPercent.isFinite) return 0;
  return illuminationPercent.clamp(0, 100).toDouble() / 100;
}

bool moonPhaseIsWaxing(String phaseName) {
  final phase = phaseName.toLowerCase();
  return !phase.contains('waning') && !phase.contains('last quarter');
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key, this.initialSection, this.initialWeather});

  final WeatherPageSection? initialSection;

  /// Already-resolved Weather from the canonical Home snapshot.
  ///
  /// When present, Weather Hub renders it immediately and does not repeat
  /// location/provider work that Home has just completed.
  final WeatherHomeResult? initialWeather;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _service = WeatherService();
  final GlobalKey _sectionDetailKey = GlobalKey();
  late final WeatherPageSectionSelection _selection;
  late Future<_WeatherViewData> _weather;
  bool _fallbackMessageShown = false;

  @override
  void initState() {
    super.initState();
    _selection = WeatherPageSectionSelection(widget.initialSection);
    final initial = _viewFromHomeResult(widget.initialWeather);
    _weather = initial == null
        ? _load()
        : Future<_WeatherViewData>.value(initial);
  }

  _WeatherViewData? _viewFromHomeResult(WeatherHomeResult? home) {
    final data = home?.data;
    final latitude = home?.latitude;
    final longitude = home?.longitude;
    if (data == null || latitude == null || longitude == null) return null;
    if (!latitude.isFinite || !longitude.isFinite) return null;

    return _WeatherViewData(
      weather: data,
      astronomy: const AstronomyService().calculate(
        dateTime: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
      ),
      isStaleFallback:
          home!.isStale || home.status == WeatherHomeStatus.staleFallback,
    );
  }

  Future<_WeatherViewData> _load({bool forceRefresh = false}) async {
    final home = await _service.getHomeWeatherResult(
      forceRefresh: forceRefresh,
    );
    final data = home.data;
    if (data == null) {
      throw WeatherServiceException(
        home.safeDiagnosticMessage ?? 'Weather data is unavailable.',
      );
    }

    final latitude = home.latitude;
    final longitude = home.longitude;
    final astronomy =
        latitude != null &&
            longitude != null &&
            latitude.isFinite &&
            longitude.isFinite
        ? const AstronomyService().calculate(
            dateTime: DateTime.now(),
            latitude: latitude,
            longitude: longitude,
          )
        : await _service.getAstronomyContext();

    return _WeatherViewData(
      weather: data,
      astronomy: astronomy,
      isStaleFallback:
          home.isStale || home.status == WeatherHomeStatus.staleFallback,
    );
  }

  Future<void> _refresh() async {
    final next = _load(forceRefresh: true);
    setState(() => _weather = next);
    await next;
  }

  void _selectSection(WeatherPageSection section) {
    if (_selection.select(section)) {
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _sectionDetailKey.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: .08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          Localizations.localeOf(context).languageCode.toLowerCase() == 'ro'
              ? 'Vreme & Solunar'
              : 'Weather & Solunar',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const ValueKey('weather-alerts-action'),
            tooltip:
                Localizations.localeOf(context).languageCode.toLowerCase() ==
                    'ro'
                ? 'Alerte meteo'
                : 'Weather alerts',
            onPressed: () =>
                AppNavigator.open<void>(context, AppDestination.alerts),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<_WeatherViewData>(
          future: _weather,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const _WeatherLoadingSurface();
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _WeatherMessage(onRetry: _refresh);
            }
            final data = snapshot.data!;
            if (data.isStaleFallback && !_fallbackMessageShown) {
              _fallbackMessageShown = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.cachedDataFallback)),
                );
              });
            }
            return _WeatherContent(
              weather: data.weather,
              astronomy: data.astronomy,
              section: _selection.selected,
              isStaleFallback: data.isStaleFallback,
              onSectionChanged: _selectSection,
              sectionDetailKey: _sectionDetailKey,
              onRefresh: _refresh,
            );
          },
        ),
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({
    required this.weather,
    required this.astronomy,
    required this.section,
    required this.isStaleFallback,
    required this.onSectionChanged,
    required this.sectionDetailKey,
    required this.onRefresh,
  });

  final WeatherData weather;
  final AstronomyContext astronomy;
  final WeatherPageSection section;
  final bool isStaleFallback;
  final ValueChanged<WeatherPageSection> onSectionChanged;
  final GlobalKey sectionDetailKey;
  final Future<void> Function() onRefresh;

  bool _isRomanian(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';

  @override
  Widget build(BuildContext context) {
    final isRomanian = _isRomanian(context);
    final graphSection = section == WeatherPageSection.solunar
        ? WeatherPageSection.temperature
        : section;

    final content = <Widget>[
      _AtmosphericHero(
        weather: weather,
        isRomanian: isRomanian,
        stale: isStaleFallback,
      ),
      const SizedBox(height: 8),
      _WeatherMetricRail(selected: graphSection, onMetricTap: onSectionChanged),
      const SizedBox(height: 8),
      KeyedSubtree(
        key: sectionDetailKey,
        child: _SectionPanel(weather: weather, section: graphSection),
      ),
      const SizedBox(height: 8),
      _SevenDayForecast(weather: weather),
      const SizedBox(height: 8),
      _FishingWeatherSummary(weather: weather),
      const SizedBox(height: 8),
      _SolunarPanel(weather: weather, astronomy: astronomy),
    ];

    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 760 ? 24.0 : 16.0;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AtmosphericHero extends StatelessWidget {
  const _AtmosphericHero({
    required this.weather,
    required this.isRomanian,
    required this.stale,
  });

  final WeatherData weather;
  final bool isRomanian;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = weatherVisualKind(weather.condition);
    final daylight = weatherIsDaylight(weather);
    final gradient = weatherAtmosphereGradient(
      kind,
      isDaylight: daylight,
      brightness: theme.brightness,
    );
    final foreground = theme.brightness == Brightness.dark || !daylight
        ? Colors.white
        : const Color(0xFF10232D);
    final today = weather.forecast.isEmpty ? null : weather.forecast.first;

    return Semantics(
      container: true,
      label:
          '${weatherConditionLabel(weather.condition, isRomanian: isRomanian)}, '
          '${weather.temperature.round()} degrees',
      child: Container(
        constraints: const BoxConstraints(minHeight: 166),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: foreground.withValues(alpha: .09)),
          boxShadow: [
            BoxShadow(
              blurRadius: 22,
              offset: const Offset(0, 9),
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? .13 : .06,
              ),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: WeatherAtmosphereBackdrop(
                kind: kind,
                isDaylight: daylight,
                foreground: foreground,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 13, 15, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${isRomanian ? 'ACUM' : 'NOW'} · '
                          '${_clock(context, weather.observedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .74),
                            fontSize: 9.5,
                            letterSpacing: .7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        stale
                            ? Icons.cloud_off_rounded
                            : Icons.cloud_done_outlined,
                        size: 14,
                        color: foreground.withValues(alpha: .68),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        fit: FlexFit.loose,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            stale
                                ? (isRomanian ? 'SALVAT' : 'CACHED')
                                : 'OPEN-METEO',
                            maxLines: 1,
                            style: TextStyle(
                              color: foreground.withValues(alpha: .68),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${weather.temperature.round()}°',
                              style: TextStyle(
                                color: foreground,
                                fontSize: 50,
                                height: .90,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -2.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(
                                  weatherVisualIcon(kind, isDaylight: daylight),
                                  size: 17,
                                  color: foreground.withValues(alpha: .92),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    weatherConditionLabel(
                                      weather.condition,
                                      isRomanian: isRomanian,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _heroSecondaryLine(
                                weather,
                                today,
                                isRomanian: isRomanian,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withValues(alpha: .72),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _WindCompass(
                        directionDegrees: weather.windDirectionDegrees,
                        directionLabel: weather.windDirectionLabel,
                        speed: weather.windSpeed,
                        gusts: weather.windGusts,
                        foreground: foreground,
                        isRomanian: isRomanian,
                      ),
                    ],
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

class _WindCompass extends StatelessWidget {
  const _WindCompass({
    required this.directionDegrees,
    required this.directionLabel,
    required this.speed,
    required this.gusts,
    required this.foreground,
    required this.isRomanian,
  });

  final double directionDegrees;
  final String directionLabel;
  final double speed;
  final double gusts;
  final Color foreground;
  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final direction = directionDegrees.isFinite ? directionDegrees : 0.0;
    return Container(
      width: 82,
      height: 86,
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: foreground.withValues(alpha: .09)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: foreground.withValues(alpha: .24),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  child: Text(
                    'N',
                    style: TextStyle(
                      color: foreground.withValues(alpha: .56),
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: direction * math.pi / 180,
                  child: Icon(
                    Icons.navigation_rounded,
                    size: 30,
                    color: foreground.withValues(alpha: .92),
                  ),
                ),
              ],
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$directionLabel ${speed.round()}',
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${isRomanian ? 'raf.' : 'gust'} ${gusts.round()}',
              maxLines: 1,
              style: TextStyle(
                color: foreground.withValues(alpha: .64),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherMetricRail extends StatelessWidget {
  const _WeatherMetricRail({required this.selected, required this.onMetricTap});

  final WeatherPageSection selected;
  final ValueChanged<WeatherPageSection> onMetricTap;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final metrics = <_WeatherMetricData>[
      _WeatherMetricData(
        icon: Icons.device_thermostat_rounded,
        label: isRomanian ? 'Temp' : 'Temp',
        section: WeatherPageSection.temperature,
      ),
      _WeatherMetricData(
        icon: Icons.air_rounded,
        label: isRomanian ? 'Vânt' : 'Wind',
        section: WeatherPageSection.wind,
      ),
      _WeatherMetricData(
        icon: Icons.speed_rounded,
        label: isRomanian ? 'Presiune' : 'Pressure',
        section: WeatherPageSection.pressure,
      ),
      _WeatherMetricData(
        icon: Icons.water_drop_rounded,
        label: isRomanian ? 'Umiditate' : 'Humidity',
        section: WeatherPageSection.humidity,
      ),
      _WeatherMetricData(
        icon: Icons.umbrella_rounded,
        label: isRomanian ? 'Ploaie' : 'Rain',
        section: WeatherPageSection.precipitation,
      ),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: metrics.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final metric = metrics[index];
          final isSelected = metric.section == selected;
          return _WeatherMetricTile(
            data: metric,
            selected: isSelected,
            onTap: () => onMetricTap(metric.section),
          );
        },
      ),
    );
  }
}

class _WeatherMetricData {
  const _WeatherMetricData({
    required this.icon,
    required this.label,
    required this.section,
  });

  final IconData icon;
  final String label;
  final WeatherPageSection section;
}

class _WeatherMetricTile extends StatelessWidget {
  const _WeatherMetricTile({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _WeatherMetricData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _sectionAccent(context, data.section);
    final radius = BorderRadius.circular(14);

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${data.label}. '
          '${Localizations.localeOf(context).languageCode.toLowerCase() == 'ro' ? 'Arată evoluția pe 24 de ore' : 'Show 24 hour evolution'}',
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: .13)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: .34,
                    ),
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: .52)
                    : theme.colorScheme.outlineVariant.withValues(alpha: .20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(data.icon, size: 14, color: accent),
                const SizedBox(width: 5),
                Text(
                  data.label,
                  style: TextStyle(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FishingWeatherSummary extends StatelessWidget {
  const _FishingWeatherSummary({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final wind = weather.windSpeed;
    final rain = weather.precipitationProbability;
    final windText = wind < 12
        ? (isRomanian ? 'vânt slab' : 'light wind')
        : wind < 25
        ? (isRomanian ? 'vânt moderat' : 'moderate wind')
        : (isRomanian ? 'vânt puternic' : 'strong wind');
    final rainText = rain < 30
        ? (isRomanian ? 'risc redus de ploaie' : 'low rain risk')
        : rain < 60
        ? (isRomanian ? 'ploaie posibilă' : 'rain possible')
        : (isRomanian ? 'risc ridicat de ploaie' : 'high rain risk');
    final pressureText = weather.pressure == null
        ? (isRomanian ? 'presiune indisponibilă' : 'pressure unavailable')
        : '${weather.pressure!.round()} hPa';

    final secondaryFacts = <String>[
      if (weather.uvIndex != null && weather.uvIndex!.isFinite)
        'UV ${weather.uvIndex!.toStringAsFixed(1)}',
      if (weather.visibility != null && weather.visibility!.isFinite)
        '${isRomanian ? 'Viz.' : 'Vis.'} ${(weather.visibility! / 1000).toStringAsFixed(weather.visibility! >= 10000 ? 0 : 1)} km',
      if (weather.dewPoint != null && weather.dewPoint!.isFinite)
        '${isRomanian ? 'P. rouă' : 'Dew'} ${weather.dewPoint!.round()}°',
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: .12),
            theme.colorScheme.tertiary.withValues(alpha: .07),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: .18),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.water_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRomanian
                      ? 'Condiții meteo pentru pescuit'
                      : 'Weather for fishing',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$windText · $rainText · $pressureText',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                if (secondaryFacts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondaryFacts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: .86,
                      ),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  isRomanian
                      ? 'Interpretare meteo deterministă; nu garantează activitatea peștilor.'
                      : 'Deterministic weather interpretation; it does not guarantee fish activity.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: .78,
                    ),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({required this.weather, required this.section});

  final WeatherData weather;
  final WeatherPageSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final accent = _sectionAccent(context, section);

    final cutoff = weather.observedAt.subtract(const Duration(minutes: 45));
    final futureHours = weather.hourlyForecast
        .where((hour) => !hour.time.isBefore(cutoff))
        .take(24)
        .toList(growable: false);
    final hours = futureHours.length >= 2
        ? futureHours
        : weather.hourlyForecast.take(24).toList(growable: false);

    final values = hours
        .map((hour) => _hourValue(hour, section))
        .toList(growable: false);
    final finite = values
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    final timeLabels = hours
        .map((hour) => _clock(context, hour.time))
        .toList(growable: false);
    final valueLabels = values
        .map(
          (value) => value == null || !value.isFinite
              ? '—'
              : _formatNumber(value, section),
        )
        .toList(growable: false);

    final range = finite.isEmpty
        ? '—'
        : '${_formatNumber(finite.reduce((a, b) => a < b ? a : b), section)} – '
              '${_formatNumber(finite.reduce((a, b) => a > b ? a : b), section)}';

    return _SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_sectionIcon(section), size: 16, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_sectionLabel(section, isRomanian: isRomanian)} · 24h',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _currentValue(
                        context,
                        weather,
                        section,
                        isRomanian: isRomanian,
                      ),
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isRomanian
                        ? 'Glisează pentru oră și valoare'
                        : 'Drag for time and value',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      range,
                      maxLines: 1,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            WeatherInteractiveSeriesChart(
              values: values,
              timeLabels: timeLabels,
              valueLabels: valueLabels,
              color: accent,
              height: 112,
            ),
            const SizedBox(height: 3),
            _TimeAxis24h(hours: hours),
          ],
        ),
      ),
    );
  }
}

class _TimeAxis24h extends StatelessWidget {
  const _TimeAxis24h({required this.hours});

  final List<WeatherForecastHour> hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (hours.isEmpty) return const SizedBox.shrink();

    final indexes = <int>{
      0,
      if (hours.length > 6) 6,
      if (hours.length > 12) 12,
      if (hours.length > 18) 18,
      hours.length - 1,
    }.toList()..sort();

    return Row(
      children: [
        for (var position = 0; position < indexes.length; position++)
          Expanded(
            child: Text(
              position == 0
                  ? (Localizations.localeOf(
                              context,
                            ).languageCode.toLowerCase() ==
                            'ro'
                        ? 'Acum'
                        : 'Now')
                  : _clock(context, hours[indexes[position]].time),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: position == 0
                  ? TextAlign.left
                  : position == indexes.length - 1
                  ? TextAlign.right
                  : TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: .78,
                ),
                fontSize: 8.5,
                fontWeight: position == 0 ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _SolunarPanel extends StatelessWidget {
  const _SolunarPanel({required this.weather, required this.astronomy});

  final WeatherData weather;
  final AstronomyContext astronomy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final accent = _sectionAccent(context, WeatherPageSection.solunar);
    final moon = astronomy.moon;
    return _SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MoonPhaseDisc(
                  illumination: normalizedMoonIllumination(
                    moon.illuminationPercent,
                  ),
                  waxing: moonPhaseIsWaxing(moon.name),
                  color: accent,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localizedMoonPhase(moon.name, isRomanian: isRomanian),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${moon.illuminationPercent.round()}% '
                        '${isRomanian ? 'iluminată' : 'illuminated'} · '
                        '${moon.ageDays.toStringAsFixed(1)} ${isRomanian ? 'zile' : 'days'}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isRomanian
                  ? 'Astronomie locală calculată pentru coordonate; nu este o garanție a activității peștilor.'
                  : 'Local astronomy calculated for coordinates; it is not a guarantee of fish activity.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            _SolunarRow(
              icon: Icons.wb_twilight_rounded,
              label: isRomanian ? 'Răsărit' : 'Sunrise',
              value: weather.sunrise == null
                  ? '—'
                  : _clock(context, weather.sunrise!),
              accent: accent,
            ),
            _SolunarRow(
              icon: Icons.nights_stay_rounded,
              label: isRomanian ? 'Apus' : 'Sunset',
              value: weather.sunset == null
                  ? '—'
                  : _clock(context, weather.sunset!),
              accent: accent,
            ),
            _SolunarRow(
              icon: Icons.wb_sunny_outlined,
              label: isRomanian ? 'Ora de aur' : 'Golden hour',
              value: _goldenHourLabel(astronomy, isRomanian: isRomanian),
              accent: accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _SolunarRow extends StatelessWidget {
  const _SolunarRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 205),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SevenDayForecast extends StatelessWidget {
  const _SevenDayForecast({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final days = weather.forecast.take(7).toList(growable: false);

    return _SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRomanian ? 'URMĂTOARELE 7 ZILE' : 'NEXT 7 DAYS',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: .9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  context.l10n.noData,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              ...days.map(
                (day) => _ForecastDayRow(day: day, isRomanian: isRomanian),
              ),
          ],
        ),
      ),
    );
  }
}

class _ForecastDayRow extends StatelessWidget {
  const _ForecastDayRow({required this.day, required this.isRomanian});

  final WeatherForecastDay day;
  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = weatherVisualKind(day.condition);
    final today = DateTime.now();
    final isToday =
        today.year == day.date.year &&
        today.month == day.date.month &&
        today.day == day.date.day;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              isToday
                  ? (isRomanian ? 'Azi' : 'Today')
                  : _dayLabel(context, day.date),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: .55,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              weatherVisualIcon(kind, isDaylight: true),
              size: 17,
              color: weatherVisualAccent(
                kind,
                isDaylight: true,
                brightness: theme.brightness,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weatherConditionLabel(day.condition, isRomanian: isRomanian),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
                if (day.precipitationProbabilityMax != null)
                  Text(
                    '${day.precipitationProbabilityMax!.round()}%${day.precipitationSum == null ? '' : ' · ${day.precipitationSum!.toStringAsFixed(1)} mm'}',
                    maxLines: 1,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${day.minimumTemperature.round()}°',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${day.maximumTemperature.round()}°',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? .38 : .55,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: child,
    );
  }
}

class _WeatherLoadingSurface extends StatelessWidget {
  const _WeatherLoadingSurface();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 196,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: .55,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(18),
          child: LinearProgressIndicator(
            minHeight: 2,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 210,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: .38,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ],
    );
  }
}

class _WeatherMessage extends StatelessWidget {
  const _WeatherMessage({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              isRomanian
                  ? 'Vremea nu este disponibilă momentan.'
                  : 'Weather is temporarily unavailable.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isRomanian
                  ? 'Verifică locația sau conexiunea și încearcă din nou.'
                  : 'Check location or connectivity and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isRomanian ? 'Reîncearcă' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoonPhaseDisc extends StatelessWidget {
  const _MoonPhaseDisc({
    required this.illumination,
    required this.waxing,
    required this.color,
  });

  final double illumination;
  final bool waxing;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(54),
    painter: _MoonPhasePainter(
      illumination: illumination,
      waxing: waxing,
      color: color,
      background: Theme.of(context).colorScheme.surface,
    ),
  );
}

class _MoonPhasePainter extends CustomPainter {
  const _MoonPhasePainter({
    required this.illumination,
    required this.waxing,
    required this.color,
    required this.background,
  });

  final double illumination;
  final bool waxing;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final disc = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, Paint()..color = background);
    canvas.save();
    canvas.clipPath(disc);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: .96),
    );
    final shadowWidth = radius * 2 * (1 - illumination.clamp(0, 1).toDouble());
    if (shadowWidth > 0) {
      final shadowLeft = waxing
          ? center.dx - radius
          : center.dx + radius - shadowWidth;
      canvas.drawOval(
        Rect.fromLTWH(shadowLeft, center.dy - radius, shadowWidth, radius * 2),
        Paint()..color = background,
      );
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) =>
      oldDelegate.illumination != illumination ||
      oldDelegate.waxing != waxing ||
      oldDelegate.color != color ||
      oldDelegate.background != background;
}

class _WeatherViewData {
  const _WeatherViewData({
    required this.weather,
    required this.astronomy,
    required this.isStaleFallback,
  });

  final WeatherData weather;
  final AstronomyContext astronomy;
  final bool isStaleFallback;
}

double? _hourValue(WeatherForecastHour hour, WeatherPageSection section) =>
    switch (section) {
      WeatherPageSection.temperature => hour.temperature,
      WeatherPageSection.wind => hour.windSpeed,
      WeatherPageSection.pressure => hour.pressure,
      WeatherPageSection.humidity => hour.humidity,
      WeatherPageSection.precipitation => hour.precipitationProbability,
      WeatherPageSection.solunar => null,
    };

String _currentValue(
  BuildContext context,
  WeatherData weather,
  WeatherPageSection section, {
  required bool isRomanian,
}) => switch (section) {
  WeatherPageSection.temperature => '${weather.temperature.round()}°C',
  WeatherPageSection.wind =>
    '${weather.windDirectionLabel} ${weather.windSpeed.toStringAsFixed(1)} km/h',
  WeatherPageSection.pressure =>
    weather.pressure == null ? '—' : '${weather.pressure!.round()} hPa',
  WeatherPageSection.humidity => '${weather.humidity.round()}%',
  WeatherPageSection.precipitation =>
    '${weather.precipitationProbability.round()}%',
  WeatherPageSection.solunar => _localizedMoonPhase(
    weather.moonPhase,
    isRomanian: isRomanian,
  ),
};

String _formatNumber(double value, WeatherPageSection section) =>
    switch (section) {
      WeatherPageSection.temperature => '${value.round()}°',
      WeatherPageSection.wind => '${value.round()} km/h',
      WeatherPageSection.pressure => '${value.round()} hPa',
      WeatherPageSection.humidity ||
      WeatherPageSection.precipitation => '${value.round()}%',
      WeatherPageSection.solunar => value.toStringAsFixed(0),
    };

String _sectionLabel(WeatherPageSection section, {required bool isRomanian}) =>
    switch (section) {
      WeatherPageSection.temperature =>
        isRomanian ? 'Temperatură' : 'Temperature',
      WeatherPageSection.wind => isRomanian ? 'Vânt' : 'Wind',
      WeatherPageSection.pressure => isRomanian ? 'Presiune' : 'Pressure',
      WeatherPageSection.humidity => isRomanian ? 'Umiditate' : 'Humidity',
      WeatherPageSection.precipitation =>
        isRomanian ? 'Precipitații' : 'Precipitation',
      WeatherPageSection.solunar => 'Solunar',
    };

IconData _sectionIcon(WeatherPageSection section) => switch (section) {
  WeatherPageSection.temperature => Icons.thermostat_rounded,
  WeatherPageSection.wind => Icons.air_rounded,
  WeatherPageSection.pressure => Icons.speed_rounded,
  WeatherPageSection.humidity => Icons.water_drop_rounded,
  WeatherPageSection.precipitation => Icons.umbrella_rounded,
  WeatherPageSection.solunar => Icons.nights_stay_rounded,
};

Color _sectionAccent(BuildContext context, WeatherPageSection section) {
  final colors = Theme.of(context).colorScheme;
  return switch (section) {
    WeatherPageSection.temperature => colors.tertiary,
    WeatherPageSection.wind => colors.primary,
    WeatherPageSection.pressure => colors.secondary,
    WeatherPageSection.humidity => colors.primary,
    WeatherPageSection.precipitation => colors.primary,
    WeatherPageSection.solunar => colors.tertiary,
  };
}

String _localizedMoonPhase(String value, {required bool isRomanian}) {
  if (!isRomanian) return value;
  return switch (value.trim().toLowerCase()) {
    'new moon' => 'Lună nouă',
    'waxing crescent' => 'Semilună în creștere',
    'first quarter' => 'Primul pătrar',
    'waxing gibbous' => 'Lună gibboasă în creștere',
    'full moon' => 'Lună plină',
    'waning gibbous' => 'Lună gibboasă în descreștere',
    'last quarter' || 'third quarter' => 'Ultimul pătrar',
    'waning crescent' => 'Semilună în descreștere',
    _ => value,
  };
}

String _goldenHourLabel(
  AstronomyContext astronomy, {
  required bool isRomanian,
}) {
  final golden = astronomy.goldenHour;
  if (astronomy.availability == AstronomyAvailability.locationRequired) {
    return isRomanian ? 'Locație necesară' : 'Location required';
  }
  if (astronomy.availability == AstronomyAvailability.notAvailable ||
      golden == null) {
    return isRomanian ? 'Indisponibil' : 'Unavailable';
  }
  return '${_clockRaw(golden.morningStart)}–${_clockRaw(golden.morningEnd)} / '
      '${_clockRaw(golden.eveningStart)}–${_clockRaw(golden.eveningEnd)}';
}

String _heroSecondaryLine(
  WeatherData weather,
  WeatherForecastDay? today, {
  required bool isRomanian,
}) {
  final feels = weather.feelsLike == null
      ? null
      : '${isRomanian ? 'Se simte' : 'Feels'} ${weather.feelsLike!.round()}°';
  final range = today == null
      ? null
      : '${today.minimumTemperature.round()}° / ${today.maximumTemperature.round()}°';
  if (feels != null && range != null) return '$feels · $range';
  return feels ??
      range ??
      (isRomanian ? 'Date meteo curente' : 'Current weather');
}

String _dayLabel(BuildContext context, DateTime date) {
  final days = [
    context.l10n.mondayShort,
    context.l10n.tuesdayShort,
    context.l10n.wednesdayShort,
    context.l10n.thursdayShort,
    context.l10n.fridayShort,
    context.l10n.saturdayShort,
    context.l10n.sundayShort,
  ];
  return days[date.weekday - 1];
}

String _clock(BuildContext context, DateTime value) =>
    TimeOfDay.fromDateTime(value.toLocal()).format(context);

String _clockRaw(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
