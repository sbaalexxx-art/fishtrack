import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters/water_freshness_formatter.dart';
import '../l10n/l10n.dart';
import '../models/station.dart';
import '../models/water_level.dart';
import '../services/water_service.dart';

enum WaterDetailsPeriod {
  sevenDays(Duration(days: 7)),
  fourteenDays(Duration(days: 14)),
  thirtyDays(Duration(days: 30));

  const WaterDetailsPeriod(this.duration);

  final Duration duration;
}

class WaterDetailsSummary {
  const WaterDetailsSummary._({
    required this.readings,
    required this.minimum,
    required this.maximum,
    required this.change,
    required this.coverage,
  });

  final List<WaterLevel> readings;
  final double? minimum;
  final double? maximum;
  final double? change;
  final Duration? coverage;

  bool get hasChart => readings.length >= 2;

  static WaterDetailsSummary fromHistory(
    List<WaterLevel> history,
    WaterDetailsPeriod period,
  ) {
    final valid =
        history
            .where(
              (reading) =>
                  reading.value.isFinite &&
                  reading.timestamp.millisecondsSinceEpoch > 0,
            )
            .toList(growable: false)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (valid.isEmpty) {
      return const WaterDetailsSummary._(
        readings: <WaterLevel>[],
        minimum: null,
        maximum: null,
        change: null,
        coverage: null,
      );
    }

    final latestTimestamp = valid.last.timestamp;
    final cutoff = latestTimestamp.subtract(period.duration);
    final byTimestamp = <int, WaterLevel>{};
    for (final reading in valid) {
      if (reading.timestamp.isBefore(cutoff)) continue;
      byTimestamp[reading.timestamp.toUtc().microsecondsSinceEpoch] = reading;
    }
    final readings = byTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (readings.isEmpty) {
      return const WaterDetailsSummary._(
        readings: <WaterLevel>[],
        minimum: null,
        maximum: null,
        change: null,
        coverage: null,
      );
    }

    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = readings
        .map((reading) => reading.value)
        .reduce((a, b) => a > b ? a : b);
    return WaterDetailsSummary._(
      readings: List<WaterLevel>.unmodifiable(readings),
      minimum: minimum,
      maximum: maximum,
      change: readings.length < 2
          ? null
          : readings.last.value - readings.first.value,
      coverage: readings.length < 2
          ? null
          : readings.last.timestamp.difference(readings.first.timestamp),
    );
  }
}

class WaterLevelPage extends StatefulWidget {
  const WaterLevelPage({super.key});

  @override
  State<WaterLevelPage> createState() => _WaterLevelPageState();
}

class _WaterLevelPageState extends State<WaterLevelPage> {
  final WaterService _waterService = WaterService();
  StreamSubscription<WaterUiResult>? _resultSubscription;

