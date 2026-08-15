import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fishtrack/core/map/hydro_ro_vector_overlay.dart';
import 'package:fishtrack/core/map/hydro_semantic_density.dart';
import 'package:fishtrack/models/water_asset.dart';
import 'package:fishtrack/widgets/fluviai/hydro_intelligence_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RC2 Hydro overlay contract', () {
    test('Hydro preferences are independent from basemap selection', () {
      const preferences = HydroOverlayPreferences(
        enabled: true,
        rivers: true,
        reservoirs: false,
        dams: true,
      );

      final afterBasemapSwitch = preferences.copyWith();

      expect(afterBasemapSwitch.enabled, isTrue);
      expect(afterBasemapSwitch.rivers, isTrue);
      expect(afterBasemapSwitch.reservoirs, isFalse);
      expect(afterBasemapSwitch.dams, isTrue);
    });

    test('semantic zoom makes Danube and major rivers visible first', () {
      expect(HydroRoMapboxOverlay.riverMinimumZoom('Dunărea'), 4.4);
      expect(HydroRoMapboxOverlay.riverMinimumZoom('Danube'), 4.4);
      expect(HydroRoMapboxOverlay.riverMinimumZoom('Mureș'), 5.6);
      expect(HydroRoMapboxOverlay.riverMinimumZoom('Olt'), 5.6);
      expect(HydroRoMapboxOverlay.riverMinimumZoom('Valea locală'), 8.2);
    });

    test('style layer registry contains no duplicate ids', () {
      expect(
        HydroRoMapboxOverlay.layerIds.toSet().length,
        HydroRoMapboxOverlay.layerIds.length,
      );
      expect(
        HydroRoMapboxOverlay.layerIds,
        contains(HydroRoMapboxOverlay.danubeLabelLayerId),
      );
      expect(
        HydroRoMapboxOverlay.layerIds,
        contains(HydroRoMapboxOverlay.riverSelectedLayerId),
      );
      expect(
        HydroRoMapboxOverlay.layerIds,
        contains(HydroRoMapboxOverlay.reservoirSelectedOutlineLayerId),
      );
      expect(
        HydroRoMapboxOverlay.layerIds,
        contains(HydroRoMapboxOverlay.reservoirOutlineLayerId),
      );
    });

    test('regional density keeps priority and restores every local entity', () {
      const candidates = <HydroDensityCandidate>[
        HydroDensityCandidate(
          key: 'dam:low',
          latitude: 45.001,
          longitude: 24.001,
          priority: 10,
        ),
        HydroDensityCandidate(
          key: 'reservoir:important',
          latitude: 45.002,
          longitude: 24.002,
          priority: 200,
        ),
        HydroDensityCandidate(
          key: 'hydropower:selected',
          latitude: 45.003,
          longitude: 24.003,
          priority: 20,
        ),
      ];

      expect(
        selectHydroDensityKeys(candidates: candidates, zoom: 7.8),
        <String>{'reservoir:important'},
      );
      expect(
        selectHydroDensityKeys(
          candidates: candidates,
          zoom: 7.8,
          selectedKeys: const <String>{'hydropower:selected'},
        ),
        <String>{'hydropower:selected'},
      );
      expect(
        selectHydroDensityKeys(candidates: candidates, zoom: 11.2),
        candidates.map((candidate) => candidate.key).toSet(),
      );
    });

    test('selected and saved priorities survive the same density cell', () {
      const candidates = <HydroDensityCandidate>[
        HydroDensityCandidate(
          key: 'reservoir:saved',
          latitude: 45.001,
          longitude: 24.001,
          priority: 10,
        ),
        HydroDensityCandidate(
          key: 'hydropower:selected',
          latitude: 45.002,
          longitude: 24.002,
          priority: 20,
        ),
        HydroDensityCandidate(
          key: 'dam:ordinary',
          latitude: 45.003,
          longitude: 24.003,
          priority: 900,
        ),
      ];

      expect(
        selectHydroDensityKeys(
          candidates: candidates,
          zoom: 7.8,
          selectedKeys: const <String>{
            'reservoir:saved',
            'hydropower:selected',
          },
        ),
        <String>{'reservoir:saved', 'hydropower:selected'},
      );
    });

    test('public selection contains presentation identity only', () {
      const selection = HydroPublicFeatureSelection(
        type: HydroPublicFeatureType.river,
        displayName: 'Olt',
        latitude: 45.1,
        longitude: 24.3,
      );

      expect(selection.displayName, 'Olt');
      expect(selection.type, HydroPublicFeatureType.river);
    });

    test('unknown backend state never fabricates an operational value', () {
      final pin = WaterMapPin.fromJson(<String, dynamic>{
        'entity_type': 'hydro_plant',
        'entity_id': 'plant-unknown',
        'canonical_key': 'ro:hydro:unknown',
        'name': 'CHE fără date',
        'latitude': 45.0,
        'longitude': 24.0,
      });

      expect(pin.operationState, 'UNKNOWN');
      expect(pin.evidenceClass, 'UNKNOWN');
      expect(pin.confidence, 0);
      expect(pin.hasOperationalData, isFalse);
      expect(pin.statePayload, isEmpty);
    });
  });

  group('RC2 integration source contracts', () {
    test('Hydro binding is idempotent and restored after style load', () {
      final overlay = File(
        'lib/core/map/hydro_ro_vector_overlay.dart',
      ).readAsStringSync();
      final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

      expect(overlay, contains('styleSourceExists(sourceId)'));
      expect(overlay, contains('styleLayerExists(layer.id)'));
      expect(mapPage, contains('_restoreRuntimeAfterStyleLoad'));
      expect(mapPage, contains('HydroRoMapboxOverlay.bind'));
      expect(mapPage, contains('HydroRoMapboxOverlay.applyConfiguration'));
      expect(mapPage, contains('_effectiveHydroPreferences.enabled'));
    });

    test('river hierarchy uses mutually exclusive vector style bands', () {
      final overlay = File(
        'lib/core/map/hydro_ro_vector_overlay.dart',
      ).readAsStringSync();

      expect(overlay, contains('_secondaryRiverFilter'));
      expect(overlay, contains("<Object>['!', _majorRiverFilter]"));
      expect(overlay, contains("<Object>['!', _danubeFilter]"));
      expect(overlay, contains("sourceLayer: 'reservoirs'"));
      expect(overlay, contains('textSizeExpression'));
    });

    test('Hydro utility reuses persistent Map and preserves physical GPS', () {
      final utilities = File(
        'lib/features/shell/presentation/utilities_hub_page.dart',
      ).readAsStringSync();

      expect(utilities, contains("utility.id == 'water.hydro-pulse'"));
      expect(utilities, contains('AppDestination.premium'));
      expect(utilities, contains('AppDestination.map'));
      expect(utilities, contains("selectCountry(countryCode: 'RO'"));
      expect(utilities, contains("source: 'hydro-ro-utility'"));
      expect(utilities, isNot(contains('currentLocationProvider.notifier')));
    });

    test(
      'camera rebuilds and pin taps cannot override explicit navigation',
      () {
        final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

        expect(
          mapPage,
          contains('late final mapbox.ViewportState? _initialViewport'),
        );
        expect(mapPage, contains('viewport: _initialViewport'));
        expect(mapPage, contains('_tapHitsHydroAnnotation(gesture)'));
        expect(mapPage, contains('_cameraZoom < 7.2'));
        expect(mapPage, contains('_visibleHydroDensityKeys'));
        expect(
          mapPage,
          contains('_hydroPublicSelection = HydroPublicFeatureSelection'),
        );
      },
    );

    test('station selection stream publishes context without reselecting', () {
      final home = File(
        'lib/features/commercial_home/presentation/commercial_home_page.dart',
      ).readAsStringSync();

      expect(
        home,
        contains(
          'ref.read(selectedContextProvider.notifier).publishStation(station)',
        ),
      );
    });

    test('all RC2 visible strings exist in both RO and EN ARB catalogs', () {
      final ro =
          jsonDecode(File('lib/l10n/app_ro.arb').readAsStringSync())
              as Map<String, dynamic>;
      final en =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      const requiredKeys = <String>{
        'hydroMapTitle',
        'hydroBaseMap',
        'hydroPremiumOverlay',
        'hydroRivers',
        'hydroReservoirs',
        'hydroDams',
        'hydroStations',
        'hydroPlants',
        'hydroUnknownState',
        'hydroEvidenceMeasured',
        'hydroEvidenceDerived',
        'hydroEvidenceEstimated',
        'hydroEvidenceObserved',
        'hydroEvidenceUnknown',
        'hydroOperationalStatus',
        'hydroOperationalUnavailable',
      };

      expect(ro.keys, containsAll(requiredKeys));
      expect(en.keys, containsAll(requiredKeys));
    });

    test('RC2.2B selection reuses canonical actions and factual freshness', () {
      final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

      expect(mapPage, contains('WaterHubRequest(initialStation: station)'));
      expect(mapPage, contains('AppDestination.newAlert'));
      expect(mapPage, contains("type: 'river'"));
      expect(mapPage, contains('_hydroFreshnessLabel'));
      expect(mapPage, contains('Ora actualizării indisponibilă'));
      expect(
        mapPage,
        contains("availabilityStatus?.toLowerCase() == 'available'"),
      );
      expect(mapPage, contains('_assetRelationships(asset, detail)'));
      expect(mapPage, contains('_riverRelationships(detail)'));
      expect(mapPage, contains('_hydropowerRelationships(plant, state)'));
      expect(mapPage, contains("'Date hidrologice'"));
      expect(mapPage, contains("'Date curente indisponibile'"));
      expect(mapPage, contains("'Date hidrologice indisponibile'"));
      expect(mapPage, contains("'Stare de funcționare'"));
      expect(mapPage, contains('_hasValidHydroWaterContext'));
      expect(mapPage, contains('_formatMetricValue(currentLevel)'));
      expect(mapPage, contains('_loadPreviewStationWater(station)'));
      expect(mapPage, contains('_waterService.getWaterUiResult('));
      expect(mapPage, contains('realWaterIntervalDelta('));
      expect(mapPage, contains('stationId: station.id'));
      expect(mapPage, contains("'Variația 24h indisponibilă'"));
      expect(mapPage, isNot(contains('station.reportedDeltaCm24h')));
      expect(mapPage, contains('WaterHubRequest(initialStation: station)'));
      expect(mapPage, isNot(contains('_localizedFreshness(')));
    });
  });

  testWidgets('unknown state is truthful without redundant status messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HydroIntelligencePanel(
            data: const HydroIntelligenceViewData(
              name: 'Olt',
              typeLabel: 'River',
              metadataLabel: 'A.B.A. Olt',
              icon: Icons.waves_rounded,
              accentColor: Color(0xFF43D9CC),
              statusTitle: 'Hydrological data',
              unavailableLabel: 'Current data unavailable',
              statusLabel: 'Unknown',
              unknownMessage: 'Unknown values remain unknown.',
            ),
            expanded: true,
            detailsLabel: 'Details',
            graphLabel: 'View graph',
            askLabel: 'Ask Fluvi',
            sourceLabel: 'Source',
            updatedLabel: 'Updated',
            onToggleExpanded: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('hydro-intelligence-panel')), findsOne);
    expect(
      find.byKey(const ValueKey<String>('hydro-intelligence-scroll:River:Olt')),
      findsOne,
    );
    expect(find.text('Olt'), findsOne);
    expect(find.text('Unknown values remain unknown.'), findsNothing);
    expect(find.text('Unknown'), findsNothing);
    expect(find.text('Hydrological data'), findsOne);
    expect(find.text('Current data unavailable'), findsOne);
    expect(find.text('A.B.A. Olt'), findsOne);
    expect(find.byKey(const ValueKey('hydro-panel-expand')), findsOne);
  });

  testWidgets(
    'RC2.2B panel presents relationships and compact useful actions',
    (tester) async {
      var waterOpened = false;
      var favoriteToggled = false;
      var alertOpened = false;
      var centered = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ro'),
          supportedLocales: const <Locale>[Locale('ro'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: HydroIntelligencePanel(
              data: const HydroIntelligenceViewData(
                name: 'Moldova Veche',
                typeLabel: 'Stație hidrometrică',
                contextLabel: 'Dunăre',
                icon: Icons.speed_rounded,
                accentColor: Color(0xFF57E6B4),
                statusTitle: 'Stare operațională',
                unavailableLabel: 'Date operaționale indisponibile',
                statusLabel: 'Nivel disponibil',
                evidenceLabel: 'Măsurare oficială',
                freshnessLabel: 'Actualizat acum 2 ore',
                unknownMessage: 'Stare necunoscută',
                hasOperationalStatus: true,
                relationships: <HydroRelationshipItem>[
                  HydroRelationshipItem(
                    label: 'Pe apă',
                    title: 'Dunăre',
                    typeLabel: 'Râu',
                    icon: Icons.waves_rounded,
                  ),
                ],
              ),
              expanded: true,
              detailsLabel: 'Detalii',
              graphLabel: 'Vezi grafic',
              askLabel: 'Întreabă Fluvi',
              sourceLabel: 'Sursă',
              updatedLabel: 'Actualizat',
              onToggleExpanded: () {},
              onClose: () {},
              onWaterIntelligence: () => waterOpened = true,
              onFavorite: () => favoriteToggled = true,
              onAlert: () => alertOpened = true,
              onCenter: () => centered = true,
            ),
          ),
        ),
      );

      expect(find.text('CE ȘTIM ACUM'), findsOne);
      expect(find.text('CONTEXT HIDRO'), findsOne);
      expect(find.text('Inteligență hidrologică'), findsOne);
      expect(find.text('Dunăre'), findsOne);
      expect(find.text('Măsurare oficială'), findsOne);
      expect(find.text('Actualizat acum 2 ore'), findsOne);

      Future<void> tapAction(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
      }

      await tapAction('hydro-panel-water-intelligence');
      await tapAction('hydro-panel-favorite');
      await tapAction('hydro-panel-alert');
      await tapAction('hydro-panel-center');

      expect(waterOpened, isTrue);
      expect(favoriteToggled, isTrue);
      expect(alertOpened, isTrue);
      expect(centered, isTrue);
    },
  );

  testWidgets('RC2.2B-7 writes five Samsung-sized AFTER panel captures', (
    tester,
  ) async {
    await tester.runAsync(_loadEvidenceFonts);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const cases = <(String, HydroIntelligenceViewData, bool, bool)>[
      (
        'station_moldova_veche_after.png',
        HydroIntelligenceViewData(
          name: 'Moldova Veche',
          typeLabel: 'Stație hidrometrică',
          contextLabel: 'Dunăre',
          icon: Icons.speed_rounded,
          accentColor: Color(0xFF57E6B4),
          statusTitle: 'Stare operațională',
          unavailableLabel: 'Date operaționale indisponibile',
          statusLabel: '692 cm',
          evidenceLabel: 'Măsurare oficială',
          freshnessLabel: 'Actualizat acum 2 ore',
          unknownMessage: 'Stare necunoscută',
          hasOperationalStatus: true,
        ),
        true,
        true,
      ),
      (
        'river_olt_after.png',
        HydroIntelligenceViewData(
          name: 'Olt',
          typeLabel: 'Râu',
          metadataLabel: 'A.B.A. Olt',
          icon: Icons.waves_rounded,
          accentColor: Color(0xFF37E4F2),
          statusTitle: 'Date hidrologice',
          unavailableLabel: 'Date curente indisponibile',
          statusLabel: 'Necunoscut',
          unknownMessage: 'Stare necunoscută',
        ),
        false,
        true,
      ),
      (
        'reservoir_vidraru_after.png',
        HydroIntelligenceViewData(
          name: 'Vidraru',
          typeLabel: 'Acumulare',
          contextLabel: 'Argeș',
          icon: Icons.water_rounded,
          accentColor: Color(0xFF39B8F2),
          statusTitle: 'Date hidrologice',
          unavailableLabel: 'Date hidrologice indisponibile',
          statusLabel: 'Necunoscut',
          unknownMessage: 'Stare necunoscută',
        ),
        false,
        true,
      ),
      (
        'dam_vidraru_after.png',
        HydroIntelligenceViewData(
          name: 'Baraj Vidraru',
          typeLabel: 'Baraj',
          contextLabel: 'Argeș',
          icon: Icons.account_balance_rounded,
          accentColor: Color(0xFFE8B24A),
          statusTitle: 'Stare operațională',
          unavailableLabel: 'Date operaționale indisponibile',
          statusLabel: 'Necunoscut',
          evidenceLabel: 'Stare neconfirmată',
          unknownMessage: 'Stare necunoscută',
        ),
        false,
        true,
      ),
      (
        'che_gura_lotrului_after.png',
        HydroIntelligenceViewData(
          name: 'Gura Lotrului',
          typeLabel: 'Hidrocentrală',
          contextLabel: 'Olt',
          icon: Icons.bolt_rounded,
          accentColor: Color(0xFFFFB84D),
          statusTitle: 'Stare de funcționare',
          unavailableLabel: 'Necunoscut',
          statusLabel: 'Necunoscut',
          evidenceLabel: 'Stare neconfirmată',
          unknownMessage: 'Stare necunoscută',
        ),
        false,
        false,
      ),
    ];

    for (final (fileName, panelData, waterAvailable, alertAvailable) in cases) {
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        _HydroPanelEvidenceFrame(
          captureKey: captureKey,
          data: panelData,
          waterAvailable: waterAvailable,
          alertAvailable: alertAvailable,
        ),
      );
      await tester.pumpAndSettle();

      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final bytes = byteData!.buffer.asUint8List();
        final directory = Directory('build/evidence/rc2_2b_7/after');
        await directory.create(recursive: true);
        await File('${directory.path}/$fileName').writeAsBytes(bytes);
      });

      expect(find.text(panelData.name), findsOne);
      expect(
        find.byKey(const ValueKey('hydro-panel-water-intelligence')),
        waterAvailable ? findsOne : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('hydro-panel-alert')),
        alertAvailable ? findsOne : findsNothing,
      );
      if (panelData.name == 'Olt' || panelData.name == 'Vidraru') {
        expect(find.text('Fără date hidrologice curente'), findsNothing);
      }
    }
  });

  testWidgets('RC2.2B-8 writes Moldova Veche station AFTER capture', (
    tester,
  ) async {
    await tester.runAsync(_loadEvidenceFonts);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final captureKey = GlobalKey();
    const panelData = HydroIntelligenceViewData(
      name: 'Moldova Veche',
      typeLabel: 'Stație hidrometrică',
      contextLabel: 'Dunăre',
      icon: Icons.speed_rounded,
      accentColor: Color(0xFF57E6B4),
      statusTitle: '−2 cm / 24h · În scădere',
      unavailableLabel: 'Date operaționale indisponibile',
      statusLabel: '692 cm',
      evidenceLabel: 'Măsurare oficială',
      freshnessLabel: 'Actualizat acum 2 ore',
      sourceLabel: 'AFDJ',
      unknownMessage: 'Stare necunoscută',
      hasOperationalStatus: true,
    );
    await tester.pumpWidget(
      _HydroPanelEvidenceFrame(
        captureKey: captureKey,
        data: panelData,
        waterAvailable: true,
        alertAvailable: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('692 cm'), findsOne);
    expect(find.text('−2 cm / 24h · În scădere'), findsOne);
    expect(find.text('Măsurare oficială'), findsOne);
    expect(find.text('Actualizat acum 2 ore'), findsOne);

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final directory = Directory('build/evidence/rc2_2b_8/after');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/station_moldova_veche_after.png',
      ).writeAsBytes(byteData!.buffer.asUint8List());
    });
  });
  testWidgets('RC2.2B-10 writes canonical Gura Lotrului CHE snapshot', (
    tester,
  ) async {
    await tester.runAsync(_loadEvidenceFonts);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final captureKey = GlobalKey();
    const panelData = HydroIntelligenceViewData(
      name: 'Gura Lotrului',
      typeLabel: 'Hidrocentrală',
      contextLabel: 'Olt',
      metadataLabel: 'Hidroelectrica S.A. · SH Ramnicu Valcea',
      icon: Icons.bolt_rounded,
      accentColor: Color(0xFFFFB84D),
      statusTitle: 'Stare de funcționare',
      unavailableLabel: 'Necunoscut',
      statusLabel: 'Necunoscut',
      evidenceLabel: 'Stare neconfirmată',
      sourceLabel: 'Date operaționale indisponibile',
      freshnessLabel: 'Ora actualizării indisponibilă',
      unknownMessage: 'Stare necunoscută',
      relationshipLabel: 'Context hidro canonic',
      relationships: <HydroRelationshipItem>[
        HydroRelationshipItem(
          label: 'Sistem',
          title: 'Olt',
          typeLabel: 'Râu',
          icon: Icons.waves_rounded,
        ),
        HydroRelationshipItem(
          label: 'Asociat',
          title: 'Gura Lotrului',
          typeLabel: 'Baraj',
          icon: Icons.account_balance_rounded,
        ),
        HydroRelationshipItem(
          label: 'Asociată',
          title: 'Gura lotrului',
          typeLabel: 'Acumulare',
          icon: Icons.water_rounded,
        ),
      ],
    );
    await tester.pumpWidget(
      _HydroPanelEvidenceFrame(
        captureKey: captureKey,
        data: panelData,
        waterAvailable: false,
        alertAvailable: false,
        expanded: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gura Lotrului'), findsWidgets);
    expect(find.text('Olt'), findsWidgets);
    expect(find.text('Stare neconfirmată'), findsOne);
    expect(find.text('Inteligență hidrologică'), findsNothing);

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final directory = Directory('build/evidence/rc2_2b_10');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/che_gura_lotrului_canonical.png',
      ).writeAsBytes(byteData!.buffer.asUint8List());
    });
  });
}

