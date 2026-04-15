import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/trading_journal.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import 'chart_visible_range.dart';

typedef _OHLC = ({
  DateTime date,
  double open,
  double high,
  double low,
  double close,
});

typedef _Marker = ({int index, bool isBuy, double price});

class JournalChartScreen extends StatefulWidget {
  final TradingJournal buy;
  final List<TradingJournal> linkedSells;
  final FirestoreService firestoreService;
  final VoidCallback onEdit;
  final void Function(TradingJournal)? onEditSell;
  final bool showEditButton;

  const JournalChartScreen({
    super.key,
    required this.buy,
    this.linkedSells = const [],
    required this.firestoreService,
    required this.onEdit,
    this.onEditSell,
    this.showEditButton = true,
  });

  @override
  State<JournalChartScreen> createState() => _JournalChartScreenState();
}

class _JournalChartScreenState extends State<JournalChartScreen> {
  List<_OHLC> _candles = [];
  bool _loading = true;
  int? _touchedIndex;
  String _range = '6mo';

  ChartVisibleRange _visibleRange = const ChartVisibleRange(0, 0);
  ChartVisibleRange? _rangeAtScaleStart;
  Offset? _focalPointAtScaleStart;

  // 전체 candles 기준 마커 인덱스
  List<_Marker> _allMarkers = [];

  @override
  void initState() {
    super.initState();
    _fetchChart();
  }

  Future<void> _fetchChart() async {
    setState(() {
      _loading = true;
      _candles = [];
      _allMarkers = [];
    });

    final ticker = widget.buy.ticker;
    final market = widget.buy.market;
    if (ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(market)) {
      setState(() => _loading = false);
      return;
    }

    final data = await StockPriceService.fetchOHLC(
      ticker, market, interval: '1d', range: _range,
    );
    if (!mounted) return;

    final markers = <_Marker>[];
    final buyIdx = _closestIndex(data, widget.buy.tradeDate);
    if (buyIdx >= 0) markers.add((index: buyIdx, isBuy: true, price: widget.buy.price));

    for (final sell in widget.linkedSells) {
      final idx = _closestIndex(data, sell.tradeDate);
      if (idx >= 0) markers.add((index: idx, isBuy: false, price: sell.price));
    }

    setState(() {
      _candles = data;
      _loading = false;
      _allMarkers = markers;
      _visibleRange = ChartVisibleRange(0, data.length.toDouble());
    });
  }

