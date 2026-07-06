import 'package:flutter/material.dart';

import '../services/reputation_service.dart';

class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.level});

  final TrustLevel level;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(level.label, style: Theme.of(context).textTheme.labelSmall),
  );
}
