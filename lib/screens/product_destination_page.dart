import 'package:flutter/material.dart';

import '../core/navigation/app_destination.dart';
import '../core/theme/fluviai_commercial_tokens.dart';
import '../widgets/fluviai/fluviai_components.dart';

class ProductDestinationPage extends StatelessWidget {
  const ProductDestinationPage({
    super.key,
    required this.destination,
    this.onOpen,
    this.entityLabel,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination>? onOpen;
  final String? entityLabel;

  bool _ro(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ro';

  @override
  Widget build(BuildContext context) {
    final isRo = _ro(context);
    final definition = AppDestinationRegistry.of(destination);
    final content = _content(isRo);
    return FluviScreen(
      title: definition.title(isRo),
      eyebrow: content.eyebrow,
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 12),
          child: FluviStatusBadge(status: FluviDataStatus.empty),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final body = _DestinationBody(
            content: content,
            entityLabel: entityLabel,
            isRo: isRo,
            onOpen: onOpen,
          );
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? 32 : 16,
              18,
              wide ? 32 : 16,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: body,
              ),
            ),
          );
        },
      ),
    );
  }

  _DestinationContent _content(bool ro) => switch (destination) {
    AppDestination.river => _DestinationContent(
      eyebrow: ro ? 'RÂU SELECTAT' : 'SELECTED RIVER',
      icon: Icons.waves_rounded,
      title: entityLabel ?? (ro ? 'Niciun râu selectat' : 'No river selected'),
      message: ro
          ? 'Selectează un râu real din Water sau Căutare. Starea oficială și comunitară rămân separate.'
          : 'Select a real river from Water or Search. Official and community state remain separate.',
      actions: const [AppDestination.water, AppDestination.favorites],
    ),
    AppDestination.reservoir => _DestinationContent(
      eyebrow: ro ? 'APĂ SELECTATĂ' : 'SELECTED WATER',
      icon: Icons.waves_rounded,
      title:
          entityLabel ??
          (ro ? 'Nicio acumulare selectată' : 'No reservoir selected'),
      message: ro
          ? 'Selectează o acumulare reală din hartă pentru nivel, tendință și sursa observației.'
          : 'Select a real reservoir on the map for level, trend and observation source.',
      actions: const [AppDestination.map, AppDestination.favorites],
    ),
    AppDestination.hydropower => _DestinationContent(
      eyebrow: ro ? 'INFRASTRUCTURĂ' : 'INFRASTRUCTURE',
      icon: Icons.electric_bolt_rounded,
      title:
          entityLabel ??
          (ro
              ? 'Nicio hidrocentrală selectată'
              : 'No hydropower plant selected'),
      message: ro
          ? 'Debitele și operațiunile apar numai când există o sursă publică verificată pentru entitatea selectată.'
          : 'Flow and operations appear only when a verified public source exists for the selected entity.',
      actions: const [AppDestination.map, AppDestination.water],
    ),
    AppDestination.askFluvi => _DestinationContent(
      eyebrow: 'FLUVI AI',
      icon: Icons.chat_bubble_rounded,
      title: ro
          ? 'Întreabă despre apa selectată'
          : 'Ask about the selected water',
      message: ro
          ? 'Răspunsurile AI nu sunt conectate încă. Contextul selectat va fi păstrat, fără răspunsuri inventate.'
          : 'AI answers are not connected yet. Selected context will be preserved without invented answers.',
      actions: const [AppDestination.fluvi, AppDestination.water],
    ),
    AppDestination.alerts ||
    AppDestination.newAlert ||
    AppDestination.editAlert => _DestinationContent(
      eyebrow: ro ? 'MONITORIZARE PERSONALĂ' : 'PERSONAL MONITORING',
      icon: Icons.notifications_active_rounded,
      title: ro ? 'Alerte pentru contextul tău' : 'Alerts for your context',
      message: ro
          ? 'Creează reguli numai pentru ape și stații reale selectate.'
          : 'Create rules only for real selected waters and stations.',
      actions: const [
        AppDestination.newAlert,
        AppDestination.notifications,
        AppDestination.safety,
      ],
    ),
    AppDestination.journal => _DestinationContent(
      eyebrow: ro ? 'JURNAL PERSONAL' : 'PERSONAL JOURNAL',
      icon: Icons.menu_book_rounded,
      title: ro
          ? 'Jurnalul este pregătit pentru date reale'
          : 'Journal is ready for real data',
      message: ro
          ? 'Nu există încă un repository de sesiuni. Ecranul rămâne gol și nu creează sesiuni demonstrative.'
          : 'There is no session repository yet. The screen stays empty and creates no demo sessions.',
      actions: const [AppDestination.addCatch, AppDestination.myCatches],
    ),
    AppDestination.permit ||
    AppDestination.regulations ||
    AppDestination.safety => _DestinationContent(
      eyebrow: ro ? 'REGULI VERIFICATE' : 'VERIFIED GUIDANCE',
      icon: AppDestinationRegistry.of(destination).icon,
      title: ro ? 'Selectează țara și zona' : 'Select country and area',
      message: ro
          ? 'Conținutul legal nu este publicat în runtime. FluviAI nu afișează limite, sezoane sau permise neverificate.'
          : 'Legal content is not published in runtime. FluviAI does not show unverified limits, seasons or permits.',
      actions: const [AppDestination.toolkit, AppDestination.support],
    ),
    AppDestination.toolkit => _DestinationContent(
      eyebrow: ro ? 'PREGĂTIRE' : 'PREPARATION',
      icon: Icons.handyman_rounded,
      title: ro
          ? 'Instrumente pentru o ieșire sigură'
          : 'Tools for a safer trip',
      message: ro
          ? 'Verifică permisele, regulile și recomandările de siguranță pentru contextul tău.'
          : 'Check permits, regulations and safety guidance for your context.',
      actions: const [
        AppDestination.permit,
        AppDestination.regulations,
        AppDestination.safety,
      ],
    ),
    AppDestination.premium || AppDestination.restore => _DestinationContent(
      eyebrow: 'FLUVIAI PREMIUM',
      icon: Icons.workspace_premium_rounded,
      title: ro
          ? 'Funcții Premium, fără promisiuni false'
          : 'Premium features, without false promises',
      message: ro
          ? 'Magazinul și restaurarea achizițiilor nu sunt conectate. Nu se efectuează nicio plată.'
          : 'Store and purchase restore are not connected. No payment is performed.',
      actions: const [AppDestination.restore, AppDestination.profile],
      premium: true,
    ),
    AppDestination.support => _DestinationContent(
      eyebrow: ro ? 'SUPORT' : 'SUPPORT',
      icon: Icons.support_agent_rounded,
      title: ro ? 'Ajutor, feedback și contact' : 'Help, feedback & contact',
      message: ro
          ? 'Canalul de suport nu este conectat încă. Poți consulta starea aplicației și informațiile legale.'
          : 'The support channel is not connected yet. You can review app status and legal information.',
      actions: const [AppDestination.about, AppDestination.legal],
    ),
    AppDestination.legal ||
    AppDestination.privacy ||
    AppDestination.terms ||
    AppDestination.licences ||
    AppDestination.about => _DestinationContent(
      eyebrow: ro ? 'TRANSPARENȚĂ' : 'TRANSPARENCY',
      icon: AppDestinationRegistry.of(destination).icon,
      title: AppDestinationRegistry.of(destination).title(ro),
      message: ro
          ? 'Documentul public complet nu este inclus în aplicație. Nu afișăm text juridic demonstrativ.'
          : 'The complete public document is not bundled in the app. No demo legal text is shown.',
      actions: const [
        AppDestination.privacy,
        AppDestination.terms,
        AppDestination.licences,
        AppDestination.about,
      ],
    ),
    AppDestination.reportDetail => _DestinationContent(
      eyebrow: ro ? 'RAPORT COMUNITATE' : 'COMMUNITY REPORT',
      icon: Icons.campaign_rounded,
      title: entityLabel ?? (ro ? 'Raport indisponibil' : 'Report unavailable'),
      message: ro
          ? 'Deschide un raport real din Comunitate sau din arhivă pentru detalii și validare.'
          : 'Open a real report from Community or the archive for details and validation.',
      actions: const [
        AppDestination.community,
        AppDestination.myReports,
        AppDestination.map,
      ],
    ),
    AppDestination.reportConfirmed => _DestinationContent(
      eyebrow: ro ? 'ÎNCREDERE COMUNITATE' : 'COMMUNITY TRUST',
      icon: Icons.verified_rounded,
      title: ro
          ? 'Confirmarea cere un raport real'
          : 'Confirmation requires a real report',
      message: ro
          ? 'Deschide un raport real și trimite validarea. Această destinație nu pretinde că o confirmare a fost înregistrată.'
          : 'Open a real report and submit validation. This destination does not claim that a confirmation was recorded.',
      actions: const [AppDestination.community, AppDestination.myReports],
    ),
    AppDestination.myCatches ||
    AppDestination.catches ||
    AppDestination.catchDetail => _DestinationContent(
      eyebrow: ro ? 'CAPTURI REALE' : 'REAL CATCHES',
      icon: Icons.set_meal_rounded,
      title:
          entityLabel ??
          (ro ? 'Nicio captură disponibilă' : 'No catch available'),
      message: ro
          ? 'Capturile salvate în cont vor apărea aici. Nu sunt generate capturi demonstrative.'
          : 'Catches saved to the account will appear here. No demo catches are generated.',
      actions: const [AppDestination.addCatch, AppDestination.community],
    ),
    AppDestination.favoriteCollection => _DestinationContent(
      eyebrow: ro ? 'APELE MELE' : 'MY WATERS',
      icon: Icons.folder_special_rounded,
      title: entityLabel ?? (ro ? 'Colecție goală' : 'Empty collection'),
      message: ro
          ? 'Salvează o entitate reală din hartă sau din pagina ei de detalii.'
          : 'Save a real entity from the map or its detail page.',
      actions: const [AppDestination.favorites, AppDestination.map],
    ),
    AppDestination.search => _DestinationContent(
      eyebrow: ro ? 'DESCOPERĂ' : 'DISCOVER',
      icon: Icons.search_rounded,
      title: ro
          ? 'Caută ape și stații reale'
          : 'Search real waters and stations',
      message: ro
          ? 'Căutarea completă este disponibilă în harta interactivă.'
          : 'Full search is available in the interactive map.',
      actions: const [AppDestination.map],
    ),
    AppDestination.premiumRestored => _DestinationContent(
      eyebrow: 'FLUVIAI PREMIUM',
      icon: Icons.restore_rounded,
      title: ro ? 'Nicio restaurare confirmată' : 'No confirmed restoration',
      message: ro
          ? 'Rezultatul apare numai după răspunsul real al repository-ului de billing. Planul nu a fost modificat.'
          : 'A result is shown only after the billing repository responds. The plan was not changed.',
      actions: const [AppDestination.premium, AppDestination.profile],
      premium: true,
    ),
    _ => _DestinationContent(
      eyebrow: 'FLUVIAI',
      icon: AppDestinationRegistry.of(destination).icon,
      title: AppDestinationRegistry.of(destination).title(ro),
      message: ro
          ? 'Destinația este înregistrată și păstrează o stare goală sinceră până la conectarea datelor reale.'
          : 'The destination is registered and keeps a truthful empty state until real data is connected.',
      actions: const [AppDestination.home],
    ),
  };
}

