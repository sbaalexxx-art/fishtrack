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
              final layout = HomePremiumLayout.of(context);
              final compact = constraints.maxWidth < 220;
              final denseHeight = constraints.maxHeight < 145;
              final dense = compact || layout.isLandscapePhone || denseHeight;
              final isRo = Localizations.localeOf(context).languageCode == 'ro';
              final status = isLoading
                  ? (isRo
                        ? 'Se încarcă activitatea...'
                        : 'Loading community...')
                  : snapshot.hasError
                  ? (isRo
                        ? 'Nu există încă actualizări din comunitate'
                        : 'No community updates available yet')
                  : isEmptyState
                  ? localizations.communityEmptyMessage
                  : (isRo
                        ? '$activeReports rapoarte active'
                        : '$activeReports active reports');
              final statusText = Text(
                status,
                maxLines: isEmptyState ? 2 : (dense ? 3 : 2),
                style: TextStyle(
                  color: Colors.white,
                  fontSize:
                      (isEmptyState ? (dense ? 11 : 13) : (dense ? 11.5 : 17)) *
                      layout.titleFontScale,
                  height: 1.04,
                  fontWeight: FontWeight.bold,
                ),
              );
              final avatarRow = _AnglerAvatars(
                avatarUrls: avatars,
                dense: dense,
              );

              return Container(
                padding: EdgeInsets.all(
                  dense
                      ? 7
                      : layout.isSmallPhone
                      ? 8
                      : (layout.isTablet ? 12 : 10),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF183021),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          color: const Color(0xFF4CAF50),
                          size: (dense ? 18 : 20) * layout.iconScale,
                        ),
                        SizedBox(width: dense ? 5 : 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              isRo ? 'COMUNITATE' : 'COMMUNITY',
                              maxLines: 1,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize:
                                    (dense ? 14 : 16) * layout.titleFontScale,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: dense ? 3 : 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: dense ? 6 : 8,
                            vertical: dense ? 2 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: dense ? 3 : 5),
                    if (dense)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          avatarRow,
                          const SizedBox(width: 5),
                          Expanded(child: statusText),
                        ],
                      )
                    else ...[
                      avatarRow,
                      const SizedBox(height: 4),
                      statusText,
                    ],
                    SizedBox(height: dense ? 2 : 3),
                    Text(
                      isEmptyState
                          ? localizations.communityEmptyCta
                          : (isRo
                                ? '$reportsToday rapoarte astăzi'
                                : '$reportsToday reports today'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: dense ? 10.5 : 13,
                        color: isEmptyState ? const Color(0xFFB8F5C7) : null,
                        fontWeight: isEmptyState ? FontWeight.w700 : null,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: dense ? 8 : 9,
                          color: const Color(0xFF4CAF50),
                        ),
                        SizedBox(width: dense ? 5 : 6),
                        Expanded(
                          child: Text(
                            isRo ? 'Activitate live' : 'Live activity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF4CAF50),
                              fontSize: dense ? 11.5 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
                  border: Border.all(color: const Color(0xFF183021), width: 2),
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