  WaterHomeStationSelection? _selection;
  Station? _station;
  WaterUiResult? _result;
  WaterDetailsPeriod _period = WaterDetailsPeriod.sevenDays;
  bool _loadingStation = true;
  bool _loadingResult = false;
  bool _loadFailed = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHomeStation());
  }

  @override
  void dispose() {
    _requestId++;
    unawaited(_resultSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadHomeStation({bool forceRefresh = false}) async {
    final requestId = ++_requestId;
    await _resultSubscription?.cancel();
    if (mounted) {
      setState(() {
        _loadingStation = true;
        _loadingResult = false;
        _loadFailed = false;
      });
    }

    try {
      final selection = await _waterService.resolveHomeStationSelection();
      if (!mounted || requestId != _requestId) return;
      final station = selection.station;
      setState(() {
        _selection = selection;
        _station = station;
        _loadingStation = false;
        _loadingResult = station != null;
        _loadFailed = station == null;
      });
      if (station != null) _listenForResult(station, requestId, forceRefresh);
    } on Exception {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingStation = false;
        _loadingResult = false;
        _loadFailed = _result == null;
      });
    }
  }

  void _listenForResult(Station station, int requestId, bool forceRefresh) {
    _resultSubscription = _waterService
        .getProgressiveWaterUiResults(
          station,
          limit: 30,
          forceRefresh: forceRefresh,
        )
        .listen(
          (result) {
            if (!mounted || requestId != _requestId) return;
            setState(() {
              _result = result;
              _loadingResult = false;
              _loadFailed = false;
            });
          },
          onError: (Object _) {
            if (!mounted || requestId != _requestId) return;
            setState(() {
              _loadingResult = false;
              _loadFailed = _result == null;
            });
          },
          onDone: () {
            if (!mounted || requestId != _requestId) return;
            setState(() => _loadingResult = false);
          },
          cancelOnError: false,
        );
  }

  Future<void> _refresh() => _loadHomeStation(forceRefresh: true);

  Future<void> _useAutomaticSelection() async {
    await _waterService.setAutomatic();
    if (mounted) await _loadHomeStation();
  }

  void _selectPeriod(WaterDetailsPeriod period) {
    if (_period == period) return;
    setState(() => _period = period);
  }

  @override
  Widget build(BuildContext context) {
    final station = _station;
    final result = _result;
    final summary = result == null
        ? null
        : WaterDetailsSummary.fromHistory(result.history, _period);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.waterLevels), centerTitle: true),
      body: SafeArea(
        child: _loadingStation
            ? const _WaterDetailsSkeleton()
            : station == null || (_loadFailed && result == null)
            ? _WaterDetailsMessage(onRefresh: _refresh)
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _WaterDetailsHero(
                      station: station,
                      selection: _selection,
                      result: result,
                      isLoading: _loadingResult && result == null,
                      onUseAutomatic: _useAutomaticSelection,
                    ),
                    const SizedBox(height: 16),
                    _WaterHistorySection(
                      result: result,
                      summary: summary,
                      period: _period,
                      onPeriodSelected: _selectPeriod,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _WaterDetailsHero extends StatelessWidget {
  const _WaterDetailsHero({
    required this.station,
    required this.selection,
    required this.result,
    required this.isLoading,
    required this.onUseAutomatic,
  });

  final Station station;
  final WaterHomeStationSelection? selection;
  final WaterUiResult? result;
  final bool isLoading;
  final Future<void> Function() onUseAutomatic;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final reading = result?.latestReading;
    final trend = result?.trend;
    final color = _trendColor(trend);
    final hasReading = reading != null && reading.value.isFinite;
    final freshness = result?.measurementTimestamp == null
        ? context.l10n.updateTimeUnavailable
        : WaterFreshnessFormatter.format(
            measurementTimestamp: result!.measurementTimestamp!,
            now: DateTime.now(),
            isStale: result.isStale,
            locale: Localizations.localeOf(context).languageCode,
          );
    final hasProviderError =
        result?.providerError == true ||
        result?.status == WaterUiStatus.providerError;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        station.river,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.waterStations,
                  onPressed: selection?.mode == WaterStationSelectionMode.pinned
                      ? onUseAutomatic
                      : null,
                  icon: Icon(
                    selection?.mode == WaterStationSelectionMode.pinned
                        ? Icons.push_pin_rounded
                        : Icons.my_location_rounded,
                    color: selection?.mode == WaterStationSelectionMode.pinned
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (!hasReading)
              Center(
                child: Text(
                  context.l10n.waterUnavailable,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              )
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _formatDelta(result!.deltaCm, reading.unit),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(_trendIcon(trend), color: color, size: 30),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _trendLabel(context, trend),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (result.comparisonDuration case final duration?) ...[
                const SizedBox(height: 2),
                Text(
                  _formatComparisonInterval(context, duration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '${reading.value.toStringAsFixed(0)} ${reading.unit}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              _sourceLabel(
                    result?.source,
                    result?.sourceName ?? reading?.sourceName,
                  ) ??
                  context.l10n.noSource,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${context.l10n.lastUpdated}: $freshness',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasProviderError || result?.isStale == true) ...[
              const SizedBox(height: 12),
              _DataStatus(
                isError: hasProviderError,
                message: hasProviderError
                    ? context.l10n.waterProviderUnavailable
                    : context.l10n.waterUnavailable,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaterHistorySection extends StatelessWidget {
  const _WaterHistorySection({
    required this.result,
    required this.summary,
    required this.period,
    required this.onPeriodSelected,
  });

  final WaterUiResult? result;
  final WaterDetailsSummary? summary;
  final WaterDetailsPeriod period;
  final ValueChanged<WaterDetailsPeriod> onPeriodSelected;

  @override
  Widget build(BuildContext context) {
    final resolvedSummary = summary;
    final trendColor = _trendColor(result?.trend);
    final hasHistory =
        resolvedSummary != null && resolvedSummary.readings.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.waterLevelHistory,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SegmentedButton<WaterDetailsPeriod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: WaterDetailsPeriod.sevenDays,
                  label: Text('7'),
                ),
                ButtonSegment(
                  value: WaterDetailsPeriod.fourteenDays,
                  label: Text('14'),
                ),
                ButtonSegment(
                  value: WaterDetailsPeriod.thirtyDays,
                  label: Text('30'),
                ),
              ],
              selected: {period},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) onPeriodSelected(selection.first);
              },
            ),
            const SizedBox(height: 16),
            if (!hasHistory)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(context.l10n.noWaterData),
                ),
              )
            else ...[
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WaterDetailsHistoryPainter(
                    resolvedSummary.readings,
                    trendColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _HistorySummary(summary: resolvedSummary, color: trendColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.summary, required this.color});

  final WaterDetailsSummary summary;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final unit = summary.readings.first.unit;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _SummaryValue(
          icon: Icons.south_rounded,
          value: _formatValue(summary.minimum, unit),
        ),
        _SummaryValue(
          icon: Icons.north_rounded,
          value: _formatValue(summary.maximum, unit),
        ),
        _SummaryValue(
          icon: _trendIconFromDelta(summary.change),
          value: _formatDelta(summary.change, unit),
          color: color,
        ),
        _SummaryValue(
          icon: Icons.data_usage_rounded,
          value: '${summary.readings.length}',
        ),
        if (summary.coverage case final coverage?)
          _SummaryValue(
            icon: Icons.schedule_rounded,
            value: coverage.toString(),
          ),
      ],
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.icon, required this.value, this.color});

  final IconData icon;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _DataStatus extends StatelessWidget {
  const _DataStatus({required this.isError, required this.message});

  final bool isError;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.cloud_off_outlined : Icons.schedule_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterDetailsHistoryPainter extends CustomPainter {
  const _WaterDetailsHistoryPainter(this.readings, this.color);

  final List<WaterLevel> readings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.isEmpty || size.isEmpty) return;
    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = readings
        .map((reading) => reading.value)
        .reduce((a, b) => a > b ? a : b);
    final valueRange = maximum - minimum;
    final firstTimestamp = readings.first.timestamp;
    final lastTimestamp = readings.last.timestamp;
    final timeRange = lastTimestamp.difference(firstTimestamp).inMilliseconds;
    final top = 12.0;
    final bottom = 18.0;
    final chartHeight = size.height - top - bottom;
    final points = <Offset>[];

    for (final reading in readings) {
      final elapsed = reading.timestamp
          .difference(firstTimestamp)
          .inMilliseconds;
      final x = timeRange <= 0
          ? size.width / 2
          : size.width * elapsed / timeRange;
      final normalized = valueRange == 0
          ? .5
          : (reading.value - minimum) / valueRange;
      final y = top + chartHeight - normalized * chartHeight;
      points.add(Offset(x, y));
    }

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    final pointPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 3.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(_WaterDetailsHistoryPainter oldDelegate) =>
      oldDelegate.readings != readings || oldDelegate.color != color;
}

class _WaterDetailsSkeleton extends StatelessWidget {
  const _WaterDetailsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const [
      Card(child: SizedBox(height: 300)),
      SizedBox(height: 16),
      Card(child: SizedBox(height: 280)),
    ],
  );
}

