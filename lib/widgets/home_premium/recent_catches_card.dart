import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../screens/community_details_page.dart';
import '../../screens/reports_page.dart';
import '../../services/community_service.dart';
import 'home_premium_layout.dart';

class RecentCatchesCardPremium extends StatefulWidget {
  const RecentCatchesCardPremium({super.key});

  @override
  State<RecentCatchesCardPremium> createState() =>
      _RecentCatchesCardPremiumState();
}

class _RecentCatchesCardPremiumState extends State<RecentCatchesCardPremium> {
  late final Future<List<CommunityPost>> _catches;

  @override
  void initState() {
    super.initState();
    _catches = const CommunityService().getFeed().then(
      (posts) => posts
          .where((post) => post.type == CommunityPostType.catchPost)
          .take(10)
          .toList(),
    );
  }

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
        final tileWidth = ((constraints.maxWidth - 16) / 3).clamp(128.0, 184.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'RECENT CATCHES',
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
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF12D8D6),
                    textStyle: TextStyle(
                      fontSize: 12 * layout.bodyFontScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: layout.recentCatchesHeight,
              child: FutureBuilder<List<CommunityPost>>(
                future: _catches,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Recent catches unavailable',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  final catches = snapshot.data ?? const [];
                  if (catches.isEmpty) {
                    return const Center(
                      child: Text(
                        'No catches yet',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: catches.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
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
    return Material(
      color: const Color(0xFF202633),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (post.imageUrl case final String imageUrl)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFF455A64),
                        child: Icon(Icons.image_not_supported_outlined),
                      ),
                    )
                  else
                    const ColoredBox(
                      color: Color(0xFF455A64),
                      child: Icon(Icons.set_meal_outlined),
                    ),
                  if (post.weight != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          child: Text(
                            '${post.weight!.toStringAsFixed(1)} kg',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10 * layout.bodyFontScale,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 12 * layout.bodyFontScale,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.location_on_rounded,
                    size: 15,
                    color: Color(0xFF67D04B),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
