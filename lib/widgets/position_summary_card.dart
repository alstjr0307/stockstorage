import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/trading_journal.dart';
import '../services/stock_price_service.dart';

// ─────────────────────────────────────────────────────────────
// PositionSummaryCard
// 사용법:
//   PositionSummaryCard(
//     journals: journals,          // List<TradingJournal> — 매수 일지만
//     livePrices: livePrices,      // Map<ticker, double> — 실시간 현재가
//   )
// ─────────────────────────────────────────────────────────────

const _kUpColor = Color(0xFFF04452);
const _kDownColor = Color(0xFF1677FF);
const _kAccent = Color(0xFF10B981);

class PositionSummaryCard extends StatefulWidget {
  final List<TradingJournal> journals;
  final Map<String, double> livePrices;

  const PositionSummaryCard({
    super.key,
    required this.journals,
    required this.livePrices,
  });

  @override
  State<PositionSummaryCard> createState() => _PositionSummaryCardState();
}

class _PositionSummaryCardState extends State<PositionSummaryCard> {
  bool _expanded = true;
  final _formatter = NumberFormat('#,###');

  // 종목별 평가금액 계산
  List<_PositionItem> get _positions {
    // 매수 일지만
    final buys = widget.journals.where((j) => j.action == '매수').toList();
    // ticker별 그룹핑
    final Map<String, List<TradingJournal>> grouped = {};
    for (final j in buys) {
      grouped.putIfAbsent(j.ticker, () => []).add(j);
    }

    return grouped.entries.map((e) {
      final ticker = e.key;
      final list = e.value;
      // 잔량: 전체 매수수량 합산 (매도 차감은 linkedBuyId로 처리 — 여기선 간략화)
      final totalQty = list.fold(0.0, (s, j) => s + j.quantity);
      final avgBuyPrice = list.fold(0.0, (s, j) => s + j.price * j.quantity)
          / totalQty;
      final livePrice = widget.livePrices[ticker] ?? avgBuyPrice;
      final evalAmt = livePrice * totalQty;
      final profit = (livePrice - avgBuyPrice) * totalQty;

      return _PositionItem(
        ticker: ticker,
        name: list.first.stockName,
        market: list.first.market,
        totalQty: totalQty,
        avgBuyPrice: avgBuyPrice,
        livePrice: livePrice,
        evalAmount: evalAmt,
        profit: profit,
      );
    }).toList()
      ..sort((a, b) => b.evalAmount.compareTo(a.evalAmount));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

    final segments = positions.asMap().entries.map((e) => _DonutSegment(
      color: segColors[e.key % segColors.length],
      value: e.value.evalAmount,
      label: e.value.name,
    )).toList();

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 헤더 ──────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  '보유 ${positions.length}',
                  style: GoogleFonts.inter(
                    color: _kAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '내 포지션',
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: cs.onSurface.withValues(alpha: 0.3),
                  size: 20,
                ),
              ),
            ]),

            // ── 펼침 내용 ──────────────────────────────────────
            if (_expanded) ...[
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
                              Row(children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: seg.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    seg.label,
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(alpha: 0.55),
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: GoogleFonts.robotoMono(
                                    color: cs.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ]),
                              Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Text(
                                  '₩${_formatter.format(pos.evalAmount.toInt())}',
                                  style: GoogleFonts.robotoMono(
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
                    top: BorderSide(
                      color: cs.onSurface.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(children: [
                  // 총 평가금액
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '총 평가금액',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₩${_formatter.format(totalEval.toInt())}',
                          style: GoogleFonts.robotoMono(
                            color: cs.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1, height: 40,
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
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isPositive ? '+' : ''}₩${_formatter.format(totalProfit.toInt())}',
                          style: GoogleFonts.robotoMono(
                            color: isPositive ? _kUpColor : _kDownColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${isPositive ? '+' : ''}${totalRate.toStringAsFixed(2)}%',
                          style: GoogleFonts.robotoMono(
                            color: isPositive ? _kUpColor : _kDownColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
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
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.segments != segments ||
      old.centerValue != centerValue;
}
