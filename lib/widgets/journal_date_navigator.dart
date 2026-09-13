import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class JournalDateNavigator extends StatelessWidget {
  final DateTime date;
  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onPickDate;

  const JournalDateNavigator({
    super.key,
    required this.date,
    required this.canGoPrev,
    required this.canGoNext,
    this.onPrev,
    this.onNext,
    this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoPrev ? onPrev : null,
            tooltip: canGoPrev ? '이전 거래일' : '이전 거래일 없음',
            icon: Icon(
              Icons.chevron_left_rounded,
              color: canGoPrev
                  ? cs.onSurface.withValues(alpha: 0.8)
                  : cs.onSurface.withValues(alpha: 0.2),
            ),
          ),
          Expanded(
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onPickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateFormat('yyyy.MM.dd').format(date),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            tooltip: canGoNext ? '다음 거래일' : '다음 거래일 없음',
            icon: Icon(
              Icons.chevron_right_rounded,
              color: canGoNext
                  ? cs.onSurface.withValues(alpha: 0.8)
                  : cs.onSurface.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
