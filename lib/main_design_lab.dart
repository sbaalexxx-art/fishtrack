import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design_lab/home_design_lab_page.dart';
import 'design_lab/home_design_lab_tokens.dart';

void main() {
  runApp(const HomeDesignLabApp());
}

class HomeDesignLabApp extends StatelessWidget {
  const HomeDesignLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluviAI Home Design Lab',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('ro'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: HomeDesignLabTokens.background,
        colorScheme: const ColorScheme.dark(
          primary: HomeDesignLabTokens.cyanAccent,
          secondary: HomeDesignLabTokens.waterStable,
          surface: HomeDesignLabTokens.surface,
          error: HomeDesignLabTokens.waterFalling,
        ),
      ),
      home: const HomeDesignLabPage(),
    );
  }
}
