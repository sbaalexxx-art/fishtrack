import 'package:flutter/material.dart';

import '../services/reputation_service.dart';

class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.level});

  final TrustLevel level;

  String _labelFor(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;

    if (languageCode != 'ro') {
      return level.label;
    }

    switch (level) {
      case TrustLevel.newUser:
        return 'Nou';
      case TrustLevel.trusted:
        return 'De încredere';
      case TrustLevel.reliable:
        return 'Fiabil';
      case TrustLevel.expert:
        return 'Expert';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      _labelFor(context),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}
