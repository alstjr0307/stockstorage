import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'journal_visual_style.dart';

/// Local display choice only. A build-time kill switch overrides preferences.
class JournalExperienceGate extends StatefulWidget {
  const JournalExperienceGate({
    super.key,
    required this.modernBuilder,
    required this.legacyBuilder,
  });
  final WidgetBuilder modernBuilder, legacyBuilder;
  static const enabled = bool.fromEnvironment('JOURNAL_V2', defaultValue: true);
  static const preferenceKey = 'journal_v2_enabled';
  @override
  State<JournalExperienceGate> createState() => _JournalExperienceGateState();
}

class _JournalExperienceGateState extends State<JournalExperienceGate> {
  bool? _modern;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var value = JournalExperienceGate.enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      value =
          value && (prefs.getBool(JournalExperienceGate.preferenceKey) ?? true);
    } catch (_) {}
    if (mounted) setState(() => _modern = value);
  }

  Future<void> _toggle() async {
    final value = !(_modern ?? true);
    setState(() => _modern = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(JournalExperienceGate.preferenceKey, value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_modern == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '매매일지',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (JournalExperienceGate.enabled)
                PopupMenuButton<String>(
                  tooltip: '화면 설정',
                  icon: Icon(
                    Icons.more_horiz,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .5),
                  ),
                  onSelected: (_) => _toggle(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(_modern! ? '기존 화면으로' : '개선 화면으로'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(_modern),
            child: _modern!
                ? JournalVisualStyle(child: widget.modernBuilder(context))
                : widget.legacyBuilder(context),
          ),
        ),
      ],
    );
  }
}
