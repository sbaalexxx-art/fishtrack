import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/context/current_location.dart';
import '../../../core/context/environmental_context.dart';
import '../../../core/context/selected_context.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/theme/fluviai_commercial_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../models/catch.dart';
import '../../../models/fishing_session.dart';
import '../../../repositories/catch_repository.dart';
import '../../../repositories/fishing_journal_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/community_service.dart';
import '../../../services/european_freshwater_species_catalog.dart';
import '../../../services/photo_quality_service.dart';
import '../../../services/saved_items_service.dart';
import 'figma_foundation.dart';

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.isNegative) return 'acum';
  if (difference.inMinutes < 1) return 'acum';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min';
  if (difference.inHours < 24) return '${difference.inHours} h';
  return '${difference.inDays} zile';
}

String _relativeAgo(DateTime value) {
  final relative = _relativeTime(value);
  return relative == 'acum' ? relative : 'acum $relative';
}

Future<void> _showCommunityInfo(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    backgroundColor: FigmaFluviTokens.surface,
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Închide'),
      ),
    ],
  ),
);

String? _reportExpiryLabel(Duration? remaining) {
  if (remaining == null) {
    return null;
  }
  if (remaining.isNegative) {
    return 'EXPIRAT';
  }
  if (remaining.inHours >= 1) {
    return 'EXPIRĂ ÎN ${remaining.inHours}H';
  }
  return 'EXPIRĂ ÎN ${remaining.inMinutes.clamp(1, 59)} MIN';
}

String _categoryLabel(ReportCategory? category) => switch (category) {
  ReportCategory.fishActivity => 'Activitate',
  ReportCategory.waterClarity => 'Apă tulbure',
  ReportCategory.floatingGrass => 'Vegetație',
  ReportCategory.highWater => 'Nivel ridicat',
  ReportCategory.lowWater => 'Nivel scăzut',
  ReportCategory.strongCurrent => 'Curent puternic',
  ReportCategory.noCurrent => 'Fără curent',
  ReportCategory.boats => 'Bărci / plase',
  ReportCategory.poaching => 'Braconaj',
  ReportCategory.theftWarning => 'Avertizare furt',
  ReportCategory.accessBlocked => 'Acces blocat',
  ReportCategory.parkingAvailable => 'Parcare',
  ReportCategory.goodFishing => 'Pescuit bun',
  ReportCategory.poorFishing => 'Pescuit slab',
  ReportCategory.other || null => 'Raport',
};

bool canVerifyCommunityReport(
  CommunityPost post, {
  bool alreadySubmitted = false,
}) =>
    post.type == CommunityPostType.report &&
    post.isActiveReport &&
    !alreadySubmitted;

double _distanceKm(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusKm = 6371.0;
  double radians(double degrees) => degrees * math.pi / 180;
  final latitudeDelta = radians(latitudeB - latitudeA);
  final longitudeDelta = radians(longitudeB - longitudeA);
  final value =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(radians(latitudeA)) *
          math.cos(radians(latitudeB)) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
}

List<CommunityPost> filterCommunityPostsWithinLocalContext(
  Iterable<CommunityPost> posts,
  LocalContentContext? local,
) {
  if (local == null) return const <CommunityPost>[];
  return posts
      .where((post) {
        final latitude = post.latitude;
        final longitude = post.longitude;
        if (latitude == null || longitude == null) return false;
        return _distanceKm(
              local.latitude,
              local.longitude,
              latitude,
              longitude,
            ) <=
            local.radiusKm;
      })
      .toList(growable: false);
}

List<CommunityPost> filterReportsForUser(
  Iterable<CommunityPost> posts,
  String? userId,
) {
  if (userId == null || userId.isEmpty) return const <CommunityPost>[];
  return posts
      .where(
        (post) =>
            post.type == CommunityPostType.report && post.userId == userId,
      )
      .toList(growable: false);
}

Color _categoryColor(ReportCategory? category) => switch (category) {
  ReportCategory.poaching ||
  ReportCategory.theftWarning ||
  ReportCategory.accessBlocked => FigmaFluviTokens.red,
  ReportCategory.highWater ||
  ReportCategory.lowWater ||
  ReportCategory.strongCurrent => FigmaFluviTokens.amber,
  ReportCategory.goodFishing ||
  ReportCategory.fishActivity ||
  ReportCategory.parkingAvailable => FigmaFluviTokens.green,
  _ => FigmaFluviTokens.cyan,
};

class FigmaCommunityPage extends ConsumerStatefulWidget {
  const FigmaCommunityPage({
    super.key,
    this.service = const CommunityService(),
    this.localContext,
  });

  final CommunityService service;
  final LocalContentContext? localContext;

  @override
  ConsumerState<FigmaCommunityPage> createState() => _FigmaCommunityPageState();
}

class _FigmaCommunityPageState extends ConsumerState<FigmaCommunityPage> {
  late Future<List<CommunityPost>> _future;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.service.getFeed();
  }

  Future<void> _refresh() async {
    final next = widget.service.getFeed(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localContext ?? ref.watch(localContentContextProvider);
    final locality = ref.watch(currentLocationProvider).location?.label;
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-community-page'),
      title: 'Comunitate',
      subtitle: locality == null || locality.trim().isEmpty
          ? 'Dovezi locale · rază 100 km'
          : 'Dovezi locale · $locality · rază 100 km',
      subtitleColor: FigmaFluviTokens.cyan,
      padding: EdgeInsets.zero,
      child: FutureBuilder<List<CommunityPost>>(
        future: _future,
        builder: (context, state) {
          final allPosts = filterCommunityPostsWithinLocalContext(
            state.data ?? const <CommunityPost>[],
            local,
          );
          final posts = switch (_filter) {
            1 =>
              allPosts
                  .where((post) => post.type == CommunityPostType.report)
                  .toList(growable: false),
            2 =>
              allPosts
                  .where((post) => post.type == CommunityPostType.catchPost)
                  .toList(growable: false),
            _ => allPosts,
          };
          final recentCutoff = DateTime.now().subtract(
            const Duration(hours: 2),
          );
          final recentCount = allPosts
              .where((post) => post.createdAt.isAfter(recentCutoff))
              .length;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _CommunitySegments(
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 14),
                _CommunityPulseCard(
                  totalCount: allPosts.length,
                  recentCount: recentCount,
                ),
                const SizedBox(height: 16),
                if (state.connectionState == ConnectionState.waiting &&
                    !state.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 90),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (state.hasError)
                  FigmaTruthfulEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Comunitatea nu este disponibilă',
                    message:
                        'Nu s-au încărcat dovezi reale. Reîncearcă atunci când conexiunea revine.',
                    actionLabel: 'Reîncearcă',
                    onAction: _refresh,
                  )
                else if (local == null)
                  FigmaTruthfulEmpty(
                    icon: Icons.location_off_outlined,
                    title: 'Locația locală nu este disponibilă',
                    message:
                        'Comunitatea locală are nevoie de poziția curentă. Nu afișăm un feed global ca înlocuitor.',
                  )
                else if (posts.isEmpty)
                  FigmaTruthfulEmpty(
                    icon: Icons.groups_2_outlined,
                    title: 'Nicio dovadă locală disponibilă',
                    message:
                        'Feedul rămâne gol; nu afișăm capturi sau rapoarte demonstrative.',
                    actionLabel: 'Adaugă raport',
                    onAction: () =>
                        AppNavigator.open(context, AppDestination.addReport),
                  )
                else
                  _CommunityEvidenceGrid(posts: posts),
                const SizedBox(height: 16),
                _CommunityContributeCard(
                  onTap: () =>
                      AppNavigator.open(context, AppDestination.addReport),
                ),
                const SizedBox(height: 14),
                const _CommunityPrivacyCard(),
                const SizedBox(height: 86),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommunitySegments extends StatelessWidget {
  const _CommunitySegments({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final labels = const ['Puls local', 'Rapoarte', 'Capturi'];
    Widget item(int index, {double? width}) => SizedBox(
      width: width,
      child: _CommunitySegment(
        label: labels[index],
        selected: selected == index,
        onTap: () => onSelected(index),
      ),
    );

    return Container(
      height: largeText ? 50 : 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF091318),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FigmaFluviTokens.border),
      ),
      child: largeText
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  item(0, width: 128),
                  item(1, width: 112),
                  item(2, width: 112),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: item(0)),
                Expanded(child: item(1)),
                Expanded(child: item(2)),
              ],
            ),
    );
  }
}

