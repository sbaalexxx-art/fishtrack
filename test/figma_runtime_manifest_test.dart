import 'dart:io';

import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/navigation/app_navigator.dart';
import 'package:fishtrack/core/navigation/figma_runtime_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all current canonical Figma frames are registered', () {
    expect(FigmaRuntimeManifest.designFileKey, '65pycGdhkI9wK5nKBgZAoZ');
    expect(FigmaRuntimeManifest.reviewRootNodeId, '329:3');
    expect(FigmaRuntimeManifest.allOfficialFrames, hasLength(11));

    final nodeIds = FigmaRuntimeManifest.allOfficialFrames
        .map((frame) => frame.nodeId)
        .toSet();
    expect(nodeIds, hasLength(11));
    for (final frame in FigmaRuntimeManifest.allOfficialFrames) {
      expect(AppDestinationRegistry.definitions, contains(frame.destination));
    }
  });

  test(
    'canonical prototype connections resolve to registered destinations',
    () {
      final connections = FigmaRuntimeManifest.connections;
      expect(connections, hasLength(22));
      expect(
        connections.map((connection) => connection.index),
        orderedEquals(List<int>.generate(22, (index) => index + 1)),
      );
      for (final connection in connections) {
        expect(AppDestinationRegistry.definitions, contains(connection.from));
        expect(AppDestinationRegistry.definitions, contains(connection.to));
      }
    },
  );

  test('the seven critical flows are represented by manifest edges', () {
    final edges = FigmaRuntimeManifest.connections
        .map((edge) => (edge.from, edge.to))
        .toSet();
    for (final edge in const [
      (AppDestination.water, AppDestination.newAlert),
      (AppDestination.map, AppDestination.addReport),
      (AppDestination.addCatch, AppDestination.myCatches),
      (AppDestination.community, AppDestination.reportDetail),
      (AppDestination.favorites, AppDestination.water),
      (AppDestination.fluvi, AppDestination.askFluvi),
      (AppDestination.premium, AppDestination.premiumRestored),
    ]) {
      expect(edges, contains(edge));
    }
  });

  test('route templates resolve static and entity paths', () {
    expect(
      AppDestinationRegistry.fromPath('/home')?.destination,
      AppDestination.home,
    );
    expect(
      AppDestinationRegistry.fromPath('/water/station-1')?.destination,
      AppDestination.water,
    );
    expect(
      AppDestinationRegistry.fromPath('/reports/report-1')?.destination,
      AppDestination.reportDetail,
    );
    expect(
      AppDestinationRegistry.fromPath('/reports/new')?.destination,
      AppDestination.addReport,
    );
    expect(
      AppDestinationRegistry.fromPath('/alerts/alert-1/edit')?.destination,
      AppDestination.editAlert,
    );
    expect(
      AppDestinationRegistry.fromPath('/account/security')?.destination,
      AppDestination.accountSecurity,
    );
    expect(
      AppDestinationRegistry.fromPath(
        '/reports/report-1/confirmed',
      )?.destination,
      AppDestination.reportConfirmed,
    );
    expect(
      AppDestinationRegistry.fromPath('/premium/restored')?.destination,
      AppDestination.premiumRestored,
    );
    expect(AppDestinationRegistry.fromPath('/not-a-route'), isNull);
  });

  test('production runtime contains no known place demos or mojibake', () {
    final excluded = <String>{
      'lib/design_lab/home_design_lab_page.dart',
      'lib/main_design_lab.dart',
      'lib/screens/home_page.dart',
      'lib/screens/home_premium_page.dart',
    };
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !excluded.contains(file.path.replaceAll('\\', '/')));
    final malformed = RegExp(r'Ã|Ä|Å|È|â€|�|™');
    for (final file in files) {
      final content = file.readAsStringSync();
      expect(content, isNot(contains('River Avon')), reason: file.path);
      expect(malformed.hasMatch(content), isFalse, reason: file.path);
    }
  });

  testWidgets('primary destinations return to the active IndexedStack bridge', (
    tester,
  ) async {
    var selectedTab = -1;
    AppNavigator.attachMainTabSelector((index) => selectedTab = index);
    addTearDown(AppNavigator.detachMainTabSelector);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppNavigator.open(context, AppDestination.map),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(selectedTab, 1);
  });
}
