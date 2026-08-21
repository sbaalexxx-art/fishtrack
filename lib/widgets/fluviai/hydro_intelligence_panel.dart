import 'package:flutter/material.dart';

@immutable
class HydroIntelligenceDatum {
  const HydroIntelligenceDatum({
    required this.label,
    required this.value,
    this.icon = Icons.info_outline_rounded,
  });

  final String label;
  final String value;
  final IconData icon;
}

@immutable
class HydroRelationshipItem {
  const HydroRelationshipItem({
    required this.label,
    required this.title,
    required this.typeLabel,
    this.icon = Icons.account_tree_rounded,
  });

  final String label;
  final String title;
  final String typeLabel;
  final IconData icon;
}

@immutable
class HydroDispatchDayViewData {
  const HydroDispatchDayViewData({
    required this.dayLabel,
    required this.dateLabel,
    required this.statusLabel,
    required this.probabilityLabel,
    required this.windowLabel,
    required this.evidenceLabel,
    required this.confidenceLabel,
    required this.freshnessLabel,
    required this.available,
  });

  final String dayLabel;
  final String dateLabel;
  final String statusLabel;
  final String probabilityLabel;
  final String windowLabel;
  final String evidenceLabel;
  final String confidenceLabel;
  final String freshnessLabel;
  final bool available;
}

@immutable
class HydroIntelligenceViewData {
  const HydroIntelligenceViewData({
    required this.name,
    required this.typeLabel,
    required this.icon,
    required this.accentColor,
    required this.statusLabel,
    required this.statusTitle,
    required this.unavailableLabel,
    required this.unknownMessage,
    this.contextLabel,
    this.metadataLabel,
    this.forecastProbabilityLabel,
    this.forecastWindowLabel,
    this.forecastConfidenceLabel,
    this.forecastEvidenceLabel,
    this.dispatchDays = const <HydroDispatchDayViewData>[],
    this.statusColor,
    this.evidenceLabel,
    this.sourceLabel,
    this.freshnessLabel,
    this.confidenceLabel,
    this.relationshipLabel,
    this.relationships = const <HydroRelationshipItem>[],
    this.data = const <HydroIntelligenceDatum>[],
    this.hasOperationalStatus = false,
    this.loading = false,
  });

  final String name;
  final String typeLabel;
  final String? contextLabel;
  final String? metadataLabel;
  final String? forecastProbabilityLabel;
  final String? forecastWindowLabel;
  final String? forecastConfidenceLabel;
  final String? forecastEvidenceLabel;
  final List<HydroDispatchDayViewData> dispatchDays;
  final IconData icon;
  final Color accentColor;
  final String statusLabel;
  final String statusTitle;
  final String unavailableLabel;
  final Color? statusColor;
  final String? evidenceLabel;
  final String? sourceLabel;
  final String? freshnessLabel;
  final String? confidenceLabel;
  final String? relationshipLabel;
  final List<HydroRelationshipItem> relationships;
  final String unknownMessage;
  final List<HydroIntelligenceDatum> data;
  final bool hasOperationalStatus;
  final bool loading;
}

class HydroIntelligencePanel extends StatelessWidget {
  const HydroIntelligencePanel({
    super.key,
    required this.data,
    required this.expanded,
    required this.detailsLabel,
    required this.graphLabel,
    required this.askLabel,
    required this.sourceLabel,
    required this.updatedLabel,
    required this.onToggleExpanded,
    required this.onClose,
    this.isFavorite = false,
    this.onFavorite,
    this.onDetails,
    this.onWaterIntelligence,
    this.onAlert,
    this.onCenter,
    this.onGraph,
    this.onAsk,
  });