class _CommunitySegment extends StatelessWidget {
  const _CommunitySegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF113B3A) : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected
                ? FigmaFluviTokens.cyan
                : FigmaFluviTokens.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _CommunityPulseCard extends StatelessWidget {
  const _CommunityPulseCard({
    required this.totalCount,
    required this.recentCount,
  });

  final int totalCount;
  final int recentCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF11111F),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: FigmaFluviTokens.cyan),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ULTIMELE 2 ORE · $recentCount ACTUALIZĂRI',
          style: const TextStyle(
            color: FigmaFluviTokens.cyan,
            fontFamily: FluviAICommercialTokens.monoFontFamily,
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          totalCount == 0 ? 'Puls local fără date' : 'Puls local actualizat',
          style: const TextStyle(
            color: FigmaFluviTokens.white,
            fontSize: 19,
            height: 1.15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$totalCount dovezi încărcate din sursele comunității',
          style: const TextStyle(
            color: FigmaFluviTokens.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _CommunityEvidenceGrid extends StatelessWidget {
  const _CommunityEvidenceGrid({required this.posts});

  final List<CommunityPost> posts;

  @override
  Widget build(BuildContext context) {
    final featured = posts.take(3).toList(growable: false);
    return Column(
      children: [
        if (featured.isNotEmpty)
          _CommunityEvidenceCard(post: featured.first, featured: true),
        for (final post in featured.skip(1)) ...[
          const SizedBox(height: 12),
          _CommunityEvidenceCard(post: post),
        ],
      ],
    );
  }
}

class _CommunityEvidenceCard extends StatelessWidget {
  const _CommunityEvidenceCard({required this.post, this.featured = false});

  final CommunityPost post;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final isReport = post.type == CommunityPostType.report;
    final accent = isReport
        ? _categoryColor(post.reportCategory)
        : FigmaFluviTokens.green;
    final title = isReport ? _categoryLabel(post.reportCategory) : post.title;
    final hasApproxLocation = post.latitude != null && post.longitude != null;
    final imageUrl = post.imageUrl?.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF0C151A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: FigmaFluviTokens.border),
        ),
        child: InkWell(
          onTap: () => AppNavigator.open(
            context,
            isReport ? AppDestination.reportDetail : AppDestination.catchDetail,
            arguments: post,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                SizedBox(
                  height: featured ? 150 : 110,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _CommunityEvidencePlaceholder(
                      accent: accent,
                      icon: isReport
                          ? Icons.outlined_flag_rounded
                          : Icons.set_meal_rounded,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: featured ? 118 : 92,
                  child: _CommunityEvidencePlaceholder(
                    accent: accent,
                    icon: isReport
                        ? Icons.outlined_flag_rounded
                        : Icons.set_meal_rounded,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isReport ? 'RAPORT REAL' : 'CAPTURĂ REALĂ',
                      style: TextStyle(
                        color: accent,
                        fontFamily: FluviAICommercialTokens.monoFontFamily,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relativeAgo(post.createdAt),
                      style: const TextStyle(
                        color: FigmaFluviTokens.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                    if (hasApproxLocation) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Locație disponibilă conform setării raportului',
                        style: TextStyle(
                          color: FigmaFluviTokens.cyan,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                    if (post.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        post.body.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 9.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityEvidencePlaceholder extends StatelessWidget {
  const _CommunityEvidencePlaceholder({
    required this.accent,
    required this.icon,
  });

  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF16353F),
    child: Center(child: Icon(icon, color: accent, size: 32)),
  );
}

class _CommunityContributeCard extends StatelessWidget {
  const _CommunityContributeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1C1C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FigmaFluviTokens.cyan),
      ),
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trimite o observație utilă',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Foto, starea apei, acces sau activitate',
                      style: TextStyle(
                        color: FigmaFluviTokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_rounded, color: FigmaFluviTokens.cyan, size: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CommunityPrivacyCard extends StatelessWidget {
  const _CommunityPrivacyCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF101C22),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: FigmaFluviTokens.border),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONFIDENȚIALITATE',
          style: TextStyle(
            color: FigmaFluviTokens.cyan,
            fontFamily: FluviAICommercialTokens.monoFontFamily,
            fontSize: 8,
          ),
        ),
        SizedBox(height: 7),
        Text(
          'Exactă / aproximativă / ascunsă se alege înainte de publicare.',
          style: TextStyle(
            color: FigmaFluviTokens.textSecondary,
            fontSize: 10,
            height: 1.25,
          ),
        ),
      ],
    ),
  );
}

class FigmaReportDetailsPage extends StatefulWidget {
  const FigmaReportDetailsPage({
    super.key,
    this.post,
    this.service = const CommunityService(),
  });

  final CommunityPost? post;
  final CommunityService service;

  @override
  State<FigmaReportDetailsPage> createState() => _FigmaReportDetailsPageState();
}

class _FigmaReportDetailsPageState extends State<FigmaReportDetailsPage> {
  bool _working = false;
  String? _result;
  ReportVerification? _submittedVerification;
  bool _savingReport = false;

  Future<void> _verify(ReportVerification verification) async {
    final post = widget.post;
    if (post == null ||
        _working ||
        !canVerifyCommunityReport(
          post,
          alreadySubmitted: _submittedVerification != null,
        )) {
      return;
    }
    setState(() {
      _working = true;
      _result = null;
    });
    try {
      await widget.service.verifyReport(post.id, verification);
      if (!mounted) return;
      setState(() {
        _submittedVerification = verification;
        _result = verification == ReportVerification.stillValid
            ? 'Confirmarea a fost trimisă.'
            : 'Marcajul „nu mai este valabil” a fost trimis.';
      });
    } on CommunityException catch (error) {
      if (mounted) setState(() => _result = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveReport() async {
    final post = widget.post;
    if (post == null || _savingReport) return;
    setState(() => _savingReport = true);
    try {
      await const SavedItemsService().save(
        type: 'report',
        referenceId: post.id,
        title: post.title,
        subtitle: post.body.trim().isEmpty ? null : post.body.trim(),
        latitude: post.latitude,
        longitude: post.longitude,
        metadata: <String, Object?>{
          'report_category': post.reportCategory?.name,
          'created_at': post.createdAt.toUtc().toIso8601String(),
          if (post.expiresAt != null)
            'expires_at': post.expiresAt!.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raport salvat în Favorite.')),
      );
    } on SavedItemsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _savingReport = false);
    }
  }

  Future<void> _openReportOptions() async {
    final post = widget.post;
    if (post == null) return;
    final abuse = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: FigmaFluviTokens.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Opțiuni raport',
                style: TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              FigmaPrimaryButton(
                label: 'Raportează conținutul',
                icon: Icons.report_gmailerrorred_rounded,
                secondary: true,
                destructive: true,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('Închide'),
              ),
            ],
          ),
        ),
      ),
    );
    if (abuse != true || !mounted) return;
    setState(() {
      _working = true;
      _result = null;
    });
    try {
      await widget.service.reportAbuse(post.id, ReportAbuseReason.other);
      if (mounted) setState(() => _result = 'Sesizarea a fost trimisă.');
    } on CommunityException catch (error) {
      if (mounted) setState(() => _result = error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final accent = _categoryColor(post?.reportCategory);
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-report-details'),
      title: 'Detalii raport',
      eyebrow: 'COMUNITATE',
      action: FigmaRoundButton(
        icon: Icons.more_horiz_rounded,
        tooltip: 'Mai multe',
        onPressed: post == null ? null : _openReportOptions,
      ),
      child: post == null
          ? const FigmaTruthfulEmpty(
              icon: Icons.campaign_outlined,
              title: 'Raport indisponibil',
              message: 'Deschide un raport real din Comunitate sau din arhivă.',
            )
          : ListView(
              children: [
                FigmaSurface(
                  accent: accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FigmaPill(
                            label: _categoryLabel(post.reportCategory),
                            color: accent,
                            active: true,
                          ),
                          const Spacer(),
                          FigmaStatusDot(
                            label: post.isActiveReport ? 'ACTIV' : 'EXPIRAT',
                            color: post.isActiveReport
                                ? FigmaFluviTokens.green
                                : FigmaFluviTokens.textMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        post.title,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 21,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (post.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(post.body, style: figmaBody(size: 12)),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${post.authorName} · ${_relativeTime(post.createdAt)}',
                              style: figmaBody(size: 10),
                            ),
                          ),
                          Text(
                            '${post.stillValidCount} confirmări',
                            style: figmaBody(
                              color: FigmaFluviTokens.green,
                              size: 10,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (post.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        post.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: FigmaFluviTokens.surface,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: FigmaFluviTokens.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FigmaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Locație și încredere',
                        style: TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: FigmaFluviTokens.cyan,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              post.latitude == null || post.longitude == null
                                  ? 'Locație indisponibilă'
                                  : 'Locație aproximativă · poziția exactă este protejată',
                              style: figmaBody(size: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: FigmaFluviTokens.green,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nivel de încredere: ${post.authorTrustLevel.name}',
                              style: figmaBody(size: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FigmaPrimaryButton(
                  key: const ValueKey('figma-report-save-action'),
                  label: 'Salvează în Favorite',
                  icon: Icons.bookmark_add_outlined,
                  secondary: true,
                  onPressed: _savingReport ? null : _saveReport,
                ),
                const SizedBox(height: 12),
                if (!post.isActiveReport)
                  const FigmaTruthfulEmpty(
                    icon: Icons.timer_off_outlined,
                    title: 'Raport expirat',
                    message:
                        'Acest raport nu mai acceptă confirmări de valabilitate.',
                  )
                else if (_submittedVerification != null)
                  FigmaSurface(
                    accent: FigmaFluviTokens.green,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: FigmaFluviTokens.green,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _submittedVerification ==
                                    ReportVerification.stillValid
                                ? 'Ai confirmat că raportul este încă valabil.'
                                : 'Ai marcat raportul ca nemaifiind valabil.',
                            style: figmaBody(size: 11),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FigmaPrimaryButton(
                          label: 'Confirmă',
                          icon: Icons.verified_rounded,
                          onPressed: _working
                              ? null
                              : () => _verify(ReportVerification.stillValid),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FigmaPrimaryButton(
                          label: 'Nu mai e valabil',
                          secondary: true,
                          onPressed: _working
                              ? null
                              : () => _verify(ReportVerification.noLongerValid),
                        ),
                      ),
                    ],
                  ),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _result!,
                    textAlign: TextAlign.center,
                    style: figmaBody(size: 11),
                  ),
                ],
              ],
            ),
    );
  }
}

class FigmaAddReportPage extends StatefulWidget {
  const FigmaAddReportPage({
    super.key,
    this.service = const CommunityService(),
    this.authService = const AuthService(),
    this.initialCategory,
  });

  final CommunityService service;
  final AuthService authService;
  final ReportCategory? initialCategory;

  @override
  State<FigmaAddReportPage> createState() => _FigmaAddReportPageState();
}

class _FigmaAddReportPageState extends State<FigmaAddReportPage> {
  final _description = TextEditingController();
  final _picker = ImagePicker();
  late ReportCategory _category;
  bool _exact = true;
  File? _photo;
  bool _saving = false;
  bool _truthConfirmed = false;
  bool _published = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? ReportCategory.fishActivity;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (image != null && mounted) setState(() => _photo = File(image.path));
  }

  Future<void> _publish() async {
    if (_saving || _published) return;
    if (!widget.authService.isAuthenticated) {
      setState(() {
        _message =
            'Autentifică-te din Cont și securitate înainte de publicare.';
      });
      return;
    }
    if (!_truthConfirmed) {
      setState(() {
        _message = 'Confirmă că informația este corectă înainte de publicare.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final reportId = await widget.service.createReport(
        category: _category,
        text: _description.text,
        cameraPhoto: _photo,
        useExactLocation: _exact,
      );
      if (!mounted) return;
      try {
        final selected = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(selectedContextProvider);
        final entityType = selected?.reservoirId != null
            ? 'reservoir'
            : selected?.damId != null
            ? 'dam'
            : selected?.stationId != null
            ? 'station'
            : selected?.riverKey != null
            ? 'river'
            : selected?.waterId != null
            ? 'water_body'
            : null;
        final entityId =
            selected?.reservoirId ??
            selected?.damId ??
            selected?.stationId ??
            selected?.riverKey ??
            selected?.waterId;
        if (entityType != null && entityId != null) {
          await widget.service.attachReportWaterContext(
            reportId: reportId,
            entityType: entityType,
            entityId: entityId,
          );
        }
      } on Exception {
        // Reportul rămâne publicat; triggerul GPS este fallback-ul sigur.
      }
      if (!mounted) return;
      setState(() {
        _published = true;
        _message = 'Raport publicat cu succes. ID: $reportId';
      });
    } on CommunityException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = <ReportCategory>[
      ReportCategory.waterClarity,
      ReportCategory.highWater,
      ReportCategory.lowWater,
      ReportCategory.strongCurrent,
      ReportCategory.noCurrent,
      ReportCategory.accessBlocked,
      ReportCategory.boats,
      ReportCategory.fishActivity,
      ReportCategory.poaching,
      ReportCategory.other,
    ];
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-add-report'),
      title: 'Raport nou',
      eyebrow: widget.authService.isAuthenticated
          ? 'RAPORT COMUNITATE'
          : 'AUTENTIFICARE NECESARĂ',
      action: FigmaRoundButton(
        icon: Icons.close_rounded,
        tooltip: 'Închide',
        onPressed: () => Navigator.maybePop(context),
      ),
      child: ListView(
        children: [
          const FigmaSectionLabel('Categorie'),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                return FigmaPill(
                  label: _categoryLabel(category),
                  color: _categoryColor(category),
                  active: _category == category,
                  onTap: () => setState(() => _category = category),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _description,
            maxLength: 300,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Descrie situația…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          FigmaSurface(
            accent: FigmaFluviTokens.cyan,
            onTap: _takePhoto,
            child: Row(
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  color: FigmaFluviTokens.cyan,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _photo == null
                        ? 'Fotografie (opțional)'
                        : 'Fotografie pregătită',
                    style: figmaBody(
                      color: FigmaFluviTokens.cyan,
                      size: 12,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_photo != null)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: FigmaFluviTokens.green,
                    size: 18,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const ValueKey('add-report-truth-confirmation'),
            value: _truthConfirmed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Confirm că informația este corectă și observată direct.',
            ),
            onChanged: _saving || _published
                ? null
                : (value) => setState(() => _truthConfirmed = value ?? false),
          ),
          FigmaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: FigmaFluviTokens.cyan,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Locația curentă',
                      style: TextStyle(
                        color: FigmaFluviTokens.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Exactă')),
                    ButtonSegment(value: false, label: Text('Aproximativă')),
                  ],
                  selected: {_exact},
                  onSelectionChanged: (selection) =>
                      setState(() => _exact = selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FigmaSurface(
            accent: FigmaFluviTokens.amber,
            child: Text(
              'Durata raportului este stabilită după categorie și confirmări. Poți proteja poziția exactă înainte de publicare.',
              style: figmaBody(size: 10),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: figmaBody(
                color: _published
                    ? FigmaFluviTokens.green
                    : FigmaFluviTokens.red,
                size: 11,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FigmaPrimaryButton(
            label: _published
                ? 'Închide'
                : _saving
                ? 'Se publică…'
                : 'Publică raportul',
            icon: Icons.outlined_flag_rounded,
            onPressed: _saving
                ? null
                : _published
                ? () => Navigator.of(context).pop(true)
                : _publish,
          ),
        ],
      ),
    );
  }
}

class FigmaCatchesPage extends StatefulWidget {
  const FigmaCatchesPage({
    super.key,
    this.repository = const CatchRepository(),
  });

  final CatchRepository repository;

  @override
  State<FigmaCatchesPage> createState() => _FigmaCatchesPageState();
}

class _FigmaCatchesPageState extends State<FigmaCatchesPage> {
  late Future<List<Catch>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getMyCatches();
  }

  Future<void> _refresh() async {
    final next = widget.repository.getMyCatches();
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    try {
      await next;
    } on Exception {
      // The state below reports the real error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-catches-page'),
      title: 'Capturile mele',
      eyebrow: 'JURNAL VIZUAL',
      action: FigmaRoundButton(
        icon: Icons.add_a_photo_outlined,
        tooltip: 'Adaugă captură',
        onPressed: () => AppNavigator.open(context, AppDestination.addCatch),
      ),
      padding: EdgeInsets.zero,
      child: FutureBuilder<List<Catch>>(
        future: _future,
        builder: (context, state) {
          final catches = state.data ?? const <Catch>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FigmaMetric(
                        value: catches.length.toString(),
                        label: 'capturi',
                      ),
                    ),
                    Expanded(
                      child: FigmaMetric(
                        value: catches
                            .where((item) => item.weight != null)
                            .fold<double>(0, (sum, item) => sum + item.weight!)
                            .toStringAsFixed(1),
                        label: 'kg total',
                        alignment: CrossAxisAlignment.center,
                      ),
                    ),
                    Expanded(
                      child: FigmaMetric(
                        value: catches
                            .map((item) => item.species)
                            .toSet()
                            .length
                            .toString(),
                        label: 'specii',
                        alignment: CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.connectionState == ConnectionState.waiting &&
                    !state.hasData)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (state.hasError)
                  FigmaTruthfulEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Capturile nu au putut fi încărcate',
                    message: 'Verifică sesiunea și conexiunea.',
                    actionLabel: 'Reîncearcă',
                    onAction: _refresh,
                  )
                else if (catches.isEmpty)
                  FigmaTruthfulEmpty(
                    icon: Icons.photo_camera_outlined,
                    title: 'Nicio captură salvată',
                    message:
                        'Galeria rămâne goală; nu afișăm capturi demonstrative.',
                    actionLabel: 'Adaugă captură',
                    onAction: () =>
                        AppNavigator.open(context, AppDestination.addCatch),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.06,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: catches.length,
                    itemBuilder: (context, index) =>
                        _CatchTile(catchItem: catches[index]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CatchTile extends StatelessWidget {
  const _CatchTile({required this.catchItem});

  final Catch catchItem;

  @override
  Widget build(BuildContext context) {
    return FigmaSurface(
      radius: 18,
      padding: const EdgeInsets.all(12),
      onTap: () => AppNavigator.open(
        context,
        AppDestination.catchDetail,
        arguments: catchItem,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B3446), Color(0xFF081321)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.set_meal_rounded,
                color: FigmaFluviTokens.cyan,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            catchItem.species,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: FigmaFluviTokens.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            [
                  if (catchItem.weight != null)
                    '${catchItem.weight!.toStringAsFixed(1)} kg',
                  if (catchItem.length != null)
                    '${catchItem.length!.toStringAsFixed(0)} cm',
                ].join(' · ').isEmpty
                ? 'Fără măsurători'
                : [
                    if (catchItem.weight != null)
                      '${catchItem.weight!.toStringAsFixed(1)} kg',
                    if (catchItem.length != null)
                      '${catchItem.length!.toStringAsFixed(0)} cm',
                  ].join(' · '),
            style: figmaBody(size: 10),
          ),
        ],
      ),
    );
  }
}

class FigmaCatchDetailsPage extends StatelessWidget {
  const FigmaCatchDetailsPage({
    super.key,
    this.catchItem,
    this.communityCatch,
    this.label,
  });

  final Catch? catchItem;
  final CommunityPost? communityCatch;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final item = catchItem;
    final post = communityCatch;
    final hasRealCatch = item != null || post != null;
    final species = item?.species ?? post?.title;
    final weight = item?.weight ?? post?.weight;
    final length = item?.length ?? post?.length;
    final date = item?.date ?? post?.createdAt;
    final imageUrl = post?.imageUrl?.trim();
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-catch-details'),
      title: 'Detalii captură',
      eyebrow: 'CAPTURĂ SALVATĂ',
      action: FigmaRoundButton(
        icon: Icons.ios_share_rounded,
        tooltip: 'Distribuie',
        onPressed: !hasRealCatch
            ? null
            : () => _showCommunityInfo(
                context,
                title: 'Distribuie captura',
                message:
                    'Distribuirea nu este conectată în această versiune. Nu s-a trimis nimic.',
              ),
      ),
      child: !hasRealCatch
          ? FigmaTruthfulEmpty(
              icon: Icons.set_meal_rounded,
              title: label ?? 'Captură indisponibilă',
              message: 'Deschide o captură reală din lista ta pentru detalii.',
            )
          : ListView(
              children: [
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0B3A4B), Color(0xFF07131F)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: FigmaFluviTokens.cyan.withValues(alpha: .16),
                    ),
                  ),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: FigmaFluviTokens.textMuted,
                                size: 44,
                              ),
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.set_meal_rounded,
                            color: FigmaFluviTokens.cyan,
                            size: 66,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                FigmaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        species!,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FigmaMetric(
                              value: weight == null
                                  ? '—'
                                  : '${weight.toStringAsFixed(1)} kg',
                              label: 'greutate',
                            ),
                          ),
                          Expanded(
                            child: FigmaMetric(
                              value: length == null
                                  ? '—'
                                  : '${length.toStringAsFixed(0)} cm',
                              label: 'lungime',
                              alignment: CrossAxisAlignment.center,
                            ),
                          ),
                          Expanded(
                            child: FigmaMetric(
                              value: '${date!.day}.${date.month}.${date.year}',
                              label: 'data',
                              alignment: CrossAxisAlignment.end,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (post != null && post.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FigmaSurface(
                    child: Text(post.body, style: figmaBody(size: 12)),
                  ),
                ],
                const SizedBox(height: 12),
                FigmaPrimaryButton(
                  key: const ValueKey('figma-catch-save-action'),
                  label: 'Salvează în Favorite',
                  icon: Icons.bookmark_add_outlined,
                  secondary: true,
                  onPressed: () async {
                    final referenceId = item?.id ?? post?.id;
                    if (referenceId == null) return;
                    try {
                      await const SavedItemsService().save(
                        type: 'catch',
                        referenceId: referenceId,
                        title: species,
                        subtitle: post?.body.trim().isEmpty == false
                            ? post!.body.trim()
                            : null,
                        latitude: post?.latitude,
                        longitude: post?.longitude,
                        metadata: <String, Object?>{
                          'weight_kg': ?weight,
                          'length_cm': ?length,
                          'created_at': date.toUtc().toIso8601String(),
                          if (post?.imageUrl != null)
                            'image_url': post!.imageUrl,
                        },
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Captură salvată în Favorite.'),
                        ),
                      );
                    } on SavedItemsException catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.message)));
                    }
                  },
                ),
                const SizedBox(height: 12),
                const FigmaTruthfulEmpty(
                  icon: Icons.location_off_outlined,
                  title: 'Context istoric indisponibil',
                  message:
                      'Snapshoturile Water și Weather apar numai când au fost salvate odată cu captura.',
                ),
              ],
            ),
    );
  }
}

