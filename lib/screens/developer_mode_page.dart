import 'package:flutter/material.dart';

import '../services/build_mode_service.dart';

class DeveloperModePage extends StatelessWidget {
  const DeveloperModePage({super.key});

  static const _appVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '1.0.0',
  );

  @override
  Widget build(BuildContext context) {
    if (!BuildModeService.isDeveloperVisible) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Panel')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                _info('App Version', _appVersion),
                _info('Environment', BuildModeService.environment),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _action(context, Icons.cloud_outlined, 'Test Weather API'),
                _action(context, Icons.water_outlined, 'Test Water API'),
                _action(context, Icons.storage_outlined, 'Test Supabase'),
                _action(context, Icons.refresh_rounded, 'Force Refresh'),
                _action(context, Icons.delete_outline_rounded, 'Clear Cache'),
                _action(context, Icons.receipt_long_outlined, 'View Logs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _info(String label, String value) =>
      ListTile(dense: true, title: Text(label), trailing: Text(value));

  static Widget _action(BuildContext context, IconData icon, String label) =>
      ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label: Coming soon.'))),
      );
}
