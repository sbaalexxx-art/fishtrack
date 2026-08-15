import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/context/selected_context.dart';
import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../core/theme/fluviai_commercial_tokens.dart';
import '../services/billing_repository.dart';
import '../widgets/fluviai/fluviai_components.dart';

class PremiumPage extends ConsumerStatefulWidget {
  const PremiumPage({
    super.key,
    this.billingRepository = const UnavailableBillingRepository(),
  });

  final BillingRepository billingRepository;

  @override
  ConsumerState<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends ConsumerState<PremiumPage> {
  bool _restoring = false;

  bool get _isRo => Localizations.localeOf(context).languageCode == 'ro';

  Future<void> _restore() async {
    setState(() => _restoring = true);
    BillingRestoreResult result;
    try {
      result = await widget.billingRepository.restorePurchases();
    } on Exception {
      result = BillingRestoreResult.error;
    }
    if (!mounted) return;
    setState(() => _restoring = false);
    if (result == BillingRestoreResult.restored) {
      ref
          .read(fluviAccessTierProvider.notifier)
          .setTier(FluviAccessTier.premium);
    }
    await AppNavigator.open<void>(
      context,
      AppDestination.premiumRestored,
      arguments: result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(fluviAccessTierProvider);
    final isPremium = tier == FluviAccessTier.premium;
    return FluviScreen(
      title: 'FluviAI Premium',
      eyebrow: isPremium
          ? (_isRo ? 'PLAN ACTIV' : 'ACTIVE PLAN')
          : (_isRo ? 'PLAN FREE' : 'FREE PLAN'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FluviStatusBadge(
            status: isPremium ? FluviDataStatus.live : FluviDataStatus.cache,
            label: isPremium ? 'PREMIUM' : 'FREE',
          ),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FluviSurfaceCard(
            accent: FluviAICommercialTokens.premium,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: FluviAICommercialTokens.premium,
                  size: 42,
                ),
                const SizedBox(height: 18),
                Text(
                  _isRo
                      ? 'Mai mult context. Aceleași date sincere.'
                      : 'More context. The same truthful data.',
                  style: const TextStyle(
                    fontSize: 25,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isRo
                      ? 'Premium poate extinde analiza, alertele și istoricul. Datele lipsă nu sunt înlocuite niciodată cu valori demonstrative.'
                      : 'Premium can extend analysis, alerts and history. Missing data is never replaced with demo values.',
                  style: const TextStyle(
                    color: FluviAICommercialTokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final feature in [
            (
              _isRo ? 'Istoric extins al apei' : 'Extended water history',
              Icons.show_chart_rounded,
            ),
            (
              _isRo ? 'Reguli de alertă avansate' : 'Advanced alert rules',
              Icons.notifications_active_rounded,
            ),
            (
              _isRo ? 'Context Fluvi aprofundat' : 'Deeper Fluvi context',
              Icons.auto_awesome_rounded,
            ),
          ]) ...[
            FluviSurfaceCard(
              child: Row(
                children: [
                  Icon(feature.$2, color: FluviAICommercialTokens.premium),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      feature.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(
                    isPremium
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    color: isPremium
                        ? FluviAICommercialTokens.waterStable
                        : FluviAICommercialTokens.textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('premium-restore-action'),
            onPressed: _restoring ? null : _restore,
            icon: _restoring
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore_rounded),
            label: Text(
              _isRo ? 'Restaurează achizițiile' : 'Restore purchases',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isRo
                ? 'Magazinul nu este conectat în această versiune. Butonul verifică repository-ul de billing și raportează rezultatul real.'
                : 'The store is not connected in this build. The button checks the billing repository and reports its real result.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: FluviAICommercialTokens.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumRestoreResultPage extends StatelessWidget {
  const PremiumRestoreResultPage({super.key, required this.result});

  final BillingRestoreResult result;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final (icon, title, message, status) = switch (result) {
      BillingRestoreResult.restored => (
        Icons.check_circle_rounded,
        isRo ? 'Premium restaurat' : 'Premium restored',
        isRo
            ? 'Drepturile Premium au fost restaurate pentru această sesiune.'
            : 'Premium entitlement was restored for this session.',
        FluviDataStatus.live,
      ),
      BillingRestoreResult.nothingToRestore => (
        Icons.info_rounded,
        isRo ? 'Nicio achiziție găsită' : 'No purchase found',
        isRo
            ? 'Magazinul nu a returnat o achiziție eligibilă.'
            : 'The store returned no eligible purchase.',
        FluviDataStatus.empty,
      ),
      BillingRestoreResult.unavailable => (
        Icons.cloud_off_rounded,
        isRo ? 'Restaurarea nu este disponibilă' : 'Restore is unavailable',
        isRo
            ? 'Repository-ul de billing nu este conectat; nu s-a modificat planul.'
            : 'The billing repository is not connected; the plan was not changed.',
        FluviDataStatus.offline,
      ),
      BillingRestoreResult.error => (
        Icons.error_outline_rounded,
        isRo ? 'Restaurarea a eșuat' : 'Restore failed',
        isRo
            ? 'Planul nu a fost modificat. Încearcă din nou mai târziu.'
            : 'The plan was not changed. Try again later.',
        FluviDataStatus.error,
      ),
    };
    return FluviScreen(
      title: isRo ? 'Rezultat restaurare' : 'Restore result',
      eyebrow: 'FLUVIAI PREMIUM',
      child: FluviStatePanel(
        icon: icon,
        title: title,
        message: message,
        actionLabel: isRo ? 'Continuă la profil' : 'Continue to profile',
        onAction: () => AppNavigator.open(context, AppDestination.profile),
      ),
    );
  }
}
