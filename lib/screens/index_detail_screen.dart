import 'dart:ui' as ui;
import 'package:stockstorage/screens/chart_visible_range.dart';
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
  ChartVisibleRange _visibleRange = const ChartVisibleRange(0, 0);
  ChartVisibleRange? _rangeAtScaleStart;
  Offset? _focalPointAtScaleStart;

  List<_OHLC> get _displayCandles {
    if (_candles.isEmpty || _visibleRange.width <= 0) return [];
    final start = _visibleRange.start.floor().clamp(0, _candles.length);
    final end = _visibleRange.end.ceil().clamp(start, _candles.length);
    return _candles.sublist(start, end);
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
      _visibleRange = ChartVisibleRange(0, data.length.toDouble());
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
      _visibleRange = const ChartVisibleRange(0, 0);
    });
    _fetchCandles();
  }

  String _formatValue(double v) {
    final name = widget.name;
    if (name == 'USD/KRW') {
      return '₩${NumberFormat('#,###').format(v.toInt())}';
    }
    if (_price?.isKrw ?? false) return NumberFormat('#,###').format(v.toInt());
    return NumberFormat('#,##0.00').format(v);
  }

  String _formatChange(PriceResult r) {
    final name = widget.name;
    if (name == 'USD/KRW') {
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.name,
            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), size: 20),
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
                            color: Theme.of(context).colorScheme.onSurface,
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
    final cs = Theme.of(context).colorScheme;
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
    if (dc.isEmpty) return const SizedBox.shrink();
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
                            : cs.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      p.label,
                      style: GoogleFonts.inter(
                        color: _selectedPeriod == p
                            ? const Color(0xFF4ADE80)
                            : cs.onSurface.withValues(alpha: 0.38),
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
                            style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.54), fontSize: 10),
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
                onLongPressStart: (d) => _onTouch(d.localPosition.dx, chartW),
                onLongPressMoveUpdate: (d) => _onTouch(d.localPosition.dx, chartW),
                onLongPressEnd: (_) => setState(() => _touchedIndex = null),
                onScaleStart: _onScaleStart,
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$label ',
                style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 10)),
            TextSpan(
                text: _formatValue(value),
                style: GoogleFonts.robotoMono(
                    color: color ?? cs.onSurface.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _onTouch(double localX, double chartW) {
    if (_candles.isEmpty) return;
    
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    final adjustedX = (localX - yAxisW).clamp(0.0, candleAreaW);
    
    // Convert screen x to a candle index within the visible range
    final visibleWidth = _visibleRange.width;
    if (visibleWidth <= 0) return;
    final fractionalIndex = _visibleRange.start + (adjustedX / candleAreaW) * visibleWidth;
    
    // The index relative to the start of the full _candles list
    final overallIndex = fractionalIndex.floor().clamp(0, _candles.length - 1);

    // We need to find the index within the _displayCandles list
    final displayStartIdx = _visibleRange.start.floor();
    final displayTouchedIdx = overallIndex - displayStartIdx;

    if (_touchedIndex != displayTouchedIdx) {
      setState(() => _touchedIndex = displayTouchedIdx);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _rangeAtScaleStart = _visibleRange;
    _focalPointAtScaleStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double chartW) {
    if (_rangeAtScaleStart == null || _focalPointAtScaleStart == null || _candles.isEmpty) return;

    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;

    // 1. Calculate new width from zoom
    final newWidth = (_rangeAtScaleStart!.width / d.scale).clamp(5.0, _candles.length.toDouble());

    // 2. Find the anchor candle (the one that should stay under the focal point)
    final focalFraction = ((_focalPointAtScaleStart!.dx - yAxisW) / candleAreaW).clamp(0.0, 1.0);
    final anchorCandle = _rangeAtScaleStart!.start + focalFraction * _rangeAtScaleStart!.width;
    
    // 3. Calculate pan delta in terms of candles
    final panDeltaX = d.localFocalPoint.dx - _focalPointAtScaleStart!.dx;
    final panDeltaCandles = (panDeltaX / candleAreaW) * newWidth;

    // 4. Calculate new start position
    var newStart = anchorCandle - (focalFraction * newWidth) - panDeltaCandles;

    // 5. Clamp to bounds
    if (newStart < 0) newStart = 0;
    if (newStart + newWidth > _candles.length) {
      newStart = _candles.length - newWidth;
    }
    final newEnd = newStart + newWidth;

    setState(() {
      _visibleRange = ChartVisibleRange(newStart, newEnd);
      _touchedIndex = null; // 줌/팬 중 툴팁 숨김
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _rangeAtScaleStart = null;
    _focalPointAtScaleStart = null;
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
