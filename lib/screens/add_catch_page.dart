import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../repositories/catch_repository.dart';
import '../services/location_service.dart';

enum _LocationPrivacy {
  exact('Exact location'),
  approximate('Approximate location'),
  hidden('Hidden location');

  const _LocationPrivacy(this.label);
  final String label;
}

enum _WaterType {
  river('River'),
  lake('Lake'),
  reservoir('Reservoir'),
  canal('Canal'),
  danube('Danube'),
  other('Other');

  const _WaterType(this.label);
  final String label;
}

enum _WeightUnit {
  grams('g'),
  kilograms('kg');

  const _WeightUnit(this.label);
  final String label;
}

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
  final _placeNameController = TextEditingController();
  final _picker = ImagePicker();
  final _locationService = const LocationService();
  final _catchRepository = const CatchRepository();

  XFile? _image;
  Position? _position;
  String? _submissionError;
  bool _isSubmitting = false;
  _LocationPrivacy _locationPrivacy = _LocationPrivacy.exact;
  _WaterType _waterType = _WaterType.river;
  _WeightUnit _weightUnit = _WeightUnit.kilograms;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _notesController.dispose();
    _placeNameController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final position = await _locationService.determinePosition();
      if (!mounted) return;
      setState(() => _position = position);
    } on LocationFailure {
      // Manual place name remains available when GPS cannot be obtained.
    }
  }

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
    final placeName = _placeNameController.text.trim();
    if (_position == null && placeName.isEmpty) {
      setState(
        () =>
            _submissionError = 'Use GPS or enter a place name for this catch.',
      );
      return;
    }

    final position = _position;
    final latitude = switch (_locationPrivacy) {
      _LocationPrivacy.exact => position?.latitude,
      _LocationPrivacy.approximate =>
        position == null ? null : (position.latitude * 100).round() / 100,
      _LocationPrivacy.hidden => null,
    };
    final longitude = switch (_locationPrivacy) {
      _LocationPrivacy.exact => position?.longitude,
      _LocationPrivacy.approximate =>
        position == null ? null : (position.longitude * 100).round() / 100,
      _LocationPrivacy.hidden => null,
    };

    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });
    try {
      await _catchRepository.createCatch(
        imagePath: _image!.path,
        species: _speciesController.text,
        weightKg: _normalizedWeightKg(_weightController.text),
        lengthCm: _optionalNumber(_lengthController.text),
        notes: _notesController.text,
        latitude: latitude,
        longitude: longitude,
        placeName: placeName.isEmpty ? null : placeName,
        waterType: _waterType.name,
        locationPrivacy: _locationPrivacy.name,
        stationId: null,
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

  String? _optionalPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.replaceAll(',', '.'));
    return number == null || number <= 0 ? 'Enter a value above 0' : null;
  }

  double? _normalizedWeightKg(String value) {
    final amount = _optionalNumber(value);
    if (amount == null) return null;
    return _weightUnit == _WeightUnit.grams ? amount / 1000 : amount;
  }

  double? _optionalNumber(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.replaceAll(',', '.'));
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
        appBar: AppBar(title: Text(context.l10n.addCatch)),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.species,
                    prefixIcon: Icon(Icons.set_meal_outlined),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _weightController,
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: context.l10n.weight),
                  validator: _optionalPositiveNumber,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_WeightUnit>(
                  initialValue: _weightUnit,
                  decoration: InputDecoration(
                    labelText: context.l10n.weightUnit,
                  ),
                  items: _WeightUnit.values
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(unit.label),
                        ),
                      )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _weightUnit = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lengthController,
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: context.l10n.lengthCm),
                  validator: _optionalPositiveNumber,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: context.l10n.notes,
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _placeNameController,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: context.l10n.placeNameOptional,
                    hintText: context.l10n.placeHint,
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_WaterType>(
                  initialValue: _waterType,
                  decoration: InputDecoration(
                    labelText: context.l10n.waterType,
                    prefixIcon: Icon(Icons.water_outlined),
                  ),
                  items: _WaterType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _waterType = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_LocationPrivacy>(
                  initialValue: _locationPrivacy,
                  decoration: InputDecoration(
                    labelText: context.l10n.locationPrivacy,
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                  items: _LocationPrivacy.values
                      .map(
                        (privacy) => DropdownMenuItem(
                          value: privacy,
                          child: Text(privacy.label),
                        ),
                      )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _locationPrivacy = value!),
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
            label: Text(context.l10n.camera),
          ),
        ),
      ],
    );
  }
}
