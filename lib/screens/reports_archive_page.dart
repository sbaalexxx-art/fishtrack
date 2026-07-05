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
  late Future<List<CommunityPost>> _reports = _load();

  Future<List<CommunityPost>> _load() =>
      _service.getReportsArchive(_period.duration);

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
              child: FutureBuilder<List<CommunityPost>>(
                future: _reports,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    );
                  }
                  final reports = snapshot.data ?? const [];
                  if (reports.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No archived reports for this period.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      _retry();
                      await _reports;
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _StatisticsCard(reports: reports),
                        const SizedBox(height: 12),
                        for (final report in reports)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.report_outlined),
                              title: Text(
                                report.reportCategory?.label ?? report.title,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (report.body.trim().isNotEmpty)
                                    Text(report.body),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_dateLabel(report.createdAt)} • '
                                    'Community • ${report.authorName}',
                                  ),
                                ],
                              ),
                            ),
                          ),
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

  static String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}.${local.month}.${local.year} $hour:$minute';
  }
}

class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({required this.reports});
  final List<CommunityPost> reports;

  @override
  Widget build(BuildContext context) {
    final counts = <_ReportGroup, int>{
      for (final group in _ReportGroup.values) group: 0,
    };
    for (final report in reports) {
      final group = _groupFor(report.reportCategory);
      counts[group] = counts[group]! + 1;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            _stat('Total', reports.length),
            _stat('Fish Activity', counts[_ReportGroup.fishActivity]!),
            _stat('Water', counts[_ReportGroup.water]!),
            _stat('Access', counts[_ReportGroup.access]!),
            _stat('Risk', counts[_ReportGroup.risk]!),
            _stat('Other', counts[_ReportGroup.other]!),
          ],
        ),
      ),
    );
  }

  static Widget _stat(String label, int value) => SizedBox(
    width: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label),
      ],
    ),
  );

  static _ReportGroup _groupFor(ReportCategory? category) => switch (category) {
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
}
