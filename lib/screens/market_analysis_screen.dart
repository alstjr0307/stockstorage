import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/market_analysis.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import 'earnings_calendar_screen.dart';
import 'index_detail_screen.dart';

class MarketAnalysisScreen extends StatefulWidget {
  const MarketAnalysisScreen({super.key});

  @override
  State<MarketAnalysisScreen> createState() => _MarketAnalysisScreenState();
}

class _MarketAnalysisScreenState extends State<MarketAnalysisScreen> {
  static const _indices = [
    ('KOSPI', '^KS11'),
    ('KOSDAQ', '^KQ11'),
    ('S&P 500', '^GSPC'),
    ('NASDAQ', '^IXIC'),
    ('USD/KRW', 'KRW=X'),
    ('나스닥100 선물', 'NQ=F'),
  ];

  final Map<String, PriceResult?> _prices = {};
  bool _loadingIndices = true;

  FearAndGreedResult? _fearAndGreed;
  bool _loadingFearAndGreed = true;

  @override
  void initState() {
    super.initState();
    _fetchIndices();
    _fetchFearAndGreed();
  }

  Future<void> _fetchIndices() async {
    setState(() => _loadingIndices = true);
    final results = await Future.wait(
      _indices.map((e) => StockPriceService.fetchPrice(e.$2, 'US')),
    );
    if (mounted) {
      setState(() {
        for (var i = 0; i < _indices.length; i++) {
          _prices[_indices[i].$1] = results[i];
        }
        _loadingIndices = false;
      });
    }
  }

