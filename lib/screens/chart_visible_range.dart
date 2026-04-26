import 'package:flutter/foundation.dart';

@immutable
class ChartVisibleRange {
  final double start;
  final double end;

  const ChartVisibleRange(this.start, this.end);

  double get width => end - start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartVisibleRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}
