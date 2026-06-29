import 'package:flutter/material.dart';

import 'screens/main_navigation.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const FishTrackApp());
}

class FishTrackApp extends StatelessWidget {
  const FishTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FishTrack',
      theme: AppTheme.lightTheme,
      home: const MainNavigation(),
    );
  }
}