class _HydroPanelEvidenceFrame extends StatelessWidget {
  const _HydroPanelEvidenceFrame({
    required this.captureKey,
    required this.data,
    required this.waterAvailable,
    required this.alertAvailable,
    this.expanded = false,
  });

  final GlobalKey captureKey;
  final HydroIntelligenceViewData data;
  final bool waterAvailable;
  final bool alertAvailable;
  final bool expanded;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('ro'),
    supportedLocales: const <Locale>[Locale('ro'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(fontFamily: 'Geist'),
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(
      key: captureKey,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const CustomPaint(painter: _HydroEvidenceMapPainter()),
            const Positioned(
              left: 16,
              top: 32,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xD90B1820),
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'HYDRO • ROMÂNIA',
                    style: TextStyle(
                      color: Color(0xFFEAF8FB),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: HydroIntelligencePanel(
                data: data,
                expanded: expanded,
                detailsLabel: 'Detalii',
                graphLabel: 'Vezi grafic',
                askLabel: 'Întreabă Fluvi',
                sourceLabel: 'Sursă',
                updatedLabel: 'Actualizat',
                onToggleExpanded: _noop,
                onClose: _noop,
                onWaterIntelligence: waterAvailable ? _noop : null,
                onDetails: _noop,
                onFavorite: _noop,
                onAlert: alertAvailable ? _noop : null,
                onCenter: _noop,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _noop() {}

Future<ByteData> _fontData(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

Future<void> _loadEvidenceFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(_fontData('assets/fonts/geist/Geist-Regular.ttf'))
    ..addFont(_fontData('assets/fonts/geist/Geist-Medium.ttf'))
    ..addFont(_fontData('assets/fonts/geist/Geist-Bold.ttf'))
    ..addFont(_fontData('assets/fonts/geist/Geist-Black.ttf'));
  await geist.load();

  var flutterRoot = File(Platform.resolvedExecutable).parent;
  File? materialIcons;
  for (var depth = 0; depth < 9; depth += 1) {
    final candidate = File(
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf',
    );
    if (candidate.existsSync()) {
      materialIcons = candidate;
      break;
    }
    flutterRoot = flutterRoot.parent;
  }
  if (materialIcons == null) {
    throw StateError('Material Icons font not found from Flutter SDK.');
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(_fontData(materialIcons.path))).load();
}

class _HydroEvidenceMapPainter extends CustomPainter {
  const _HydroEvidenceMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFF18322E), Color(0xFF0C222A)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final terrain = Paint()
      ..color = const Color(0xFF52735A).withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var offset = -120.0; offset < size.height; offset += 72) {
      canvas.drawArc(
        Rect.fromLTWH(-80, offset, size.width + 160, 180),
        .15,
        2.7,
        false,
        terrain,
      );
    }

    final river = Paint()
      ..color = const Color(0xFF55DCEB).withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    final path = Path()
      ..moveTo(size.width * .78, -20)
      ..cubicTo(
        size.width * .36,
        size.height * .22,
        size.width * .82,
        size.height * .39,
        size.width * .43,
        size.height * .58,
      )
      ..cubicTo(
        size.width * .22,
        size.height * .69,
        size.width * .56,
        size.height * .82,
        size.width * .18,
        size.height + 20,
      );
    canvas.drawPath(path, river);
  }

  @override
  bool shouldRepaint(covariant _HydroEvidenceMapPainter oldDelegate) => false;
}
