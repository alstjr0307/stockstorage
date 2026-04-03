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
        text: '주식저장소 시장 심리 지표',
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
    final captureFrame = _showWatermark || _capturing;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          '시장 심리 지표',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: cs.onSurface,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: captureFrame
                    ? const EdgeInsets.fromLTRB(12, 12, 12, 16)
                    : EdgeInsets.zero,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(captureFrame ? 18 : 0),
                  ),
                  padding: captureFrame
                      ? const EdgeInsets.symmetric(horizontal: 4)
                      : EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildAnimatedBlocks(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            _StaggerReveal(
              delay: const Duration(milliseconds: 740),
              child: FilledButton.icon(
                onPressed: _capturing ? null : _captureAndShare,
                icon: _capturing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _capturing ? '캡처 중...' : '캡처해서 공유하기',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAnimatedBlocks(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return [
      _StaggerReveal(
        delay: const Duration(milliseconds: 40),
        child: _buildSectionHeader(context, '공포와 탐욕'),
      ),
      const SizedBox(height: 6),
      _StaggerReveal(
        delay: const Duration(milliseconds: 150),
        child: _buildFearAndGreedBlock(context),
      ),
      const SizedBox(height: 20),
      _StaggerReveal(
        delay: const Duration(milliseconds: 260),
        child: _buildSectionHeader(context, '핵심 지표'),
      ),
      const SizedBox(height: 4),
      _StaggerReveal(
        delay: const Duration(milliseconds: 360),
        child: _buildMetricRow(
          context,
          title: 'VIX 공포지수',
          benchmarkText: '20 이하 안정, 30 이상 경계',
          valueText: _priceText('VIX 공포지수', ''),
          changeText: _changeRateText('VIX 공포지수'),
          description:
              '옵션 가격 기반의 대표 변동성 지표로, 급등 시 시장 불안 심리가 커졌다는 신호로 자주 해석됩니다.',
        ),
      ),
      _StaggerReveal(
        delay: const Duration(milliseconds: 470),
        child: _buildMetricRow(
          context,
          title: '미 10년 국채금리',
          benchmarkText: '4% 전후 부담선',
          valueText: _priceText('미 10년 국채금리', '%'),
          changeText: _changeRateText('미 10년 국채금리'),
          description:
              '장기 금리 기준점 역할을 하며, 금리 상승은 성장주 부담, 하락은 위험자산 선호 회복으로 연결되기 쉽습니다.',
        ),
      ),
      _StaggerReveal(
        delay: const Duration(milliseconds: 580),
        child: _buildMetricRow(
          context,
          title: '장단기 금리차',
          benchmarkText: '0%p 아래 역전 구간',
          valueText: _spreadValue(),
          changeText: _spreadChange(),
          description:
              '10년물과 3개월물의 차이입니다. 음수 구간이 길어질수록 경기 둔화 우려가 커졌다는 신호로 봅니다.',
        ),
      ),
      _StaggerReveal(
        delay: const Duration(milliseconds: 690),
        child: _buildMetricRow(
          context,
          title: '구리/금 비율',
          benchmarkText: '상승: 경기 선호, 하락: 방어 선호',
          valueText: _copperGoldValue(),
          changeText: _copperGoldChange(),
          description:
              '경기민감 자산인 구리와 안전자산인 금의 상대 강도로, 위험 선호 흐름을 가늠할 때 자주 참고합니다.',
        ),
      ),
      _StaggerReveal(
        delay: const Duration(milliseconds: 800),
        child: _buildMetricRow(
          context,
          title: '달러 인덱스',
          benchmarkText: '100 중립, 105 이상 강달러',
          valueText: _priceText('달러 인덱스', ''),
          changeText: _changeRateText('달러 인덱스'),
          description:
              '달러 강세는 신흥국 자산과 원자재에 부담, 약세는 위험자산 회복 분위기로 이어지는 경우가 많습니다.',
          showDivider: false,
        ),
      ),
      if (_showWatermark) ...[
        _StaggerReveal(
          delay: const Duration(milliseconds: 900),
          child: const SizedBox(height: 14),
        ),
        _StaggerReveal(
          delay: const Duration(milliseconds: 940),
          child: Center(
            child: Text(
              '주식저장소 앱에서 확인하세요',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.42),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '실시간 시장 온도와 흐름을 확인하세요',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.45),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.onSurface.withValues(alpha: 0.08),
        ),
      ],
    );
  }

  Widget _buildFearAndGreedBlock(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loadingFearAndGreed) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }
    if (_fearAndGreed == null) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            '데이터 없음',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    final fg = _fearAndGreed!;
    final color = _fearAndGreedColor(fg.score);
    final comparisons = [
      ('전일', fg.previousClose),
      ('1주 전', fg.previousWeek),
      ('1개월 전', fg.previousMonth),
      ('1년 전', fg.previousYear),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Fear & Greed',
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'CNN 기준',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 240,
                height: 122,
                child: CustomPaint(
                  painter: SemicircleGaugePainter(
                    score: fg.score,
                    trackColor: cs.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Text(
                fg.score.toStringAsFixed(0),
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fearAndGreedLabel(fg.rating),
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: comparisons.map((item) {
            final isUp = fg.score >= item.$2;
            final chipColor = isUp
                ? const Color(0xFFF04452)
                : const Color(0xFF1677FF);
            return Container(
              width: 78,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    item.$1,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isUp ? '▲' : '▼'} ${item.$2.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: chipColor,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String title,
    required String benchmarkText,
    required String description,
    required String valueText,
    required String? changeText,
    bool showDivider = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = changeText == null || !changeText.startsWith('-');
    final color = isPositive ? const Color(0xFFF04452) : const Color(0xFF1677FF);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        benchmarkText,
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    valueText,
                    style: GoogleFonts.robotoMono(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: valueText == '--' ? 20 : 31,
                      height: 1,
                    ),
                  ),
                  if (changeText != null) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        changeText,
                        style: GoogleFonts.inter(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.58),
              fontSize: 12.5,
              height: 1.56,
            ),
          ),
          if (showDivider) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              thickness: 1,
              color: cs.onSurface.withValues(alpha: 0.08),
            ),
          ],
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
    if (score < 75) return const Color(0xFF10B981);
    return const Color(0xFF10B981);
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

class _StaggerReveal extends StatefulWidget {
  const _StaggerReveal({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<_StaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curve);
    _play();
  }

  Future<void> _play() async {
    if (widget.delay > Duration.zero) {
      await Future.delayed(widget.delay);
    }
    if (mounted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: RepaintBoundary(child: widget.child),
      ),
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
    (0.55, 0.75, Color(0xFF10B981)),
    (0.75, 1.0, Color(0xFF10B981)),
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
      Offset(
        cx + needleLen * math.cos(needleAngle),
        cy + needleLen * math.sin(needleAngle),
      ),
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


