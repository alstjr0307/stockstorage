import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/trading_journal.dart';

// ─────────────────────────────────────────────────────────────
// PositionSummaryCard
// 사용법:
//   PositionSummaryCard(
//     journals: journals,          // List<TradingJournal> — 전체 일지
//     livePrices: livePrices,      // Map<market:ticker, double> — 실시간 현재가
//   )
// ─────────────────────────────────────────────────────────────

const _kUpColor = Color(0xFFF04452);
const _kDownColor = Color(0xFF1677FF);
const _kQtyEpsilon = 1e-6;
const _kUsdToKrw = 1480.0;

class PositionSummaryCard extends StatefulWidget {
  final List<TradingJournal> journals;
  final Map<String, double> livePrices;
  final EdgeInsetsGeometry margin;

  const PositionSummaryCard({
    super.key,
    required this.journals,
    required this.livePrices,
    this.margin = const EdgeInsets.fromLTRB(20, 0, 20, 16),
  });

  @override
  State<PositionSummaryCard> createState() => _PositionSummaryCardState();
}

class _PositionSummaryCardState extends State<PositionSummaryCard> {
  final _formatter = NumberFormat('#,###');

  String _priceKey(String market, String ticker) => '$market:$ticker';

  // 종목별 평가금액 계산
  List<_PositionItem> get _positions {
    final buysByStock = <String, List<TradingJournal>>{};
    final sellQtyByStock = <String, double>{};
    for (final journal in widget.journals) {
      if (journal.ticker.isEmpty) continue;
      final key = _priceKey(journal.market, journal.ticker);
      if (journal.action == '매수') {
        buysByStock.putIfAbsent(key, () => <TradingJournal>[]).add(journal);
      } else if (journal.action == '매도') {
        sellQtyByStock.update(
          key,
          (value) => value + journal.quantity,
          ifAbsent: () => journal.quantity,
        );
      }
    }

    final positions = <_PositionItem>[];
    for (final entry in buysByStock.entries) {
      final buys = entry.value
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      var soldLeft = sellQtyByStock[entry.key] ?? 0.0;
      var remainingQty = 0.0;
      var remainingCost = 0.0;

      for (final buy in buys) {
        final consumed = soldLeft > buy.quantity ? buy.quantity : soldLeft;
        final remain = (buy.quantity - consumed).clamp(0.0, buy.quantity);
        if (remain > _kQtyEpsilon) {
          remainingQty += remain;
          remainingCost += buy.price * remain;
        }
        soldLeft = soldLeft > consumed ? soldLeft - consumed : 0.0;
      }
      if (remainingQty <= _kQtyEpsilon) {
        continue;
      }

      final avgBuyPrice = remainingCost / remainingQty;
      final livePrice = widget.livePrices[entry.key] ?? avgBuyPrice;
      final first = buys.first;
      final fxRate = first.market == 'US' ? _kUsdToKrw : 1.0;
      final evalAmt = livePrice * remainingQty * fxRate;
      final profit = (livePrice - avgBuyPrice) * remainingQty * fxRate;

      positions.add(
        _PositionItem(
          ticker: first.ticker,
          name: first.stockName,
          market: first.market,
          totalQty: remainingQty,
          avgBuyPrice: avgBuyPrice,
          livePrice: livePrice,
          evalAmount: evalAmt,
          profit: profit,
        ),
      );
    }

    positions.sort((a, b) => b.evalAmount.compareTo(a.evalAmount));
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final positions = _positions;
    if (positions.isEmpty) return const SizedBox.shrink();

    final totalEval = positions.fold(0.0, (s, p) => s + p.evalAmount);
    final totalProfit = positions.fold(0.0, (s, p) => s + p.profit);
    final totalCost = totalEval - totalProfit;
    final totalRate = totalCost > 0 ? (totalProfit / totalCost) * 100 : 0.0;
    final isPositive = totalProfit >= 0;

    // 도넛 세그먼트 색상
    const segColors = [
      Color(0xFF3182F6),
      Color(0xFF34D399),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
    ];

    final segments = positions
        .asMap()
        .entries
        .map(
          (e) => _DonutSegment(
            color: segColors[e.key % segColors.length],
            value: e.value.evalAmount,
            label: e.value.name,
          ),
        )
        .toList();

    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '보유 종목',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          ...[
            const SizedBox(height: 16),

            // 행 1: 도넛 차트(110px) + 범례
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 도넛 차트
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CustomPaint(
                    painter: _DonutChartPainter(
                      segments: segments,
                      centerLabel: '보유',
                      centerValue: '${positions.length}종목',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 범례
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: segments.asMap().entries.map((e) {
                      final seg = e.value;
                      final pos = positions[e.key];
                      final pct = totalEval > 0
                          ? (seg.value / totalEval * 100).toStringAsFixed(0)
                          : '0';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: seg.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    seg.label,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.95)
                                          : cs.onSurface.withValues(
                                              alpha: 0.88,
                                            ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Text(
                                '₩${_formatter.format(pos.evalAmount.toInt())}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.38),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            // 행 2: 총 평가금액 / 평가손익 — 별도 행
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                children: [
                  // 총 평가금액
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '총 평가금액',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₩${_formatter.format(totalEval.toInt())}',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: cs.onSurface.withValues(alpha: 0.06),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  // 평가손익
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '평가손익',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isPositive ? '+' : ''}₩${_formatter.format(totalProfit.toInt())}',
                          style: TextStyle(
                            color: isPositive ? _kUpColor : _kDownColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${isPositive ? '+' : ''}${totalRate.toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: isPositive ? _kUpColor : _kDownColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 내부 데이터 클래스
// ─────────────────────────────────────────────────────────────

class _PositionItem {
  final String ticker;
  final String name;
  final String market;
  final double totalQty;
  final double avgBuyPrice;
  final double livePrice;
  final double evalAmount;
  final double profit;

  const _PositionItem({
    required this.ticker,
    required this.name,
    required this.market,
    required this.totalQty,
    required this.avgBuyPrice,
    required this.livePrice,
    required this.evalAmount,
    required this.profit,
  });
}

class _DonutSegment {
  final Color color;
  final double value;
  final String label;

  const _DonutSegment({
    required this.color,
    required this.value,
    required this.label,
  });
}

// ─────────────────────────────────────────────────────────────
// 도넛 차트 CustomPainter
// ─────────────────────────────────────────────────────────────

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final String centerLabel;
  final String centerValue;

  const _DonutChartPainter({
    required this.segments,
    required this.centerLabel,
    required this.centerValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (s, e) => s + e.value);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 10.0;

    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweep = (seg.value / total) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += sweep;
    }

    // 중앙 라벨
    _paintText(
      canvas,
      centerLabel,
      const TextStyle(
        color: Colors.white38,
        fontSize: 9,
        fontFamily: 'Pretendard',
      ),
      Offset(center.dx, center.dy - 9),
    );

    // 중앙 값
    _paintText(
      canvas,
      centerValue,
      const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFamily: 'JetBrainsMono',
      ),
      Offset(center.dx, center.dy + 7),
    );
  }

  void _paintText(Canvas canvas, String text, TextStyle style, Offset center) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.segments != segments || old.centerValue != centerValue;
}
