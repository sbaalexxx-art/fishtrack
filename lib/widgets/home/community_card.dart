import 'package:flutter/material.dart';

class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key});

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
                Icon(Icons.groups, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Community',
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
                backgroundColor: Colors.green,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                'Water flowing normally',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Posted 25 min ago',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.white54),
            ),

            const Divider(color: Colors.white12),

            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '12',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Reports', style: TextStyle(color: Colors.white54)),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '4',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Anglers', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
