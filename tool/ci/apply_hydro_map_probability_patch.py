from pathlib import Path

MAP = Path('lib/screens/map_page.dart')
PANEL = Path('lib/widgets/fluviai/hydro_intelligence_panel.dart')
SERVICE = Path('lib/services/hydro_dispatch_service.dart')
PRESENTATION = Path('lib/features/hydro_dispatch/presentation/hydro_dispatch_presentation.dart')
TEST = Path('test/hydro_dispatch_mobile_contract_test.dart')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'ABORT {label}: expected exactly 1 match, got {count}')
    return text.replace(old, new, 1)


def patch_service(text: str) -> str:
    if 'class HydroMapDispatchSnapshot' not in text:
        marker = 'class HydroDispatchDayForecast {'
        safe_model = '''class HydroMapDispatchSnapshot {
  const HydroMapDispatchSnapshot({
    required this.plantId,
    required this.name,
    required this.availabilityStatus,
    required this.confidence,
    required this.evidenceClass,
    required this.observedState,
    required this.observedFreshness,
    required this.observedReportCount,
    this.damId,
    this.reservoirId,
    this.windowStart,
    this.windowEnd,
    this.windowProbability,
    this.peakProbability,
    this.updatedAt,
    this.observedConfidence,
  });

  factory HydroMapDispatchSnapshot.fromJson(Map<String, dynamic> json) =>
      HydroMapDispatchSnapshot(
        plantId: json['plant_id']?.toString() ?? '',
        damId: _text(json['dam_id']),
        reservoirId: _text(json['reservoir_id']),
        name: json['name']?.toString() ?? '',
        availabilityStatus:
            json['availability_status']?.toString() ?? 'UNAVAILABLE',
        windowStart: _dateTime(json['window_start']),
        windowEnd: _dateTime(json['window_end']),
        windowProbability: _double(json['window_probability']),
        peakProbability: _double(json['peak_probability']),
        confidence: json['confidence']?.toString() ?? 'unknown',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        updatedAt: _dateTime(json['updated_at']),
        observedState: json['observed_state']?.toString() ?? 'unknown',
        observedConfidence: _double(json['observed_confidence']),
        observedFreshness:
            json['observed_freshness']?.toString() ?? 'unavailable',
        observedReportCount: _int(json['observed_report_count']) ?? 0,
      );

  final String plantId;
  final String? damId;
  final String? reservoirId;
  final String name;
  final String availabilityStatus;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double? windowProbability;
  final double? peakProbability;
  final String confidence;
  final String evidenceClass;
  final DateTime? updatedAt;
  final String observedState;
  final double? observedConfidence;
  final String observedFreshness;
  final int observedReportCount;

  bool get isAvailable =>
      availabilityStatus == 'AVAILABLE' &&
      windowStart != null &&
      windowEnd != null &&
      windowProbability != null;
}

'''
        text = replace_once(text, marker, safe_model + marker, 'safe map snapshot model')

    method_marker = '  Future<List<HydroDispatchDayForecast>> getTodayTomorrow(String plantId) =>\n'
    if 'getMapDispatchSnapshot' not in text:
        method = '''  Future<HydroMapDispatchSnapshot?> getMapDispatchSnapshot(
    String plantId,
  ) => _guard(() async {
    final response = await _supabase.rpc('get_hydro_map_dispatch_overlay_v1');
    if (response is! List) return null;
    for (final row in response.whereType<Map>()) {
      final snapshot = HydroMapDispatchSnapshot.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (snapshot.plantId == plantId) return snapshot;
    }
    return null;
  });

'''
        text = replace_once(
            text,
            method_marker,
            method + method_marker,
            'safe map snapshot service method',
        )
    return text


