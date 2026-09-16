import 'package:flutter/material.dart';

/// Keeps asynchronously loaded list sections from restarting when scrolled away.
class KeepAliveSection extends StatefulWidget {
  const KeepAliveSection({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveSection> createState() => _KeepAliveSectionState();
}

class _KeepAliveSectionState extends State<KeepAliveSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
