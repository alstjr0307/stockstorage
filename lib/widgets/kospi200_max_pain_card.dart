import 'package:flutter/material.dart';

import '../models/kospi200_max_pain.dart';
import '../screens/kospi200_max_pain_screen.dart';
import '../services/firestore_service.dart';

/// 홈 화면 코스피200 옵션 Max Pain 미리보기 카드.
/// 서버가 캐시한 값을 보여주고, 탭하면 전용 상세 화면으로 이동.
/// 데이터가 없으면(장 시작 전 등) 카드를 숨긴다.
class Kospi200MaxPainCard extends StatelessWidget {
  const Kospi200MaxPainCard({super.key});

  static const _accent = Color(0xFF10B981);
  static const _callColor = Color(0xFFF04452);
  static const _putColor = Color(0xFF1677FF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Kospi200MaxPain?>(
      stream: FirestoreService().watchKospi200MaxPain(),
      builder: (context, snapshot) {
        final mp = snapshot.data;
        if (mp == null || mp.strikes.isEmpty) return const SizedBox.shrink();
        return _card(context, mp);
      },
    );
  }

  Widget _card(BuildContext context, Kospi200MaxPain mp) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ref = mp.referenceLevel;
    final pct = ref > 0 ? (mp.maxPain - ref) / ref * 100 : 0.0;
    final up = pct >= 0;
    final deltaColor = up ? _callColor : _putColor;
    final dday = mp.daysToExpiry;
    final ddayLabel = dday <= 0 ? 'D-day' : 'D-$dday';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Kospi200MaxPainScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent.withValues(alpha: isDark ? 0.12 : 0.10),
              _accent.withValues(alpha: 0.02),
            ],
          ),
          border: Border.all(color: _accent.withValues(alpha: 0.26)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('🎯', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '코스피200 옵션 Max Pain',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ddayLabel,
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        mp.maxPain.toStringAsFixed(2),
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '현재 ${ref.toStringAsFixed(1)} · ${up ? '↑' : '↓'}${pct.abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: deltaColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withValues(alpha: 0.35),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
