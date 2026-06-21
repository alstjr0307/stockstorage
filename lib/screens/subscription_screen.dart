import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/subscription_service.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subscription = context.watch<SubscriptionService>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('프리미엄 멤버십')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2035) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFF5B547),
                  size: 36,
                ),
                const SizedBox(height: 14),
                Text(
                  subscription.isPremium ? '프리미엄 이용 중' : '주식저장소 프리미엄',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subscription.displayPrice,
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                const _BenefitRow(text: '앱의 모든 광고 제거'),
                const SizedBox(height: 12),
                const _BenefitRow(text: 'AI 종목 분석 하루 5회 광고 없이 이용'),
                const SizedBox(height: 12),
                const _BenefitRow(text: '언제든 스토어에서 해지 가능'),
                const SizedBox(height: 22),
                if (subscription.isPremium)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: subscription.openManageSubscription,
                      child: const Text('구독 관리'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed:
                          subscription.loading || !subscription.isConfigured
                          ? null
                          : () => _purchase(context, subscription),
                      child: subscription.loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '월간 멤버십 시작',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!subscription.isConfigured)
            const Text(
              '스토어 결제 연결 준비 중입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            )
          else if (subscription.error != null)
            Text(
              subscription.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          TextButton(
            onPressed: subscription.loading || !subscription.isConfigured
                ? null
                : () => _restore(context, subscription),
            child: const Text('이전 구매 복원'),
          ),
          Text(
            '결제는 App Store 또는 Google Play 계정으로 매월 자동 갱신됩니다. '
            '해지 후에도 현재 결제 기간이 끝날 때까지 혜택을 이용할 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.45),
              fontSize: 11.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _purchase(
    BuildContext context,
    SubscriptionService subscription,
  ) async {
    final success = await subscription.purchaseMonthly();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '프리미엄 멤버십이 활성화되었습니다.' : '결제를 완료하지 못했어요.'),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    SubscriptionService subscription,
  ) async {
    final restored = await subscription.restore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restored ? '프리미엄 구매를 복원했습니다.' : '복원할 구매 내역이 없어요.'),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