  Future<void> _fetchFearAndGreed() async {
    setState(() => _loadingFearAndGreed = true);
    final result = await StockPriceService.fetchFearAndGreed();
    if (mounted) {
      setState(() {
        _fearAndGreed = result;
        _loadingFearAndGreed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: const Color(0xFF4ADE80),
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: () async {
        await Future.wait([_fetchIndices(), _fetchFearAndGreed()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── 공포탐욕지수 섹션 ──
          _buildFearAndGreedCard(context),
          const SizedBox(height: 24),

          // ── 주요 지수 섹션 ──
          Row(
            children: [
              Text(
                '주요 지수',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.54),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_loadingIndices)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF4ADE80)),
                )
              else
                GestureDetector(
                  onTap: _fetchIndices,
                  child: Icon(Icons.refresh,
                      color: cs.onSurface.withValues(alpha: 0.38), size: 16),
                ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: _indices.map((e) => _buildIndexCard(context, e.$1)).toList(),
          ),
          const SizedBox(height: 28),

          // ── 실적 캘린더 섹션 ──
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EarningsCalendarScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_month,
                        color: Color(0xFF4ADE80), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('실적 발표 캘린더',
                            style: GoogleFonts.inter(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Text('추천 종목의 실적 발표 일정 확인',
                            style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.54),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: cs.onSurface.withValues(alpha: 0.38)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── 시황 분석 포스트 섹션 ──
          Text(
            '시황 분석',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.54),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<MarketAnalysis>>(
            stream: FirestoreService().getMarketAnalyses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF4ADE80))),
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      '등록된 시황 분석이 없습니다',
                      style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38)),
                    ),
                  ),
                );
              }
              return Column(
                children: list.map((a) => _buildAnalysisCard(context, a)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _fearAndGreedColor(double score) {
    if (score < 25) return const Color(0xFFEF4444);
    if (score < 45) return const Color(0xFFF97316);
    if (score < 56) return const Color(0xFFEAB308);
    if (score < 75) return const Color(0xFF84CC16);
    return const Color(0xFF4ADE80);
  }

  String _fearAndGreedLabel(String rating) {
    switch (rating.toLowerCase()) {
      case 'extreme fear':
        return '극단적 공포';
      case 'fear':
        return '공포';
      case 'neutral':
        return '중립';
      case 'greed':
        return '탐욕';
      case 'extreme greed':
        return '극단적 탐욕';
      default:
        return rating;
    }
  }

  Widget _buildFearAndGreedCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: _loadingFearAndGreed
          ? const SizedBox(
              height: 80,
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)),
              ),
            )
          : _fearAndGreed == null
              ? SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      '데이터 없음',
                      style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.38),
                          fontSize: 13),
                    ),
                  ),
                )
              : _buildFearAndGreedContent(context, _fearAndGreed!, cs),
    );
  }

  Widget _buildFearAndGreedContent(
      BuildContext context, FearAndGreedResult fg, ColorScheme cs) {
    final color = _fearAndGreedColor(fg.score);
    final label = _fearAndGreedLabel(fg.rating);
    final comparisons = [
      ('전일', fg.previousClose),
      ('1주전', fg.previousWeek),
      ('1달전', fg.previousMonth),
      ('1년전', fg.previousYear),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Row(
          children: [
            Text('공포탐욕지수',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.54),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            const Spacer(),
            Text('S&P 500 기준 · CNN',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),

        // 반원 게이지
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 220,
                height: 115,
                child: CustomPaint(
                  painter: _SemicircleGaugePainter(
                    score: fg.score,
                    trackColor: cs.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fg.score.toStringAsFixed(0),
                style: GoogleFonts.inter(
                    color: color,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    height: 1),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: GoogleFonts.inter(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // 구간 라벨
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('극도 공포',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.3),
                      fontSize: 10)),
              Text('극도 탐욕',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.3),
                      fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 비교 칩
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: comparisons.map((c) {
            final prev = c.$2;
            final isUp = fg.score >= prev;
            final chipColor = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(c.$1,
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(
                      '${isUp ? '▲' : '▼'} ${prev.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                          color: chipColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildIndexCard(BuildContext context, String name) {
    final entry = _indices.firstWhere((e) => e.$1 == name);
    final result = _prices[name];
    final isUp = result?.isUp ?? true;
    final color = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IndexDetailScreen(
            name: name,
            symbol: entry.$2,
            initialPrice: result,
          ),
        ),
      ),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            name,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.54),
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          if (_loadingIndices)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFF4ADE80)),
            )
          else if (result == null)
            Text('--',
                style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 13))
          else ...[
            Text(
              _formatValue(name, result),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            Text(
              '${isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: color, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
      ),
    );
  }

  String _formatValue(String name, PriceResult result) {
    if (name == 'USD/KRW') {
      return '₩${NumberFormat('#,###').format(result.price.toInt())}';
    }
    if (result.isKrw) {
      return NumberFormat('#,###').format(result.price.toInt());
    }
    return NumberFormat('#,##0.00').format(result.price);
  }

  Widget _buildAnalysisCard(BuildContext context, MarketAnalysis a) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('yyyy년 MM월 dd일').format(a.createdAt),
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.38), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  a.title,
                  style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  a.body,
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.7), fontSize: 14, height: 1.9),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy.MM.dd').format(a.createdAt),
              style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11),
            ),
            const SizedBox(height: 5),
            Text(
              a.title,
              style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              a.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.54), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SemicircleGaugePainter extends CustomPainter {
  final double score;
  final Color trackColor;

  const _SemicircleGaugePainter({
    required this.score,
    required this.trackColor,
  });

  static const _segments = [
    (0.0,  0.25, Color(0xFFEF4444)),
    (0.25, 0.45, Color(0xFFF97316)),
    (0.45, 0.55, Color(0xFFEAB308)),
    (0.55, 0.75, Color(0xFF84CC16)),
    (0.75, 1.0,  Color(0xFF4ADE80)),
  ];

  Color get _needleColor {
    for (final s in _segments) {
      if (score / 100 <= s.$2) return s.$3;
    }
    return _segments.last.$3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;          // 바닥에 중심
    final radius = size.width * 0.44;
    const strokeWidth = 14.0;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // 트랙 (전체 반원)
    canvas.drawArc(
      rect, startAngle, sweepAngle, false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt,
    );

    // 구간별 색상 아크 (score까지만)
    final pct = (score / 100).clamp(0.0, 1.0);
    for (final seg in _segments) {
      final segStart = seg.$1;
      final segEnd = seg.$2;
      final segColor = seg.$3;
      if (pct <= segStart) break;
      final drawEnd = pct < segEnd ? pct : segEnd;
      canvas.drawArc(
        rect,
        startAngle + sweepAngle * segStart,
        sweepAngle * (drawEnd - segStart),
        false,
        Paint()
          ..color = segColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
    }

    // 바늘
    final needleAngle = startAngle + sweepAngle * pct;
    final needleLen = radius - strokeWidth - 4;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + needleLen * math.cos(needleAngle),
             cy + needleLen * math.sin(needleAngle)),
      Paint()
        ..color = _needleColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 중심 원
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = _needleColor);
  }

  @override
  bool shouldRepaint(_SemicircleGaugePainter old) => old.score != score;
}
