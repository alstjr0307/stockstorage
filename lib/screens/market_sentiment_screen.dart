import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../services/stock_price_service.dart';

class MarketSentimentScreen extends StatefulWidget {
  const MarketSentimentScreen({super.key});

  @override
  State<MarketSentimentScreen> createState() => _MarketSentimentScreenState();
}

class _MarketSentimentScreenState extends State<MarketSentimentScreen> {
  final _captureKey = GlobalKey();
  final Map<String, PriceResult?> _prices = {};

  FearAndGreedResult? _fearAndGreed;
  bool _loadingPrices = true;
  bool _loadingFearAndGreed = true;
  bool _capturing = false;
  bool _showWatermark = false;

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  static const _symbols = [
    ('VIX 공포지수', '^VIX'),
    ('미 10년 국채금리', '^TNX'),
    ('미 3개월 국채금리', '^IRX'),
    ('달러 인덱스', 'DX-Y.NYB'),
    ('구리', 'HG=F'),
    ('금', 'GC=F'),
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([_fetchPrices(), _fetchFearAndGreed()]);
  }

  Future<void> _fetchPrices() async {
    if (mounted) setState(() => _loadingPrices = true);
    try {
      final results = await Future.wait(
        _symbols.map((item) => StockPriceService.fetchPrice(item.$2, 'US')),
      );
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _symbols.length; i++) {
          _prices[_symbols[i].$1] = results[i];
        }
      });
    } finally {
      if (mounted) setState(() => _loadingPrices = false);
    }
  }

  Future<void> _fetchFearAndGreed() async {
    if (mounted) setState(() => _loadingFearAndGreed = true);
    final result = await StockPriceService.fetchFearAndGreed();
    if (!mounted) return;
    setState(() {
      _fearAndGreed = result;
      _loadingFearAndGreed = false;
    });
  }

  Future<void> _captureAndShare() async {
    setState(() {
      _capturing = true;
      _showWatermark = true;
    });
    await Future.delayed(const Duration(milliseconds: 80));
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File(
        '${Directory.systemTemp.path}/sentiment_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '📊 주식저장소 시장 심리 지표',
        sharePositionOrigin: _shareOrigin(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _showWatermark = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '시장 심리 지표',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF4ADE80),
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: Container(
                width: double.infinity,
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(context, '공포 & 탐욕'),
                    const SizedBox(height: 10),
                    _buildFearAndGreedCard(context),
                    const SizedBox(height: 24),
                    _sectionLabel(context, '변동성'),
                    const SizedBox(height: 10),
                    _buildMetricCard(
                      context,
                      title: 'VIX 공포지수',
                      benchmarkText: '20 이하 안정 · 30 이상 경계',
                      description:
                          'S&P 500 옵션 가격으로 계산하는 대표 변동성 지수입니다. 보통 20 아래면 비교적 안정적이고, 30 이상이면 시장이 급격히 불안해진 상태로 해석하는 경우가 많습니다.',
                      valueText: _priceText('VIX 공포지수', ''),
                      changeText: _changeRateText('VIX 공포지수'),
                    ),
                    const SizedBox(height: 24),
                    _sectionLabel(context, '금리'),
                    const SizedBox(height: 10),
                    _buildMetricCard(
                      context,
                      title: '미 10년 국채금리',
                      benchmarkText: '4% 전후 부담선 · 4.5% 이상 긴장',
                      description:
                          '미국 장기 시장금리의 기준처럼 보는 지표입니다. 금리가 빠르게 오르면 성장주 밸류에이션 부담이 커질 수 있고, 반대로 하락하면 주식시장에 우호적으로 해석되기도 합니다.',
                      valueText: _priceText('미 10년 국채금리', '%'),
                      changeText: _changeRateText('미 10년 국채금리'),
                    ),
                    const SizedBox(height: 12),
                    _buildMetricCard(
                      context,
                      title: '장단기 금리차',
                      benchmarkText: '0%p 아래 역전 · +1%p 안팎 정상',
                      description:
                          '미 10년물 금리에서 3개월물 금리를 뺀 값입니다. 이 수치가 마이너스가 되면 금리 역전으로 보며, 경기 둔화나 침체 우려 신호로 자주 언급됩니다.',
                      valueText: _spreadValue(),
                      changeText: _spreadChange(),
                    ),
                    const SizedBox(height: 24),
                    _sectionLabel(context, '경기 심리'),
                    const SizedBox(height: 10),
                    _buildMetricCard(
                      context,
                      title: '구리/금 비율',
                      benchmarkText: '상승세면 경기 선호 · 하락세면 방어 선호',
                      description:
                          '구리는 경기민감 자산, 금은 대표 안전자산으로 자주 비교됩니다. 비율이 오르면 경기 회복 기대가 강해지고, 내려가면 방어 심리나 둔화 우려가 커진 것으로 해석할 수 있습니다.',
                      valueText: _copperGoldValue(),
                      changeText: _copperGoldChange(),
                    ),
                    const SizedBox(height: 12),
                    _buildMetricCard(
                      context,
                      title: '달러 인덱스',
                      benchmarkText: '100 중립선 · 105 이상 강달러 경계',
                      description:
                          '주요 6개 통화 대비 달러의 상대 강도를 보여주는 지수입니다. 달러가 강해지면 신흥국 자산과 원자재에 부담이 생기기 쉽고, 약해지면 위험자산 선호가 살아나는 흐름이 나타나기도 합니다.',
                      valueText: _priceText('달러 인덱스', ''),
                      changeText: _changeRateText('달러 인덱스'),
                    ),
                    if (_showWatermark) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          '주식저장소 앱에서 확인하세요',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _capturing ? null : _captureAndShare,
              icon: _capturing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.camera_alt_outlined, color: Colors.black),
              label: Text(
                _capturing ? '캡처 중...' : '캡처해서 공유하기',
                style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4ADE80),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              color: cs.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 96,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFearAndGreedCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loadingFearAndGreed) {
      return _SurfaceCard(child: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80)))));
    }
    if (_fearAndGreed == null) {
      return _SurfaceCard(child: SizedBox(height: 80, child: Center(child: Text('데이터 없음', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4))))));
    }

    final fg = _fearAndGreed!;
    final color = _fearAndGreedColor(fg.score);
    final comparisons = [
      ('전일', fg.previousClose),
      ('1주전', fg.previousWeek),
      ('1달전', fg.previousMonth),
      ('1년전', fg.previousYear),
    ];

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Text('공포탐욕지수', style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              Text('S&P 500 기준 · CNN', style: GoogleFonts.inter(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35))),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 240,
                  height: 122,
                  child: CustomPaint(
                    painter: SemicircleGaugePainter(score: fg.score, trackColor: cs.onSurface.withValues(alpha: 0.08)),
                  ),
                ),
                Text(fg.score.toStringAsFixed(0), style: GoogleFonts.inter(color: color, fontSize: 44, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(height: 4),
                Text(_fearAndGreedLabel(fg.rating), style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: comparisons.map((item) {
              final isUp = fg.score >= item.$2;
              final chipColor = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
              return Container(
                width: 72,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text(item.$1, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.45))),
                    const SizedBox(height: 4),
                    Text('${isUp ? '▲' : '▼'} ${item.$2.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: chipColor)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String benchmarkText,
    required String description,
    required String valueText,
    required String? changeText,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = changeText == null || !changeText.startsWith('-');
    final color = isPositive ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface, letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text(
            benchmarkText,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  valueText,
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: valueText == '--' ? 20 : 32,
                    height: 1,
                  ),
                ),
              ),
              if (changeText != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
                      child: Text(changeText, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 4),
                    Text('전일 대비', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.34), fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 1,
            color: cs.onSurface.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.58),
              fontSize: 12.5,
              height: 1.58,
            ),
          ),
        ],
      ),
    );
  }

  String _priceText(String key, String unit) {
    if (_loadingPrices) return '...';
    final result = _prices[key];
    if (result == null) return '--';
    return '${result.price.toStringAsFixed(2)}$unit';
  }

  String? _changeRateText(String key) {
    if (_loadingPrices) return null;
    final result = _prices[key];
    if (result == null) return null;
    return '${result.isUp ? '+' : ''}${result.changeRate.toStringAsFixed(2)}%';
  }

  String _spreadValue() {
    if (_loadingPrices) return '...';
    final t10 = _prices['미 10년 국채금리']?.price;
    final t3m = _prices['미 3개월 국채금리']?.price;
    if (t10 == null || t3m == null) return '--';
    final value = t10 - t3m;
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%p';
  }

  String? _spreadChange() {
    if (_loadingPrices) return null;
    final t10 = _prices['미 10년 국채금리'];
    final t3m = _prices['미 3개월 국채금리'];
    if (t10 == null || t3m == null) return null;
    final prevSpread = (t10.price - t10.change) - (t3m.price - t3m.change);
    final currSpread = t10.price - t3m.price;
    final change = currSpread - prevSpread;
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%p';
  }

  String _copperGoldValue() {
    if (_loadingPrices) return '...';
    final copper = _prices['구리']?.price;
    final gold = _prices['금']?.price;
    if (copper == null || gold == null || gold == 0) return '--';
    return (copper / gold * 1000).toStringAsFixed(2);
  }

  String? _copperGoldChange() {
    if (_loadingPrices) return null;
    final copper = _prices['구리'];
    final gold = _prices['금'];
    if (copper == null || gold == null || gold.price == 0) return null;
    final prevCopper = copper.price - copper.change;
    final prevGold = gold.price - gold.change;
    if (prevGold == 0) return null;
    final curr = copper.price / gold.price * 1000;
    final prev = prevCopper / prevGold * 1000;
    final change = curr - prev;
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}';
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
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.018),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SemicircleGaugePainter extends CustomPainter {
  const SemicircleGaugePainter({
    required this.score,
    required this.trackColor,
  });

  final double score;
  final Color trackColor;

  static const _segments = [
    (0.0, 0.25, Color(0xFFEF4444)),
    (0.25, 0.45, Color(0xFFF97316)),
    (0.45, 0.55, Color(0xFFEAB308)),
    (0.55, 0.75, Color(0xFF84CC16)),
    (0.75, 1.0, Color(0xFF4ADE80)),
  ];

  Color get _needleColor {
    for (final segment in _segments) {
      if (score / 100 <= segment.$2) return segment.$3;
    }
    return _segments.last.$3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;
    final radius = size.width * 0.44;
    const strokeWidth = 14.0;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt,
    );

    final pct = (score / 100).clamp(0.0, 1.0);
    for (final segment in _segments) {
      final segStart = segment.$1;
      final segEnd = segment.$2;
      if (pct <= segStart) break;
      final drawEnd = pct < segEnd ? pct : segEnd;
      canvas.drawArc(
        rect,
        startAngle + sweepAngle * segStart,
        sweepAngle * (drawEnd - segStart),
        false,
        Paint()
          ..color = segment.$3
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
    }

    final needleAngle = startAngle + sweepAngle * pct;
    final needleLen = radius - strokeWidth - 4;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + needleLen * math.cos(needleAngle), cy + needleLen * math.sin(needleAngle)),
      Paint()
        ..color = _needleColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = _needleColor);
  }

  @override
  bool shouldRepaint(covariant SemicircleGaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.trackColor != trackColor;
  }
}
