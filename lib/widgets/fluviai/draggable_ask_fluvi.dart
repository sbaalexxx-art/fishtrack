import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AskFluviPlacementScope { home, fullMap }

@immutable
class AskFluviPlacementGeometry {
  const AskFluviPlacementGeometry({
    required this.workspace,
    required this.controlSize,
    this.obstacles = const <Rect>[],
  });

  final Rect workspace;
  final Size controlSize;
  final List<Rect> obstacles;

  Rect get _topLeftBounds => Rect.fromLTRB(
    workspace.left,
    workspace.top,
    math.max(workspace.left, workspace.right - controlSize.width),
    math.max(workspace.top, workspace.bottom - controlSize.height),
  );

  Offset denormalize(Offset normalized) {
    final bounds = _topLeftBounds;
    return constrain(
      Offset(
        bounds.left + bounds.width * normalized.dx.clamp(0.0, 1.0),
        bounds.top + bounds.height * normalized.dy.clamp(0.0, 1.0),
      ),
    );
  }

  Offset normalize(Offset position) {
    final bounds = _topLeftBounds;
    final safe = constrain(position);
    return Offset(
      bounds.width <= 0 ? 0 : (safe.dx - bounds.left) / bounds.width,
      bounds.height <= 0 ? 0 : (safe.dy - bounds.top) / bounds.height,
    );
  }

  Offset constrain(Offset desired) {
    final bounds = _topLeftBounds;
    final clamped = Offset(
      desired.dx.clamp(bounds.left, bounds.right),
      desired.dy.clamp(bounds.top, bounds.bottom),
    );
    if (_isSafe(clamped)) return clamped;

    final candidates =
        <Offset>[
          Offset(bounds.left, clamped.dy),
          Offset(bounds.right, clamped.dy),
          Offset(clamped.dx, bounds.top),
          Offset(clamped.dx, bounds.bottom),
          Offset(bounds.left, bounds.top),
          Offset(bounds.right, bounds.top),
          Offset(bounds.left, bounds.bottom),
          Offset(bounds.right, bounds.bottom),
          for (final obstacle in obstacles) ...[
            Offset(obstacle.left - controlSize.width, clamped.dy),
            Offset(obstacle.right, clamped.dy),
            Offset(clamped.dx, obstacle.top - controlSize.height),
            Offset(clamped.dx, obstacle.bottom),
          ],
        ].map(
          (candidate) => Offset(
            candidate.dx.clamp(bounds.left, bounds.right),
            candidate.dy.clamp(bounds.top, bounds.bottom),
          ),
        );
    final safeCandidates = candidates.where(_isSafe).toList(growable: false);
    if (safeCandidates.isEmpty) return clamped;
    safeCandidates.sort(
      (a, b) => (a - desired).distanceSquared.compareTo(
        (b - desired).distanceSquared,
      ),
    );
    return safeCandidates.first;
  }

  Offset snap(Offset desired) {
    final bounds = _topLeftBounds;
    final safe = constrain(desired);
    final left = constrain(Offset(bounds.left, safe.dy));
    final right = constrain(Offset(bounds.right, safe.dy));
    return (left - safe).distanceSquared <= (right - safe).distanceSquared
        ? left
        : right;
  }

  bool _isSafe(Offset topLeft) {
    final control = topLeft & controlSize;
    return control.left >= workspace.left &&
        control.top >= workspace.top &&
        control.right <= workspace.right &&
        control.bottom <= workspace.bottom &&
        obstacles.every((obstacle) => !control.overlaps(obstacle));
  }
}

class AskFluviPlacementStore {
  static const _prefix = 'ask_fluvi_placement_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _key(
    AskFluviPlacementScope scope,
    Orientation orientation,
    String axis,
  ) => '$_prefix.${scope.name}.${orientation.name}.$axis';

  static Future<Offset?> load(
    AskFluviPlacementScope scope,
    Orientation orientation,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final x = preferences.getDouble(_key(scope, orientation, 'x'));
    final y = preferences.getDouble(_key(scope, orientation, 'y'));
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  static Future<void> save(
    AskFluviPlacementScope scope,
    Orientation orientation,
    Offset normalized,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(
      _key(scope, orientation, 'x'),
      normalized.dx.clamp(0.0, 1.0),
    );
    await preferences.setDouble(
      _key(scope, orientation, 'y'),
      normalized.dy.clamp(0.0, 1.0),
    );
  }

  static Future<void> resetAll() async {
    final preferences = await SharedPreferences.getInstance();
    for (final scope in AskFluviPlacementScope.values) {
      for (final orientation in Orientation.values) {
        await preferences.remove(_key(scope, orientation, 'x'));
        await preferences.remove(_key(scope, orientation, 'y'));
      }
    }
    revision.value++;
  }
}

