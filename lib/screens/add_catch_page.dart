import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../core/map/map_feature_registry.dart';
import '../l10n/l10n.dart';
import '../repositories/catch_repository.dart';
import '../services/location_service.dart';
import '../services/european_freshwater_species_catalog.dart';
import '../services/photo_quality_service.dart';

enum _LocationPrivacy { exact, approximate, hidden }

enum _WaterType { river, lake, reservoir, canal, danube, other }

enum _WeightUnit {
  grams('gr'),
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
  final _photoQualityService = const PhotoQualityService();

  XFile? _image;
  PhotoQualityResult? _photoQuality;
  bool _isAnalyzingPhoto = false;
  Position? _position;
  String? _submissionError;
  bool _isSubmitting = false;
  bool _isLocating = true;
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
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (image != null && mounted) {
        setState(() {
          _image = image;
          _photoQuality = null;
          _isAnalyzingPhoto = true;
          _submissionError = null;
        });
        try {
          final quality = await _photoQualityService.analyzeFile(image.path);
          if (!mounted || _image?.path != image.path) return;
          setState(() => _photoQuality = quality);
        } on Exception {
          // The photo remains usable. Quality analysis is an aid and must not
          // block a real catch submission when decoding fails.
        } finally {
          if (mounted && _image?.path == image.path) {
            setState(() => _isAnalyzingPhoto = false);
          }
        }
      }
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.photoCaptureFailed)));
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_image == null) {
      setState(() => _submissionError = context.l10n.cameraPhotoRequired);
      return;
    }

    final placeName = _placeNameController.text.trim();
    if (_position == null && placeName.isEmpty) {
      setState(() => _submissionError = context.l10n.catchLocationRequired);
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
      final taxonomy = EuropeanFreshwaterSpeciesCatalog.match(
        _speciesController.text,
        languageCode: Localizations.localeOf(context).languageCode,
      );
      await _catchRepository.createCatch(
        imagePath: _image!.path,
        species: taxonomy?.displayName ?? _speciesController.text.trim(),
        speciesScientific: taxonomy?.scientificName,
        speciesSource: taxonomy == null ? 'manual' : 'manual_taxonomy',
        speciesUserConfirmed: true,
        weightKg: _normalizedWeightKg(_weightController.text),
        lengthCm: _optionalNumber(_lengthController.text),
        notes: _notesController.text.trim(),
        latitude: latitude,
        longitude: longitude,
        placeName: placeName.isEmpty ? null : placeName,
        waterType: _waterType.name,
        locationPrivacy: _locationPrivacy.name,
        stationId: null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.catchSaved)));
      Navigator.of(context).pop(true);
    } on CatchSubmissionException catch (error) {
      if (mounted) setState(() => _submissionError = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _requiredText(String? value) =>
      value == null || value.trim().isEmpty ? context.l10n.requiredField : null;

  String? _optionalPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.replaceAll(',', '.'));
    return number == null || number <= 0
        ? context.l10n.positiveValueRequired
        : null;
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

  String _waterTypeLabel(BuildContext context, _WaterType type) =>
      switch (type) {
        _WaterType.river => context.l10n.river,
        _WaterType.lake => context.l10n.lake,
        _WaterType.reservoir => context.l10n.reservoir,
        _WaterType.canal => context.l10n.canal,
        _WaterType.danube => context.l10n.danube,
        _WaterType.other => context.l10n.other,
      };

  String _privacyLabel(BuildContext context, _LocationPrivacy privacy) =>
      switch (privacy) {
        _LocationPrivacy.exact => context.l10n.exactLocation,
        _LocationPrivacy.approximate => context.l10n.approximateLocation,
        _LocationPrivacy.hidden => context.l10n.hiddenLocation,
      };

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final isDark = baseTheme.brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF12D8D6),
      brightness: baseTheme.brightness,
    );
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final catchPresentation = MapFeatureRegistry.forFeature(
      MapFeatureType.catchEntry,
      context.l10n,
    );
    final photoPresentation = MapFeatureRegistry.forFeature(
      MapFeatureType.photo,
      context.l10n,
    );
    final placePresentation = MapFeatureRegistry.forFeature(
      MapFeatureType.fishingPlace,
      context.l10n,
    );

    final pageTheme = baseTheme.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: baseTheme.scaffoldBackgroundColor,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: baseTheme.scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF151D24)
            : colorScheme.surfaceContainerLowest,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: .72),
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .72),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .42),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF12D8D6), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 1.8),
        ),
      ),
    );

    return Theme(
      data: pageTheme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.l10n.addCatch,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _PhotoPicker(
                  image: _image,
                  enabled: !_isSubmitting,
                  onCamera: _takePhoto,
                  accentColor: photoPresentation.color,
                  icon: photoPresentation.icon,
                  isRomanian: isRomanian,
                ),
                if (_image != null) ...[
                  const SizedBox(height: 10),
                  _SpeciesRecognitionState(
                    isRomanian: isRomanian,
                    quality: _photoQuality,
                    isAnalyzing: _isAnalyzingPhoto,
                  ),
                ],
                const SizedBox(height: 16),
                _SectionCard(
                  icon: catchPresentation.icon,
                  accentColor: catchPresentation.color,
                  title: isRomanian ? 'Detalii captură' : 'Catch details',
                  subtitle: isRomanian
                      ? 'Specia este obligatorie. Măsurătorile sunt opționale.'
                      : 'Species is required. Measurements are optional.',
                  children: [
                    TextFormField(
                      controller: _speciesController,
                      enabled: !_isSubmitting,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.l10n.species,
                        prefixIcon: const Icon(Icons.set_meal_outlined),
                        suffixIcon: const _RequiredFieldMark(),
                      ),
                      validator: _requiredText,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _weightController,
                                enabled: !_isSubmitting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: isRomanian
                                      ? 'Greutate (opțional)'
                                      : 'Weight (optional)',
                                  hintText: _weightUnit == _WeightUnit.grams
                                      ? '850'
                                      : '2,35',
                                  prefixIcon: const Icon(Icons.scale_outlined),
                                ),
                                validator: _optionalPositiveNumber,
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: constraints.maxWidth < 340 ? 96 : 108,
                              child: _WeightUnitSelector(
                                value: _weightUnit,
                                enabled: !_isSubmitting,
                                onChanged: (value) {
                                  setState(() => _weightUnit = value);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _lengthController,
                      enabled: !_isSubmitting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: isRomanian
                            ? 'Lungime (opțional)'
                            : 'Length (optional)',
                        hintText: '52',
                        suffixText: 'cm',
                        prefixIcon: const Icon(Icons.straighten_rounded),
                      ),
                      validator: _optionalPositiveNumber,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      enabled: !_isSubmitting,
                      minLines: 3,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: isRomanian
                            ? 'Notițe (opțional)'
                            : 'Notes (optional)',
                        hintText: isRomanian
                            ? 'Nălucă, adâncime, condiții, detalii utile…'
                            : 'Lure, depth, conditions, useful details…',
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 54),
                          child: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: placePresentation.icon,
                  accentColor: placePresentation.color,
                  title: isRomanian ? 'Locul capturii' : 'Catch location',
                  subtitle: isRomanian
                      ? 'Alege cât de precisă să fie locația afișată.'
                      : 'Choose how precisely the location is displayed.',
                  children: [
                    _LocationStatus(
                      isLocating: _isLocating,
                      hasPosition: _position != null,
                      isRomanian: isRomanian,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _placeNameController,
                      enabled: !_isSubmitting,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.l10n.placeNameOptional,
                        hintText: context.l10n.placeHint,
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_WaterType>(
                      isExpanded: true,
                      initialValue: _waterType,
                      decoration: InputDecoration(
                        labelText: context.l10n.waterType,
                        prefixIcon: const Icon(Icons.water_outlined),
                      ),
                      items: _WaterType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_waterTypeLabel(context, type)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _waterType = value);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_LocationPrivacy>(
                      isExpanded: true,
                      initialValue: _locationPrivacy,
                      decoration: InputDecoration(
                        labelText: context.l10n.locationPrivacy,
                        prefixIcon: const Icon(Icons.shield_outlined),
                      ),
                      items: _LocationPrivacy.values
                          .map(
                            (privacy) => DropdownMenuItem(
                              value: privacy,
                              child: Text(_privacyLabel(context, privacy)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _locationPrivacy = value);
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    _PrivacyHint(
                      privacy: _locationPrivacy,
                      isRomanian: isRomanian,
                    ),
                  ],
                ),
                if (_submissionError != null) ...[
                  const SizedBox(height: 14),
                  _SubmissionError(message: _submissionError!),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(catchPresentation.icon),
                  label: Text(
                    _isSubmitting
                        ? context.l10n.savingCatch
                        : context.l10n.saveCatch,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeciesRecognitionState extends StatelessWidget {
  const _SpeciesRecognitionState({
    required this.isRomanian,
    required this.quality,
    required this.isAnalyzing,
  });

  final bool isRomanian;
  final PhotoQualityResult? quality;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    final current = quality;
    final good = current?.isGood == true;
    final accent = isAnalyzing
        ? const Color(0xFF43D9CC)
        : good
        ? const Color(0xFF00C853)
        : const Color(0xFFFFC857);

    final title = isAnalyzing
        ? (isRomanian ? 'Fluvi Vision verifică fotografia' : 'Fluvi Vision is checking the photo')
        : good
        ? (isRomanian ? 'Fotografie potrivită pentru analiză' : 'Photo is suitable for analysis')
        : (isRomanian ? 'Verifică fotografia' : 'Check the photo');

    final subtitle = isAnalyzing
        ? (isRomanian
              ? 'Analiză locală: claritate, lumină, contrast și rezoluție.'
              : 'Local analysis: sharpness, exposure, contrast and resolution.')
        : current == null
        ? (isRomanian
              ? 'Calitatea nu a putut fi analizată. Poți continua și confirma specia manual.'
              : 'Photo quality could not be analysed. You can continue and confirm the species manually.')
        : good
        ? (isRomanian
              ? 'Calitatea este bună. Modelul de specie nu este încă validat pentru producție; confirmă specia manual.'
              : 'Photo quality is good. The species model is not yet production-validated; confirm the species manually.')
        : _issueText(current.issues, isRomanian);

    return Container(
      key: const Key('catch-fluvi-vision-quality'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: .32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAnalyzing)
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
          else
            Icon(good ? Icons.verified_rounded : Icons.auto_awesome_rounded, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                if (current != null && !isAnalyzing) ...[
                  const SizedBox(height: 7),
                  Text(
                    '${current.width}×${current.height} · '
                    '${isRomanian ? 'lumină' : 'exposure'} ${current.brightness.round()} · '
                    '${isRomanian ? 'claritate' : 'sharpness'} ${current.sharpness.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _issueText(List<PhotoQualityIssue> issues, bool ro) {
    if (issues.isEmpty) {
      return ro
          ? 'Confirmă specia manual înainte de salvare.'
          : 'Confirm the species manually before saving.';
    }
    final labels = issues.map((issue) {
      return switch (issue) {
        PhotoQualityIssue.lowResolution => ro ? 'rezoluție mică' : 'low resolution',
        PhotoQualityIssue.tooDark => ro ? 'prea întunecată' : 'too dark',
        PhotoQualityIssue.tooBright => ro ? 'supraexpusă' : 'overexposed',
        PhotoQualityIssue.lowContrast => ro ? 'contrast redus' : 'low contrast',
        PhotoQualityIssue.blurry => ro ? 'posibil neclară' : 'possibly blurry',
      };
    }).join(', ');
    return ro
        ? 'Poza are $labels. Refă fotografia dacă poți; specia rămâne confirmată manual.'
        : 'The photo has $labels. Retake it if possible; the species remains manually confirmed.';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accentColor.withValues(alpha: .24),
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
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
    required this.accentColor,
    required this.icon,
    required this.isRomanian,
  });

  final XFile? image;
  final bool enabled;
  final VoidCallback onCamera;
  final Color accentColor;
  final IconData icon;
  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = image != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasImage
              ? const Color(0xFF67D04B).withValues(alpha: .36)
              : accentColor.withValues(alpha: .18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isRomanian ? 'Fotografie live' : 'Live photo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const _RequiredBadge(),
              ],
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled ? onCamera : null,
                  borderRadius: BorderRadius.circular(17),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: hasImage
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(image!.path),
                                  fit: BoxFit.cover,
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: .68),
                                        ],
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        28,
                                        12,
                                        10,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF67D04B),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 7),
                                          Expanded(
                                            child: Text(
                                              isRomanian
                                                  ? 'Fotografie pregătită'
                                                  : 'Photo ready',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.refresh_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: .12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 29,
                                    color: accentColor,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  isRomanian
                                      ? 'Fotografia capturii este obligatorie'
                                      : 'A catch photo is required',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isRomanian
                                      ? 'Doar cameră live'
                                      : 'Live camera only',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: enabled ? onCamera : null,
              icon: Icon(
                hasImage ? Icons.refresh_rounded : Icons.camera_alt_outlined,
              ),
              label: Text(
                hasImage
                    ? (isRomanian ? 'Refă fotografia' : 'Retake photo')
                    : (isRomanian ? 'Deschide camera' : 'Open camera'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightUnitSelector extends StatelessWidget {
  const _WeightUnitSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final _WeightUnit value;
  final bool enabled;
  final ValueChanged<_WeightUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .72)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final unit in _WeightUnit.values)
              Expanded(
                child: _WeightUnitButton(
                  unit: unit,
                  selected: value == unit,
                  enabled: enabled,
                  onTap: () => onChanged(unit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeightUnitButton extends StatelessWidget {
  const _WeightUnitButton({
    required this.unit,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _WeightUnit unit;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const accent = Color(0xFF12D8D6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: .48)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            unit.label,
            style: TextStyle(
              color: enabled
                  ? (selected ? accent : scheme.onSurfaceVariant)
                  : scheme.onSurface.withValues(alpha: .38),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _RequiredBadge extends StatelessWidget {
  const _RequiredBadge();

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        isRomanian ? 'Obligatorie' : 'Required',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RequiredFieldMark extends StatelessWidget {
  const _RequiredFieldMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      widthFactor: 1,
      child: Text(
        '*',
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({
    required this.isLocating,
    required this.hasPosition,
    required this.isRomanian,
  });

  final bool isLocating;
  final bool hasPosition;
  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isLocating
        ? const Color(0xFF12D8D6)
        : hasPosition
        ? const Color(0xFF67D04B)
        : scheme.onSurfaceVariant;
    final text = isLocating
        ? (isRomanian ? 'Se caută locația GPS…' : 'Finding GPS location…')
        : hasPosition
        ? (isRomanian ? 'Locație GPS detectată' : 'GPS location detected')
        : (isRomanian
              ? 'GPS indisponibil — completează numele locului'
              : 'GPS unavailable — enter the place name');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          children: [
            if (isLocating)
              SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(
                hasPosition
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
                size: 18,
                color: color,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyHint extends StatelessWidget {
  const _PrivacyHint({required this.privacy, required this.isRomanian});

  final _LocationPrivacy privacy;
  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final message = switch (privacy) {
      _LocationPrivacy.exact =>
        isRomanian
            ? 'Coordonatele exacte pot fi afișate comunității.'
            : 'Exact coordinates may be shown to the community.',
      _LocationPrivacy.approximate =>
        isRomanian
            ? 'Locația va fi rotunjită pentru mai multă confidențialitate.'
            : 'The location will be rounded for more privacy.',
      _LocationPrivacy.hidden =>
        isRomanian
            ? 'Coordonatele nu vor fi publicate.'
            : 'Coordinates will not be published.',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubmissionError extends StatelessWidget {
  const _SubmissionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.error.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
