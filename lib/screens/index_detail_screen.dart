import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/analytics_service.dart';
import '../services/stock_price_service.dart';

typedef _OHLC = ({
  DateTime date,
  double open,
  double high,
  double low,
  double close,
});

enum _Period {
  min1('1분', '1m', '1d'),
  min5('5분', '5m', '5d'),
  min60('60분', '60m', '1mo'),
  day1('일봉', '1d', '2y'),
  week('주봉', '1wk', 'max'),
  month('월봉', '1mo', 'max');

  const _Period(this.label, this.interval, this.range);
  final String label;
  final String interval;
  final String range;
  bool get isMinute => this == min1 || this == min5 || this == min60;
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
  int _fetchSeq = 0;

  @override
  void initState() {
    super.initState();
    _price = widget.initialPrice;
    if (_price == null) _fetchPrice();
    _fetchCandles(++_fetchSeq);
    AnalyticsService.instance.logViewIndexDetail(widget.name);
  }

  Future<void> _fetchPrice() async {
    setState(() => _loadingPrice = true);
    final result = await StockPriceService.fetchPrice(widget.symbol, 'US');
    if (!mounted) return;
    setState(() {
      _price = result;
      _loadingPrice = false;
    });
  }

  Future<void> _fetchCandles(int seq) async {
    final data = await StockPriceService.fetchOHLC(
      widget.symbol,
      'US',
      interval: _selectedPeriod.interval,
      range: _selectedPeriod.range,
    );
    if (!mounted || _fetchSeq != seq) return;
    setState(() {
      _candles = data;
      _loadingChart = false;
      _touchedIndex = null;
    });
  }

  Future<void> _refresh() async {
    StockPriceService.invalidateCache(widget.symbol);
    setState(() {
      _loadingPrice = true;
      _loadingChart = true;
      _touchedIndex = null;
    });
    await Future.wait([_fetchPrice(), _fetchCandles(++_fetchSeq)]);
  }

