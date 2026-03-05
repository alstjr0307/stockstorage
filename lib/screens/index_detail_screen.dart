import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/stock_price_service.dart';

typedef _OHLC = ({DateTime date, double open, double high, double low, double close});

enum _Period {
  min1('1분봉', '1m', '1d'),
  day1('1일봉', '1d', '1mo'),
  week('주봉', '1wk', '6mo'),
  month('월봉', '1mo', '2y');

  const _Period(this.label, this.interval, this.range);
  final String label;
  final String interval;
  final String range;
}

class IndexDetailScreen extends StatefulWidget {
  final String name;
  final String symbol;
  final PriceResult? initialPrice;

  const IndexDetailScreen({
    super.key,
    required this.name,
    required this.symbol,
    this.initialPrice,
  });

  @override
  State<IndexDetailScreen> createState() => _IndexDetailScreenState();
}

class _IndexDetailScreenState extends State<IndexDetailScreen> {
  PriceResult? _price;
  List<_OHLC> _candles = [];
  bool _loadingPrice = false;
  bool _loadingChart = true;
  int? _touchedIndex;
  _Period _selectedPeriod = _Period.day1;

  // 줌/패닝 상태
  int _visibleCount = 0; // 0 = 전체 표시
  int _startIdx = 0;
  int _visibleCountAtScaleStart = 0;
  int _startIdxAtScaleStart = 0;
  double _focalFractionAtScaleStart = 0;
  Offset? _lastFocalPoint;

  List<_OHLC> get _displayCandles {
    if (_candles.isEmpty) return [];
    final count = _visibleCount > 0 ? _visibleCount.clamp(1, _candles.length) : _candles.length;
    final start = _startIdx.clamp(0, _candles.length - count);
    return _candles.sublist(start, start + count);
  }

  @override
  void initState() {
    super.initState();
    _price = widget.initialPrice;
    if (_price == null) _fetchPrice();
    _fetchCandles();
  }

  Future<void> _fetchPrice() async {
    setState(() => _loadingPrice = true);
    final result = await StockPriceService.fetchPrice(widget.symbol, 'US');
    if (mounted) setState(() { _price = result; _loadingPrice = false; });
  }

  Future<void> _fetchCandles() async {
    final data = await StockPriceService.fetchOHLC(
      widget.symbol, 'US',
      interval: _selectedPeriod.interval,
      range: _selectedPeriod.range,
    );
    if (mounted) setState(() {
      _candles = data;
      _loadingChart = false;
      _visibleCount = 0;
      _startIdx = 0;
    });
  }

  Future<void> _refresh() async {
    StockPriceService.invalidateCache(widget.symbol);
    setState(() { _loadingPrice = true; _loadingChart = true; _touchedIndex = null; });
    await Future.wait([_fetchPrice(), _fetchCandles()]);
  }