  int _closestIndex(List<_OHLC> candles, DateTime date) {
    if (candles.isEmpty) return -1;
    int best = -1;
    int bestDiff = 999999;
    for (int i = 0; i < candles.length; i++) {
      final diff = candles[i].date.difference(date).inDays.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return bestDiff <= 5 ? best : -1;
  }

  List<_OHLC> get _displayCandles {
    if (_candles.isEmpty || _visibleRange.width <= 0) return [];
    final start = _visibleRange.start.floor().clamp(0, _candles.length);
    final end = _visibleRange.end.ceil().clamp(start, _candles.length);
    return _candles.sublist(start, end);
  }

  static const _leftPad = 4.0;
  static const _rightAxisW = 42.0;

  double _candleAreaW(double totalW) => totalW - _leftPad - _rightAxisW;

  void _onTouch(double localX, double chartW) {
    if (_candles.isEmpty) return;
    final candleAreaW = _candleAreaW(chartW);
    final adjustedX = (localX - _leftPad).clamp(0.0, candleAreaW);
    final visibleWidth = _visibleRange.width;
    if (visibleWidth <= 0) return;
    final fractionalIndex =
        _visibleRange.start + (adjustedX / candleAreaW) * visibleWidth;
    final overallIndex = fractionalIndex.floor().clamp(0, _candles.length - 1);
    final dispIdx = overallIndex - _visibleRange.start.floor();
    if (_touchedIndex != dispIdx) setState(() => _touchedIndex = dispIdx);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _rangeAtScaleStart = _visibleRange;
    _focalPointAtScaleStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double chartW) {
    if (_rangeAtScaleStart == null || _focalPointAtScaleStart == null || _candles.isEmpty) return;
    final candleAreaW = _candleAreaW(chartW);

    final newWidth = (_rangeAtScaleStart!.width / d.scale)
        .clamp(5.0, _candles.length.toDouble());
    final focalFraction =
        ((_focalPointAtScaleStart!.dx - _leftPad) / candleAreaW).clamp(0.0, 1.0);
    final anchorCandle =
        _rangeAtScaleStart!.start + focalFraction * _rangeAtScaleStart!.width;
    final panDeltaCandles =
        (d.localFocalPoint.dx - _focalPointAtScaleStart!.dx) / candleAreaW * newWidth;

    var newStart = anchorCandle - focalFraction * newWidth - panDeltaCandles;
    newStart = newStart.clamp(0.0, (_candles.length - newWidth).clamp(0.0, double.infinity));
    final newEnd = newStart + newWidth;

    setState(() {
      _visibleRange = ChartVisibleRange(newStart, newEnd);
      _touchedIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buy = widget.buy;
    final isKrw = buy.market != 'US';
    String fmtP(double p) =>
        isKrw ? '₩${NumberFormat('#,###').format(p.toInt())}' : '\$${p.toStringAsFixed(2)}';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              buy.stockName,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: cs.onSurface),
            ),
            if (buy.ticker.isNotEmpty)
              Text(
                '${buy.ticker} · ${buy.market}',
                style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4)),
              ),
          ],
        ),
        actions: widget.showEditButton
            ? [
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 20, color: cs.onSurface.withValues(alpha: 0.6)),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEdit();
                  },
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _candles.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.show_chart,
                        size: 48, color: cs.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text('차트 데이터를 불러올 수 없습니다',
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.4))),
                  ]),
                )
              : Column(
                  children: [
                    _rangeSelector(cs),
                    _legend(cs),
                    Expanded(child: _buildChart(cs)),
                    _tradeInfo(cs, fmtP),
                  ],
                ),
    );
  }

  Widget _rangeSelector(ColorScheme cs) {
    const opts = [('1개월', '1mo'), ('3개월', '3mo'), ('6개월', '6mo'), ('1년', '1y')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: opts.map((opt) {
          final selected = _range == opt.$2;
          return GestureDetector(
            onTap: () {
              if (_range == opt.$2) return;
              setState(() => _range = opt.$2);
              _fetchChart();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF10B981)
                    : cs.onSurface.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(opt.$1,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.black
                          : cs.onSurface.withValues(alpha: 0.6))),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _legend(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        _legendDot(const Color(0xFF10B981), '매수', cs),
        const SizedBox(width: 12),
        _legendDot(Colors.redAccent, '매도', cs),
      ]),
    );
  }

  Widget _legendDot(Color color, String label, ColorScheme cs) {
    return Row(children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
    ]);
  }

  Widget _buildChart(ColorScheme cs) {
    final dc = _displayCandles;
    if (dc.isEmpty) return const SizedBox();

    final dispStart = _visibleRange.start.floor();
    final dispMarkers = <_Marker>[];
    for (final m in _allMarkers) {
      final dispIdx = m.index - dispStart;
      if (dispIdx >= 0 && dispIdx < dc.length) {
        dispMarkers.add((index: dispIdx, isBuy: m.isBuy, price: m.price));
      }
    }

    final touched = (_touchedIndex != null && _touchedIndex! >= 0 && _touchedIndex! < dc.length)
        ? dc[_touchedIndex!]
        : null;

    return Column(
      children: [
        if (touched != null) _touchedBar(touched, cs),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              final chartW = constraints.maxWidth;
              return GestureDetector(
                onLongPressStart: (d) => _onTouch(d.localPosition.dx, chartW),
                onLongPressMoveUpdate: (d) => _onTouch(d.localPosition.dx, chartW),
                onLongPressEnd: (_) => setState(() => _touchedIndex = null),
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, chartW),
                child: CustomPaint(
                  size: Size(chartW, constraints.maxHeight),
                  painter: _JournalCandlePainter(
                    candles: dc,
                    allCandles: _candles,
                    visibleStart: dispStart,
                    touchedIndex: _touchedIndex,
                    labelColor: cs.onSurface,
                    markers: dispMarkers,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _touchedBar(_OHLC c, ColorScheme cs) {
    final isKrw = widget.buy.market != 'US';
    String fmt(double v) =>
        isKrw ? NumberFormat('#,###').format(v.toInt()) : v.toStringAsFixed(2);
    final isGreen = c.close >= c.open;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: cs.onSurface.withValues(alpha: 0.04),
      child: Row(children: [
        Text(DateFormat('yyyy.MM.dd').format(c.date),
            style: GoogleFonts.robotoMono(
                fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
        const SizedBox(width: 10),
        ...[ ('O', c.open), ('H', c.high), ('L', c.low), ('C', c.close) ].map(
          (e) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Text('${e.$1} ',
                  style: GoogleFonts.robotoMono(
                      fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35))),
              Text(fmt(e.$2),
                  style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      color: isGreen ? const Color(0xFF10B981) : Colors.redAccent)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tradeInfo(ColorScheme cs, String Function(double) fmtP) {
    final buy = widget.buy;
    final sells = widget.linkedSells;
    double totalPnl = 0;
    bool hasPnl = false;
    for (final s in sells) {
      if (s.buyPrice > 0) {
        totalPnl += (s.price - s.buyPrice) * s.quantity;
        hasPnl = true;
      }
    }
    final isPnlUp = totalPnl >= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _infoCell('매수일', DateFormat('yy.MM.dd').format(buy.tradeDate), cs),
            _infoCell('매수가', fmtP(buy.price), cs),
            _infoCell('수량',
                '${buy.quantity % 1 == 0 ? buy.quantity.toInt() : buy.quantity}주', cs),
            if (hasPnl)
              _infoCell(
                '실현손익',
                '${isPnlUp ? '+' : ''}${fmtP(totalPnl)}',
                cs,
                valueColor: isPnlUp ? const Color(0xFF10B981) : Colors.redAccent,
              ),
          ]),
          if (sells.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...sells.map((s) => _sellRow(s, cs, fmtP)),
          ],
        ],
      ),
    );
  }

  Widget _infoCell(String label, String value, ColorScheme cs, {Color? valueColor}) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4))),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.robotoMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? cs.onSurface)),
      ]),
    );
  }

  Widget _sellRow(TradingJournal sell, ColorScheme cs, String Function(double) fmtP) {
    final pnlPct = sell.buyPrice > 0
        ? (sell.price - sell.buyPrice) / sell.buyPrice * 100
        : null;
    final isUp = pnlPct != null && pnlPct >= 0;
    final qty = sell.quantity % 1 == 0 ? sell.quantity.toInt() : sell.quantity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Container(
          width: 6, height: 6,
          margin: const EdgeInsets.only(right: 8),
          decoration: const BoxDecoration(
              color: Colors.redAccent, shape: BoxShape.circle),
        ),
        Text(DateFormat('yy.MM.dd').format(sell.tradeDate),
            style: GoogleFonts.robotoMono(
                fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45))),
        const SizedBox(width: 8),
        Text('매도 ${fmtP(sell.price)} × $qty주',
            style: GoogleFonts.robotoMono(
                fontSize: 11, color: cs.onSurface.withValues(alpha: 0.8))),
        const Spacer(),
        if (pnlPct != null)
          Text('${isUp ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
              style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUp ? const Color(0xFF10B981) : Colors.redAccent)),
        if (widget.onEditSell != null)
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onEditSell!(sell);
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.edit_outlined,
                  size: 14, color: cs.onSurface.withValues(alpha: 0.35)),
            ),
          ),
      ]),
    );
  }
}

