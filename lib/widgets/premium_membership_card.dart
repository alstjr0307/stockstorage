import 'package:flutter/material.dart';

/// Home entry point; opening benefits never starts a purchase.
class PremiumMembershipCard extends StatelessWidget {
  const PremiumMembershipCard({
    super.key,
    required this.isPremium,
    required this.onTap,
  });

  final bool isPremium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFF5B547);
    return Material(
      color: dark ? const Color(0xFF1A2035) : const Color(0xFFFFFBF2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: gold.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: gold,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: isPremium ? '프리미엄 이용 중' : '프리미엄',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: isPremium ? ' · 멤버십 관리' : ' · 광고 없이 더 편하게',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
