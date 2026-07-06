import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/catch.dart';
import '../repositories/catch_repository.dart';

class RecentCatches extends StatelessWidget {
  final String stationId;

  const RecentCatches({super.key, required this.stationId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Catch>>(
      future: const CatchRepository().getCatchesForStation(stationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(context.l10n.recentCatchesLoadError),
            ),
          );
        }

        final catches = snapshot.data ?? [];

        if (catches.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(context.l10n.noRecentCatches),
            ),
          );
        }

        return Column(
          children: catches.map((fish) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.set_meal, color: Colors.white),
                ),
                title: Text(
                  fish.species,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  [
                    if (fish.weight != null)
                      '${fish.weight!.toStringAsFixed(1)} kg',
                    if (fish.length != null)
                      '${fish.length!.toStringAsFixed(0)} cm',
                  ].join(' • '),
                ),
                trailing: Text(
                  "${fish.date.day}.${fish.date.month}.${fish.date.year}",
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
