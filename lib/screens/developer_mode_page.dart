import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_client.dart';
import '../services/community_service.dart';
import '../services/fishing_score_service.dart';
import '../services/water_service.dart';
import '../services/weather_service.dart';

enum _HealthLevel { ok, warning, error }

class _HealthResult {
  const _HealthResult(this.level, this.message);
  final _HealthLevel level;
  final String message;
}

class DeveloperModePage extends StatefulWidget {
  const DeveloperModePage({super.key});

  @override
  State<DeveloperModePage> createState() => _DeveloperModePageState();
}

class _DeveloperModePageState extends State<DeveloperModePage> {
  final _results = <String, _HealthResult>{};
  final _logs = <String>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _runHealthCheck();
  }

  Future<void> _runHealthCheck() async {
    if (_running) return;
    setState(() => _running = true);
    final checks = <String, Future<void> Function()>{
      'Weather': () =>
          _check('Weather', () => WeatherService().getCurrentWeather()),
      'Water Level': () => _check(
        'Water Level',
        () => WaterService().getStations(forceRefresh: true),
      ),
      'Community': () => _check(
        'Community',
        () => const CommunityService().getActiveReports(),
      ),
      'AI': () => _check('AI', () => FishingScoreService().calculate()),
      'GPS': _checkGps,
      'Internet': () => _check(
        'Internet',
        () => const ApiClient().get(
          'https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0&current=temperature_2m',
        ),
      ),
      'Supabase': () => _check(
        'Supabase',
        () => Supabase.instance.client.from('profiles').select('id').limit(1),
      ),
      'Storage': () => _check(
        'Storage',
        () => Supabase.instance.client.storage.listBuckets(),
      ),
      'Camera': _checkCamera,
    };
    await Future.wait(checks.values.map((check) => check()));
    if (mounted) setState(() => _running = false);
  }

  Future<void> _check(String name, Future<Object?> Function() operation) async {
    try {
      await operation().timeout(const Duration(seconds: 15));
      _setResult(name, const _HealthResult(_HealthLevel.ok, 'Available'));
    } on Exception catch (error) {
      _setResult(name, _HealthResult(_HealthLevel.error, _shortError(error)));
    }
  }

  Future<void> _checkGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final denied =
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;
    _setResult(
      'GPS',
      !enabled || denied
          ? const _HealthResult(
              _HealthLevel.warning,
              'Disabled or permission missing',
            )
          : const _HealthResult(_HealthLevel.ok, 'Ready'),
    );
  }

  Future<void> _checkCamera() async {
    _setResult(
      'Camera',
      defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? const _HealthResult(
              _HealthLevel.warning,
              'Use Test Camera to verify',
            )
          : const _HealthResult(_HealthLevel.error, 'Unsupported platform'),
    );
  }

  void _setResult(String name, _HealthResult result) {
    _logs.insert(
      0,
      '${DateTime.now().toIso8601String()} $name: ${result.message}',
    );
    if (mounted) setState(() => _results[name] = result);
  }

  Future<void> _quickTest(String name, Future<Object?> Function() test) async {
    _setResult(name, const _HealthResult(_HealthLevel.warning, 'Testing…'));
    await _check(name, test);
  }

  Future<void> _testCamera() async {
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      _setResult(
        'Camera',
        photo == null
            ? const _HealthResult(_HealthLevel.warning, 'Camera cancelled')
            : const _HealthResult(_HealthLevel.ok, 'Capture succeeded'),
      );
    } on Exception catch (error) {
      _setResult(
        'Camera',
        _HealthResult(_HealthLevel.error, _shortError(error)),
      );
    }
  }

  void _showLogs() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Developer logs'),
        content: SizedBox(
          width: 560,
          child: SelectableText(
            _logs.isEmpty ? 'No logs yet.' : _logs.join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _clearCache() {
    WeatherService.clearCache();
    WaterService.clearCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _logs.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Weather, water, image cache and logs cleared.'),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Mode'),
        actions: [
          IconButton(
            tooltip: 'Health Check',
            onPressed: _running ? null : _runHealthCheck,
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _section('App Information', [
            _info(
              'App version',
              const String.fromEnvironment(
                'FLUTTER_BUILD_NAME',
                defaultValue: '1.0.0',
              ),
            ),
            _info(
              'Build mode',
              kReleaseMode
                  ? 'Release'
                  : kProfileMode
                  ? 'Profile'
                  : 'Debug',
            ),
            _info('Platform', defaultTargetPlatform.name),
          ]),
          _statusSection('API Status', [
            'Weather',
            'Water Level',
            'Community',
            'AI',
            'Supabase',
          ]),
          _section('Device', [
            _statusTile('GPS'),
            _statusTile('Internet'),
            _statusTile('Camera'),
            _info('Location permission', _permissionLabel),
          ]),
          _section('Database', [
            _statusTile('Supabase'),
            _info('Logged user', user?.email ?? 'Not logged in'),
            _statusTile('Storage'),
          ]),
          _section('Quick Tests', [
            _action(
              'Test Weather',
              () => _quickTest(
                'Weather',
                () => WeatherService().getCurrentWeather(),
              ),
            ),
            _action(
              'Test Water Level',
              () => _quickTest(
                'Water Level',
                () => WaterService().getStations(forceRefresh: true),
              ),
            ),
            _action(
              'Test Community',
              () => _quickTest(
                'Community',
                () => const CommunityService().getActiveReports(),
              ),
            ),
            _action('Test Camera', _testCamera),
            _action('Test Notifications', () async {
              _setResult(
                'Notifications',
                const _HealthResult(
                  _HealthLevel.warning,
                  'Notification provider not configured',
                ),
              );
            }),
          ]),
          _section('Debug', [
            _action('View logs', () async => _showLogs()),
            _action('Clear cache', () async => _clearCache()),
            _action('Reload data', _runHealthCheck),
          ]),
        ],
      ),
    );
  }

  String get _permissionLabel {
    final result = _results['GPS'];
    return result?.level == _HealthLevel.ok ? 'Granted' : 'Check required';
  }

  Widget _statusSection(String title, List<String> names) =>
      _section(title, names.map(_statusTile).toList());

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );

  Widget _statusTile(String name) {
    final result = _results[name];
    final level = result?.level;
    return ListTile(
      dense: true,
      leading: Text(switch (level) {
        _HealthLevel.ok => '🟢',
        _HealthLevel.warning => '🟡',
        _HealthLevel.error => '🔴',
        null => '⚪',
      }),
      title: Text(name),
      subtitle: Text(
        result?.message ?? (_running ? 'Checking…' : 'Not checked'),
      ),
    );
  }

  static Widget _info(String label, String value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: Flexible(child: Text(value, textAlign: TextAlign.end)),
  );

  static Widget _action(String label, Future<void> Function() action) =>
      ListTile(
        dense: true,
        title: Text(label),
        trailing: const Icon(Icons.play_arrow_rounded),
        onTap: action,
      );

  static String _shortError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.length > 90 ? '${text.substring(0, 87)}…' : text;
  }
}