def patch_presentation(text: str) -> str:
    if 'HydroDispatchPresentation.mapSnapshot' in text:
        return text
    marker = '  static String aiExplanation(\n'
    method = '''  static HydroDispatchDayPresentation mapSnapshot(
    HydroMapDispatchSnapshot? snapshot, {
    required bool isRomanian,
  }) {
    if (snapshot == null || !snapshot.isAvailable) {
      return HydroDispatchDayPresentation(
        dayLabel: isRomanian ? 'Azi' : 'Today',
        statusLabel: isRomanian ? 'Date indisponibile' : 'Data unavailable',
        probabilityLabel: '—',
        windowLabel: '—',
        evidenceLabel: snapshot?.evidenceClass ?? 'UNKNOWN',
        confidenceLabel: _confidence(
          snapshot?.confidence ?? 'unknown',
          isRomanian,
        ),
        available: false,
      );
    }
    return HydroDispatchDayPresentation(
      dayLabel: isRomanian ? 'Azi' : 'Today',
      statusLabel: isRomanian
          ? 'Probabilitate uzinare'
          : 'Generation probability',
      probabilityLabel: _percent(snapshot.windowProbability),
      windowLabel:
          '${_romaniaTime(snapshot.windowStart)}–${_romaniaTime(snapshot.windowEnd)}',
      evidenceLabel: snapshot.evidenceClass,
      confidenceLabel: _confidence(snapshot.confidence, isRomanian),
      available: true,
    );
  }

'''
    text = replace_once(text, marker, method + marker, 'map snapshot presentation')
    return text


def patch_panel(text: str) -> str:
    if 'forecastProbabilityLabel' not in text:
        text = replace_once(
            text,
            '    this.contextLabel,\n    this.metadataLabel,\n    this.statusColor,',
            '    this.contextLabel,\n    this.metadataLabel,\n    this.forecastProbabilityLabel,\n    this.forecastWindowLabel,\n    this.forecastConfidenceLabel,\n    this.forecastEvidenceLabel,\n    this.statusColor,',
            'panel constructor forecast fields',
        )
        text = replace_once(
            text,
            '  final String? contextLabel;\n  final String? metadataLabel;\n  final IconData icon;',
            '  final String? contextLabel;\n  final String? metadataLabel;\n  final String? forecastProbabilityLabel;\n  final String? forecastWindowLabel;\n  final String? forecastConfidenceLabel;\n  final String? forecastEvidenceLabel;\n  final IconData icon;',
            'panel forecast fields',
        )
        old = '''                    _OperationalSummary(
                      sectionTitle: isRomanian
                          ? 'CE ȘTIM ACUM'
                          : 'WHAT WE KNOW NOW',
                      title: data.statusTitle,
                      status: data.statusLabel,
                      unavailableLabel: data.unavailableLabel,
                      available: data.hasOperationalStatus,
                      color: effectiveStatusColor,
                    ),
                    if (data.evidenceLabel?.isNotEmpty == true ||'''
        new = '''                    _OperationalSummary(
                      sectionTitle: isRomanian
                          ? 'CE ȘTIM ACUM'
                          : 'WHAT WE KNOW NOW',
                      title: data.statusTitle,
                      status: data.statusLabel,
                      unavailableLabel: data.unavailableLabel,
                      available: data.hasOperationalStatus,
                      color: effectiveStatusColor,
                    ),
                    if (data.forecastProbabilityLabel?.isNotEmpty == true &&
                        data.forecastWindowLabel?.isNotEmpty == true) ...<Widget>[
                      const SizedBox(height: 8),
                      _DispatchForecastSummary(
                        probability: data.forecastProbabilityLabel!,
                        window: data.forecastWindowLabel!,
                        confidence: data.forecastConfidenceLabel,
                        evidence: data.forecastEvidenceLabel,
                        color: data.accentColor,
                      ),
                    ],
                    if (data.evidenceLabel?.isNotEmpty == true ||'''
        text = replace_once(text, old, new, 'panel forecast position')

    if 'class _DispatchForecastSummary' not in text:
        marker = 'class _OperationalSummary extends StatelessWidget {'
        widget = '''class _DispatchForecastSummary extends StatelessWidget {
  const _DispatchForecastSummary({
    required this.probability,
    required this.window,
    required this.color,
    this.confidence,
    this.evidence,
  });

  final String probability;
  final String window;
  final String? confidence;
  final String? evidence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return Container(
      key: const ValueKey('hydro-panel-dispatch-summary'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            color.withValues(alpha: .16),
            const Color(0xFF0A1920).withValues(alpha: .96),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isRomanian
                      ? 'PROBABILITATE DE UZINARE'
                      : 'GENERATION PROBABILITY',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
              ),
              if (evidence?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color.withValues(alpha: .35)),
                  ),
                  child: Text(
                    evidence!,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                probability,
                style: const TextStyle(
                  color: Color(0xFFF6FBFD),
                  fontSize: 29,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    isRomanian ? 'Interval estimat' : 'Estimated window',
                    style: const TextStyle(
                      color: Color(0xFF91A8B5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    window,
                    style: const TextStyle(
                      color: Color(0xFFF6FBFD),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (confidence?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              confidence!,
              style: const TextStyle(
                color: Color(0xFF9FB4BE),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

'''
        text = replace_once(text, marker, widget + marker, 'forecast widget')
    return text


