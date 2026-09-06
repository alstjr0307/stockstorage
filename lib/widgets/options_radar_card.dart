import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/stock_detail_screen.dart';
import '../services/stock_price_service.dart';

/// 홈 화면 "옵션 만기 레이더" 카드.
/// 인기 미국 종목의 Max Pain(옵션 만기 수렴가) vs 현재가 괴리를 한눈에 요약한다.
/// 옵션 미결제약정 데이터(야후)를 재활용하며, 전부 실패하면 카드를 숨긴다.
class OptionsRadarCard extends StatefulWidget {
  const OptionsRadarCard({super.key});

  /// 레이더에 표시할 인기 종목 (옵션 거래가 활발한 대형주 위주).
  static const tickers = ['NVDA', 'TSLA', 'AAPL', 'AMD', 'MSFT'];

  @override
  State<OptionsRadarCard> createState() => _OptionsRadarCardState();
}

class _OptionsRadarCardState extends State<OptionsRadarCard> {
  late Future<List<_RadarEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_RadarEntry>> _load() async {
    final results = await Future.wait(
      OptionsRadarCard.tickers.map((t) async {
        final mp = await StockPriceService.fetchMaxPain(t, 'US');
        return mp == null ? null : _RadarEntry(ticker: t, data: mp);
      }),
    );
    return results.whereType<_RadarEntry>().toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_RadarEntry>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final entries = snapshot.data ?? const <_RadarEntry>[];
        // 로딩 중엔 스켈레톤, 결과가 하나도 없으면 카드 숨김
        if (!loading && entries.isEmpty) return const SizedBox.shrink();
        return _Card(loading: loading, entries: entries);
      },
    );
  }
}

class _RadarEntry {
  const _RadarEntry({required this.ticker, required this.data});
  final String ticker;
  final MaxPainResult data;
}

class _Card extends StatelessWidget {
  const _Card({required this.loading, required this.entries});

  final bool loading;
  final List<_RadarEntry> entries;

  static const _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 가장 가까운 만기 (엔트리 중 최솟값)
    DateTime? nearestExpiry;
    for (final e in entries) {
      if (nearestExpiry == null || e.data.expiration.isBefore(nearestExpiry)) {
        nearestExpiry = e.data.expiration;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '옵션 만기 레이더',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              if (nearestExpiry != null)
                _ExpiryChip(expiry: nearestExpiry),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '옵션 미결제약정이 가리키는 만기일 수렴가(Max Pain)',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          if (loading)
            const _RadarSkeleton()
          else
            for (final e in entries) _RadarRow(entry: e),
        ],
      ),
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({required this.expiry});
  final DateTime expiry;

  @override
  Widget build(BuildContext context) {
    // 만기까지 D-day (날짜 기준, UTC 만기를 로컬 자정과 비교)
    final today = DateTime.now();
    final expDate = DateTime(expiry.year, expiry.month, expiry.day);
    final nowDate = DateTime(today.year, today.month, today.day);
    final days = expDate.difference(nowDate).inDays;
    final label = days <= 0
        ? '만기 D-day'
        : 'D-$days · ${DateFormat('M/d').format(expiry)}';
    const accent = Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RadarRow extends StatelessWidget {
  const _RadarRow({required this.entry});
  final _RadarEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mp = entry.data;
    final price = mp.underlyingPrice;
    final maxPain = mp.maxPain;

    double? pct;
    if (price != null && price > 0) {
      pct = (maxPain - price) / price * 100;
    }
    final up = (pct ?? 0) >= 0;
    // 상승 여지=빨강, 하락 여지=파랑 (앱 관례)
    final deltaColor = pct == null
        ? cs.onSurface.withValues(alpha: 0.5)
        : up
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        stockDetailRoute(
          stockPickForGeneralDetail(
            ticker: entry.ticker,
            name: entry.ticker,
            market: 'US',
          ),
          enablePickFeatures: false,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                entry.ticker,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // 현재가 → MP 게이지
            Expanded(
              child: _MpGauge(currentPrice: price, maxPain: maxPain),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MP \$${_fmt(maxPain)}',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (pct != null)
                  Text(
                    '${up ? '↑' : '↓'}${pct.abs().toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: deltaColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) => v >= 1000
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
}

/// 현재가(●)와 Max Pain(│) 상대 위치를 보여주는 미니 게이지.
class _MpGauge extends StatelessWidget {
  const _MpGauge({required this.currentPrice, required this.maxPain});
  final double? currentPrice;
  final double maxPain;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (currentPrice == null || currentPrice! <= 0) {
      return const SizedBox(height: 8);
    }
    return SizedBox(
      height: 14,
      child: CustomPaint(
        painter: _GaugePainter(
          currentPrice: currentPrice!,
          maxPain: maxPain,
          trackColor: cs.onSurface.withValues(alpha: 0.12),
          priceColor: cs.onSurface.withValues(alpha: 0.85),
          maxPainColor: const Color(0xFF10B981),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.currentPrice,
    required this.maxPain,
    required this.trackColor,
    required this.priceColor,
    required this.maxPainColor,
  });

  final double currentPrice;
  final double maxPain;
  final Color trackColor;
  final Color priceColor;
  final Color maxPainColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    // 현재가와 MP를 양 끝에서 15% 안쪽에 배치, 나머지는 상대 위치
    final lo = currentPrice < maxPain ? currentPrice : maxPain;
    final hi = currentPrice < maxPain ? maxPain : currentPrice;
    final span = (hi - lo).abs() < 0.001 ? 1.0 : hi - lo;
    const pad = 0.18;
    double xFor(double v) =>
        size.width * (pad + (1 - 2 * pad) * ((v - lo) / span));

    // 트랙
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      Paint()
        ..color = trackColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final px = xFor(currentPrice);
    final mx = xFor(maxPain);

    // 현재가 → MP 연결 구간 강조
    canvas.drawLine(
      Offset(px, cy),
      Offset(mx, cy),
      Paint()
        ..color = maxPainColor.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Max Pain 세로 막대
    canvas.drawLine(
      Offset(mx, cy - 5),
      Offset(mx, cy + 5),
      Paint()
        ..color = maxPainColor
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // 현재가 점
    canvas.drawCircle(Offset(px, cy), 3.4, Paint()..color = priceColor);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.currentPrice != currentPrice || old.maxPain != maxPain;
}

class _RadarSkeleton extends StatelessWidget {
  const _RadarSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
