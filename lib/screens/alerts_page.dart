import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/context/selected_context.dart';
import '../core/theme/fluviai_commercial_tokens.dart';
import '../models/station.dart';
import '../services/alert_rule_repository.dart';
import '../widgets/fluviai/fluviai_components.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key, this.repository = const AlertRuleRepository()});

  final AlertRuleRepository repository;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  late Future<List<AlertRule>> _rules;

  @override
  void initState() {
    super.initState();
    _rules = widget.repository.load();
  }

  bool get _isRo => Localizations.localeOf(context).languageCode == 'ro';

  Future<void> _refresh() async {
    final next = widget.repository.load();
    setState(() => _rules = next);
    await next;
  }

  Future<void> _edit({AlertRule? rule}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: RouteSettings(
          name: rule == null ? '/alerts/new' : '/alerts/${rule.id}/edit',
        ),
        builder: (_) => AlertEditorPage(
          rule: rule,
          repository: widget.repository,
          returnToList: true,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FluviScreen(
      title: _isRo ? 'Alerte, reguli și siguranță' : 'Alerts, rules & safety',
      eyebrow: _isRo ? 'MONITORIZARE PERSONALĂ' : 'PERSONAL MONITORING',
      actions: [
        IconButton(
          key: const Key('alerts-add-action'),
          tooltip: _isRo ? 'Alertă nouă' : 'New alert',
          onPressed: _edit,
          icon: const Icon(Icons.add_alert_rounded),
        ),
      ],
      child: FutureBuilder<List<AlertRule>>(
        future: _rules,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return FluviStatePanel(
              icon: Icons.error_outline_rounded,
              title: _isRo
                  ? 'Alertele nu pot fi citite'
                  : 'Alerts cannot be loaded',
              message: _isRo
                  ? 'Regulile locale nu au fost modificate.'
                  : 'Local rules were not changed.',
              actionLabel: _isRo ? 'Reîncearcă' : 'Retry',
              onAction: _refresh,
            );
          }
          final rules = snapshot.data ?? const <AlertRule>[];
          if (rules.isEmpty) {
            return FluviStatePanel(
              icon: Icons.notifications_none_rounded,
              title: _isRo ? 'Nicio alertă personală' : 'No personal alerts',
              message: _isRo
                  ? 'Creează o regulă pentru o apă sau stație selectată. FluviAI nu pornește monitorizări implicite.'
                  : 'Create a rule for a selected water or station. FluviAI starts no monitoring by default.',
              actionLabel: _isRo ? 'Creează alertă' : 'Create alert',
              onAction: _edit,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: rules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final rule = rules[index];
                return FluviSurfaceCard(
                  onTap: () => _edit(rule: rule),
                  child: Row(
                    children: [
                      Icon(
                        _kindIcon(rule.kind),
                        color: rule.enabled
                            ? FluviAICommercialTokens.brandFocus
                            : FluviAICommercialTokens.textMuted,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rule.entityLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _kindLabel(rule.kind, _isRo),
                              style: const TextStyle(
                                color: FluviAICommercialTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FluviStatusBadge(
                        status: rule.enabled
                            ? FluviDataStatus.live
                            : FluviDataStatus.offline,
                        label: rule.enabled
                            ? (_isRo ? 'ACTIVĂ' : 'ACTIVE')
                            : (_isRo ? 'OPRITĂ' : 'OFF'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class AlertEditorPage extends ConsumerStatefulWidget {
  const AlertEditorPage({
    super.key,
    this.station,
    this.rule,
    this.repository = const AlertRuleRepository(),
    this.returnToList = false,
  });

  final Station? station;
  final AlertRule? rule;
  final AlertRuleRepository repository;
  final bool returnToList;

  @override
  ConsumerState<AlertEditorPage> createState() => _AlertEditorPageState();
}

class _AlertEditorPageState extends ConsumerState<AlertEditorPage> {
  late AlertRuleKind _kind;
  late bool _enabled;
  late final TextEditingController _threshold;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.rule?.kind ?? AlertRuleKind.rapidChange;
    _enabled = widget.rule?.enabled ?? true;
    _threshold = TextEditingController(
      text: widget.rule?.threshold?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  bool get _isRo => Localizations.localeOf(context).languageCode == 'ro';

  Future<void> _save() async {
    final selected = ref.read(selectedContextProvider);
    final entityId =
        widget.rule?.entityId ??
        widget.station?.id ??
        selected?.stationId ??
        selected?.waterId;
    final entityLabel =
        widget.rule?.entityLabel ??
        widget.station?.name ??
        selected?.primaryLabel;
    if (entityId == null || entityLabel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRo
                ? 'Selectează mai întâi o apă sau o stație reală.'
                : 'Select a real water or station first.',
          ),
        ),
      );
      return;
    }
    final parsedThreshold = double.tryParse(
      _threshold.text.trim().replaceAll(',', '.'),
    );
    setState(() => _saving = true);
    try {
      await widget.repository.save(
        AlertRule(
          id:
              widget.rule?.id ??
              'alert-${DateTime.now().microsecondsSinceEpoch}',
          entityId: entityId,
          entityLabel: entityLabel,
          kind: _kind,
          createdAt: widget.rule?.createdAt ?? DateTime.now(),
          threshold: parsedThreshold,
          enabled: _enabled,
        ),
      );
      if (!mounted) return;
      if (widget.returnToList) {
        Navigator.of(context).pop(true);
      } else {
        await Navigator.of(context).pushReplacement<void, bool>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/alerts'),
            builder: (_) => AlertsPage(repository: widget.repository),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final rule = widget.rule;
    if (rule == null) return;
    await widget.repository.remove(rule.id);
    if (!mounted) return;
    if (widget.returnToList) {
      Navigator.of(context).pop(true);
    } else {
      await Navigator.of(context).pushReplacement<void, bool>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/alerts'),
          builder: (_) => AlertsPage(repository: widget.repository),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedContextProvider);
    final entityLabel =
        widget.rule?.entityLabel ??
        widget.station?.name ??
        selected?.primaryLabel;
    return FluviScreen(
      title: widget.rule == null
          ? (_isRo ? 'Alertă nouă' : 'New alert')
          : (_isRo ? 'Editează alerta' : 'Edit alert'),
      eyebrow: _isRo ? 'REGULĂ PERSONALĂ' : 'PERSONAL RULE',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FluviSurfaceCard(
            child: Row(
              children: [
                const Icon(
                  Icons.water_rounded,
                  color: FluviAICommercialTokens.brandFocus,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entityLabel ??
                        (_isRo ? 'Nicio apă selectată' : 'No water selected'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                FluviStatusBadge(
                  status: entityLabel == null
                      ? FluviDataStatus.empty
                      : FluviDataStatus.live,
                  label: entityLabel == null
                      ? (_isRo ? 'NESELECTAT' : 'UNSELECTED')
                      : (_isRo ? 'SELECTAT' : 'SELECTED'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AlertRuleKind>(
            initialValue: _kind,
            decoration: InputDecoration(
              labelText: _isRo ? 'Tip alertă' : 'Alert type',
            ),
            items: AlertRuleKind.values
                .map(
                  (kind) => DropdownMenuItem(
                    value: kind,
                    child: Text(_kindLabel(kind, _isRo)),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _kind = value ?? _kind),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _threshold,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _isRo ? 'Prag opțional' : 'Optional threshold',
              suffixText: widget.station?.waterLevelUnit,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
            title: Text(_isRo ? 'Alertă activă' : 'Alert active'),
            subtitle: Text(
              _isRo
                  ? 'Regula este stocată local pe acest dispozitiv.'
                  : 'The rule is stored locally on this device.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_isRo ? 'Salvează alerta' : 'Save alert'),
          ),
          if (widget.rule != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _saving ? null : _remove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(_isRo ? 'Șterge alerta' : 'Delete alert'),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _kindIcon(AlertRuleKind kind) => switch (kind) {
  AlertRuleKind.levelAbove => Icons.trending_up_rounded,
  AlertRuleKind.levelBelow => Icons.trending_down_rounded,
  AlertRuleKind.rapidChange => Icons.change_circle_rounded,
  AlertRuleKind.stateChange => Icons.water_drop_outlined,
  AlertRuleKind.communityReport => Icons.campaign_rounded,
};

String _kindLabel(AlertRuleKind kind, bool isRo) => switch (kind) {
  AlertRuleKind.levelAbove =>
    isRo ? 'Nivel peste prag' : 'Level above threshold',
  AlertRuleKind.levelBelow => isRo ? 'Nivel sub prag' : 'Level below threshold',
  AlertRuleKind.rapidChange => isRo ? 'Schimbare rapidă' : 'Rapid change',
  AlertRuleKind.stateChange =>
    isRo ? 'Schimbare stare observată' : 'Observed state change',
  AlertRuleKind.communityReport =>
    isRo ? 'Raport nou în zonă' : 'New nearby report',
};