class FigmaAddCatchPage extends StatefulWidget {
  const FigmaAddCatchPage({
    super.key,
    this.repository = const CatchRepository(),
  });

  final CatchRepository repository;

  @override
  State<FigmaAddCatchPage> createState() => _FigmaAddCatchPageState();
}

class _FigmaAddCatchPageState extends State<FigmaAddCatchPage> {
  final _picker = ImagePicker();
  final _species = TextEditingController();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _notes = TextEditingController();
  File? _photo;
  final _photoQualityService = const PhotoQualityService();
  PhotoQualityResult? _photoQuality;
  bool _analyzingPhoto = false;
  bool _saving = false;
  String? _message;
  String _unit = 'kg';

  @override
  void dispose() {
    _species.dispose();
    _weight.dispose();
    _length.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 86,
      maxWidth: 1800,
    );
    if (image == null || !mounted) return;

    setState(() {
      _photo = File(image.path);
      _photoQuality = null;
      _analyzingPhoto = true;
      _message = null;
    });
    try {
      final quality = await _photoQualityService.analyzeFile(image.path);
      if (!mounted || _photo?.path != image.path) return;
      setState(() => _photoQuality = quality);
    } on Exception {
      // Quality analysis is advisory. A real catch must remain submittable
      // when local image decoding/analysis fails.
    } finally {
      if (mounted && _photo?.path == image.path) {
        setState(() => _analyzingPhoto = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_photo == null || _species.text.trim().isEmpty) {
      setState(() => _message = 'Fotografia și specia sunt obligatorii.');
      return;
    }
    final rawWeight = double.tryParse(_weight.text.replaceAll(',', '.'));
    final weightKg = rawWeight == null
        ? null
        : (_unit == 'gr' ? rawWeight / 1000 : rawWeight);
    final lengthCm = double.tryParse(_length.text.replaceAll(',', '.'));
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      SelectedContext? selected;
      try {
        selected = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(selectedContextProvider);
      } on StateError {
        selected = null;
      }
      final waterType = selected?.reservoirId != null
          ? 'reservoir'
          : selected?.damId != null
          ? 'dam'
          : selected?.riverName != null || selected?.waterName != null
          ? 'river'
          : 'unknown';
      final languageCode = Localizations.localeOf(context).languageCode;
      final taxonomy = EuropeanFreshwaterSpeciesCatalog.match(
        _species.text,
        languageCode: languageCode,
      );
      await widget.repository.createCatch(
        imagePath: _photo!.path,
        species: taxonomy?.displayName ?? _species.text.trim(),
        speciesScientific: taxonomy?.scientificName,
        speciesSource: taxonomy == null ? 'manual' : 'manual_taxonomy',
        speciesUserConfirmed: true,
        weightKg: weightKg,
        lengthCm: lengthCm,
        notes: _notes.text,
        // The current design keeps catch location hidden. We still preserve
        // the selected canonical water/station relationship so the catch can
        // participate in My Catches, Water and Fluvi without leaking GPS.
        latitude: null,
        longitude: null,
        placeName: selected?.primaryLabel,
        waterType: waterType,
        locationPrivacy: 'hidden',
        stationId: selected?.stationId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CatchSubmissionException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SelectedContext? selected;
    try {
      selected = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(selectedContextProvider);
    } on StateError {
      selected = null;
    }
    final selectedLabel = selected?.primaryLabel;
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-add-catch'),
      title: 'Adaugă captură',
      subtitle: 'Camera live · fotografie obligatorie',
      action: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF120E1D),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: FigmaFluviTokens.cyan),
        ),
        child: const Text(
          'CAPTURĂ',
          style: TextStyle(
            color: FigmaFluviTokens.cyan,
            fontFamily: FluviAICommercialTokens.monoFontFamily,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
        children: [
          Container(
            height: 126,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF061C22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: FigmaFluviTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Captura se adaugă în contextul curent',
                        style: TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _CatchActualPill(),
                  ],
                ),
                Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: FigmaFluviTokens.cyan,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedLabel == null
                            ? 'Locația publică rămâne ascunsă. Selectează o apă pentru asociere.'
                            : '$selectedLabel · locația publică rămâne ascunsă',
                        style: const TextStyle(
                          color: FigmaFluviTokens.textSecondary,
                          fontSize: 10,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1115),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: FigmaFluviTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: SizedBox(
                    width: 24,
                    child: Divider(
                      color: FigmaFluviTokens.textSecondary,
                      thickness: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Fotografiază captura',
                  style: TextStyle(
                    color: FigmaFluviTokens.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  key: const ValueKey('figma-add-catch-camera'),
                  onTap: _capture,
                  child: Container(
                    height: 166,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A242B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: FigmaFluviTokens.border),
                      image: _photo == null
                          ? null
                          : DecorationImage(
                              image: FileImage(_photo!),
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: _photo == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: FigmaFluviTokens.cyan,
                                child: Icon(
                                  Icons.photo_camera_outlined,
                                  color: Color(0xFF05080A),
                                  size: 25,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'APASĂ PENTRU FOTOGRAFIE',
                                style: TextStyle(
                                  color: FigmaFluviTokens.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xCC071015),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: FigmaFluviTokens.cyan,
                                  ),
                                ),
                                child: const Text(
                                  'Refă fotografia',
                                  style: TextStyle(
                                    color: FigmaFluviTokens.cyan,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0E17),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FigmaFluviTokens.cyan),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SPECIE · CONFIRMARE NECESARĂ',
                        style: TextStyle(
                          color: FigmaFluviTokens.cyan,
                          fontFamily: FluviAICommercialTokens.monoFontFamily,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('figma-add-catch-species'),
                        controller: _species,
                        style: const TextStyle(
                          color: FigmaFluviTokens.white,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Introdu specia observată',
                          border: InputBorder.none,
                        ),
                      ),
                      const Text(
                        'Specia este confirmată de pescar. FluviAI normalizează taxonomia local; modelul ML va adăuga sugestii numai după validare.',
                        style: TextStyle(
                          color: FigmaFluviTokens.textMuted,
                          fontSize: 9,
                          height: 1.25,
                        ),
                      ),
                      if (_photo != null) ...[
                        const SizedBox(height: 10),
                        _FigmaVisionQualityStatus(
                          quality: _photoQuality,
                          analyzing: _analyzingPhoto,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _CatchMeasurementCard(
                  weightController: _weight,
                  lengthController: _length,
                  unit: _unit,
                  onUnitChanged: (value) => setState(() => _unit = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(color: FigmaFluviTokens.white),
                  decoration: const InputDecoration(
                    labelText: 'Note (opțional)',
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: figmaBody(color: FigmaFluviTokens.red, size: 11),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('figma-add-catch-save'),
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: FigmaFluviTokens.cyan,
                      foregroundColor: const Color(0xFF05080A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _saving ? 'Se salvează…' : 'Salvează captura',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 86),
        ],
      ),
    );
  }
}

class _CatchActualPill extends StatelessWidget {
  const _CatchActualPill();

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF061917),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: FigmaFluviTokens.cyan),
    ),
    child: const Text(
      'ACTUAL',
      style: TextStyle(
        color: FigmaFluviTokens.cyan,
        fontFamily: FluviAICommercialTokens.monoFontFamily,
        fontSize: 9,
      ),
    ),
  );
}

class _FigmaVisionQualityStatus extends StatelessWidget {
  const _FigmaVisionQualityStatus({
    required this.quality,
    required this.analyzing,
  });

  final PhotoQualityResult? quality;
  final bool analyzing;

  @override
  Widget build(BuildContext context) {
    final current = quality;
    final good = current?.isGood == true;
    final color = analyzing
        ? FigmaFluviTokens.cyan
        : good
        ? FigmaFluviTokens.green
        : FigmaFluviTokens.amber;
    final label = analyzing
        ? 'Fluvi Vision verifică fotografia local…'
        : current == null
        ? 'Analiza locală nu este disponibilă; confirmarea manuală rămâne activă.'
        : good
        ? 'Fotografia este potrivită pentru recunoaștere.'
        : 'Fotografia poate reduce precizia recunoașterii.';

    return Container(
      key: const ValueKey('figma-catch-vision-quality'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analyzing)
            SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
            )
          else
            Icon(
              good ? Icons.verified_outlined : Icons.auto_awesome_outlined,
              color: color,
              size: 18,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (current != null && !analyzing) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${current.width}×${current.height} · lumină ${current.brightness.round()} · claritate ${current.sharpness.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: FigmaFluviTokens.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatchMeasurementCard extends StatelessWidget {
  const _CatchMeasurementCard({
    required this.weightController,
    required this.lengthController,
    required this.unit,
    required this.onUnitChanged,
  });

  final TextEditingController weightController;
  final TextEditingController lengthController;
  final String unit;
  final ValueChanged<String> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final weightField = TextField(
      controller: weightController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: FigmaFluviTokens.white),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Greutate',
        suffixText: unit,
      ),
    );
    final unitSelector = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'gr', label: Text('gr')),
        ButtonSegment(value: 'kg', label: Text('kg')),
      ],
      selected: {unit},
      onSelectionChanged: (values) => onUnitChanged(values.first),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E161A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FigmaFluviTokens.border),
      ),
      child: Column(
        children: [
          if (largeText) ...[
            weightField,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: unitSelector),
          ] else
            Row(
              children: [
                Expanded(child: weightField),
                const SizedBox(width: 10),
                unitSelector,
              ],
            ),
          const SizedBox(height: 10),
          TextField(
            controller: lengthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: FigmaFluviTokens.white),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Lungime',
              suffixText: 'cm',
            ),
          ),
        ],
      ),
    );
  }
}

