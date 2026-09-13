import 'package:flutter/material.dart';

/// Creates each tab on its first visit, then preserves its state between visits.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  }) : assert(index >= 0 && index < itemCount);

  final int index;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
  }

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((index) => index >= widget.itemCount);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: List.generate(widget.itemCount, (index) {
        return TickerMode(
          enabled: index == widget.index,
          child: _visited.contains(index)
              ? widget.itemBuilder(context, index)
              : const SizedBox.shrink(),
        );
      }),
    );
  }
}
