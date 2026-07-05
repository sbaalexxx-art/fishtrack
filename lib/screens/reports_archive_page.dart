import 'package:flutter/material.dart';

import '../services/community_service.dart';

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
      appBar: AppBar(title: const Text('Reports Archive')),
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SegmentedButton<_ArchivePeriod>(
                segments: [
                  for (final period in _ArchivePeriod.values)
                    ButtonSegment(value: period, label: Text(period.label)),
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
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
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
        ? 'No data'
        : categories.first.key.label;
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
                _summary('Total reports', '${comparison.current.length}'),
                _summary('Most active category', mostActive),
                _summary('Risk reports', '${groupCounts[_ReportGroup.risk]}'),
                _summary('Water reports', '${groupCounts[_ReportGroup.water]}'),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Trend: ${comparison.trendLabel}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${comparison.current.length} in selected period vs '
              '${comparison.previous.length} in previous period',
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
              'Reports by category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (counts.isEmpty)
              const Text('No category data for this period.')
            else
              for (final entry in counts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(entry.key.label), Text('${entry.value}')],
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

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.report_outlined),
      title: Text(report.reportCategory?.label ?? report.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.body.trim().isNotEmpty) Text(report.body),
          const SizedBox(height: 4),
          Text(
            '${_dateLabel(report.createdAt)} • Community • ${report.authorName}',
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