def patch_map(text: str) -> str:
    if '_previewHydroDispatchSnapshot' in text:
        return text
    text = replace_once(
        text,
        "import '../core/water/water_history_analysis.dart';\nimport '../l10n/l10n.dart';",
        "import '../core/water/water_history_analysis.dart';\nimport '../features/hydro_dispatch/presentation/hydro_dispatch_presentation.dart';\nimport '../l10n/l10n.dart';",
        'map presentation import',
    )
    text = replace_once(
        text,
        "import '../services/favorite_stations_service.dart';\nimport '../services/location_service.dart';",
        "import '../services/favorite_stations_service.dart';\nimport '../services/hydro_dispatch_service.dart';\nimport '../services/location_service.dart';",
        'map service import',
    )
    text = replace_once(
        text,
        '  final WaterAssetService _waterAssetService = const WaterAssetService();\n  final SavedItemsService _savedItemsService = const SavedItemsService();',
        '  final WaterAssetService _waterAssetService = const WaterAssetService();\n  final HydroDispatchService _hydroDispatchService =\n      const HydroDispatchService();\n  final SavedItemsService _savedItemsService = const SavedItemsService();',
        'map service field',
    )
    text = replace_once(
        text,
        '  WaterMapPin? _previewHydropowerPin;\n  HydropowerPlantState? _previewHydropowerState;\n  HydroOverlayPreferences _hydroPreferences = const HydroOverlayPreferences();',
        '  WaterMapPin? _previewHydropowerPin;\n  HydropowerPlantState? _previewHydropowerState;\n  HydroMapDispatchSnapshot? _previewHydroDispatchSnapshot;\n  HydroOverlayPreferences _hydroPreferences = const HydroOverlayPreferences();',
        'map snapshot state',
    )
    text = replace_once(
        text,
        '      _previewHydropowerPin = selected;\n      _previewHydropowerState = null;\n      _isLoadingHydroSelection = true;',
        '      _previewHydropowerPin = selected;\n      _previewHydropowerState = null;\n      _previewHydroDispatchSnapshot = null;\n      _isLoadingHydroSelection = true;',
        'map clear snapshot on tap',
    )

    old_refresh = '''  Future<void> _refreshHydropowerPreview(WaterMapPin pin) async {
    try {
      final state = await _waterAssetService.getHydropowerPlantState(
        pin.entityId,
      );
      if (!mounted || _previewHydropowerPin?.entityId != pin.entityId) return;
      setState(() => _previewHydropowerState = state);
      if (state != null) {
        ref
            .read(selectedContextProvider.notifier)
            .select(
              SelectedContext(
                countryCode: state.countryCode ?? pin.countryCode,
                locationName: state.name,
                latitude: state.latitude ?? pin.latitude,
                longitude: state.longitude ?? pin.longitude,
                waterId: state.waterBodyId ?? pin.waterBodyId,
                waterName: pin.riverName,
                riverName: pin.riverName,
                damId: state.damId,
                reservoirId: state.reservoirId,
                hydropowerPlantId: state.plantId,
                source: state.evidenceSource,
                observedAt: state.evidenceObservedAt,
              ),
            );
      }
    } on Exception {
      // The map-pin state remains the truthful fallback when detail refresh fails.
    } finally {
      if (mounted && _previewHydropowerPin?.entityId == pin.entityId) {
        setState(() => _isLoadingHydroSelection = false);
      }
    }
  }
'''
    new_refresh = '''  Future<void> _refreshHydropowerPreview(WaterMapPin pin) async {
    HydroMapDispatchSnapshot? snapshot;
    try {
      snapshot = await _hydroDispatchService.getMapDispatchSnapshot(
        pin.entityId,
      );
    } on Exception {
      // Forecast is optional. The canonical map pin remains independently valid.
    }
    if (!mounted || _previewHydropowerPin?.entityId != pin.entityId) return;
    setState(() {
      _previewHydroDispatchSnapshot = snapshot;
      _isLoadingHydroSelection = false;
    });
    ref
        .read(selectedContextProvider.notifier)
        .select(
          SelectedContext(
            countryCode: pin.countryCode,
            locationName: pin.name,
            latitude: pin.latitude,
            longitude: pin.longitude,
            waterId: pin.waterBodyId,
            waterName: pin.riverName,
            riverName: pin.riverName,
            damId: snapshot?.damId,
            reservoirId: snapshot?.reservoirId,
            hydropowerPlantId: pin.entityId,
            source: pin.stateSource,
            observedAt: snapshot?.updatedAt,
          ),
        );
  }
'''
    text = replace_once(text, old_refresh, new_refresh, 'safe map preview refresh')

    text = replace_once(
        text,
        '      final evidenceClass = state?.evidenceClass ?? plant.evidenceClass;\n      final hasOperationalEvidence =',
        '      final evidenceClass = state?.evidenceClass ?? plant.evidenceClass;\n      final dispatch = _previewHydroDispatchSnapshot;\n      final dispatchPresentation = HydroDispatchPresentation.mapSnapshot(\n        dispatch,\n        isRomanian: isRomanian,\n      );\n      final hasDispatchForecast = dispatch?.isAvailable == true;\n      final hasOperationalEvidence =',
        'map forecast presentation',
    )

    old_mw = '''        if (state?.installedPowerMw case final power?)
          HydroIntelligenceDatum(
            label: isRomanian ? 'Putere instalată' : 'Installed capacity',
            value: '${_formatMetricValue(power)} MW',
            icon: Icons.bolt_rounded,
          ),
'''
    text = replace_once(text, old_mw, '', 'remove map MW tile')

    text = replace_once(
        text,
        "        accentColor: MapFeatureRegistry.hydropower,\n        statusTitle: isRomanian ? 'Stare de funcționare' : 'Operating status',",
        "        accentColor: MapFeatureRegistry.hydropower,\n        forecastProbabilityLabel: hasDispatchForecast\n            ? dispatchPresentation.probabilityLabel\n            : null,\n        forecastWindowLabel: hasDispatchForecast\n            ? dispatchPresentation.windowLabel\n            : null,\n        forecastConfidenceLabel: hasDispatchForecast\n            ? dispatchPresentation.confidenceLabel\n            : null,\n        forecastEvidenceLabel: hasDispatchForecast\n            ? dispatchPresentation.evidenceLabel\n            : null,\n        statusTitle: isRomanian ? 'Stare de funcționare' : 'Operating status',",
        'map forecast panel fields',
    )

    text = replace_once(
        text,
        '          _previewHydropowerPin = focusedHydropower;\n          _previewHydropowerState = focusedHydropowerState;\n          _isLoadingHydroSelection = focusedHydropowerState == null;',
        '          _previewHydropowerPin = focusedHydropower;\n          _previewHydropowerState = focusedHydropowerState;\n          _previewHydroDispatchSnapshot = null;\n          _isLoadingHydroSelection = true;',
        'map focused snapshot reset',
    )
    text = replace_once(
        text,
        "      if (focusedHydropower != null) {\n        _publishHydropowerContext(focusedHydropower);\n        if (focusedHydropowerState == null) {\n          unawaited(_refreshHydropowerPreview(focusedHydropower));\n        }\n      }",
        "      if (focusedHydropower != null) {\n        _publishHydropowerContext(focusedHydropower);\n        unawaited(_refreshHydropowerPreview(focusedHydropower));\n      }",
        'map focused snapshot load',
    )
    return text


