import 'package:flutter/material.dart';

import '../core/theme/fluviai_commercial_tokens.dart';
import '../core/navigation/app_navigator.dart';
import '../services/community_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/fluviai/fluviai_components.dart';

class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    super.key,
    required this.post,
    this.onChanged,
    this.onOpenMap,
    this.onOpenFavorites,
    this.service = const CommunityService(),
  });

  final CommunityPost post;
  final VoidCallback? onChanged;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenFavorites;
  final CommunityService service;

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  bool _saving = false;
  bool _savingArea = false;
  late int _validCount;
  late int _invalidCount;

  @override
  void initState() {
    super.initState();
    _validCount = widget.post.stillValidCount;
    _invalidCount = widget.post.noLongerValidCount;
  }

  bool get _isRo => Localizations.localeOf(context).languageCode == 'ro';

  Future<void> _verify(ReportVerification verification) async {
    setState(() => _saving = true);
    try {
      await widget.service.verifyReport(widget.post.id, verification);
      if (!mounted) return;
      setState(() {
        if (verification == ReportVerification.stillValid) {
          _validCount++;
        } else {
          _invalidCount++;
        }
      });
      widget.onChanged?.call();
      await AppNavigator.openPath<void>(
        context,
        '/reports/${widget.post.id}/confirmed',
        arguments: verification == ReportVerification.stillValid,
      );
    } on CommunityException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveArea() async {
    final post = widget.post;
    final lat = post.latitude;
    final lng = post.longitude;
    if (lat == null || lng == null || _savingArea) return;
    setState(() => _savingArea = true);
    try {
      await const SavedItemsService().save(
        type: 'report',
        referenceId: post.id,
        title: post.title,
        subtitle: post.body.isEmpty ? null : post.body,
        latitude: lat,
        longitude: lng,
        metadata: <String, Object?>{
          'report_category': post.reportCategory?.name,
          'created_at': post.createdAt.toUtc().toIso8601String(),
          if (post.expiresAt != null)
            'expires_at': post.expiresAt!.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isRo ? 'Zona a fost salvată.' : 'Area saved.')),
      );
    } on SavedItemsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _savingArea = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return FluviScreen(
      title: _isRo ? 'Detaliu raport' : 'Report detail',
      eyebrow: _isRo ? 'COMUNITATE VERIFICATĂ' : 'VERIFIED COMMUNITY',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FluviStatusBadge(
            status: post.isActiveReport
                ? FluviDataStatus.live
                : FluviDataStatus.cache,
            label: post.isActiveReport
                ? (_isRo ? 'ACTIV' : 'ACTIVE')
                : (_isRo ? 'ÎNCHEIAT' : 'ENDED'),
          ),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          FluviSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (post.imageUrl case final String imageUrl)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: FluviAICommercialTokens.surfaceRaised,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.body.isEmpty
                            ? (_isRo
                                  ? 'Fără descriere suplimentară.'
                                  : 'No additional description.')
                            : post.body,
                        style: const TextStyle(
                          color: FluviAICommercialTokens.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 18,
                            color: FluviAICommercialTokens.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              post.authorName,
                              style: const TextStyle(
                                color: FluviAICommercialTokens.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            _date(post.createdAt),
                            style: const TextStyle(
                              color: FluviAICommercialTokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FluviSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isRo ? 'Mai este valabil?' : 'Is it still valid?',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRo
                      ? 'Confirmă numai dacă poți verifica situația din teren.'
                      : 'Confirm only when you can verify the situation in the field.',
                  style: const TextStyle(
                    color: FluviAICommercialTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('report-confirm-action'),
                        onPressed: _saving
                            ? null
                            : () => _verify(ReportVerification.stillValid),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          '${_isRo ? 'Confirmă' : 'Confirm'} · $_validCount',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('report-invalidate-action'),
                        onPressed: _saving
                            ? null
                            : () => _verify(ReportVerification.noLongerValid),
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(
                          '${_isRo ? 'Încheiat' : 'Ended'} · $_invalidCount',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (post.latitude != null && post.longitude != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('report-open-map-action'),
                    onPressed: widget.onOpenMap,
                    icon: const Icon(Icons.map_rounded),
                    label: Text(_isRo ? 'Deschide harta' : 'Open map'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('report-save-area-action'),
                    onPressed: _savingArea ? null : _saveArea,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(_isRo ? 'Salvează zona' : 'Save area'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }
}

class ReportValidationResultPage extends StatelessWidget {
  const ReportValidationResultPage({super.key, required this.stillValid});

  final bool stillValid;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    return FluviScreen(
      title: isRo ? 'Validare trimisă' : 'Validation sent',
      eyebrow: isRo ? 'ÎNCREDERE COMUNITATE' : 'COMMUNITY TRUST',
      child: FluviStatePanel(
        icon: stillValid ? Icons.verified_rounded : Icons.event_busy_rounded,
        title: stillValid
            ? (isRo ? 'Raport confirmat' : 'Report confirmed')
            : (isRo ? 'Raport marcat ca încheiat' : 'Report marked ended'),
        message: isRo
            ? 'Contribuția ta a fost înregistrată de serviciul comunității.'
            : 'Your contribution was recorded by the community service.',
        actionLabel: isRo ? 'Înapoi la Comunitate' : 'Back to Community',
        onAction: () {
          Navigator.of(context)
            ..pop()
            ..pop();
        },
      ),
    );
  }
}