  void _selectPeriod(_Period period) {
    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
      _loadingChart = true;
      _touchedIndex = null;
      _visibleCount = 0;
      _startIdx = 0;
    });
    _fetchCandles();
  }

  String _formatValue(double v) {
    final name = widget.name;
    if (name == 'USD/KRW' || name == '환율(엔)') {
      return '₩${NumberFormat('#,###').format(v.toInt())}';
    }
    if (_price?.isKrw ?? false) return NumberFormat('#,###').format(v.toInt());
    return NumberFormat('#,##0.00').format(v);
  }

  String _formatChange(PriceResult r) {
    final name = widget.name;
    if (name == 'USD/KRW' || name == '환율(엔)') {
      return NumberFormat('#,###.##').format(r.change.abs());
    }
    if (r.isKrw) return NumberFormat('#,###').format(r.change.abs().toInt());
    return r.change.abs().toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final price = _price;
    final isUp = price?.isUp ?? true;
    final color = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.name,
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white38, size: 20),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 현재가 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: _loadingPrice || price == null
                  ? const SizedBox(
                      height: 60,
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF4ADE80)),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatValue(price.price),
                          style: GoogleFonts.robotoMono(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 32,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${isUp ? '+' : ''}${price.changeRate.toStringAsFixed(2)}%  '
                            '(${isUp ? '+' : ''}${_formatChange(price)})',
                            style: GoogleFonts.inter(
                                color: color, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _buildCandleChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildCandleChart() {
    if (_loadingChart) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4ADE80)),
        ),
      );
    }
    if (_candles.length < 2) return const SizedBox.shrink();

    final dc = _displayCandles;
    final firstClose = dc.first.close;
    final lastClose = dc.last.close;
    final changePct = ((lastClose - firstClose) / firstClose) * 100;
    final sign = changePct >= 0 ? '+' : '';
    final touched = _touchedIndex != null && _touchedIndex! < dc.length
        ? dc[_touchedIndex!]
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Row(
              children: [
                ..._Period.values.map((p) => GestureDetector(
                  onTap: () => _selectPeriod(p),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedPeriod == p
                          ? const Color(0xFF4ADE80).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _selectedPeriod == p
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
                            : Colors.white12,
                      ),
                    ),
                    child: Text(
                      p.label,
                      style: GoogleFonts.inter(
                        color: _selectedPeriod == p
                            ? const Color(0xFF4ADE80)
                            : Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )),
                const Spacer(),
                Text('$sign${changePct.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      color: changePct >= 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),

          // 터치 툴팁
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: touched != null
                ? Padding(
                    key: ValueKey(_touchedIndex),
                    padding: const EdgeInsets.only(left: 8, bottom: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            _selectedPeriod == _Period.min1
                                ? DateFormat('HH:mm').format(touched.date)
                                : _selectedPeriod == _Period.month
                                    ? DateFormat('yyyy년 MM월').format(touched.date)
                                    : DateFormat('MM월 dd일').format(touched.date),
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                          ),
                          const SizedBox(width: 12),
                          _ohlcLabel('시', touched.open),
                          _ohlcLabel('고', touched.high, color: const Color(0xFF4ADE80)),
                          _ohlcLabel('저', touched.low, color: Colors.redAccent),
                          _ohlcLabel('종', touched.close,
                              color: touched.close >= touched.open
                                  ? const Color(0xFF4ADE80)
                                  : Colors.redAccent),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), height: 18),
          ),

          // 차트
          LayoutBuilder(
            builder: (context, constraints) {
              final chartW = constraints.maxWidth;
              return GestureDetector(
                onTapDown: (d) => _onTouch(d.localPosition.dx, chartW),
                onScaleStart: (d) => _onScaleStart(d, chartW),
                onScaleUpdate: (d) => _onScaleUpdate(d, chartW),
                onScaleEnd: _onScaleEnd,
                child: CustomPaint(
                  size: Size(chartW, 200),
                  painter: _CandlePainter(
                    candles: dc,
                    touchedIndex: _touchedIndex,
                    formatValue: _formatValue,
                    formatDate: _selectedPeriod == _Period.min1
                        ? (d) => DateFormat('HH:mm').format(d)
                        : _selectedPeriod == _Period.month
                            ? (d) => DateFormat('yy/MM').format(d)
                            : (d) => DateFormat('MM/dd').format(d),
                  ),
                ),
              );
            },
          ),

        ],
      ),
    );
  }

  Widget _ohlcLabel(String label, double value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$label ',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10)),
            TextSpan(
                text: _formatValue(value),
                style: GoogleFonts.robotoMono(
                    color: color ?? Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _onTouch(double localX, double chartW) {
    final dc = _displayCandles;
    if (dc.isEmpty) return;
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    final adjustedX = (localX - yAxisW).clamp(0.0, candleAreaW);
    final candleWidth = candleAreaW / dc.length;
    final idx = (adjustedX / candleWidth).floor().clamp(0, dc.length - 1);
    if (_touchedIndex != idx) setState(() => _touchedIndex = idx);
  }

  void _onScaleStart(ScaleStartDetails d, double chartW) {
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    _visibleCountAtScaleStart = _visibleCount > 0 ? _visibleCount : _candles.length;
    _startIdxAtScaleStart = _startIdx;
    final adjustedX = (d.localFocalPoint.dx - yAxisW).clamp(0.0, candleAreaW);
    _focalFractionAtScaleStart = (adjustedX / candleAreaW).clamp(0.0, 1.0);
    _lastFocalPoint = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double chartW) {
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    if (d.pointerCount >= 2) {
      // 핀치 줌
      final newCount = (_visibleCountAtScaleStart / d.scale)
          .round()
          .clamp(5, _candles.length);
      final focalCandle = _startIdxAtScaleStart +
          (_focalFractionAtScaleStart * _visibleCountAtScaleStart).round();
      final newStart = (focalCandle - (_focalFractionAtScaleStart * newCount).round())
          .clamp(0, (_candles.length - newCount).clamp(0, _candles.length));
      setState(() {
        _visibleCount = newCount;
        _startIdx = newStart;
        _touchedIndex = null;
        _lastFocalPoint = d.localFocalPoint;
      });
    } else {
      // 한 손가락: 패닝 + 툴팁
      final prev = _lastFocalPoint;
      _lastFocalPoint = d.localFocalPoint;
      final vc = _visibleCount > 0 ? _visibleCount : _candles.length;
      if (prev != null && vc < _candles.length) {
        final dx = prev.dx - d.localFocalPoint.dx;
        final candleWidth = candleAreaW / vc;
        final delta = (dx / candleWidth).round();
        final maxStart = _candles.length - vc;
        final newStart = (_startIdx + delta).clamp(0, maxStart);
        if (newStart != _startIdx) setState(() => _startIdx = newStart);
      }
      _onTouch(d.localFocalPoint.dx, chartW);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _lastFocalPoint = null;
    setState(() => _touchedIndex = null);
  }
}

class _CandlePainter extends CustomPainter {
  final List<_OHLC> candles;
  final int? touchedIndex;
  final String Function(double) formatValue;
  final String Function(DateTime) formatDate;

  _CandlePainter({
    required this.candles,
    required this.touchedIndex,
    required this.formatValue,
    required this.formatDate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const xLabelH = 18.0;
    const yAxisW = 46.0; // Y축 레이블 영역 너비
    final chartH = size.height - xLabelH;
    final chartW = size.width - yAxisW;

    final allHigh = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final allLow = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final range = allHigh - allLow;
    if (range == 0) return;

    final pad = range * 0.08;
    final minY = allLow - pad;
    final maxY = allHigh + pad;
    final yRange = maxY - minY;

    // 캔들 영역 좌측 오프셋 적용
    double toY(double v) => chartH - ((v - minY) / yRange) * chartH;
    double toX(int i, int n) => yAxisW + chartW * i / n + chartW / n / 2;

    // 클리핑: 캔들이 차트 영역 밖으로 나가지 않도록
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(yAxisW, 0, chartW, chartH));

    // Y축 그리드 (3줄)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = chartH * i / 4;
      canvas.drawLine(Offset(yAxisW, y), Offset(size.width, y), gridPaint);
    }

    final n = candles.length;

    for (int i = 0; i < n; i++) {
      final c = candles[i];
      final isGreen = c.close >= c.open;
      final baseColor = isGreen ? const Color(0xFF4ADE80) : Colors.redAccent;
      final isTouched = touchedIndex == i;
      final color = isTouched ? Colors.white : baseColor;

      final totalCandleW = chartW / n;
      final bodyW = (totalCandleW * 0.6).clamp(2.0, 10.0);
      final cx = toX(i, n);

      // 심지 (wick)
      final wickPaint = Paint()..color = color..strokeWidth = 1;
      canvas.drawLine(Offset(cx, toY(c.high)), Offset(cx, toY(c.low)), wickPaint);

      // 몸통 (body)
      final top = toY(isGreen ? c.close : c.open);
      final bottom = toY(isGreen ? c.open : c.close);
      final bodyH = (bottom - top).abs().clamp(1.0, double.infinity);

      final bodyRect = Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH);
      final bodyPaint = Paint()..color = color;
      canvas.drawRect(bodyRect, bodyPaint);
    }

    // 터치 십자선
    if (touchedIndex != null) {
      final cx = toX(touchedIndex!, n);
      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx, 0), Offset(cx, chartH), linePaint);
    }

    canvas.restore();

    // Y축 레이블 (3개) - 클리핑 밖에서 그려서 항상 보임
    for (int i = 1; i <= 3; i++) {
      final v = minY + yRange * (1 - i / 4);
      final tp = TextPainter(
        text: TextSpan(
          text: formatValue(v),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 8,
              fontFamily: 'RobotoMono'),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final y = (chartH * i / 4 - tp.height / 2).clamp(0.0, chartH - tp.height);
      tp.paint(canvas, Offset(0, y));
    }

    // X축 레이블
    const labelCount = 5;
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 8,
      fontFamily: 'RobotoMono',
    );
    for (int i = 0; i < labelCount; i++) {
      final idx = ((n - 1) * i / (labelCount - 1)).round().clamp(0, n - 1);
      final cx = toX(idx, n);
      final tp = TextPainter(
        text: TextSpan(text: formatDate(candles[idx].date), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final x = (cx - tp.width / 2).clamp(yAxisW, size.width - tp.width);
      tp.paint(canvas, Offset(x, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles || old.touchedIndex != touchedIndex;
}