  final HydroIntelligenceViewData data;
  final bool expanded;
  final bool isFavorite;
  final String detailsLabel;
  final String graphLabel;
  final String askLabel;
  final String sourceLabel;
  final String updatedLabel;
  final VoidCallback onToggleExpanded;
  final VoidCallback onClose;
  final VoidCallback? onFavorite;
  final VoidCallback? onDetails;
  final VoidCallback? onWaterIntelligence;
  final VoidCallback? onAlert;
  final VoidCallback? onCenter;
  final VoidCallback? onGraph;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final effectiveStatusColor = data.statusColor ?? data.accentColor;
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return Material(
      key: const ValueKey('hydro-intelligence-panel'),
      color: Colors.transparent,
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFA0B1820), Color(0xFA081218)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: data.accentColor.withValues(alpha: .52)),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .58,
            ),
            child: SingleChildScrollView(
              key: ValueKey<String>(
                'hydro-intelligence-scroll:${data.typeLabel}:${data.name}',
              ),
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 10, 13),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggleExpanded,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFF78909C),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('hydro-intelligence-panel-header'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: onToggleExpanded,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: data.accentColor.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: data.accentColor.withValues(alpha: .48),
                                ),
                              ),
                              child: Icon(
                                data.icon,
                                color: data.accentColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    data.name,
                                    maxLines: expanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFF5FBFF),
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      height: 1.05,
                                      letterSpacing: -.25,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    <String>[
                                      data.typeLabel,
                                      if (data.contextLabel?.isNotEmpty == true)
                                        data.contextLabel!,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF91A8B5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                              onPressed: onClose,
                              visualDensity: VisualDensity.compact,
                              color: const Color(0xFFD9E5EA),
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (data.loading) ...<Widget>[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        minHeight: 2,
                        color: data.accentColor,
                        backgroundColor: const Color(0xFF20323B),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _OperationalSummary(
                      sectionTitle: isRomanian
                          ? 'CE ȘTIM ACUM'
                          : 'WHAT WE KNOW NOW',
                      title: data.statusTitle,
                      status: data.statusLabel,
                      unavailableLabel: data.unavailableLabel,
                      available: data.hasOperationalStatus,
                      color: effectiveStatusColor,
                    ),
                    if (data.dispatchDays.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      _DispatchDayStack(
                        days: data.dispatchDays,
                        accent: data.accentColor,
                      ),
                    ] else if (data.forecastProbabilityLabel?.isNotEmpty ==
                            true &&
                        data.forecastWindowLabel?.isNotEmpty == true) ...<Widget>[
                      const SizedBox(height: 8),
                      _DispatchForecastSummary(
                        probability: data.forecastProbabilityLabel!,
                        window: data.forecastWindowLabel!,
                        confidence: data.forecastConfidenceLabel,
                        evidence: data.forecastEvidenceLabel,
                        color: data.accentColor,
                      ),
                    ],
                    if (data.evidenceLabel?.isNotEmpty == true ||
                        data.freshnessLabel?.isNotEmpty == true) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: <Widget>[
                          if (data.evidenceLabel?.isNotEmpty == true)
                            _TruthChip(
                              icon: Icons.verified_outlined,
                              label: data.evidenceLabel!,
                              color: data.accentColor,
                            ),
                          if (data.freshnessLabel?.isNotEmpty == true)
                            _TruthChip(
                              icon: Icons.schedule_rounded,
                              label: data.freshnessLabel!,
                              color: const Color(0xFF8FB7CB),
                            ),
                        ],
                      ),
                    ],
                    if (expanded) ...<Widget>[
                      const SizedBox(height: 12),
                      if (data.relationships.isNotEmpty ||
                          data.relationshipLabel?.isNotEmpty == true) ...<Widget>[
                        _SectionLabel(
                          label: isRomanian ? 'CONTEXT HIDRO' : 'HYDRO CONTEXT',
                        ),
                        const SizedBox(height: 7),
                        _RelationshipContext(
                          relationships: data.relationships.isNotEmpty
                              ? data.relationships
                              : <HydroRelationshipItem>[
                                  HydroRelationshipItem(
                                    label: isRomanian ? 'Asociat' : 'Related',
                                    title: data.relationshipLabel!,
                                    typeLabel: isRomanian
                                        ? 'Context verificat'
                                        : 'Verified context',
                                  ),
                                ],
                          color: data.accentColor,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (data.data.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: data.data
                              .map(
                                (datum) => _DatumTile(
                                  datum: datum,
                                  color: data.accentColor,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: <Widget>[
                          if (data.sourceLabel?.isNotEmpty == true)
                            _TruthChip(
                              icon: Icons.source_rounded,
                              label: '$sourceLabel: ${data.sourceLabel}',
                              color: const Color(0xFF8FB7CB),
                            ),
                          if (data.metadataLabel?.isNotEmpty == true)
                            _TruthChip(
                              icon: Icons.account_balance_outlined,
                              label: data.metadataLabel!,
                              color: const Color(0xFF8FB7CB),
                            ),
                          if (data.confidenceLabel?.isNotEmpty == true)
                            _TruthChip(
                              icon: Icons.insights_rounded,
                              label: data.confidenceLabel!,
                              color: const Color(0xFF8FB7CB),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 9),
                    if (onWaterIntelligence != null || onDetails != null)
                      Row(
                        children: <Widget>[
                          if (onWaterIntelligence != null)
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey(
                                  'hydro-panel-water-intelligence',
                                ),
                                onPressed: onWaterIntelligence,
                                style: FilledButton.styleFrom(
                                  foregroundColor: const Color(0xFF041318),
                                  backgroundColor: data.accentColor,
                                  minimumSize: const Size(0, 42),
                                ),
                                icon: const Icon(
                                  Icons.water_drop_rounded,
                                  size: 17,
                                ),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isRomanian
                                        ? 'Inteligență hidrologică'
                                        : 'Water Intelligence',
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                          if (onWaterIntelligence != null && onDetails != null)
                            const SizedBox(width: 8),
                          if (onDetails != null)
                            SizedBox(
                              width: onWaterIntelligence == null ? 148 : 112,
                              child: OutlinedButton.icon(
                                key: const ValueKey('hydro-panel-details'),
                                onPressed: onDetails,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFF5FBFF),
                                  side: BorderSide(
                                    color: data.accentColor.withValues(
                                      alpha: .52,
                                    ),
                                  ),
                                  minimumSize: const Size(0, 42),
                                ),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                ),
                                label: Text(detailsLabel),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        if (onFavorite != null)
                          _PanelAction(
                            key: const ValueKey('hydro-panel-favorite'),
                            onTap: onFavorite!,
                            color: data.accentColor,
                            icon: isFavorite
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            label: isFavorite
                                ? (isRomanian ? 'Salvat' : 'Saved')
                                : (isRomanian ? 'Salvează' : 'Save'),
                          ),
                        if (onAlert != null)
                          _PanelAction(
                            key: const ValueKey('hydro-panel-alert'),
                            onTap: onAlert!,
                            color: data.accentColor,
                            icon: Icons.notifications_none_rounded,
                            label: isRomanian ? 'Alertă' : 'Alert',
                          ),
                        if (onCenter != null)
                          _PanelAction(
                            key: const ValueKey('hydro-panel-center'),
                            onTap: onCenter!,
                            color: data.accentColor,
                            icon: Icons.my_location_rounded,
                            label: isRomanian ? 'Centrează' : 'Center',
                          ),
                        if (onGraph != null)
                          IconButton(
                            key: const ValueKey('hydro-panel-graph'),
                            tooltip: graphLabel,
                            onPressed: onGraph,
                            color: data.accentColor,
                            icon: const Icon(Icons.show_chart_rounded),
                          ),
                        if (onAsk != null)
                          IconButton(
                            key: const ValueKey('hydro-panel-ask'),
                            tooltip: askLabel,
                            onPressed: onAsk,
                            color: data.accentColor,
                            icon: const Icon(Icons.auto_awesome_rounded),
                          ),
                        const Spacer(),
                        IconButton(
                          key: const ValueKey('hydro-panel-expand'),
                          onPressed: onToggleExpanded,
                          color: const Color(0xFFB6CAD4),
                          icon: AnimatedRotation(
                            duration: const Duration(milliseconds: 220),
                            turns: expanded ? .5 : 0,
                            child: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DispatchDayStack extends StatelessWidget {
  const _DispatchDayStack({required this.days, required this.accent});

  final List<HydroDispatchDayViewData> days;
  final Color accent;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('hydro-panel-dispatch-summary'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (var index = 0; index < days.length; index++) ...<Widget>[
        _DispatchDayCard(day: days[index], accent: accent),
        if (index != days.length - 1) const SizedBox(height: 8),
      ],
    ],
  );
}

class _DispatchDayCard extends StatelessWidget {
  const _DispatchDayCard({required this.day, required this.accent});

  final HydroDispatchDayViewData day;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey<String>('hydro-panel-dispatch-${day.dayLabel}'),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
    decoration: BoxDecoration(
      color: const Color(0xFF102029),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: accent.withValues(alpha: .34)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.bolt_rounded, color: accent, size: 15),
            const SizedBox(width: 5),
            Text(
              day.dayLabel.toUpperCase(),
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .75,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              day.dateLabel,
              style: const TextStyle(
                color: Color(0xFF91A8B5),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              day.evidenceLabel,
              style: const TextStyle(
                color: Color(0xFFA7BBC5),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              day.probabilityLabel,
              style: const TextStyle(
                color: Color(0xFFF6FBFD),
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  day.available ? day.windowLabel : day.statusLabel,
                  style: const TextStyle(
                    color: Color(0xFFF6FBFD),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  day.confidenceLabel,
                  style: const TextStyle(
                    color: Color(0xFF91A8B5),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          day.freshnessLabel,
          style: const TextStyle(
            color: Color(0xFF78909C),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _DispatchForecastSummary extends StatelessWidget {
  const _DispatchForecastSummary({
    required this.probability,
    required this.window,
    required this.color,
    this.confidence,
    this.evidence,
  });

  final String probability;
  final String window;
  final String? confidence;
  final String? evidence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return Container(
      key: const ValueKey('hydro-panel-dispatch-summary-legacy'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF102029),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isRomanian
                      ? 'PROBABILITATE DE UZINARE'
                      : 'GENERATION PROBABILITY',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
              ),
              if (evidence?.isNotEmpty == true)
                Text(
                  evidence!,
                  style: const TextStyle(
                    color: Color(0xFFA7BBC5),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                probability,
                style: const TextStyle(
                  color: Color(0xFFF6FBFD),
                  fontSize: 29,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    isRomanian ? 'Interval estimat' : 'Estimated window',
                    style: const TextStyle(
                      color: Color(0xFF91A8B5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    window,
                    style: const TextStyle(
                      color: Color(0xFFF6FBFD),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (confidence?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              confidence!,
              style: const TextStyle(
                color: Color(0xFF9FB4BE),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OperationalSummary extends StatelessWidget {
  const _OperationalSummary({
    required this.sectionTitle,
    required this.title,
    required this.status,
    required this.unavailableLabel,
    required this.available,
    required this.color,
  });

  final String sectionTitle;
  final String title;
  final String status;
  final String unavailableLabel;
  final bool available;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('hydro-panel-operational-summary'),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          sectionTitle,
          style: TextStyle(
            color: color.withValues(alpha: .92),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: .85,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.monitor_heart_outlined, color: color, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8EA5B1),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    available ? status : unavailableLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: available ? color : const Color(0xFFD3E0E6),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: Color(0xFF8EA5B1),
      fontSize: 9,
      fontWeight: FontWeight.w900,
      letterSpacing: .85,
    ),
  );
}

class _RelationshipContext extends StatelessWidget {
  const _RelationshipContext({
    required this.relationships,
    required this.color,
  });

  final List<HydroRelationshipItem> relationships;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Column(
      children: relationships
          .take(3)
          .map(
            (relationship) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 58,
                    child: Text(
                      relationship.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(relationship.icon, color: color, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          relationship.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE1EDF2),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          relationship.typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF829AA7),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB7C9D2),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DatumTile extends StatelessWidget {
  const _DatumTile({required this.datum, required this.color});

  final HydroIntelligenceDatum datum;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: (MediaQuery.sizeOf(context).width - 78) / 2,
    constraints: const BoxConstraints(minWidth: 126, maxWidth: 220),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFF12242D),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFF263D48)),
    ),
    child: Row(
      children: <Widget>[
        Icon(datum.icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                datum.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF829AA7),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                datum.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF0F7FA),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TruthChip extends StatelessWidget {
  const _TruthChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: .24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
