import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../widgets/home_premium/home_map.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.fishingMap), centerTitle: true),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 100),
          child: HomePremiumMap(showWaterStations: true),
        ),
      ),
    );
  }
}