  void _selectPeriod(_Period period) {
    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
      _loadingChart = true;
      _touchedIndex = null;
    });
    _fetchCandles(++_fetchSeq);
  }

  String _formatValue(double value) {
    if (widget.name == 'USD/KRW') {
      return '₩${NumberFormat('#,###').format(value.toInt())}';
    }
    if (_price?.isKrw ?? false) {
      return NumberFormat('#,###').format(value.toInt());
    }
    return NumberFormat('#,##0.00').format(value);
  }

  String _formatChange(PriceResult result) {
    if (widget.name == 'USD/KRW') {
      return NumberFormat('#,###.##').format(result.change.abs());
    }
    if (result.isKrw) {
      return NumberFormat('#,###').format(result.change.abs().toInt());
    }
    return result.change.abs().toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    if (_selectedPeriod.isMinute) {
      return DateFormat('MM.dd HH:mm').format(date);
    }
    if (_selectedPeriod == _Period.month) {
      return DateFormat('yyyy.MM').format(date);
    }
    return DateFormat('yyyy.MM.dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final price = _price;
    final isUp = price?.isUp ?? true;
    final moveColor = isUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0A0E1A)
          : const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.name,
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          children: [
            _buildHeroCard(context, moveColor, price),
            const SizedBox(height: 16),
            _buildChartCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    Color moveColor,
    PriceResult? price,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xFF182235), Color(0xFF0D1423)]
              : const [Color(0xFFEAFEF1), Color(0xFFF8FBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: moveColor.withValues(alpha: 0.18)),
      ),
      child: _loadingPrice || price == null
          ? const SizedBox(
              height: 140,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4ADE80),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '실시간 스냅샷',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _formatValue(price.price),
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricChip(
                      label: '등락률',
                      value:
                          '${price.isUp ? '+' : ''}${price.changeRate.toStringAsFixed(2)}%',
                      color: moveColor,
                    ),
                    _metricChip(
                      label: '변동폭',
                      value: '${price.isUp ? '+' : ''}${_formatChange(price)}',
                      color: moveColor,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _summaryStat(
                        context,
                        label: '추세',
                        value: price.changeRate >= 0 ? '상승 우위' : '하락 우위',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _summaryStat(
                        context,
                        label: '기준 시각',
                        value: price.marketTime == null
                            ? '-'
                            : DateFormat(
                                'MM.dd HH:mm',
                              ).format(price.marketTime!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildChartCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasData = !_loadingChart && _candles.length >= 2;
    final touched =
        hasData && _touchedIndex != null && _touchedIndex! < _candles.length
        ? _candles[_touchedIndex!]
        : null;
    final firstClose = hasData ? _candles.first.close : 0.0;
    final lastClose = hasData ? _candles.last.close : 0.0;
    final deltaPct = hasData
        ? ((lastClose - firstClose) / firstClose) * 100
        : 0.0;
    final deltaColor = deltaPct >= 0
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '가격 흐름',
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (hasData)
                Text(
                  '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    color: deltaColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _periodPill(
                '분봉',
                _selectedPeriod.isMinute,
                () => _selectPeriod(_Period.min1),
              ),
              ...[_Period.day1, _Period.week, _Period.month].map(
                (p) => _periodPill(
                  p.label,
                  _selectedPeriod == p,
                  () => _selectPeriod(p),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: _selectedPeriod.isMinute
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [_Period.min1, _Period.min5, _Period.min60]
                          .map(
                            (p) => _periodPill(
                              p.label,
                              _selectedPeriod == p,
                              () => _selectPeriod(p),
                              compact: true,
                            ),
                          )
                          .toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          if (touched != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    _formatDate(touched.date),
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                  _ohlcLabel(context, '시가', touched.open),
                  _ohlcLabel(
                    context,
                    '고가',
                    touched.high,
                    color: const Color(0xFF22C55E),
                  ),
                  _ohlcLabel(
                    context,
                    '저가',
                    touched.low,
                    color: const Color(0xFFEF4444),
                  ),
                  _ohlcLabel(
                    context,
                    '종가',
                    touched.close,
                    color: touched.close >= touched.open
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                  ),
                ],
              ),
            ),
          if (_loadingChart)
            const SizedBox(
              height: 240,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4ADE80),
                ),
              ),
            )
          else if (!hasData)
            SizedBox(
              height: 240,
              child: Center(
                child: Text(
                  '차트 데이터를 불러오지 못했습니다.',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) => _handleTouch(
                    details.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  onHorizontalDragDown: (details) => _handleTouch(
                    details.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  onHorizontalDragUpdate: (details) => _handleTouch(
                    details.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  onHorizontalDragEnd: (_) =>
                      setState(() => _touchedIndex = null),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 240),
                    painter: _CandlePainter(
                      candles: _candles,
                      touchedIndex: _touchedIndex,
                      formatValue: _formatValue,
                      formatDate: (date) {
                        if (_selectedPeriod.isMinute) {
                          return DateFormat('HH:mm').format(date);
                        }
                        if (_selectedPeriod == _Period.month) {
                          return DateFormat('yy/MM').format(date);
                        }
                        return DateFormat('MM/dd').format(date);
                      },
                      labelColor: cs.onSurface,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _handleTouch(double localX, double width) {
    if (_candles.isEmpty) return;
    const yAxisW = 48.0;
    final chartWidth = width - yAxisW;
    final adjustedX = (localX - yAxisW).clamp(0.0, chartWidth);
    final index = ((adjustedX / chartWidth) * (_candles.length - 1)).round();
    if (_touchedIndex != index) {
      setState(() => _touchedIndex = index);
    }
  }

  Widget _periodPill(
    String label,
    bool active,
    VoidCallback onTap, {
    bool compact = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF4ADE80).withValues(alpha: 0.16)
              : cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFF4ADE80).withValues(alpha: 0.34)
                : cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: active
                ? const Color(0xFF1F9D55)
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.58),
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _metricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: GoogleFonts.inter(
                color: color.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ohlcLabel(
    BuildContext context,
    String label,
    double value, {
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.42),
              fontSize: 11,
            ),
          ),
          TextSpan(
            text: _formatValue(value),
            style: GoogleFonts.robotoMono(
              color: color ?? cs.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<_OHLC> candles;
  final int? touchedIndex;
  final String Function(double) formatValue;
  final String Function(DateTime) formatDate;
  final Color labelColor;

  const _CandlePainter({
    required this.candles,
    required this.touchedIndex,
    required this.formatValue,
    required this.formatDate,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const xLabelH = 18.0;
    const yAxisW = 48.0;
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

    double toY(double value) => chartH - ((value - minY) / yRange) * chartH;
    double toX(int i, int n) => yAxisW + chartW * i / n + chartW / n / 2;

    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = chartH * i / 4;
      canvas.drawLine(Offset(yAxisW, y), Offset(size.width, y), gridPaint);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(yAxisW, 0, chartW, chartH));

    final n = candles.length;
    for (int i = 0; i < n; i++) {
      final c = candles[i];
      final up = c.close >= c.open;
      final candleColor = up
          ? const Color(0xFF22C55E)
          : const Color(0xFFEF4444);
      final color = touchedIndex == i ? labelColor : candleColor;
      final totalW = chartW / n;
      final bodyW = (totalW * 0.56).clamp(2.0, 10.0);
      final cx = toX(i, n);

      canvas.drawLine(
        Offset(cx, toY(c.high)),
        Offset(cx, toY(c.low)),
        Paint()
          ..color = color
          ..strokeWidth = 1,
      );

      final top = toY(up ? c.close : c.open);
      final bottom = toY(up ? c.open : c.close);
      final bodyH = (bottom - top).abs().clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
        Paint()..color = color,
      );
    }

    if (touchedIndex != null && touchedIndex! < candles.length) {
      final cx = toX(touchedIndex!, candles.length);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, chartH),
        Paint()
          ..color = labelColor.withValues(alpha: 0.22)
          ..strokeWidth = 1,
      );
    }

    canvas.restore();

    for (int i = 1; i <= 3; i++) {
      final value = minY + yRange * (1 - i / 4);
      final tp = TextPainter(
        text: TextSpan(
          text: formatValue(value),
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.35),
            fontSize: 8,
            fontFamily: 'RobotoMono',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, chartH * i / 4 - tp.height / 2));
    }

    const count = 4;
    final style = TextStyle(
      color: labelColor.withValues(alpha: 0.35),
      fontSize: 8,
      fontFamily: 'RobotoMono',
    );
    for (int i = 0; i < count; i++) {
      final idx = ((candles.length - 1) * i / (count - 1)).round().clamp(
        0,
        candles.length - 1,
      );
      final cx = toX(idx, candles.length);
      final tp = TextPainter(
        text: TextSpan(text: formatDate(candles[idx].date), style: style),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final x = (cx - tp.width / 2).clamp(yAxisW, size.width - tp.width);
      tp.paint(canvas, Offset(x, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.touchedIndex != touchedIndex ||
        oldDelegate.labelColor != labelColor;
  }
}
