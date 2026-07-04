import 'package:flutter/material.dart';

import '../widgets/home_premium/dashboard.dart';
import '../widgets/home_premium/home_header.dart';
import '../widgets/home_premium/home_map.dart';
import '../widgets/home_premium/home_premium_layout.dart';

class HomePremiumPage extends StatelessWidget {
  const HomePremiumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: layout.horizontalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: layout.sectionGap * .25),
                      const HomePremiumHeader(),
                      SizedBox(height: layout.sectionGap * .5),
                      SizedBox(
                        height: layout.heroMapHeight,
                        child: const HomePremiumMap(),
                      ),
                      SizedBox(height: layout.sectionGap),
                      const PremiumDashboard(),
                      SizedBox(height: layout.bottomSafeClearance),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
