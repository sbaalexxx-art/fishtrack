import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/theme/fluviai_commercial_tokens.dart';

enum FluviConnectivityState { unknown, live, offline }

class FluviAIConnectivityPill extends StatefulWidget {
  const FluviAIConnectivityPill({super.key, this.compact = false});

  final bool compact;

  @override
  State<FluviAIConnectivityPill> createState() =>
      _FluviAIConnectivityPillState();
}

class _FluviAIConnectivityPillState extends State<FluviAIConnectivityPill> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  FluviConnectivityState _state = FluviConnectivityState.unknown;

  @override
  void initState() {
    super.initState();
    _subscription = _connectivity.onConnectivityChanged.listen(_apply);
    unawaited(_loadInitial());
  }

  Future<void> _loadInitial() async {
    try {
      _apply(await _connectivity.checkConnectivity());
    } catch (_) {
      // Unknown is intentionally silent until the platform reports a state.
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final next =
        results.isNotEmpty &&
            results.every((result) => result == ConnectivityResult.none)
        ? FluviConnectivityState.offline
        : FluviConnectivityState.live;
    if (!mounted || next == _state) return;
    setState(() => _state = next);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == FluviConnectivityState.unknown) {
      return const SizedBox.shrink();
    }
    final offline = _state == FluviConnectivityState.offline;
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final label = offline ? 'OFFLINE' : 'LIVE';
    final semantic = offline
        ? (isRomanian ? 'Aplicația este offline' : 'App is offline')
        : (isRomanian ? 'Aplicația este conectată' : 'App is live');
    final foreground = offline
        ? FluviAICommercialTokens.textSecondary
        : FluviAICommercialTokens.brandFocus;

    return Semantics(
      liveRegion: true,
      label: semantic,
      child: Container(
        key: ValueKey<String>(
          offline ? 'connectivity-offline' : 'connectivity-live',
        ),
        height: widget.compact ? 20 : 24,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 7 : 9),
        decoration: BoxDecoration(
          color: FluviAICommercialTokens.surface.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: foreground.withValues(alpha: offline ? .22 : .36),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: widget.compact ? 6 : 7,
              height: widget.compact ? 6 : 7,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontFamily: FluviAICommercialTokens.fontFamily,
                fontSize: widget.compact ? 8.5 : 9.5,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: .55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
