import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import 'home_premium_layout.dart';

class CommunityCardPremium extends StatelessWidget {
  const CommunityCardPremium({
    super.key,
    this.activeAnglers = 248,
    this.liveReports = 37,
  });

  final int activeAnglers;
  final int liveReports;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HomePremiumLayout.of(context);
        final compact = constraints.maxWidth < 180;

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
                    color: Color(0xFF4CAF50),
                    size: 20 * layout.iconScale,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'COMMUNITY',
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
              const _AnglerAvatars(),
              const SizedBox(height: 4),
              Text(
                '$activeAnglers anglers nearby',
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
                '$liveReports new reports today',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontSize: compact ? 11 : 13,
                ),
              ),
              const Spacer(),
              const Row(
                children: [
                  Icon(Icons.circle, size: 9, color: Color(0xFF4CAF50)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Live activity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
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
    );
  }
}

class _AnglerAvatars extends StatelessWidget {
  const _AnglerAvatars();

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
                child: const Icon(
                  Icons.person,
                  color: Colors.white70,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
