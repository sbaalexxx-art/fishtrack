import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
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

        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = HomePremiumLayout.of(context);
              final compact = constraints.maxWidth < 180;
              final isRo = Localizations.localeOf(context).languageCode == 'ro';
              final status = isLoading
                  ? (isRo
                        ? 'Se încarcă activitatea...'
                        : 'Loading community...')
                  : snapshot.hasError
                  ? (isRo
                        ? 'Nu există încă actualizări din comunitate'
                        : 'No community updates available yet')
                  : (isRo
                        ? '$activeReports rapoarte active'
                        : '$activeReports active reports');

              return Container(
                padding: EdgeInsets.all(
                  layout.isSmallPhone ? 8 : (layout.isTablet ? 12 : 10),
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
                          size: 20 * layout.iconScale,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isRo ? 'COMUNITATE' : 'COMMUNITY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 16 * layout.titleFontScale,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 6 : 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _AnglerAvatars(avatarUrls: avatars),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (compact ? 15 : 17) * layout.titleFontScale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isRo
                          ? '$reportsToday rapoarte astăzi'
                          : '$reportsToday reports today',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          size: 9,
                          color: Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isRo ? 'Activitate live' : 'Live activity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 13,
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
  const _AnglerAvatars({required this.avatarUrls});

  final List<String> avatarUrls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: 68,
      child: Stack(
        children: [
          for (var index = 0; index < 3; index++)
            Positioned(
              left: index * 20,
              child: Container(
                width: 28,
                height: 28,
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
                            size: 16,
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 16,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
