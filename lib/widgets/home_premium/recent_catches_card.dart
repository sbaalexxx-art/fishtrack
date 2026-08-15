import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../screens/community_details_page.dart';
import '../../screens/reports_page.dart';
import '../../services/community_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

class RecentCatchesCardPremium extends StatefulWidget {
  const RecentCatchesCardPremium({super.key});

  @override
  State<RecentCatchesCardPremium> createState() =>
      _RecentCatchesCardPremiumState();
}

class _RecentCatchesCardPremiumState extends State<RecentCatchesCardPremium> {
  late Future<List<CommunityPost>> _catches;

  @override
  void initState() {
    super.initState();
    _catches = _load();
  }

  Future<List<CommunityPost>> _load({bool forceRefresh = false}) =>
      const CommunityService()
          .getFeed(forceRefresh: forceRefresh)
          .then(
            (posts) => posts
                .where((post) => post.type == CommunityPostType.catchPost)
                .take(10)
                .toList(),
          );

  void _retry() => setState(() => _catches = _load(forceRefresh: true));

  void _openAll() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportsPage()));
  }

  void _openCatch(CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CatchDetailsPage(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HomePremiumLayout.of(context);
        final availableWidth = constraints.maxWidth;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 1.3).toDouble();
        final widthFactor = layout.isTablet ? .58 : .78;
        final tileWidth =
            ((availableWidth * widthFactor) + ((textScale - 1) * 36))
                .clamp(220.0, 380.0)
                .toDouble();
        final itemGap = availableWidth < 360 ? 5.0 : 6.0;
        final placeholderCount =
            ((availableWidth + itemGap) / (tileWidth + itemGap))
                .ceil()
                .clamp(1, 6)
                .toInt();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.recentCatches.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle.copyWith(
                      fontSize: 15 * layout.titleFontScale,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _openAll,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF12D8D6),
                    textStyle: TextStyle(
                      fontSize: 12 * layout.bodyFontScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(context.l10n.viewAll),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Expanded(
              child: FutureBuilder<List<CommunityPost>>(
                future: _catches,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return PremiumLoadingShimmer(
                      isLoading: true,
                      borderRadius: 12,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: placeholderCount,
                        separatorBuilder: (_, _) => SizedBox(width: itemGap),
                        itemBuilder: (context, index) => SizedBox(
                          width: tileWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF202633),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(context.l10n.retryRecentCatches),
                      ),
                    );
                  }
                  final catches = snapshot.data ?? const [];
                  if (catches.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.noCatchesYet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 12 * layout.bodyFontScale,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: catches.length,
                    separatorBuilder: (_, _) => SizedBox(width: itemGap),
                    itemBuilder: (context, index) => SizedBox(
                      width: tileWidth,
                      child: _CatchCard(
                        post: catches[index],
                        layout: layout,
                        onTap: () => _openCatch(catches[index]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CatchCard extends StatelessWidget {
  const _CatchCard({
    required this.post,
    required this.layout,
    required this.onTap,
  });

  final CommunityPost post;
  final HomePremiumLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeLabel = _relativeTime(context, post.createdAt);
    final weightLabel = post.weight == null
        ? null
        : '${post.weight!.toStringAsFixed(1)} kg';
    final locationIsHidden = post.latitude == null || post.longitude == null;
    final privacyLabel = locationIsHidden
        ? context.l10n.hiddenLocation
        : context.l10n.locationPrivacy;
    final semanticValue = [?weightLabel, timeLabel, privacyLabel].join(', ');

    return Semantics(
      container: true,
      button: true,
      label: '${context.l10n.catchDetails}: ${post.title}',
      value: semanticValue,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: const Color(0xFF202633),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x1FFFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post.imageUrl case final String imageUrl)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFF455A64),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white70,
                    ),
                  ),
                )
              else
                const ColoredBox(
                  color: Color(0xFF455A64),
                  child: Icon(Icons.set_meal_outlined, color: Colors.white70),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .48, 1],
                    colors: [
                      Color(0x42000000),
                      Color(0x08000000),
                      Color(0xE8141820),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Tooltip(
                  message: privacyLabel,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xC7141820),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      child: Icon(
                        locationIsHidden
                            ? Icons.location_off_rounded
                            : Icons.location_on_rounded,
                        size: 14,
                        color: locationIsHidden
                            ? Colors.white70
                            : const Color(0xFF67D04B),
                      ),
                    ),
                  ),
                ),
              ),
              if (weightLabel != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xD9141820),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        weightLabel,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5 * layout.bodyFontScale,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13 * layout.bodyFontScale,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white70,
                              fontSize: 10.5 * layout.bodyFontScale,
                              height: 1.05,
                            ),
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
      ),
    );
  }
}

String _relativeTime(BuildContext context, DateTime createdAt) {
  final difference = DateTime.now().difference(createdAt);
  if (difference.inMinutes < 1) return context.l10n.justNow;
  if (difference.inHours < 1) {
    return context.l10n.minutesAgo(difference.inMinutes);
  }
  if (difference.inDays < 1) {
    return context.l10n.hoursAgo(difference.inHours);
  }
  return context.l10n.daysAgo(difference.inDays);
}