// ── 차트 페인터 (매수/매도 마커 포함) ──────────────────────────────────────
class _JournalCandlePainter extends CustomPainter {
  final List<_OHLC> candles;
  final List<_OHLC>? allCandles;
  final int visibleStart;
  final int? touchedIndex;
  final Color labelColor;
  final List<_Marker> markers;

  const _JournalCandlePainter({
    required this.candles,
    required this.allCandles,
    required this.visibleStart,
    required this.touchedIndex,
    required this.labelColor,
    required this.markers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const xLabelH = 18.0;
    const leftPad = 4.0;
    const chartToAxisGap = 1.0;
    const rightAxisW = 42.0; // 우측 가격/축 레이블 공간
    // Extra top padding for buy/sell marker triangles
    const markerH = 16.0;
    final chartH = size.height - xLabelH - markerH;
    final chartW = size.width - leftPad - rightAxisW;

    final allHigh = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final allLow = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final range = allHigh - allLow;
    if (range == 0) return;

    final pad = range * 0.10;
    final minY = allLow - pad;
    final maxY = allHigh + pad;
    final yRange = maxY - minY;

    double toY(double v) => markerH + chartH - ((v - minY) / yRange) * chartH;
    double toX(int i, int n) => leftPad + chartW * i / n + chartW / n / 2;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(leftPad, 0, chartW, markerH + chartH));

    // 그리드
    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = markerH + chartH * i / 4;
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
    }