class DraggableAskFluviControl extends StatefulWidget {
  const DraggableAskFluviControl({
    super.key,
    this.controlKey,
    required this.scope,
    required this.controlSize,
    required this.defaultNormalizedPosition,
    required this.workspaceBuilder,
    required this.obstaclesBuilder,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final Key? controlKey;
  final AskFluviPlacementScope scope;
  final Size controlSize;
  final Offset defaultNormalizedPosition;
  final Rect Function(Size size) workspaceBuilder;
  final List<Rect> Function(Size size) obstaclesBuilder;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<DraggableAskFluviControl> createState() =>
      _DraggableAskFluviControlState();
}

class _DraggableAskFluviControlState extends State<DraggableAskFluviControl> {
  Offset? _normalizedPosition;
  Offset? _dragPosition;
  Offset? _dragGlobalStart;
  Offset? _dragStartPosition;
  bool _dragging = false;
  int _loadGeneration = 0;
  Orientation? _loadedOrientation;

  @override
  void initState() {
    super.initState();
    AskFluviPlacementStore.revision.addListener(_handleReset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_loadedOrientation != orientation) {
      _loadedOrientation = orientation;
      _loadPosition();
    }
  }

  @override
  void didUpdateWidget(covariant DraggableAskFluviControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) _loadPosition();
  }

  @override
  void dispose() {
    AskFluviPlacementStore.revision.removeListener(_handleReset);
    super.dispose();
  }

  void _handleReset() {
    if (!mounted) return;
    setState(() {
      _normalizedPosition = widget.defaultNormalizedPosition;
      _dragPosition = null;
    });
  }

  Future<void> _loadPosition() async {
    final generation = ++_loadGeneration;
    final orientation =
        MediaQuery.maybeOrientationOf(context) ?? Orientation.portrait;
    final stored = await AskFluviPlacementStore.load(widget.scope, orientation);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _normalizedPosition = stored ?? widget.defaultNormalizedPosition;
      _dragPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final geometry = AskFluviPlacementGeometry(
          workspace: widget.workspaceBuilder(size),
          controlSize: widget.controlSize,
          obstacles: widget.obstaclesBuilder(size),
        );
        final position =
            _dragPosition ??
            geometry.denormalize(
              _normalizedPosition ?? widget.defaultNormalizedPosition,
            );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: position.dx,
              top: position.dy,
              width: widget.controlSize.width,
              height: widget.controlSize.height,
              child: Semantics(
                button: true,
                label: widget.semanticLabel,
                hint: 'Long press and drag to reposition',
                child: GestureDetector(
                  key: widget.controlKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onLongPressStart: (details) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _dragging = true;
                      _dragPosition = position;
                      _dragGlobalStart = details.globalPosition;
                      _dragStartPosition = position;
                    });
                  },
                  onLongPressMoveUpdate: (details) {
                    final origin = _dragStartPosition ?? position;
                    final globalStart =
                        _dragGlobalStart ?? details.globalPosition;
                    setState(() {
                      _dragPosition = geometry.constrain(
                        origin + (details.globalPosition - globalStart),
                      );
                    });
                  },
                  onLongPressEnd: (_) {
                    final snapped = geometry.snap(_dragPosition ?? position);
                    final normalized = geometry.normalize(snapped);
                    setState(() {
                      _dragging = false;
                      _dragPosition = null;
                      _dragGlobalStart = null;
                      _dragStartPosition = null;
                      _normalizedPosition = normalized;
                    });
                    HapticFeedback.lightImpact();
                    AskFluviPlacementStore.save(
                      widget.scope,
                      orientation,
                      normalized,
                    );
                  },
                  child: AnimatedScale(
                    scale: _dragging ? 1.045 : 1,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: ExcludeSemantics(
                      child: IgnorePointer(child: widget.child),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
