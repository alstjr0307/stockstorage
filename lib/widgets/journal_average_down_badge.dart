import 'package:flutter/material.dart';

/// Presentation only. The ledger decides whether this is an additional buy.
class JournalAdditionalBuyBadge extends StatelessWidget {
  const JournalAdditionalBuyBadge({super.key, required this.buyNumber});

  final int buyNumber;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blue = dark ? const Color(0xFF79B4FF) : const Color(0xFF2563EB);
    return Tooltip(
      message: '보유 중인 종목을 추가로 매수한 기록입니다.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: dark ? .12 : .07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: blue),
            const SizedBox(width: 5),
            Text(
              '추가매수',
              style: TextStyle(
                color: blue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (buyNumber > 1) ...[
              Container(
                width: 1,
                height: 11,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                color: blue.withValues(alpha: .22),
              ),
              Text(
                '$buyNumber차 매수',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
