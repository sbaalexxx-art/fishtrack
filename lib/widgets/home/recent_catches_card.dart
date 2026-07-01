import 'package:flutter/material.dart';

class RecentCatchesCard extends StatelessWidget {
  const RecentCatchesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.phishing, color: Colors.lightBlueAccent),
                SizedBox(width: 8),
                Text(
                  'Recent Catches',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                'Zander • 3.8 kg',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Danube - Giurgiu',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: Icon(Icons.photo, color: Colors.white54),
            ),

            const Divider(color: Colors.white12),

            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                'Carp • 8.2 kg',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Danube - Călărași',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: Icon(Icons.photo, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