class FigmaJournalPage extends ConsumerStatefulWidget {
  const FigmaJournalPage({
    super.key,
    this.sessionLabel,
    this.repository = const FishingJournalRepository(),
  });

  final String? sessionLabel;
  final FishingJournalRepository repository;

  @override
  ConsumerState<FigmaJournalPage> createState() => _FigmaJournalPageState();
}

class _FigmaJournalPageState extends ConsumerState<FigmaJournalPage> {
  late Future<List<FishingSession>> _sessions;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _sessions = widget.repository.getSessions();
  }

  Future<void> _refresh() async {
    final next = widget.repository.getSessions();
    if (mounted) setState(() => _sessions = next);
    try {
      await next;
    } on FishingJournalException {
      // FutureBuilder renders the error state.
    }
  }

  Future<void> _startSession() async {
    if (_working) return;
    final titleController = TextEditingController();
    final notesController = TextEditingController();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FigmaFluviTokens.surface,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Începe partidă',
              style: TextStyle(
                color: FigmaFluviTokens.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Titlu opțional'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notițe inițiale'),
            ),
            const SizedBox(height: 14),
            FigmaPrimaryButton(
              label: 'Pornește partida',
              icon: Icons.play_arrow_rounded,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) {
      titleController.dispose();
      notesController.dispose();
      return;
    }

    SelectedContext? selected;
    try {
      selected = ref.read(selectedContextProvider);
    } on StateError {
      selected = null;
    }
    setState(() => _working = true);
    try {
      await widget.repository.startSession(
        context: selected,
        title: titleController.text,
        notes: notesController.text,
      );
      await _refresh();
    } on FishingJournalException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      titleController.dispose();
      notesController.dispose();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _endSession(FishingSession session) async {
    if (_working) return;
    final notesController = TextEditingController(text: session.notes ?? '');
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FigmaFluviTokens.surface,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Încheie partida',
              style: TextStyle(
                color: FigmaFluviTokens.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notesController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Notițe finale'),
            ),
            const SizedBox(height: 14),
            FigmaPrimaryButton(
              label: 'Încheie partida',
              icon: Icons.stop_circle_outlined,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) {
      notesController.dispose();
      return;
    }
    setState(() => _working = true);
    try {
      await widget.repository.endSession(
        session.id,
        notes: notesController.text,
      );
      await _refresh();
    } on FishingJournalException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      notesController.dispose();
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRo =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    String copy(String ro, String en) => isRo ? ro : en;

    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-journal-page'),
      title:
          widget.sessionLabel ?? copy('Jurnal de pescuit', 'Fishing journal'),
      eyebrow: copy('DATE PERSONALE', 'PERSONAL RECORDS'),
      child: FutureBuilder<List<FishingSession>>(
        future: _sessions,
        builder: (context, state) {
          if (state.connectionState == ConnectionState.waiting &&
              !state.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (state.hasError) {
            return FigmaTruthfulEmpty(
              icon: Icons.cloud_off_rounded,
              title: copy('Jurnal indisponibil', 'Journal unavailable'),
              message: copy(
                'Verifică autentificarea și conexiunea.',
                'Check authentication and connection.',
              ),
              actionLabel: copy('Reîncearcă', 'Retry'),
              onAction: _refresh,
            );
          }
          final sessions = state.data ?? const <FishingSession>[];
          FishingSession? active;
          for (final session in sessions) {
            if (session.isOpen) {
              active = session;
              break;
            }
          }
          final history = sessions
              .where((session) => !session.isOpen)
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (active != null)
                  FigmaSurface(
                    accent: FigmaFluviTokens.green,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FigmaStatusDot(
                          label: 'PARTIDĂ ACTIVĂ',
                          color: FigmaFluviTokens.green,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          active.title?.trim().isNotEmpty == true
                              ? active.title!
                              : (active.placeName ??
                                    copy(
                                      'Partidă de pescuit',
                                      'Fishing session',
                                    )),
                          style: figmaTitle(size: 20),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          active.placeName ??
                              copy(
                                'Context nespecificat',
                                'No location context',
                              ),
                          style: figmaBody(size: 11),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _journalDuration(active.duration, isRo: isRo),
                          style: figmaBody(
                            color: FigmaFluviTokens.cyan,
                            size: 12,
                            weight: FontWeight.w800,
                          ),
                        ),
                        if (active.notes?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Text(active.notes!, style: figmaBody(size: 11)),
                        ],
                        const SizedBox(height: 14),
                        FigmaPrimaryButton(
                          label: copy('Încheie partida', 'End session'),
                          icon: Icons.stop_circle_outlined,
                          secondary: true,
                          onPressed: _working
                              ? null
                              : () => _endSession(active!),
                        ),
                      ],
                    ),
                  )
                else
                  FigmaTruthfulEmpty(
                    icon: Icons.menu_book_outlined,
                    title: context.l10n.journalEmptyTitle,
                    message: context.l10n.journalEmptyMessage,
                    actionLabel: context.l10n.journalEmptyAction,
                    actionKey: const ValueKey('journal-start-session'),
                    onAction: _working ? null : _startSession,
                    minHeight: 270,
                  ),
                const SizedBox(height: 16),
                if (history.isNotEmpty) ...[
                  Text(
                    copy('Partide recente', 'Recent sessions'),
                    style: figmaTitle(size: 16),
                  ),
                  const SizedBox(height: 10),
                  for (final session in history.take(10)) ...[
                    _FigmaJournalSessionCard(session: session, isRo: isRo),
                    const SizedBox(height: 10),
                  ],
                ],
                FigmaPrimaryButton(
                  key: const ValueKey('journal-open-catches'),
                  label: copy('Capturile mele', 'My catches'),
                  icon: Icons.photo_library_rounded,
                  secondary: true,
                  onPressed: () =>
                      AppNavigator.open(context, AppDestination.myCatches),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('journal-open-reports'),
                  onPressed: () =>
                      AppNavigator.open(context, AppDestination.myReports),
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: Text(copy('Rapoartele mele', 'My reports')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _journalDuration(Duration duration, {required bool isRo}) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return isRo ? '$minutes min' : '$minutes min';
  return '${hours}h ${minutes}m';
}

class _FigmaJournalSessionCard extends StatelessWidget {
  const _FigmaJournalSessionCard({required this.session, required this.isRo});
  final FishingSession session;
  final bool isRo;

  @override
  Widget build(BuildContext context) {
    final ended = session.endedAt;
    final date = session.startedAt;
    return FigmaSurface(
      child: Row(
        children: [
          const Icon(Icons.menu_book_rounded, color: FigmaFluviTokens.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title?.trim().isNotEmpty == true
                      ? session.title!
                      : (session.placeName ??
                            (isRo ? 'Partidă de pescuit' : 'Fishing session')),
                  style: const TextStyle(
                    color: FigmaFluviTokens.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.day}.${date.month}.${date.year} · ${_journalDuration((ended ?? DateTime.now()).difference(date), isRo: isRo)}',
                  style: figmaBody(size: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FigmaReportsArchivePage extends ConsumerStatefulWidget {
  const FigmaReportsArchivePage({
    super.key,
    this.service = const CommunityService(),
  });

  final CommunityService service;

  @override
  ConsumerState<FigmaReportsArchivePage> createState() =>
      _FigmaReportsArchivePageState();
}

class _FigmaReportsArchivePageState
    extends ConsumerState<FigmaReportsArchivePage> {
  late Future<List<CommunityPost>> _future;
  int _tab = 0;
  bool _verifying = false;
  final Set<String> _verifiedReportIds = {};

  @override
  void initState() {
    super.initState();
    _future = widget.service.getReportsArchive(const Duration(days: 3650));
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.service.getReportsArchive(const Duration(days: 3650));
    });
    await _future;
  }

  Future<void> _verify(
    CommunityPost post,
    ReportVerification verification,
  ) async {
    if (_verifying ||
        !canVerifyCommunityReport(
          post,
          alreadySubmitted: _verifiedReportIds.contains(post.id),
        )) {
      return;
    }
    setState(() => _verifying = true);
    try {
      await widget.service.verifyReport(post.id, verification);
      if (mounted) setState(() => _verifiedReportIds.add(post.id));
      await _refresh();
    } on CommunityException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localContentContextProvider);
    return FigmaCanonicalScaffold(
      key: const ValueKey('figma-reports-archive'),
      title: 'Rapoarte',
      subtitle: 'TEMPORARE · CONFIRMATE · CU LOCAȚIE',
      subtitleColor: FigmaFluviTokens.amber,
      padding: EdgeInsets.zero,
      child: FutureBuilder<List<CommunityPost>>(
        future: _future,
        builder: (context, state) {
          final userId = const AuthService().currentUser?.id;
          final allReports = filterReportsForUser(
            state.data ?? const <CommunityPost>[],
            userId,
          );
          final reports = switch (_tab) {
            0 => filterCommunityPostsWithinLocalContext(
              allReports,
              local,
            ).where((post) => post.isActiveReport).toList(growable: false),
            1 => const <CommunityPost>[],
            _ => allReports,
          };
          final myReportCount = allReports.length;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _ReportsSegments(
                  selected: _tab,
                  onSelected: (value) => setState(() => _tab = value),
                ),
                const SizedBox(height: 14),
                if (state.connectionState == ConnectionState.waiting &&
                    !state.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 90),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (state.hasError)
                  FigmaTruthfulEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Rapoartele nu sunt disponibile',
                    message:
                        'Nu s-au încărcat rapoarte reale. Reîncearcă atunci când conexiunea revine.',
                    actionLabel: 'Reîncearcă',
                    onAction: _refresh,
                  )
                else if (userId == null)
                  const FigmaTruthfulEmpty(
                    icon: Icons.login_rounded,
                    title: 'Autentificare necesară',
                    message:
                        'Rapoartele mele nu pot fi afișate fără un cont autentificat.',
                  )
                else if (_tab == 0 && local == null)
                  const FigmaTruthfulEmpty(
                    icon: Icons.location_off_outlined,
                    title: 'Locația locală nu este disponibilă',
                    message:
                        'Fila Aproape folosește poziția curentă și nu revine la rapoarte globale.',
                  )
                else if (_tab == 1)
                  _ReportsFollowingEmpty(myReportCount: myReportCount)
                else if (reports.isEmpty)
                  FigmaTruthfulEmpty(
                    icon: Icons.inventory_2_outlined,
                    title: _tab == 0
                        ? 'Niciun raport activ'
                        : 'Arhiva este goală',
                    message:
                        'Nu afișăm rapoarte demonstrative atunci când sursa reală nu întoarce rezultate.',
                    actionLabel: 'Adaugă raport',
                    onAction: () =>
                        AppNavigator.open(context, AppDestination.addReport),
                  )
                else ...[
                  _ReportEvidenceImage(post: reports.first),
                  const SizedBox(height: 12),
                  _PrimaryReportCard(
                    post: reports.first,
                    verifying: _verifying,
                    onConfirm:
                        canVerifyCommunityReport(
                          reports.first,
                          alreadySubmitted: _verifiedReportIds.contains(
                            reports.first.id,
                          ),
                        )
                        ? () => _verify(
                            reports.first,
                            ReportVerification.stillValid,
                          )
                        : null,
                    onExpired:
                        canVerifyCommunityReport(
                          reports.first,
                          alreadySubmitted: _verifiedReportIds.contains(
                            reports.first.id,
                          ),
                        )
                        ? () => _verify(
                            reports.first,
                            ReportVerification.noLongerValid,
                          )
                        : null,
                    onOpen: () => AppNavigator.open(
                      context,
                      AppDestination.reportDetail,
                      arguments: reports.first,
                    ),
                  ),
                  if (reports.length > 1) ...[
                    const SizedBox(height: 12),
                    for (final report in reports.skip(1).take(3)) ...[
                      _CompactReportCard(report: report),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
                const SizedBox(height: 16),
                _CreateReportCard(
                  onTap: () =>
                      AppNavigator.open(context, AppDestination.addReport),
                ),
                const SizedBox(height: 10),
                const _ReportModerationCard(),
                const SizedBox(height: 86),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReportsSegments extends StatelessWidget {
  const _ReportsSegments({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    const labels = ['Aproape', 'Urmărite', 'Arhivă'];
    Widget item(int index, {double? width}) => SizedBox(
      width: width,
      child: _ReportSegment(
        label: labels[index],
        selected: selected == index,
        onTap: () => onSelected(index),
      ),
    );
    return Container(
      height: largeText ? 50 : 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF091318),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FigmaFluviTokens.border),
      ),
      child: largeText
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  item(0, width: 112),
                  item(1, width: 112),
                  item(2, width: 112),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: item(0)),
                Expanded(child: item(1)),
                Expanded(child: item(2)),
              ],
            ),
    );
  }
}

class _ReportSegment extends StatelessWidget {
  const _ReportSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF113B3A) : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? FigmaFluviTokens.cyan
                : FigmaFluviTokens.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _ReportsFollowingEmpty extends StatelessWidget {
  const _ReportsFollowingEmpty({required this.myReportCount});

  final int myReportCount;

  @override
  Widget build(BuildContext context) => FigmaTruthfulEmpty(
    icon: Icons.bookmark_border_rounded,
    title: 'Nicio colecție de rapoarte urmărite',
    message: myReportCount == 0
        ? 'Urmărirea rapoartelor va fi legată de colecția reală în etapa de integrare a utilităților.'
        : 'Ai $myReportCount rapoarte proprii în arhivă; acestea nu sunt prezentate ca rapoarte urmărite.',
  );
}

class _ReportEvidenceImage extends StatelessWidget {
  const _ReportEvidenceImage({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final imageUrl = post.imageUrl?.trim();
    return Container(
      height: 180,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF16353F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FigmaFluviTokens.border),
      ),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _ReportImagePlaceholder(),
            )
          : const _ReportImagePlaceholder(),
    );
  }
}

class _ReportImagePlaceholder extends StatelessWidget {
  const _ReportImagePlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.photo_camera_back_outlined,
          color: FigmaFluviTokens.amber,
          size: 32,
        ),
        SizedBox(height: 8),
        Text(
          'Dovadă foto indisponibilă',
          style: TextStyle(color: FigmaFluviTokens.textSecondary, fontSize: 10),
        ),
      ],
    ),
  );
}

class _PrimaryReportCard extends StatelessWidget {
  const _PrimaryReportCard({
    required this.post,
    required this.verifying,
    required this.onConfirm,
    required this.onExpired,
    required this.onOpen,
  });

  final CommunityPost post;
  final bool verifying;
  final VoidCallback? onConfirm;
  final VoidCallback? onExpired;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor(post.reportCategory);
    final remaining = post.expiresAt?.difference(DateTime.now());
    final expiryLabel = _reportExpiryLabel(remaining);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C151A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_categoryLabel(post.reportCategory).toUpperCase()} · ${_relativeAgo(post.createdAt).toUpperCase()}',
            style: TextStyle(
              color: accent,
              fontFamily: FluviAICommercialTokens.monoFontFamily,
              fontSize: 8.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _categoryLabel(post.reportCategory),
            style: const TextStyle(
              color: FigmaFluviTokens.white,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (post.body.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              post.body.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: FigmaFluviTokens.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                '${post.stillValidCount} confirmări',
                style: const TextStyle(
                  color: FigmaFluviTokens.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (post.latitude != null && post.longitude != null)
                const Text(
                  'Locație disponibilă',
                  style: TextStyle(
                    color: FigmaFluviTokens.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (onConfirm != null)
                _ReportActionPill(
                  label: verifying ? 'SE TRIMITE…' : 'CONFIRMĂ',
                  color: FigmaFluviTokens.cyan,
                  onTap: verifying ? null : onConfirm,
                ),
              if (expiryLabel != null)
                _ReportActionPill(
                  label: expiryLabel,
                  color: FigmaFluviTokens.amber,
                ),
              _ReportActionPill(
                label: 'DETALII',
                color: FigmaFluviTokens.green,
                onTap: onOpen,
              ),
            ],
          ),
          if (onExpired != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: verifying ? null : onExpired,
              child: const Text('Nu mai este valabil'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportActionPill extends StatelessWidget {
  const _ReportActionPill({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: FluviAICommercialTokens.monoFontFamily,
          fontSize: 8,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: child,
    );
  }
}

class _CompactReportCard extends StatelessWidget {
  const _CompactReportCard({required this.report});

  final CommunityPost report;

  @override
  Widget build(BuildContext context) => FigmaSurface(
    accent: _categoryColor(report.reportCategory),
    onTap: () => AppNavigator.open(
      context,
      AppDestination.reportDetail,
      arguments: report,
    ),
    child: Row(
      children: [
        Icon(
          Icons.outlined_flag_rounded,
          color: _categoryColor(report.reportCategory),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _categoryLabel(report.reportCategory),
                style: const TextStyle(
                  color: FigmaFluviTokens.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _relativeTime(report.createdAt),
                style: const TextStyle(
                  color: FigmaFluviTokens.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: FigmaFluviTokens.textSecondary,
          size: 18,
        ),
      ],
    ),
  );
}

class _CreateReportCard extends StatelessWidget {
  const _CreateReportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: FigmaFluviTokens.cyan,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '+  Adaugă raport',
              style: TextStyle(
                color: Color(0xFF05080B),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Categoria este obligatorie · descriere/foto opționale',
              style: TextStyle(color: Color(0xFF07312E), fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReportModerationCard extends StatelessWidget {
  const _ReportModerationCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF11111F),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: FigmaFluviTokens.cyan),
    ),
    child: const Text(
      'Moderare asistată · textul original este păstrat',
      style: TextStyle(
        color: FigmaFluviTokens.cyan,
        fontFamily: FluviAICommercialTokens.monoFontFamily,
        fontSize: 9,
        height: 1.3,
      ),
    ),
  );
}