class _WaterDetailsMessage extends StatelessWidget {
  const _WaterDetailsMessage({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.water_drop_outlined, size: 48),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(context.l10n.waterUnavailable),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Color _trendColor(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => const Color(0xFF2196F3),
  WaterTrend.stable => const Color(0xFF43A047),
  WaterTrend.falling => const Color(0xFFE53935),
  null => const Color(0xFF9AA7B2),
};

IconData _trendIcon(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => Icons.trending_up_rounded,
  WaterTrend.stable => Icons.trending_flat_rounded,
  WaterTrend.falling => Icons.trending_down_rounded,
  null => Icons.help_outline_rounded,
};

IconData _trendIconFromDelta(double? delta) => delta == null
    ? Icons.remove_rounded
    : _trendIcon(
        delta > .01
            ? WaterTrend.rising
            : delta < -.01
            ? WaterTrend.falling
            : WaterTrend.stable,
      );

String _trendLabel(BuildContext context, WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => context.l10n.rising,
  WaterTrend.stable => context.l10n.stable,
  WaterTrend.falling => context.l10n.falling,
  null => context.l10n.unknown,
};

String? _sourceLabel(WaterLevelSource? source, String? sourceName) {
  if (sourceName != null &&
      sourceName.trim().isNotEmpty &&
      sourceName != source?.name) {
    return sourceName;
  }
  return switch (source) {
    WaterLevelSource.afdj => 'AFDJ',
    WaterLevelSource.danubeHis => 'DanubeHIS',
    WaterLevelSource.danubeFis => 'DanubeFIS',
    WaterLevelSource.inhga => 'INHGA',
    WaterLevelSource.manualFallback => 'Manual',
    null => null,
  };
}

String _formatComparisonInterval(BuildContext context, Duration duration) {
  final days = duration.inDays;
  final remainder = duration - Duration(days: days);
  final clock = '${remainder.inHours.toString().padLeft(2, '0')}:'
      '${(remainder.inMinutes % 60).toString().padLeft(2, '0')}';
  if (days == 0) return clock;
  return remainder.inMinutes == 0
      ? context.l10n.days(days)
      : '${context.l10n.days(days)} · $clock';
}

String _formatValue(double? value, String unit) =>
    value == null ? '—' : '${value.toStringAsFixed(0)} $unit';

String _formatDelta(double? value, String unit) {
  if (value == null) return '—';
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(0)} $unit';
}
