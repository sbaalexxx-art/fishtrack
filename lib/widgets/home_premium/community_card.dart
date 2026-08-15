import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/app_localizations.dart';
import '../../services/community_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

class CommunityCardPremium extends StatefulWidget {
  const CommunityCardPremium({super.key});

  @override
  State<CommunityCardPremium> createState() => _CommunityCardPremiumState();
}

class _CommunityCardPremiumState extends State<CommunityCardPremium> {
  late final Stream<List<CommunityPost>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = const CommunityService().watchReports();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityPost>>(
      stream: _reports,
      builder: (context, snapshot) {
        final posts = snapshot.data ?? const <CommunityPost>[];
        final now = DateTime.now();
        final activeReports = posts.where((post) => post.isActiveReport).length;
        final reportsToday = posts.where((post) {
          final date = post.createdAt;
          return post.type == CommunityPostType.report &&
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        }).length;
        final avatars = posts
            .map((post) => post.authorAvatar)
            .whereType<String>()
            .where((url) => url.isNotEmpty)
            .toSet()
            .take(3)
            .toList();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final isEmptyState =
            !isLoading &&
            !snapshot.hasError &&
            activeReports == 0 &&
            reportsToday == 0;
        final localizations = AppLocalizations.of(context);

        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const accent = Color(0xFF4CAF50);
              final layout = HomePremiumLayout.of(context);
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final compactWidth = constraints.maxWidth < 230;
              final constrainedHeight =
                  constraints.hasBoundedHeight && constraints.maxHeight < 158;
              final dense =
                  compactWidth ||
                  layout.isLandscapePhone ||
                  constrainedHeight ||
                  textScale >= 1.25;
              final cardPadding = dense
                  ? 8.0
                  : layout.isTablet
                  ? 12.0
                  : 10.0;
              final hasActivity =
                  !isLoading && !snapshot.hasError && !isEmptyState;
              final primaryStatus = isLoading
                  ? localizations.loading
                  : snapshot.hasError
                  ? localizations.communityUnavailable
                  : isEmptyState
                  ? localizations.communityEmptyMessage
                  : localizations.reportCount(activeReports);
              final supportingStatus = isLoading
                  ? localizations.loadingFishingReports
                  : snapshot.hasError
                  ? localizations.noCommunityUpdate
                  : localizations.reportsToday(reportsToday);
              final footerStatus = isLoading
                  ? localizations.loading
                  : snapshot.hasError
                  ? localizations.noCommunityUpdate
                  : isEmptyState
                  ? localizations.communityEmptyCta
                  : localizations.liveActivity;
              final stateColor = snapshot.hasError
                  ? Colors.orangeAccent
                  : accent;
              final statusText = Text(
                primaryStatus,
                maxLines: hasActivity ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize:
                      (hasActivity ? (dense ? 15 : 17) : (dense ? 11 : 12.5)) *
                      layout.titleFontScale,
                  height: 1.04,
                  fontWeight: hasActivity ? FontWeight.w800 : FontWeight.w700,
                ),
              );
              final avatarRow = _AnglerAvatars(
                avatarUrls: avatars,
                dense: dense,
              );

              return Container(
                padding: EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF142632), Color(0xFF0B1B25)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: dense ? 24 : 27,
                          height: dense ? 24 : 27,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.groups_rounded,
                            color: accent,
                            size: (dense ? 16 : 18) * layout.iconScale,
                          ),
                        ),
                        SizedBox(width: dense ? 6 : 8),
                        Expanded(
                          child: Text(
                            localizations.community,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize:
                                  (dense ? 13.5 : 15) * layout.titleFontScale,
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: footerStatus,
                          child: Semantics(
                            label: footerStatus,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: stateColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: stateColor.withValues(alpha: 0.38),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: dense ? 4 : 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          avatarRow,
                          SizedBox(width: dense ? 6 : 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                statusText,
                                SizedBox(height: dense ? 2 : 3),
                                Text(
                                  supportingStatus,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize:
                                        (dense ? 10.5 : 11.5) *
                                        layout.bodyFontScale,
                                    height: 1.05,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: dense ? 4 : 6),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: dense ? 6 : 8,
                        vertical: dense ? 4 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: stateColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: stateColor.withValues(alpha: 0.13),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEmptyState
                                ? Icons.arrow_forward_rounded
                                : snapshot.hasError
                                ? Icons.info_outline_rounded
                                : Icons.circle,
                            size: isEmptyState || snapshot.hasError ? 13 : 7,
                            color: stateColor,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              footerStatus,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: stateColor,
                                fontSize:
                                    (dense ? 10.5 : 11.5) *
                                    layout.bodyFontScale,
                                height: 1.05,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AnglerAvatars extends StatelessWidget {
  const _AnglerAvatars({required this.avatarUrls, required this.dense});

  final List<String> avatarUrls;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final avatarSize = dense ? 22.0 : 28.0;
    final overlapStep = dense ? 16.0 : 20.0;
    return SizedBox(
      height: avatarSize,
      width: avatarSize + (overlapStep * 2),
      child: Stack(
        children: [
          for (var index = 0; index < 3; index++)
            Positioned(
              left: index * overlapStep,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF415547),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF142632), width: 2),
                ),
                child: ClipOval(
                  child: index < avatarUrls.length
                      ? Image.network(
                          avatarUrls[index],
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person,
                            color: Colors.white70,
                            size: 14,
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 14,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
