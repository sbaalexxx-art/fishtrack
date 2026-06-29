import 'package:flutter/material.dart';
import 'quick_action.dart';

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          QuickAction(icon: Icons.water_drop, title: "Ape", onTap: () {}),

          const SizedBox(width: 12),

          QuickAction(icon: Icons.map, title: "Hartă", onTap: () {}),

          const SizedBox(width: 12),

          QuickAction(icon: Icons.campaign, title: "Live", onTap: () {}),

          const SizedBox(width: 12),

          QuickAction(icon: Icons.favorite, title: "Favorite", onTap: () {}),
        ],
      ),
    );
  }
}
