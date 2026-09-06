import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/price_alert.dart';
import '../services/firestore_service.dart';
import '../services/subscription_service.dart';
import 'stock_detail_screen.dart';
import 'subscription_screen.dart';

/// 내가 걸어둔 조건 알림 전체 목록.
/// 종목 상세로 들어가지 않아도 여기서 켜기/끄기·재무장·삭제를 할 수 있다.
class PriceAlertsScreen extends StatelessWidget {
  const PriceAlertsScreen({super.key});

  static const _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final fs = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('🔔 내 조건 알림')),
      body: uid.isEmpty
          ? _centered(cs, '로그인하면 조건 알림을 관리할 수 있습니다.')
          : StreamBuilder<List<PriceAlert>>(
              stream: fs.watchPriceAlerts(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _accent),
                  );
                }
                final alerts = snapshot.data ?? const <PriceAlert>[];
                if (alerts.isEmpty) {
                  return _centered(
                    cs,
                    '아직 걸어둔 조건 알림이 없습니다.\n'
                    '관심종목 목록의 🔔 버튼이나 종목 상세에서 설정해보세요.',
                  );
                }

                final active = alerts
                    .where((a) => a.enabled && !a.triggered)
                    .length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _QuotaBanner(activeCount: active),
                    const SizedBox(height: 14),
                    for (final a in alerts) ...[
                      _AlertCard(alert: a, fs: fs),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _centered(ColorScheme cs, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.5),
          fontSize: 14,
          height: 1.6,
        ),
      ),
    ),
  );
}

/// 무료 한도 안내 배너. 프리미엄이면 개수만 보여준다.
class _QuotaBanner extends StatelessWidget {
  const _QuotaBanner({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final premium = SubscriptionService.instance.isPremium;
    final limit = FirestoreService.freeAlertLimit;
    final overLimit = !premium && activeCount >= limit;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          Icon(
            premium
                ? Icons.workspace_premium_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: premium
                ? const Color(0xFFF5C451)
                : cs.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              premium
                  ? '프리미엄 · 활성 알림 $activeCount개 (무제한)'
                  : '활성 알림 $activeCount / $limit개 (무료 플랜)',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.72),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (overLimit)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '더 걸기',
                style: TextStyle(
                  color: Color(0xFFCF9F2E),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 알림 한 건 — 종목명 + 조건 + 상태, 켜기/끄기·재무장·삭제.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.fs});

  final PriceAlert alert;
  final FirestoreService fs;

  static const _accent = Color(0xFF10B981);

  String get _marketLabel => switch (alert.market) {
    'US' => '미국',
    'KQ' => '코스닥',
    _ => '코스피',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fired = alert.triggered;
    final off = !alert.enabled;
    final dimmed = fired || off;

    return Container(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.09)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => Navigator.push(
              context,
              stockDetailRoute(
                stockPickForGeneralDetail(
                  ticker: alert.ticker,
                  name: alert.name,
                  market: alert.market,
                  reason: '조건 알림에서 열린 종목입니다.',
                ),
                enablePickFeatures: false,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dimmed
                          ? cs.onSurface.withValues(alpha: 0.28)
                          : _accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.name.isEmpty ? alert.ticker : alert.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface.withValues(
                              alpha: dimmed ? 0.55 : 1,
                            ),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_marketLabel · ${alert.ticker}',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.42),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.describe(),
                        style: TextStyle(
                          color: cs.onSurface.withValues(
                            alpha: dimmed ? 0.5 : 0.88,
                          ),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          decoration: fired ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (fired)
                        Text(
                          '발동됨 · 다시 켜려면 ↻ 를 눌러주세요',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        )
                      else if (off)
                        Text(
                          '꺼짐',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (fired)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    color: _accent,
                    onPressed: () => fs.rearmPriceAlert(alert.id),
                    tooltip: '다시 켜기',
                  )
                else
                  Switch(
                    value: alert.enabled,
                    activeThumbColor: _accent,
                    onChanged: (v) => fs.setPriceAlertEnabled(alert.id, v),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: cs.onSurface.withValues(alpha: 0.4),
                  onPressed: () => _confirmDelete(context),
                  tooltip: '삭제',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '알림 삭제',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '${alert.name.isEmpty ? alert.ticker : alert.name} · ${alert.describe()}\n'
          '이 조건 알림을 삭제할까요?',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.78),
            fontSize: 13.5,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '삭제',
              style: TextStyle(
                color: Color(0xFFE5484D),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await fs.deletePriceAlert(alert.id);
  }
}
