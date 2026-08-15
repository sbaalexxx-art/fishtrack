import 'package:flutter/foundation.dart';

@immutable
class HydroDensityCandidate {
  const HydroDensityCandidate({
    required this.key,
    required this.latitude,
    required this.longitude,
    required this.priority,
  });

  final String key;
  final double latitude;
  final double longitude;
  final int priority;
}

double? hydroDensityCellSize(double zoom) {
  if (zoom < 7.2) return double.infinity;
  if (zoom < 8.2) return .55;
  if (zoom < 9.2) return .28;
  if (zoom < 10.2) return .12;
  if (zoom < 10.8) return .055;
  return null;
}

/// Selects a deterministic, priority-aware subset for regional map display.
///
/// This changes presentation density only. It never mutates or discards the
/// canonical candidates, and all entities return at local zoom.
Set<String> selectHydroDensityKeys({
  required Iterable<HydroDensityCandidate> candidates,
  required double zoom,
  Set<String> selectedKeys = const <String>{},
}) {
  final source = candidates
      .where(
        (candidate) =>
            candidate.key.isNotEmpty &&
            candidate.latitude.isFinite &&
            candidate.longitude.isFinite,
      )
      .toList(growable: false);
  final cellSize = hydroDensityCellSize(zoom);
  if (cellSize == null) return source.map((item) => item.key).toSet();
  if (cellSize.isInfinite) {
    return source
        .where((item) => selectedKeys.contains(item.key))
        .map((item) => item.key)
        .toSet();
  }

  final ranked = List<HydroDensityCandidate>.of(source)
    ..sort((left, right) {
      final leftSelected = selectedKeys.contains(left.key);
      final rightSelected = selectedKeys.contains(right.key);
      if (leftSelected != rightSelected) return leftSelected ? -1 : 1;
      final priority = right.priority.compareTo(left.priority);
      return priority != 0 ? priority : left.key.compareTo(right.key);
    });
  String cellFor(HydroDensityCandidate candidate) =>
      '${(candidate.latitude / cellSize).floor()}:'
      '${(candidate.longitude / cellSize).floor()}';
  final occupiedCells = <String>{
    for (final candidate in ranked)
      if (selectedKeys.contains(candidate.key)) cellFor(candidate),
  };
  final visible = <String>{
    for (final candidate in ranked)
      if (selectedKeys.contains(candidate.key)) candidate.key,
  };
  for (final candidate in ranked) {
    if (selectedKeys.contains(candidate.key)) continue;
    final cell = cellFor(candidate);
    if (occupiedCells.add(cell)) visible.add(candidate.key);
  }
  return visible;
}