    final n = candles.length;
    final totalCandleW = chartW / n;

    for (int i = 0; i < n; i++) {
      final c = candles[i];
      final isGreen = c.close >= c.open;
      final baseColor = isGreen ? const Color(0xFF10B981) : Colors.redAccent;
      final color = touchedIndex == i ? labelColor : baseColor;

      final bodyW = (totalCandleW * 0.6).clamp(2.0, 10.0);
      final cx = toX(i, n);

      canvas.drawLine(
        Offset(cx, toY(c.high)),
        Offset(cx, toY(c.low)),
        Paint()
          ..color = color
          ..strokeWidth = 1,
      );
      final top = toY(isGreen ? c.close : c.open);
      final bottom = toY(isGreen ? c.open : c.close);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, (bottom - top).abs().clamp(1.0, double.infinity)),
        Paint()..color = color,
      );
    }

    // 이동평균선
    if (allCandles != null && allCandles!.isNotEmpty) {
      const maConfigs = [
        (5, Color(0xFFFFA726)),
        (20, Color(0xFF42A5F5)),
        (60, Color(0xFFAB47BC)),
      ];
      for (final (period, color) in maConfigs) {
        final path = Path();
        bool started = false;
        for (int i = 0; i < n; i++) {
          final g = visibleStart + i;
          if (g < period - 1) continue;
          double sum = 0;
          for (int k = g - period + 1; k <= g; k++) { sum += allCandles![k].close; }
          final ma = sum / period;
          final cx = toX(i, n);
          final cy = toY(ma);
          if (!started) {
            path.moveTo(cx, cy);
            started = true;
          } else {
            path.lineTo(cx, cy);
          }
        }
        if (started) {
          canvas.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: 0.7)
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }

    // 십자선
    if (touchedIndex != null) {
      final cx = toX(touchedIndex!, n);
      canvas.drawLine(
        Offset(cx, markerH),
        Offset(cx, markerH + chartH),
        Paint()
          ..color = labelColor.withValues(alpha: 0.2)
          ..strokeWidth = 1,
      );
    }

    canvas.restore();

    // ── 매수/매도 가격선 (점선) ────────────────────────────────────────────
    for (final m in markers) {
      if (m.price <= 0) continue;
      final py = toY(m.price);
      if (py < markerH || py > markerH + chartH) continue;
      final color = m.isBuy ? const Color(0xFF10B981) : Colors.redAccent;
      final dashPaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      // 점선
      double x = leftPad;
      const dashW = 5.0, gapW = 4.0;
      final lineEnd = leftPad + chartW;
      while (x < lineEnd) {
        canvas.drawLine(Offset(x, py), Offset((x + dashW).clamp(0, lineEnd), py), dashPaint);
        x += dashW + gapW;
      }
      // 좌측: 액션 pill, 우측: 가격 텍스트
      final actionLabel = m.isBuy ? '매수' : '매도';
      final isKrw = m.price >= 100;
      final priceLabel = isKrw
          ? NumberFormat('#,###').format(m.price.toInt())
          : m.price.toStringAsFixed(2);

      // pill 텍스트 레이아웃
      final pillTp = TextPainter(
        text: TextSpan(
          text: actionLabel,
          style: const TextStyle(
              color: Colors.black,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter'),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      final priceTp = TextPainter(
        text: TextSpan(
          text: priceLabel,
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'RobotoMono'),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      const hPad = 5.0, vPad = 2.5;
      final pillW = pillTp.width + hPad * 2;
      final pillH = pillTp.height + vPad * 2;
      final leftStickerX = leftPad + 2;
      final rightPriceX = leftPad + chartW + chartToAxisGap;

      // 좌측 pill 배경
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(leftStickerX, py - pillH / 2, pillW, pillH),
          const Radius.circular(4),
        ),
        Paint()..color = color,
      );
      // 좌측 pill 텍스트
      pillTp.paint(canvas, Offset(leftStickerX + hPad, py - pillTp.height / 2));
      // 우측 가격 텍스트
      priceTp.paint(canvas, Offset(rightPriceX, py - priceTp.height / 2));
    }

    // ── 매수/매도 마커 ─────────────────────────────────────────────────────
    for (final m in markers) {
      if (m.index < 0 || m.index >= n) continue;
      final cx = toX(m.index, n);
      final candleY = m.isBuy
          ? toY(candles[m.index].low)  // 매수: 캔들 아래 (위쪽 삼각형)
          : toY(candles[m.index].high); // 매도: 캔들 위 (아래쪽 삼각형)

      final color = m.isBuy ? const Color(0xFF10B981) : Colors.redAccent;
      const triSize = 7.0;
      const gap = 4.0;

      final path = Path();
      if (m.isBuy) {
        final ty = candleY + gap;
        path.moveTo(cx, ty);
        path.lineTo(cx - triSize, ty + triSize * 1.4);
        path.lineTo(cx + triSize, ty + triSize * 1.4);
      } else {
        final ty = candleY - gap;
        path.moveTo(cx, ty);
        path.lineTo(cx - triSize, ty - triSize * 1.4);
        path.lineTo(cx + triSize, ty - triSize * 1.4);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    // Y축 레이블 (오른쪽)
    for (int i = 1; i <= 3; i++) {
      final v = minY + yRange * (1 - i / 4);
      final tp = TextPainter(
        text: TextSpan(
          text: _fmtVal(v),
          style: TextStyle(
              color: labelColor.withValues(alpha: 0.65),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFamily: 'RobotoMono'),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final y = (markerH + chartH * i / 4 - tp.height / 2)
          .clamp(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(leftPad + chartW + chartToAxisGap, y));
    }

    // X축 레이블
    const labelCount = 4;
    final labelStyle = TextStyle(
        color: labelColor.withValues(alpha: 0.35),
        fontSize: 10,
        fontFamily: 'RobotoMono');
    for (int i = 0; i < labelCount; i++) {
      final idx = ((n - 1) * i / (labelCount - 1)).round().clamp(0, n - 1);
      final cx = toX(idx, n);
      final tp = TextPainter(
        text: TextSpan(text: _fmtDate(candles[idx].date), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final x = (cx - tp.width / 2).clamp(leftPad, leftPad + chartW - tp.width);
      tp.paint(canvas, Offset(x, markerH + chartH + 4));
    }
  }

  String _fmtVal(double v) {
    if (v >= 1000) return NumberFormat('#,###').format(v.toInt());
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  String _fmtDate(DateTime d) => DateFormat('MM/dd').format(d);

  @override
  bool shouldRepaint(_JournalCandlePainter old) =>
      old.candles != candles ||
      old.touchedIndex != touchedIndex ||
      old.markers != markers ||
      old.visibleStart != visibleStart;
}