class _DestinationBody extends StatelessWidget {
  const _DestinationBody({
    required this.content,
    required this.entityLabel,
    required this.isRo,
    required this.onOpen,
  });
  final _DestinationContent content;
  final String? entityLabel;
  final bool isRo;
  final ValueChanged<AppDestination>? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluviSurfaceCard(
          accent: content.premium
              ? FluviAICommercialTokens.premium
              : FluviAICommercialTokens.accent,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color:
                      (content.premium
                              ? FluviAICommercialTokens.premium
                              : FluviAICommercialTokens.accent)
                          .withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  content.icon,
                  color: content.premium
                      ? FluviAICommercialTokens.premium
                      : FluviAICommercialTokens.brandFocus,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                content.title,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                content.message,
                style: const TextStyle(
                  color: FluviAICommercialTokens.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          isRo ? 'ACȚIUNI' : 'ACTIONS',
          style: const TextStyle(
            color: FluviAICommercialTokens.brandFocus,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        for (final destination in content.actions) ...[
          _DestinationAction(
            destination: destination,
            isRo: isRo,
            onTap: onOpen == null ? null : () => onOpen!(destination),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DestinationAction extends StatelessWidget {
  const _DestinationAction({
    required this.destination,
    required this.isRo,
    this.onTap,
  });
  final AppDestination destination;
  final bool isRo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final definition = AppDestinationRegistry.of(destination);
    return FluviSurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(definition.icon, color: FluviAICommercialTokens.brandFocus),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              definition.title(isRo),
              style: const TextStyle(fontWeight: FontWeight.w700),
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

class _DestinationContent {
  const _DestinationContent({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    this.premium = false,
  });
  final String eyebrow;
  final IconData icon;
  final String title;
  final String message;
  final List<AppDestination> actions;
  final bool premium;
}
