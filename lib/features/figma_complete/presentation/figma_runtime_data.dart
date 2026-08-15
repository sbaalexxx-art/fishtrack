import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/current_location.dart';
import '../../../core/runtime/app_runtime.dart';
import '../../../models/station.dart';
import '../../commercial_home/data/commercial_home_data_source.dart';
import 'figma_foundation.dart';

class FigmaRuntimeSnapshotBuilder extends ConsumerStatefulWidget {
  const FigmaRuntimeSnapshotBuilder({
    super.key,
    required this.builder,
    this.dataSource,
    this.station,
    this.loadingLabel,
  });

  final Widget Function(
    BuildContext context,
    CommercialHomeSnapshot? snapshot,
    VoidCallback refresh,
  )
  builder;
  final CommercialHomeDataSource? dataSource;
  final Station? station;
  final String? loadingLabel;

  @override
  ConsumerState<FigmaRuntimeSnapshotBuilder> createState() =>
      _FigmaRuntimeSnapshotBuilderState();
}

class _FigmaRuntimeSnapshotBuilderState
    extends ConsumerState<FigmaRuntimeSnapshotBuilder> {
  late CommercialHomeDataSource _dataSource;

  CommercialHomeSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _configureDataSource();
  }

  @override
  void didUpdateWidget(covariant FigmaRuntimeSnapshotBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final customSourceChanged = !identical(
      oldWidget.dataSource,
      widget.dataSource,
    );
    final stationChanged = oldWidget.station?.id != widget.station?.id;
    if (!customSourceChanged && !stationChanged) return;
    _configureDataSource();
  }

  void _configureDataSource() {
    _dataSource =
        widget.dataSource ??
        LiveCommercialHomeDataSource(pinnedStation: widget.station);

    final generation = ++_requestGeneration;
    _snapshot = null;
    _error = null;
    _loading = true;
    unawaited(_performLoad(generation: generation));
  }

  void _refresh() {
    final generation = ++_requestGeneration;
    setState(() {
      _error = null;
      _loading = true;
    });
    unawaited(_performLoad(generation: generation, forceRefresh: true));
  }

  Future<void> _performLoad({
    required int generation,
    bool forceRefresh = false,
  }) async {
    try {
      CommercialHomeSnapshot snapshot;

      if (_dataSource
          case final CurrentLocationAwareCommercialHomeDataSource
              locationAwareSource) {
        final languageCode =
            WidgetsBinding.instance.platformDispatcher.locale.languageCode;

        final appRuntime = ref.read(appRuntimeProvider.notifier);

        if (forceRefresh) {
          await appRuntime.forceRefresh(languageCode: languageCode);
        } else {
          await appRuntime.start(languageCode: languageCode);
        }

        final locationState = ref.read(currentLocationProvider);
        final location = locationState.location;

        if (locationState.hasUsableLocation && location != null) {
          if (_dataSource
              case final ProgressiveCommercialHomeDataSource
                  progressiveSource) {
            snapshot = await progressiveSource.loadProgressively(
              location,
              forceRefresh: forceRefresh,
              onUpdate: (progressiveSnapshot) {
                if (!mounted || generation != _requestGeneration) return;

                setState(() {
                  _snapshot = progressiveSnapshot;
                  _error = null;
                });
              },
            );
          } else {
            snapshot = await locationAwareSource.loadForCurrentLocation(
              location,
              forceRefresh: forceRefresh,
            );
          }
        } else {
          snapshot = await _dataSource.load(forceRefresh: forceRefresh);
        }
      } else {
        snapshot = await _dataSource.load(forceRefresh: forceRefresh);
      }

      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _snapshot == null) {
      return Center(
        key: const ValueKey('figma-runtime-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              widget.loadingLabel ?? 'Se încarcă datele reale…',
              textAlign: TextAlign.center,
              style: figmaBody(),
            ),
          ],
        ),
      );
    }

    if (_error != null && _snapshot == null) {
      final isRomanian =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';

      return Center(
        key: const ValueKey('figma-runtime-error'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FigmaSurface(
              accent: FigmaFluviTokens.amber,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: FigmaFluviTokens.amber,
                    size: 34,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isRomanian
                        ? 'Datele nu au putut fi încărcate'
                        : 'Data could not be loaded',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FigmaFluviTokens.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isRomanian
                        ? 'Conținutul nu este fabricat. Verifică conexiunea și încearcă din nou.'
                        : 'No content was fabricated. Check the connection and try again.',
                    textAlign: TextAlign.center,
                    style: figmaBody(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('figma-runtime-retry'),
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(isRomanian ? 'Reîncearcă' : 'Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.builder(context, _snapshot, _refresh);
  }
}
