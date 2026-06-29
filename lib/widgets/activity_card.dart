import 'package:flutter/material.dart';

class ActivityCard extends StatelessWidget {
  final String user;
  final String location;
  final String fish;
  final String time;

  const ActivityCard({
    super.key,
    required this.user,
    required this.location,
    required this.fish,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(user, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("$fish • $location\n$time"),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
