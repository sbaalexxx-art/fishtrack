import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../services/community_service.dart';
import '../widgets/loading_list_skeleton.dart';
import '../widgets/trust_badge.dart';

enum _ArchivePeriod {
  day('Last 24h', Duration(hours: 24)),
  threeDays('Last 3 days', Duration(days: 3)),
  week('Last 7 days', Duration(days: 7));

  const _ArchivePeriod(this.label, this.duration);
  final String label;
  final Duration duration;
}

enum _ReportGroup { fishActivity, water, access, risk, other }

class ReportsArchivePage extends StatefulWidget {
  const ReportsArchivePage({super.key});

  @override
  State<ReportsArchivePage> createState() => _ReportsArchivePageState();
}

class _ReportsArchivePageState extends State<ReportsArchivePage> {
  final _service = const CommunityService();
  _ArchivePeriod _period = _ArchivePeriod.day;
  late Future<_ArchiveComparison> _reports = _load();

  Future<_ArchiveComparison> _load() async {
    final now = DateTime.now();
    final previousEnd = now.subtract(_period.duration);
    final results = await Future.wait([
      _service.getReportsArchive(_period.duration, end: now),
      _service.getReportsArchive(_period.duration, end: previousEnd),
    ]);
    return _ArchiveComparison(current: results[0], previous: results[1]);
  }

  void _selectPeriod(_ArchivePeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _reports = _load();
    });
  }

  void _retry() => setState(() => _reports = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.reportsArchive)),
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SegmentedButton<_ArchivePeriod>(
                segments: [
                  for (final period in _ArchivePeriod.values)
                    ButtonSegment(
                      value: period,
                      label: Text(_localizedArchiveLabel(context, period.label)),
                    ),
                ],
                selected: {_period},
                onSelectionChanged: (selection) =>
                    _selectPeriod(selection.first),
              ),
            ),
            Expanded(
              child: FutureBuilder<_ArchiveComparison>(
                future: _reports,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingListSkeleton();
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _localizedArchiveLabel(
                                context,
                                'Reports archive is currently unavailable.',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: Text(context.l10n.retry),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final comparison = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async {
                      _retry();
                      await _reports;
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _SummaryCard(comparison: comparison),
                        const SizedBox(height: 12),
                        _CategoryCountsCard(reports: comparison.current),
                        const SizedBox(height: 12),
                        if (comparison.current.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No archived reports for this period.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          for (final report in comparison.current)
                            _ReportTile(report: report),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.comparison});
  final _ArchiveComparison comparison;

  @override
  Widget build(BuildContext context) {
    final groupCounts = _groupCounts(comparison.current);
    final categories = _categoryCounts(comparison.current).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mostActive = categories.isEmpty
        ? _localizedArchiveLabel(context, 'No data')
        : _localizedCategoryLabel(context, categories.first.key.label);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _summary(
                  _localizedArchiveLabel(context, 'Total reports'),
                  '${comparison.current.length}',
                ),
                _summary(
                  _localizedArchiveLabel(context, 'Most active category'),
                  mostActive,
                ),
                _summary(
                  _localizedArchiveLabel(context, 'Risk reports'),
                  '${groupCounts[_ReportGroup.risk]}',
                ),
                _summary(
                  _localizedArchiveLabel(context, 'Water reports'),
                  '${groupCounts[_ReportGroup.water]}',
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              '${_localizedArchiveLabel(context, 'Trend:')} '
              '${_localizedArchiveLabel(context, comparison.trendLabel)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              _localizedComparisonLabel(
                context,
                comparison.current.length,
                comparison.previous.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _summary(String label, String value) => SizedBox(
    width: 135,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label),
      ],
    ),
  );
}

class _CategoryCountsCard extends StatelessWidget {
  const _CategoryCountsCard({required this.reports});
  final List<CommunityPost> reports;

  @override
  Widget build(BuildContext context) {
    final counts = _categoryCounts(reports).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizedArchiveLabel(context, 'Reports by category'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (counts.isEmpty)
              Text(context.l10n.noCategoryData)
            else
              for (final entry in counts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_localizedCategoryLabel(context, entry.key.label)),
                      Text('${entry.value}'),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final CommunityPost report;

  Future<void> _reportAbuse(BuildContext context) async {
    final reason = await showDialog<ReportAbuseReason>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.reportAbuse),
        children: [
          for (final reason in ReportAbuseReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason),
              child: Text(_localizedAbuseReason(context, reason.label)),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await const CommunityService().reportAbuse(report.id, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.reportSubmitted)),
        );
      }
    } on CommunityException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.report_outlined),
      title: Text(
        report.reportCategory == null
            ? report.title
            : _localizedCategoryLabel(
                context,
                report.reportCategory!.label,
              ),
      ),
      trailing: IconButton(
        tooltip: context.l10n.reportAbuse,
        onPressed: () => _reportAbuse(context),
        icon: const Icon(Icons.flag_outlined),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.isSuspicious) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _localizedArchiveLabel(context, 'Under review'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (report.body.trim().isNotEmpty) Text(report.body),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_dateLabel(report.createdAt)} • '
                '${_localizedArchiveLabel(context, 'Community')} • '
                '${report.authorName}',
              ),
              TrustBadge(level: report.authorTrustLevel),
            ],
          ),
        ],
      ),
    ),
  );

  static String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}.${local.month}.${local.year} $hour:$minute';
  }
}

