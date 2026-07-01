import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Avatar utilizator
          GestureDetector(
            onTap: () {
              // TODO: Deschide meniul/profilul
            },
            child: const CircleAvatar(
              radius: 22,
              backgroundColor: Color(0xFF1F2937),
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),

          const Spacer(),

          // Logo
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              children: [
                TextSpan(
                  text: 'AI',
                  style: TextStyle(color: Color(0xFF1E88E5)),
                ),
                TextSpan(
                  text: 'FishMap',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Search
          IconButton(
            onPressed: () {
              // TODO: Search
            },
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}
