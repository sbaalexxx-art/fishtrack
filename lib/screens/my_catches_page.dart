import 'package:flutter/material.dart';

import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../core/theme/fluviai_commercial_tokens.dart';
import '../models/catch.dart';
import '../repositories/catch_repository.dart';
import '../widgets/fluviai/fluviai_components.dart';

class MyCatchesPage extends StatefulWidget {
  const MyCatchesPage({super.key, this.repository = const CatchRepository()});

  final CatchRepository repository;

  @override
  State<MyCatchesPage> createState() => _MyCatchesPageState();
}

class _MyCatchesPageState extends State<MyCatchesPage> {
  late Future<List<Catch>> _catches;

  @override
  void initState() {
    super.initState();
    _catches = widget.repository.getMyCatches();
  }

  bool get _isRo => Localizations.localeOf(context).languageCode == 'ro';

  Future<void> _refresh() async {
    final next = widget.repository.getMyCatches();
    setState(() => _catches = next);
    await next;
  }

  Future<void> _add() async {
    final added = await AppNavigator.open<bool>(
      context,
      AppDestination.addCatch,
    );
    if (added == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FluviScreen(
      title: _isRo ? 'Capturile mele' : 'My catches',
      eyebrow: _isRo ? 'JURNAL PERSONAL' : 'PERSONAL JOURNAL',
      actions: [
        IconButton(
          key: const Key('my-catches-add-action'),
          tooltip: _isRo ? 'Adaugă captură' : 'Add catch',
          onPressed: _add,
          icon: const Icon(Icons.add_a_photo_rounded),
        ),
      ],
      child: FutureBuilder<List<Catch>>(
        future: _catches,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return FluviStatePanel(
              icon: Icons.cloud_off_rounded,
              title: _isRo
                  ? 'Capturile nu pot fi încărcate'
                  : 'Catches cannot be loaded',
              message: _isRo
                  ? 'Nu afișăm capturi demonstrative. Verifică sesiunea și conexiunea.'
                  : 'No demo catches are shown. Check your session and connection.',
              actionLabel: _isRo ? 'Reîncearcă' : 'Retry',
              onAction: _refresh,
            );
          }
          final catches = snapshot.data ?? const <Catch>[];
          if (catches.isEmpty) {
            return FluviStatePanel(
              icon: Icons.set_meal_outlined,
              title: _isRo ? 'Nicio captură salvată' : 'No saved catches',
              message: _isRo
                  ? 'Fotografia și datele capturii vor apărea aici după salvarea reală.'
                  : 'The photo and catch data will appear here after a real save.',
              actionLabel: _isRo ? 'Adaugă captură' : 'Add catch',
              onAction: _add,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: catches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _CatchCard(catchEntry: catches[index]),
            ),
          );
        },
      ),
    );
  }
}

class _CatchCard extends StatelessWidget {
  const _CatchCard({required this.catchEntry});

  final Catch catchEntry;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final measurements = <String>[
      if (catchEntry.weight != null)
        '${catchEntry.weight!.toStringAsFixed(1)} kg',
      if (catchEntry.length != null)
        '${catchEntry.length!.toStringAsFixed(0)} cm',
    ];
    return FluviSurfaceCard(
      onTap: () => AppNavigator.open(context, AppDestination.addCatch),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: FluviAICommercialTokens.waterStable.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.set_meal_rounded,
              color: FluviAICommercialTokens.waterStable,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  catchEntry.species,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  measurements.isEmpty
                      ? (isRo ? 'Fără măsurători' : 'No measurements')
                      : measurements.join(' · '),
                  style: const TextStyle(
                    color: FluviAICommercialTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: FluviAICommercialTokens.textMuted,
          ),
        ],
      ),
    );
  }
}