def patch_test(text: str) -> str:
    if not text.startswith("import 'dart:io';"):
        text = "import 'dart:io';\n\n" + text
    if "hydro_intelligence_panel.dart" not in text:
        text = replace_once(
            text,
            "import 'package:fishtrack/features/hydro_dispatch/presentation/hydro_dispatch_presentation.dart';\n",
            "import 'package:fishtrack/features/hydro_dispatch/presentation/hydro_dispatch_presentation.dart';\nimport 'package:fishtrack/widgets/fluviai/hydro_intelligence_panel.dart';\n",
            'test panel import',
        )
    if "package:flutter/material.dart" not in text:
        text = replace_once(
            text,
            "import 'package:fishtrack/services/saved_items_service.dart';\nimport 'package:flutter_test/flutter_test.dart';",
            "import 'package:fishtrack/services/saved_items_service.dart';\nimport 'package:flutter/material.dart';\nimport 'package:flutter_test/flutter_test.dart';",
            'test material import',
        )

    name = "Hydro Map safe snapshot preserves forecast truth"
    if name not in text:
        block = '''
    test('Hydro Map safe snapshot preserves forecast truth', () {
      final snapshot = HydroMapDispatchSnapshot.fromJson(<String, dynamic>{
        'plant_id': '11111111-1111-1111-1111-111111111111',
        'dam_id': '22222222-2222-2222-2222-222222222222',
        'reservoir_id': '33333333-3333-3333-3333-333333333333',
        'name': 'Frunzaru',
        'availability_status': 'AVAILABLE',
        'window_start': '2026-08-21T15:15:00Z',
        'window_end': '2026-08-21T20:45:00Z',
        'window_probability': 0.742,
        'peak_probability': 0.801,
        'confidence': 'medium',
        'evidence_class': 'ESTIMATED',
        'updated_at': '2026-08-21T11:00:00Z',
        'observed_state': 'unknown',
        'observed_freshness': 'unavailable',
        'observed_report_count': 0,
        'model_version': 'must-not-be-needed-by-map',
        'installed_power_mw': 99.9,
        'market_price': 123.45,
      });

      expect(snapshot.isAvailable, isTrue);
      expect(snapshot.windowProbability, closeTo(.742, .000001));
      expect(snapshot.damId, '22222222-2222-2222-2222-222222222222');
      final view = HydroDispatchPresentation.mapSnapshot(
        snapshot,
        isRomanian: true,
      );
      expect(view.probabilityLabel, '74.2%');
      expect(view.windowLabel, '18:15–23:45');
      expect(view.evidenceLabel, 'ESTIMATED');
      expect(view.confidenceLabel, 'încredere moderată');
    });

    testWidgets('Hydro panel surfaces forecast before expansion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ro'),
          home: Scaffold(
            body: HydroIntelligencePanel(
              data: const HydroIntelligenceViewData(
                name: 'Frunzaru',
                typeLabel: 'Baraj',
                icon: Icons.bolt_rounded,
                accentColor: Color(0xFF12D8D6),
                statusLabel: 'Necunoscut',
                statusTitle: 'Stare de funcționare',
                unavailableLabel: 'Indisponibil',
                unknownMessage: 'Necunoscut',
                forecastProbabilityLabel: '74.2%',
                forecastWindowLabel: '18:15–23:45',
                forecastConfidenceLabel: 'încredere moderată',
                forecastEvidenceLabel: 'ESTIMATED',
              ),
              expanded: false,
              detailsLabel: 'Detalii',
              graphLabel: 'Grafic',
              askLabel: 'Întreabă Fluvi',
              sourceLabel: 'Sursă',
              updatedLabel: 'Actualizat',
              onToggleExpanded: _noop,
              onClose: _noop,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('hydro-panel-dispatch-summary')), findsOneWidget);
      expect(find.text('PROBABILITATE DE UZINARE'), findsOneWidget);
      expect(find.text('74.2%'), findsOneWidget);
      expect(find.text('18:15–23:45'), findsOneWidget);
      expect(find.text('ESTIMATED'), findsOneWidget);
    });

    test('Hydro Map mini-card does not request or render installed MW', () {
      final source = File('lib/screens/map_page.dart').readAsStringSync();
      expect(source, contains('getMapDispatchSnapshot'));
      expect(source, isNot(contains('state?.installedPowerMw')));
      expect(source, isNot(contains("label: isRomanian ? 'Putere instalată'")));
    });
'''
        end = '  });\n}\n'
        if not text.endswith(end):
            raise SystemExit('ABORT tests: unexpected group ending')
        text = text[:-len(end)] + block + end

    if 'void _noop() {}' not in text:
        text += '\nvoid _noop() {}\n'
    return text


files = {
    SERVICE: patch_service(SERVICE.read_text(encoding='utf-8')),
    PRESENTATION: patch_presentation(PRESENTATION.read_text(encoding='utf-8')),
    PANEL: patch_panel(PANEL.read_text(encoding='utf-8')),
    MAP: patch_map(MAP.read_text(encoding='utf-8')),
    TEST: patch_test(TEST.read_text(encoding='utf-8')),
}

for path, content in files.items():
    path.write_text(content, encoding='utf-8')

print('Hydro Map probability patch applied safely.')