class _ArchiveComparison {
  const _ArchiveComparison({required this.current, required this.previous});
  final List<CommunityPost> current;
  final List<CommunityPost> previous;

  String get trendLabel {
    if (previous.isEmpty) return 'Not enough data';
    if (current.length > previous.length) return 'Increasing';
    if (current.length < previous.length) return 'Decreasing';
    return 'Stable';
  }
}

String _localizedArchiveLabel(BuildContext context, String value) {
  if (Localizations.localeOf(context).languageCode != 'ro') return value;
  return switch (value.trim().toLowerCase()) {
    'last 24h' => 'Ultimele 24 h',
    'last 3 days' => 'Ultimele 3 zile',
    'last 7 days' => 'Ultimele 7 zile',
    'reports archive is currently unavailable.' =>
      'Arhiva raportărilor este momentan indisponibilă.',
    'no data' => 'Nu există date',
    'total reports' => 'Total raportări',
    'most active category' => 'Cea mai activă categorie',
    'risk reports' => 'Raportări de risc',
    'water reports' => 'Raportări despre apă',
    'trend:' => 'Tendință:',
    'reports by category' => 'Raportări pe categorii',
    'under review' => 'În curs de verificare',
    'community' => 'Comunitate',
    'not enough data' => 'Date insuficiente',
    'increasing' => 'În creștere',
    'decreasing' => 'În scădere',
    'stable' => 'Stabil',
    _ => value,
  };
}

String _localizedComparisonLabel(
  BuildContext context,
  int current,
  int previous,
) {
  if (Localizations.localeOf(context).languageCode != 'ro') {
    return '$current in selected period vs $previous in previous period';
  }
  return '$current în perioada selectată față de $previous în perioada precedentă';
}

String _localizedCategoryLabel(BuildContext context, String value) {
  if (Localizations.localeOf(context).languageCode != 'ro') return value;
  return switch (value.trim().toLowerCase()) {
    'fish activity' => 'Activitate a peștilor',
    'water clarity' => 'Claritatea apei',
    'floating grass' => 'Vegetație plutitoare',
    'high water' => 'Nivel ridicat al apei',
    'low water' => 'Nivel scăzut al apei',
    'strong current' => 'Curent puternic',
    'no current' => 'Fără curent',
    'boats' => 'Ambarcațiuni',
    'poaching' => 'Braconaj',
    'theft warning' => 'Avertizare de furt',
    'access blocked' => 'Acces blocat',
    'parking available' => 'Parcare disponibilă',
    'good fishing' => 'Pescuit bun',
    'poor fishing' => 'Pescuit slab',
    'other' => 'Altele',
    _ => value,
  };
}

String _localizedAbuseReason(BuildContext context, String value) {
  if (Localizations.localeOf(context).languageCode != 'ro') return value;
  return switch (value.trim().toLowerCase()) {
    'spam' => 'Spam',
    'fake information' => 'Informații false',
    'offensive content' => 'Conținut ofensator',
    'dangerous/illegal activity' =>
      'Activitate periculoasă sau ilegală',
    'other' => 'Alt motiv',
    _ => value,
  };
}

Map<ReportCategory, int> _categoryCounts(List<CommunityPost> reports) {
  final counts = <ReportCategory, int>{};
  for (final report in reports) {
    final category = report.reportCategory ?? ReportCategory.other;
    counts[category] = (counts[category] ?? 0) + 1;
  }
  return counts;
}

Map<_ReportGroup, int> _groupCounts(List<CommunityPost> reports) {
  final counts = <_ReportGroup, int>{
    for (final group in _ReportGroup.values) group: 0,
  };
  for (final report in reports) {
    final group = _groupFor(report.reportCategory);
    counts[group] = counts[group]! + 1;
  }
  return counts;
}

_ReportGroup _groupFor(ReportCategory? category) => switch (category) {
  ReportCategory.fishActivity ||
  ReportCategory.goodFishing ||
  ReportCategory.poorFishing => _ReportGroup.fishActivity,
  ReportCategory.waterClarity ||
  ReportCategory.floatingGrass ||
  ReportCategory.highWater ||
  ReportCategory.lowWater ||
  ReportCategory.strongCurrent ||
  ReportCategory.noCurrent => _ReportGroup.water,
  ReportCategory.boats ||
  ReportCategory.accessBlocked ||
  ReportCategory.parkingAvailable => _ReportGroup.access,
  ReportCategory.poaching || ReportCategory.theftWarning => _ReportGroup.risk,
  ReportCategory.other || null => _ReportGroup.other,
};
