import 'package:flutter/material.dart';

import '../core/cache/timed_cache.dart';
import '../l10n/l10n.dart';
import '../models/weather.dart';
import '../services/astronomy_service.dart';
import '../services/weather_service.dart';

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
  const WeatherPage({super.key, this.initialSection});

  final WeatherPageSection? initialSection;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _service = WeatherService();
  late final WeatherPageSectionSelection _selection;
  late Future<_WeatherViewData> _weather;
  bool _fallbackMessageShown = false;

  @override
  void initState() {
    super.initState();
    _selection = WeatherPageSectionSelection(widget.initialSection);
    _weather = _load();
  }

  Future<_WeatherViewData> _load({bool forceRefresh = false}) async {
    final values = await Future.wait<Object>([
      _service.getCurrentWeatherResult(forceRefresh: forceRefresh),
      _service.getAstronomyContext(),
    ]);
    final weather = values[0] as CacheResult<WeatherData>;
    return _WeatherViewData(
      weather: weather.value,
      astronomy: values[1] as AstronomyContext,
      isStaleFallback: weather.isStaleFallback,
    );
  }

  Future<void> _refresh() async {
    final weather = _load(forceRefresh: true);
    setState(() => _weather = weather);
    await weather;
  }

  void _selectSection(WeatherPageSection section) {
    if (_selection.select(section)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        title: Text(context.l10n.weather),
        backgroundColor: const Color(0xFF0F1115),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: FutureBuilder<_WeatherViewData>(
          future: _weather,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _WeatherMessage(onRetry: _refresh);
            }
            if (snapshot.data!.isStaleFallback && !_fallbackMessageShown) {
              _fallbackMessageShown = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.cachedDataFallback)),
                  );
                }
              });
            }
            return _WeatherContent(
              weather: snapshot.data!.weather,
              astronomy: snapshot.data!.astronomy,
              section: _selection.selected,
              onSectionChanged: _selectSection,
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
    required this.onSectionChanged,
    required this.onRefresh,
  });

  final WeatherData weather;
  final AstronomyContext astronomy;
  final WeatherPageSection section;
  final ValueChanged<WeatherPageSection> onSectionChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(context, section);
    final hero = _ContextHero(
      presentation: presentation,
      value: _primaryValue(context, section, weather, astronomy),
      subtitle: _subtitle(context, section, weather, astronomy),
      symbol: section == WeatherPageSection.solunar
          ? _MoonPhaseDisc(
              illumination: normalizedMoonIllumination(
                astronomy.moon.illuminationPercent,
              ),
              waxing: moonPhaseIsWaxing(astronomy.moon.name),
              color: presentation.accent,
            )
          : Icon(presentation.icon, color: presentation.accent, size: 52),
      metrics: _heroMetrics(context, section, weather, astronomy),
    );
    final details = _ContextDetails(
      weather: weather,
      astronomy: astronomy,
      section: section,
      accent: presentation.accent,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionSelector(
                  selected: section,
                  onChanged: onSectionChanged,
                ),
                const SizedBox(height: 16),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: hero),
                      const SizedBox(width: 16),
                      Expanded(child: details),
                    ],
                  )
                else ...[
                  hero,
                  const SizedBox(height: 16),
                  details,
                ],
                const SizedBox(height: 20),
                _ThreeDayForecast(weather: weather),
              ],
            ),
          );
        },
      ),
    );
  }

  static _SectionPresentation _presentation(
    BuildContext context,
    WeatherPageSection section,
  ) => switch (section) {
    WeatherPageSection.temperature => _SectionPresentation(
      label: context.l10n.temperature,
      icon: Icons.wb_sunny_rounded,
      accent: const Color(0xFFFFC857),
    ),
    WeatherPageSection.wind => _SectionPresentation(
      label: context.l10n.wind,
      icon: Icons.air_rounded,
      accent: const Color(0xFF36D6E7),
    ),
    WeatherPageSection.pressure => _SectionPresentation(
      label: context.l10n.pressure,
      icon: Icons.speed_rounded,
      accent: const Color(0xFF72D572),
    ),
    WeatherPageSection.humidity => _SectionPresentation(
      label: context.l10n.humidity,
      icon: Icons.water_drop_rounded,
      accent: const Color(0xFF4FA9F7),
    ),
    WeatherPageSection.precipitation => _SectionPresentation(
      label: context.l10n.precipitation,
      icon: Icons.umbrella_rounded,
      accent: const Color(0xFF8C7BFF),
    ),
    WeatherPageSection.solunar => _SectionPresentation(
      label: context.l10n.solunar,
      icon: Icons.nights_stay_rounded,
      accent: const Color(0xFFC38CFF),
    ),
  };

  static String _primaryValue(
    BuildContext context,
    WeatherPageSection section,
    WeatherData weather,
    AstronomyContext astronomy,
  ) => switch (section) {
    WeatherPageSection.temperature => _value(
      context,
      weather.temperature,
      suffix: '°C',
    ),
    WeatherPageSection.wind => _value(
      context,
      weather.windSpeed,
      suffix: ' km/h',
      decimals: 1,
    ),
    WeatherPageSection.pressure => _value(
      context,
      weather.pressure,
      suffix: ' hPa',
    ),
    WeatherPageSection.humidity => _value(
      context,
      weather.humidity,
      suffix: '%',
    ),
    WeatherPageSection.precipitation => _value(
      context,
      weather.precipitationProbability,
      suffix: '%',
    ),
    WeatherPageSection.solunar => _localizedMoonPhase(
      context,
      astronomy.moon.name,
    ),
  };

  static String _subtitle(
    BuildContext context,
    WeatherPageSection section,
    WeatherData weather,
    AstronomyContext astronomy,
  ) => switch (section) {
    WeatherPageSection.temperature => _localizedWeatherCondition(
      context,
      weather.condition,
    ),
    WeatherPageSection.wind => _windDirection(
      context,
      weather.windDirectionDegrees,
      _localizedWindDirectionLabel(context, weather.windDirectionLabel),
    ),
    WeatherPageSection.pressure => context.l10n.lastUpdated,
    WeatherPageSection.humidity => context.l10n.lastUpdated,
    WeatherPageSection.precipitation => context.l10n.precipitationProbability,
    WeatherPageSection.solunar =>
      '${astronomy.moon.illuminationPercent.round()}% ${context.l10n.illuminated}',
  };

  static List<_HeroMetric> _heroMetrics(
    BuildContext context,
    WeatherPageSection section,
    WeatherData weather,
    AstronomyContext astronomy,
  ) {
    final daily = weather.forecast.isEmpty ? null : weather.forecast.first;
    return switch (section) {
      WeatherPageSection.temperature => [
        if (weather.feelsLike != null)
          _HeroMetric(
            Icons.thermostat_rounded,
            context.l10n.feelsLike(weather.feelsLike!.round()),
          ),
        if (daily != null)
          _HeroMetric(
            Icons.swap_vert_rounded,
            '${daily.minimumTemperature.round()}° / ${daily.maximumTemperature.round()}°',
          ),
      ],
      WeatherPageSection.wind => [
        _HeroMetric(
          Icons.explore_rounded,
          _windDirection(
            context,
            weather.windDirectionDegrees,
            _localizedWindDirectionLabel(context, weather.windDirectionLabel),
          ),
        ),
        _HeroMetric(
          Icons.air_rounded,
          _value(context, weather.windGusts, suffix: ' km/h', decimals: 1),
        ),
      ],
      WeatherPageSection.pressure => [
        _HeroMetric(Icons.schedule_rounded, _time(context, weather.observedAt)),
      ],
      WeatherPageSection.humidity => [
        _HeroMetric(
          Icons.cloud_outlined,
          _value(context, weather.cloudCover, suffix: '%'),
        ),
        _HeroMetric(Icons.schedule_rounded, _time(context, weather.observedAt)),
      ],
      WeatherPageSection.precipitation => [
        _HeroMetric(
          Icons.cloud_outlined,
          _value(context, weather.cloudCover, suffix: '%'),
        ),
        _HeroMetric(Icons.schedule_rounded, _time(context, weather.observedAt)),
      ],
      WeatherPageSection.solunar => [
        _HeroMetric(
          Icons.brightness_2_rounded,
          '${astronomy.moon.illuminationPercent.round()}% ${context.l10n.illuminated}',
        ),
        _HeroMetric(
          Icons.schedule_rounded,
          context.l10n.moonAge(astronomy.moon.ageDays.toStringAsFixed(1)),
        ),
      ],
    };
  }

  static String _time(BuildContext context, DateTime dateTime) =>
      TimeOfDay.fromDateTime(dateTime.toLocal()).format(context);

  static String _value(
    BuildContext context,
    double? value, {
    required String suffix,
    int decimals = 0,
  }) {
    if (value == null || !value.isFinite) return context.l10n.noData;
    return '${value.toStringAsFixed(decimals)}$suffix';
  }

  static String _windDirection(
    BuildContext context,
    double? degrees,
    String label,
  ) {
    if (degrees == null || !degrees.isFinite || label.isEmpty) {
      return context.l10n.noData;
    }
    return '$label (${degrees.round()}°)';
  }

  static String _localizedWeatherCondition(BuildContext context, String value) {
    if (Localizations.localeOf(context).languageCode != 'ro') return value;
    return switch (value.trim().toLowerCase()) {
      'clear' || 'clear sky' || 'sunny' => 'Senin',
      'mainly clear' || 'mostly clear' => 'Mai mult senin',
      'partly cloudy' => 'Parțial înnorat',
      'cloudy' => 'Înnorat',
      'overcast' => 'Cer acoperit',
      'fog' || 'mist' => 'Ceață',
      'drizzle' => 'Burniță',
      'rain' || 'light rain' || 'moderate rain' || 'heavy rain' => 'Ploaie',
      'showers' || 'rain showers' => 'Averse',
      'snow' || 'snow showers' => 'Ninsoare',
      'sleet' => 'Lapoviță',
      'thunderstorm' || 'thunderstorms' => 'Furtună',
      'hail' => 'Grindină',
      _ => value,
    };
  }

  static String _localizedWindDirectionLabel(
    BuildContext context,
    String value,
  ) {
    if (Localizations.localeOf(context).languageCode != 'ro') return value;
    return switch (value.trim().toLowerCase()) {
      'n' || 'north' => 'N',
      'ne' || 'north east' || 'northeast' => 'NE',
      'e' || 'east' => 'E',
      'se' || 'south east' || 'southeast' => 'SE',
      's' || 'south' => 'S',
      'sw' || 'south west' || 'southwest' => 'SV',
      'w' || 'west' => 'V',
      'nw' || 'north west' || 'northwest' => 'NV',
      _ => value,
    };
  }

  static String _localizedMoonPhase(BuildContext context, String value) {
    if (Localizations.localeOf(context).languageCode != 'ro') return value;
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

  static String _dayLabel(BuildContext context, DateTime date) {
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

  static String _goldenHourLabel(
    BuildContext context,
    AstronomyContext astronomy,
  ) {
    final golden = astronomy.goldenHour;
    if (astronomy.availability == AstronomyAvailability.locationRequired) {
      return context.l10n.locationRequired;
    }
    if (astronomy.availability == AstronomyAvailability.notAvailable ||
        golden == null) {
      return context.l10n.notAvailable;
    }
    return '${_clock(golden.morningStart)}–${_clock(golden.morningEnd)} '
        '${context.l10n.or} ${_clock(golden.eveningStart)}–${_clock(golden.eveningEnd)}';
  }

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _SectionSelector extends StatelessWidget {
  const _SectionSelector({required this.selected, required this.onChanged});

  final WeatherPageSection selected;
  final ValueChanged<WeatherPageSection> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: WeatherPageSection.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final section = WeatherPageSection.values[index];
        final presentation = _WeatherContent._presentation(context, section);
        final active = section == selected;
        return Semantics(
          button: true,
          selected: active,
          label: presentation.label,
          child: Material(
            color: active
                ? presentation.accent.withValues(alpha: .20)
                : const Color(0xFF17212B),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: () => onChanged(section),
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      presentation.icon,
                      color: presentation.accent,
                      size: 19,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      presentation.label,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ContextHero extends StatelessWidget {
  const _ContextHero({
    required this.presentation,
    required this.value,
    required this.subtitle,
    required this.symbol,
    required this.metrics,
  });

  final _SectionPresentation presentation;
  final String value;
  final String subtitle;
  final Widget symbol;
  final List<_HeroMetric> metrics;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFF17212B),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: presentation.accent.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: symbol,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presentation.label,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: metrics
                  .map(
                    (metric) => _HeroMetricChip(
                      metric: metric,
                      accent: presentation.accent,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ContextDetails extends StatelessWidget {
  const _ContextDetails({
    required this.weather,
    required this.astronomy,
    required this.section,
    required this.accent,
  });

  final WeatherData weather;
  final AstronomyContext astronomy;
  final WeatherPageSection section;
  final Color accent;

  @override
  Widget build(BuildContext context) => switch (section) {
    WeatherPageSection.temperature => _HourlyDetails(
      title: context.l10n.next24Hours,
      accent: accent,
      hours: weather.hourlyForecast,
      itemBuilder: (hour) => [
        _DetailValue(Icons.thermostat_rounded, '${hour.temperature.round()}°C'),
        _DetailValue(
          Icons.device_thermostat_rounded,
          context.l10n.feelsLike(hour.feelsLike.round()),
        ),
      ],
    ),
    WeatherPageSection.wind => _HourlyDetails(
      title: context.l10n.next24Hours,
      accent: accent,
      hours: weather.hourlyForecast,
      itemBuilder: (hour) => [
        _DetailValue(
          Icons.air_rounded,
          '${hour.windSpeed.toStringAsFixed(1)} km/h',
        ),
        _DetailValue(
          Icons.explore_rounded,
          '${hour.windDirectionLabel} (${hour.windDirectionDegrees.round()}°)',
        ),
        _DetailValue(
          Icons.air_rounded,
          '${hour.windGusts.toStringAsFixed(1)} km/h',
        ),
      ],
    ),
    WeatherPageSection.pressure => _DetailsCard(
      title: context.l10n.pressure,
      accent: accent,
      children: [
        _DetailsRow(
          icon: Icons.speed_rounded,
          label: context.l10n.pressure,
          value: _WeatherContent._value(
            context,
            weather.pressure,
            suffix: ' hPa',
          ),
          accent: accent,
        ),
        _DetailsRow(
          icon: Icons.schedule_rounded,
          label: context.l10n.lastUpdated,
          value: _WeatherContent._time(context, weather.observedAt),
          accent: accent,
        ),
      ],
    ),
    WeatherPageSection.humidity => _HourlyDetails(
      title: context.l10n.next24Hours,
      accent: accent,
      hours: weather.hourlyForecast,
      itemBuilder: (hour) => [
        _DetailValue(Icons.water_drop_rounded, '${hour.humidity.round()}%'),
        _DetailValue(Icons.cloud_outlined, '${hour.cloudCover.round()}%'),
      ],
    ),
    WeatherPageSection.precipitation => _HourlyDetails(
      title: context.l10n.next24Hours,
      accent: accent,
      hours: weather.hourlyForecast,
      itemBuilder: (hour) => [
        _DetailValue(
          Icons.umbrella_rounded,
          '${hour.precipitationProbability.round()}%',
        ),
        _DetailValue(Icons.cloud_outlined, '${hour.cloudCover.round()}%'),
      ],
    ),
    WeatherPageSection.solunar => _DetailsCard(
      title: context.l10n.solunar,
      accent: accent,
      children: [
        _DetailsRow(
          icon: Icons.wb_twilight_rounded,
          label: context.l10n.sunrise,
          value: weather.sunrise == null
              ? context.l10n.noData
              : _WeatherContent._time(context, weather.sunrise!),
          accent: accent,
        ),
        _DetailsRow(
          icon: Icons.nights_stay_rounded,
          label: context.l10n.sunset,
          value: weather.sunset == null
              ? context.l10n.noData
              : _WeatherContent._time(context, weather.sunset!),
          accent: accent,
        ),
        _DetailsRow(
          icon: Icons.wb_sunny_outlined,
          label: context.l10n.goldenHour,
          value: _WeatherContent._goldenHourLabel(context, astronomy),
          accent: accent,
        ),
      ],
    ),
  };
}

class _HourlyDetails extends StatelessWidget {
  const _HourlyDetails({
    required this.title,
    required this.accent,
    required this.hours,
    required this.itemBuilder,
  });

  final String title;
  final Color accent;
  final List<WeatherForecastHour> hours;
  final List<_DetailValue> Function(WeatherForecastHour) itemBuilder;

  @override
  Widget build(BuildContext context) => _DetailsCard(
    title: title,
    accent: accent,
    children: [
      if (hours.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.noData,
            style: const TextStyle(color: Colors.white70),
          ),
        )
      else
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: hours.take(24).length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final hour = hours[index];
              return SizedBox(
                width: 132,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101820),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _WeatherContent._time(context, hour.time),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...itemBuilder(hour).map(
                          (value) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              children: [
                                Icon(value.icon, color: accent, size: 15),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    value.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFF17212B),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 22, color: accent),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

class _DetailsRow extends StatelessWidget {
  const _DetailsRow({
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
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ThreeDayForecast extends StatelessWidget {
  const _ThreeDayForecast({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) => _DetailsCard(
    title: context.l10n.threeDayForecast,
    accent: const Color(0xFF36D6E7),
    children: [
      if (weather.forecast.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.noData,
            style: const TextStyle(color: Colors.white70),
          ),
        )
      else
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: weather.forecast.take(3).map((day) {
            return SizedBox(
              width: 152,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF101820),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _WeatherContent._dayLabel(context, day.date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _WeatherContent._localizedWeatherCondition(
                          context,
                          day.condition,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${day.minimumTemperature.round()}° / ${day.maximumTemperature.round()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
    ],
  );
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
    ),
  );
}

class _MoonPhasePainter extends CustomPainter {
  const _MoonPhasePainter({
    required this.illumination,
    required this.waxing,
    required this.color,
  });

  final double illumination;
  final bool waxing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final disc = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF101820));
    canvas.save();
    canvas.clipPath(disc);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: .95),
    );
    final shadowWidth = radius * 2 * (1 - illumination.clamp(0, 1).toDouble());
    if (shadowWidth > 0) {
      final shadowLeft = waxing
          ? center.dx - radius
          : center.dx + radius - shadowWidth;
      canvas.drawOval(
        Rect.fromLTWH(shadowLeft, center.dy - radius, shadowWidth, radius * 2),
        Paint()..color = const Color(0xFF101820),
      );
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) =>
      oldDelegate.illumination != illumination ||
      oldDelegate.waxing != waxing ||
      oldDelegate.color != color;
}

class _SectionPresentation {
  const _SectionPresentation({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;
}

class _HeroMetric {
  const _HeroMetric(this.icon, this.value);

  final IconData icon;
  final String value;
}

class _HeroMetricChip extends StatelessWidget {
  const _HeroMetricChip({required this.metric, required this.accent});

  final _HeroMetric metric;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF101820),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(metric.icon, color: accent, size: 17),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            metric.value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _DetailValue {
  const _DetailValue(this.icon, this.value);

  final IconData icon;
  final String value;
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

class _WeatherMessage extends StatelessWidget {
  const _WeatherMessage({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.white70),
        const SizedBox(height: 12),
        Text(
          context.l10n.weatherUnavailable,
          style: const TextStyle(color: Colors.white),
        ),
        TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
}
