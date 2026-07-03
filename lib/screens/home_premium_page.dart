import 'package:flutter/material.dart';

import '../core/theme/app_dimensions.dart';
import '../widgets/home_premium/dashboard.dart';
import '../widgets/home_premium/home_header.dart';
import '../widgets/home_premium/home_map.dart';

class HomePremiumPage extends StatelessWidget {
  const HomePremiumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bool tablet = AppDimensions.isTablet(context);

    final double horizontalPadding = tablet ? 22 : 16;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: screenHeight * 0.008),

                const HomePremiumHeader(),

                SizedBox(height: screenHeight * 0.010),

                SizedBox(
                  height: screenHeight * 0.43,
                  child: const HomePremiumMap(),
                ),

                SizedBox(height: screenHeight * 0.018),

                const PremiumDashboard(),

                SizedBox(height: screenHeight * 0.12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
