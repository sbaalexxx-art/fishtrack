import 'package:flutter/material.dart';

import '../widgets/score_card.dart';
import '../widgets/section_title.dart';
import '../widgets/quick_actions_row.dart';
import '../widgets/activity_card.dart';
import '../widgets/menu_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FishTrack"), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "👋 Bun venit!",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text(
                "Pescari reali.\nDate reale.\nDecizii mai bune.",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),

              const SizedBox(height: 30),

              const ScoreCard(),

              const SizedBox(height: 30),

              const SectionTitle(title: "⚡ Acțiuni rapide"),

              const SizedBox(height: 15),

              const QuickActionsRow(),

              const SizedBox(height: 35),

              const SectionTitle(title: "🔥 Activitate recentă"),

              const SizedBox(height: 15),

              const ActivityCard(
                user: "Mihai",
                location: "Giurgiu",
                fish: "Crap 5.2 kg",
                time: "Acum 15 minute",
              ),

              const SizedBox(height: 12),

              const ActivityCard(
                user: "Alex",
                location: "Călărași",
                fish: "Șalău 2.8 kg",
                time: "Acum 1 oră",
              ),

              const SizedBox(height: 35),

              const SectionTitle(title: "🚀 Acces rapid"),

              MenuCard(
                icon: Icons.water_drop,
                iconColor: Colors.blue,
                title: "Nivelul apelor",
                subtitle: "Vezi nivelul Dunării și al râurilor",
                onTap: () {},
              ),

              const SizedBox(height: 15),

              MenuCard(
                icon: Icons.cloud,
                iconColor: Colors.orange,
                title: "Meteo",
                subtitle: "Prognoza pentru pescuit",
                onTap: () {},
              ),

              const SizedBox(height: 15),

              MenuCard(
                icon: Icons.campaign,
                iconColor: Colors.red,
                title: "Raportări Live",
                subtitle: "Capturi și informații din teren",
                onTap: () {},
              ),

              const SizedBox(height: 15),

              MenuCard(
                icon: Icons.favorite,
                iconColor: Colors.pink,
                title: "Capturile mele",
                subtitle: "Vezi istoricul capturilor",
                onTap: () {},
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
