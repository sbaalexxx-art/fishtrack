import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/station.dart';
import '../repositories/catch_repository.dart';
import '../services/location_service.dart';
import '../services/water_service.dart';

class AddCatchPage extends StatefulWidget {
  const AddCatchPage({super.key});

  @override
  State<AddCatchPage> createState() => _AddCatchPageState();
}

class _AddCatchPageState extends State<AddCatchPage> {
  final _formKey = GlobalKey<FormState>();
  final _speciesController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _notesController = TextEditingController();
  final _picker = ImagePicker();
  final _locationService = const LocationService();
  final _waterService = WaterService();
  final _catchRepository = const CatchRepository();

  late final Future<List<Station>> _stationsFuture;
  XFile? _image;
  Position? _position;
  Station? _station;
  String? _locationError;
  String? _submissionError;
  bool _isLocating = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _stationsFuture = _loadStations();
    _loadLocation();
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<List<Station>> _loadStations() async {
    final stations = await _waterService.getStations();
    if (stations.isNotEmpty && mounted) {
      final selected = _waterService.selectedStation;
      setState(() {
        _station = selected == null
            ? stations.first
            : stations.cast<Station?>().firstWhere(
                (station) => station?.id == selected.id,
                orElse: () => stations.first,
              );
      });
    }
    return stations;
  }

  Future<void> _loadLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });
    try {
      final position = await _locationService.determinePosition();
      if (!mounted) return;
      setState(() => _position = position);
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() => _locationError = _locationMessage(failure.reason));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  String _locationMessage(LocationFailureReason reason) => switch (reason) {
    LocationFailureReason.serviceDisabled =>
      'Turn on location services to attach GPS coordinates.',
    LocationFailureReason.permissionDenied =>
      'Location permission is required to save a catch.',
    LocationFailureReason.permissionDeniedForever =>
      'Enable location permission in system settings, then retry.',
    LocationFailureReason.unavailable =>
      'Your current location is unavailable. Please retry.',
  };

  Future<void> _takePhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (image != null && mounted) setState(() => _image = image);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The photo could not be captured.')),
      );
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_image == null) {
      setState(() => _submissionError = 'Take a photo with the camera.');
      return;
    }
    if (_station == null) {
      setState(() => _submissionError = 'Select a fishing station.');
      return;
    }
    if (_position == null) {
      setState(() => _submissionError = _locationError ?? 'GPS is not ready.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });
    try {
      await _catchRepository.createCatch(
        imagePath: _image!.path,
        species: _speciesController.text,
        weight: double.parse(_weightController.text.replaceAll(',', '.')),
        length: double.parse(_lengthController.text.replaceAll(',', '.')),
        notes: _notesController.text,
        latitude: _position!.latitude,
        longitude: _position!.longitude,
        stationId: _station!.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catch saved successfully.')),
      );
      Navigator.of(context).pop(true);
    } on CatchSubmissionException catch (error) {
      if (mounted) setState(() => _submissionError = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _positiveNumber(String? value) {
    final number = double.tryParse((value ?? '').replaceAll(',', '.'));
    return number == null || number <= 0 ? 'Enter a value above 0' : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Theme(
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12D8D6),
          brightness: theme.brightness,
        ),
        scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
        appBarTheme: AppBarTheme(
          backgroundColor: theme.scaffoldBackgroundColor,
          foregroundColor: scheme.onSurface,
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          labelStyle: TextStyle(color: scheme.onSurfaceVariant),
          prefixIconColor: scheme.onSurfaceVariant,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: scheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF12D8D6), width: 2),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Catch')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _PhotoPicker(
                  image: _image,
                  enabled: !_isSubmitting,
                  onCamera: _takePhoto,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _speciesController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Species',
                    prefixIcon: Icon(Icons.set_meal_outlined),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _weightController,
                        enabled: !_isSubmitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Weight (kg)',
                        ),
                        validator: _positiveNumber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lengthController,
                        enabled: !_isSubmitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Length (cm)',
                        ),
                        validator: _positiveNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Station>>(
                  future: _stationsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
                      return const ListTile(
                        leading: Icon(Icons.error_outline),
                        title: Text('Fishing stations are unavailable.'),
                      );
                    }
                    return DropdownButtonFormField<Station>(
                      initialValue: _station,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Station',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      items: snapshot.data!
                          .map(
                            (station) => DropdownMenuItem(
                              value: station,
                              child: Text(
                                station.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isSubmitting
                          ? null
                          : (station) => setState(() => _station = station),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _isLocating
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _position == null
                              ? Icons.gps_off_rounded
                              : Icons.gps_fixed_rounded,
                        ),
                  title: Text(
                    _isLocating
                        ? 'Getting GPS coordinates…'
                        : _position == null
                        ? (_locationError ?? 'Location unavailable')
                        : '${_position!.latitude.toStringAsFixed(5)}, '
                              '${_position!.longitude.toStringAsFixed(5)}',
                  ),
                  trailing: !_isLocating && _position == null
                      ? TextButton(
                          onPressed: _loadLocation,
                          child: const Text('Retry'),
                        )
                      : null,
                ),
                if (_submissionError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _submissionError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_isSubmitting ? 'Saving catch…' : 'Save Catch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.image,
    required this.enabled,
    required this.onCamera,
  });

  final XFile? image;
  final bool enabled;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: image == null
                  ? const Center(
                      child: Icon(Icons.add_a_photo_outlined, size: 42),
                    )
                  : Image.file(File(image!.path), fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: enabled ? onCamera : null,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Camera'),
          ),
        ),
      ],
    );
  }
}
