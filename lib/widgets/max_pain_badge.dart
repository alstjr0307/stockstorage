import 'package:flutter/material.dart';

import '../services/stock_price_service.dart';

/// 관심종목/리스트 행에 붙이는 컴팩트 Max Pain 칩.
/// 미국주식(market == 'US')에서만 렌더링되고, 그 외/로딩/실패 시에는
/// SizedBox.shrink() 로 자리를 차지하지 않는다.
///
/// [currentPrice] 가 주어지면 현재가 대비 괴리율(↑/↓ %)을 함께 표시한다.
class MaxPainBadge extends StatefulWidget {
  const MaxPainBadge({
    super.key,
    required this.ticker,
    required this.market,
    this.currentPrice,
    this.compact = false,
  });

  final String ticker;
  final String market;
  final double? currentPrice;

  /// true면 아이콘/라벨을 생략하고 최소 크기로 렌더 (리스트 행용).
  final bool compact;

  @override
  State<MaxPainBadge> createState() => _MaxPainBadgeState();
}

class _MaxPainBadgeState extends State<MaxPainBadge> {
  Future<MaxPainResult?>? _future;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant MaxPainBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticker != widget.ticker ||
        oldWidget.market != widget.market) {
      _future = null;
      _maybeLoad();
    }
  }

  void _maybeLoad() {
    if (widget.market != 'US') return;
    _future = StockPriceService.fetchMaxPain(widget.ticker, widget.market);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.market != 'US' || _future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<MaxPainResult?>(
      future: _future,
      builder: (context, snapshot) {
        final mp = snapshot.data;
        if (mp == null) return const SizedBox.shrink();
        return _MaxPainChip(
          maxPain: mp.maxPain,
          currentPrice: widget.currentPrice ?? mp.underlyingPrice,
          compact: widget.compact,
        );
      },
    );
  }
}

class _MaxPainChip extends StatelessWidget {
  const _MaxPainChip({
    required this.maxPain,
    required this.currentPrice,
    required this.compact,
  });

  final double maxPain;
  final double? currentPrice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF10B981);

    String deltaText = '';
    Color deltaColor = cs.onSurface.withValues(alpha: 0.55);
    if (currentPrice != null && currentPrice! > 0) {
      final pct = (maxPain - currentPrice!) / currentPrice! * 100;
      final up = pct >= 0;
      deltaText = ' ${up ? '↑' : '↓'}${pct.abs().toStringAsFixed(1)}%';
      // 상승 여지(빨강)/하락 여지(파랑) — 앱 관례(상승=빨강)와 통일
      deltaColor = up ? const Color(0xFFF04452) : const Color(0xFF1677FF);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MP',
            style: TextStyle(
              color: accent,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '\$${_fmt(maxPain)}',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.85),
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (deltaText.isNotEmpty)
            Text(
              deltaText,
              style: TextStyle(
                color: deltaColor,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
  }
}
