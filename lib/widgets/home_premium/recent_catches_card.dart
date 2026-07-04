import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import 'home_premium_layout.dart';

class RecentCatchesCardPremium extends StatelessWidget {
  const RecentCatchesCardPremium({super.key});

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
                  onPressed: () {},
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
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _catches.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final catchData = _catches[index];
                  return SizedBox(
                    width: tileWidth,
                    child: _CatchCard(
                      fish: catchData.fish,
                      weight: catchData.weight,
                      angler: catchData.angler,
                      color: catchData.color,
                      layout: layout,
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

const _catches = <_CatchData>[
  _CatchData('Carp', '8.4 kg', 'John', Color(0xFF8D6E63)),
  _CatchData('Pike', '5.8 kg', 'Michael', Color(0xFF546E7A)),
  _CatchData('Perch', '1.3 kg', 'Daniel', Color(0xFF455A64)),
];

class _CatchData {
  const _CatchData(this.fish, this.weight, this.angler, this.color);

  final String fish;
  final String weight;
  final String angler;
  final Color color;
}

class _CatchCard extends StatelessWidget {
  const _CatchCard({
    required this.fish,
    required this.weight,
    required this.angler,
    required this.color,
    required this.layout,
  });

  final String fish;
  final String weight;
  final String angler;
  final Color color;
  final HomePremiumLayout layout;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF202633),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .20),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withValues(alpha: .88), color],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Icon(
                      Icons.water_rounded,
                      size: 76 * layout.iconScale,
                      color: Colors.white.withValues(alpha: .07),
                    ),
                    Center(
                      child: Icon(
                        Icons.image_rounded,
                        size: 36 * layout.iconScale,
                        color: Colors.white.withValues(alpha: .52),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .32),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          weight,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10 * layout.bodyFontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                          fish,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          angler,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 12 * layout.bodyFontScale,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.location_on_rounded,
                    size: 15 * layout.iconScale,
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
