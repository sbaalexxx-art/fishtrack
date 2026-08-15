import 'dart:io';

import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/navigation/figma_runtime_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved canonical Figma inventory is represented in Flutter', () {
    const requiredNodes = <String>{
      '329:11',
      '329:293',
      '329:365',
      '329:425',
      '329:518',
      '329:629',
      '329:697',
      '329:769',
      '329:836',
      '329:898',
      '437:5',
    };
    expect(
      FigmaRuntimeManifest.allOfficialFrames
          .map((frame) => frame.nodeId)
          .toSet(),
      requiredNodes,
    );
  });

  test('every runtime destination is registered and routed', () {
    final router = File(
      'lib/features/figma_complete/presentation/figma_destination_router.dart',
    ).readAsStringSync();
    for (final destination in AppDestination.values) {
      expect(
        AppDestinationRegistry.definitions,
        contains(destination),
        reason: 'Missing registry entry for ${destination.name}',
      );
      expect(
        router,
        contains('AppDestination.${destination.name}'),
        reason: 'Missing Figma router branch for ${destination.name}',
      );
    }
  });

  test('active Home, Map and shell do not import legacy destination pages', () {
    final activeFiles = <String>[
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
      'lib/screens/map_page.dart',
      'lib/screens/main_navigation.dart',
      'lib/core/navigation/app_navigator.dart',
      'lib/widgets/home_premium/home_map.dart',
    ];
    const forbidden = <String>[
      'ProductDestinationPage',
      'WaterLevelPage(',
      'WeatherPage(',
      'FishingInsightsPage(',
      'StationDetailsPage(',
    ];
    for (final path in activeFiles) {
      final source = File(path).readAsStringSync();
      for (final token in forbidden) {
        expect(source, isNot(contains(token)), reason: '$path uses $token');
      }
    }
  });

  test('PO Developer Console is gated to developer-visible builds', () {
    final source = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('DeveloperModePage'),
      reason: 'PO Developer Console is an intentional runtime capability',
    );
    expect(
      source,
      contains('if (!BuildModeService.isDeveloperVisible) return;'),
      reason: 'Developer Console must refuse access outside debug/PO builds',
    );
    expect(
      RegExp(
        r'onDeveloperMode:\s*BuildModeService\.isDeveloperVisible\s*'
        r'\?\s*_openDeveloperMode\s*:\s*null',
        multiLine: true,
      ).hasMatch(source),
      isTrue,
      reason:
          'Home must not expose the Developer Console callback in production',
    );
  });

  test('canonical implementation has no empty tap or press callbacks', () {
    final files = <File>[
      ...Directory('lib/features/figma_complete')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      File(
        'lib/features/commercial_home/presentation/commercial_home_page.dart',
      ),
      File('lib/screens/map_page.dart'),
      File('lib/widgets/home_premium/side_menu.dart'),
    ];
    final emptyCallback = RegExp(
      r'(?:onTap|onPressed)\s*:\s*\(\)\s*(?:async\s*)?\{\s*\}',
      multiLine: true,
    );
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(emptyCallback.hasMatch(source), isFalse, reason: file.path);
    }
  });

  test('only the production application shell owns bottom navigation', () {
    final owners = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      if (path.contains('/design_lab/') ||
          path.endsWith('/main_design_lab.dart')) {
        continue;
      }
      if (file.readAsStringSync().contains('bottomNavigationBar:')) {
        owners.add(path);
      }
    }
    expect(owners, hasLength(1));
    expect(owners.single, endsWith('lib/screens/main_navigation.dart'));
  });
}
