import 'package:flutter/material.dart';

/// Kept independent of Firebase so loading, failure and small-screen states
/// can be checked without creating users or saving production data.
class AnalysisFollowCard extends StatefulWidget {
  const AnalysisFollowCard({
    super.key,
    required this.savedStream,
    required this.onSave,
    required this.onAlert,
  });
  final Stream<bool> savedStream;
  final Future<void> Function() onSave;
  final Future<void> Function() onAlert;

  @override
  State<AnalysisFollowCard> createState() => _AnalysisFollowCardState();
}

class _AnalysisFollowCardState extends State<AnalysisFollowCard> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: widget.savedStream,
    builder: (context, snapshot) {
      final saved = snapshot.data == true;
      final ready = snapshot.hasData && !snapshot.hasError;
      final cs = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              saved ? '저장한 종목, 계속 지켜보세요' : '분석한 종목, 계속 지켜보세요',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              saved
                  ? '홈에서 시세를 확인하고, 원하는 가격에 알림을 받아보세요.'
                  : '관심종목에 저장하면 홈에서 시세를 바로 확인할 수 있어요.',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: !ready || _busy || saved
                      ? null
                      : () => _run(widget.onSave),
                  icon: Icon(
                    saved ? Icons.check_rounded : Icons.star_outline_rounded,
                  ),
                  label: Text(saved ? '관심종목에 저장됨' : '관심종목 저장'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onAlert),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('가격 알림 설정'),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
            if (_error != null || snapshot.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error ?? '저장 상태를 확인하지 못했어요.',
                  style: TextStyle(color: cs.error),
                ),
              ),
          ],
        ),
      );
    },
  );
}
