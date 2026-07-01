import 'package:flutter/material.dart';

import '../widgets/home/home_header.dart';
import '../widgets/home/map_preview.dart';
import '../widgets/home/dashboard.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const HomeHeader(),

              MapPreview(
                onTap: () {
                  // TODO: Open Explore Mode (Full Screen Map)
                },
                child: Container(
                  color: const Color(0xFF1B1B1B),
                  child: const Center(
                    child: Text(
                      'OpenStreetMap Preview',
                      style: TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                  ),
                ),
              ),

              const Dashboard(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
