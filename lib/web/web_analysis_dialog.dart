import 'package:flutter/material.dart';

/// Web has no ad SDK; the same daily quota is still enforced by the server.
class WebAnalysisDialog extends StatelessWidget {
  const WebAnalysisDialog({super.key, required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 분석 시작'),
      content: Text(
        '웹에서는 광고 없이 분석을 시작합니다.\n'
        '오늘 남은 횟수 ${(limit - used).clamp(0, limit)} / $limit회\n\n'
        '분석을 시작하면 오늘 사용 횟수에 반영됩니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: used < limit ? () => Navigator.pop(context, true) : null,
          child: const Text('분석 시작'),
        ),
      ],
    );
  }
}
