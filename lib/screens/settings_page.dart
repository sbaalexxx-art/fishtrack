import 'package:flutter/material.dart';

import '../core/localization/locale_controller.dart';
import '../l10n/l10n.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final languageCode = LocaleScope.of(context).languageCode;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              languageCode == 'ro' ? 'Limbă' : 'Language',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: const Text('Română'),
                    selected: languageCode == 'ro',
                    selectedColor: colorScheme.onPrimaryContainer,
                    selectedTileColor: colorScheme.primaryContainer,
                    trailing: languageCode == 'ro'
                        ? Icon(Icons.check_rounded, color: colorScheme.primary)
                        : null,
                    onTap: () async {
                      await LocaleScope.of(context).setLanguageCode('ro');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: const Text('English'),
                    selected: languageCode == 'en',
                    selectedColor: colorScheme.onPrimaryContainer,
                    selectedTileColor: colorScheme.primaryContainer,
                    trailing: languageCode == 'en'
                        ? Icon(Icons.check_rounded, color: colorScheme.primary)
                        : null,
                    onTap: () async {
                      await LocaleScope.of(context).setLanguageCode('en');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
