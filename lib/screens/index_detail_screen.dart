import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/analytics_service.dart';
import '../services/stock_price_service.dart';
import 'chart_visible_range.dart';

typedef _OHLC = ({
  DateTime date,
  double open,
  double high,
  double low,
  double close,
});

const _kUpColor = Color(0xFFF04452);
const _kDownColor = Color(0xFF1677FF);

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
      final defaultView = _selectedPeriod == _Period.day1 ? 120 : data.length;
      final startIdx = (data.length - defaultView)
          .clamp(0, data.length)
          .toDouble();
      _visibleRange = ChartVisibleRange(startIdx, data.length.toDouble());
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
      _visibleRange = const ChartVisibleRange(0, 0);
    });
    _fetchCandles(++_fetchSeq);
  }

  void _openFullscreenChart() {
    if (_candles.length < 2) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _IndexFullscreenChartPage(
          title: widget.name,
          symbol: widget.symbol,
          initialCandles: _candles,
          initialPeriod: _selectedPeriod,
          initialRange: _visibleRange,
          formatValue: _formatValue,
        ),
      ),
    );
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
    final moveColor = isUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0A0E1A)
          : const Color(0xFFF8F9FA),
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
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 19,
            letterSpacing: -0.3,
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          children: [
            _buildHeroCard(context, moveColor, price),
            const SizedBox(height: 24),
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
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: _loadingPrice || price == null
          ? const SizedBox(
              height: 140,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF10B981),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '실시간 스냅샷',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _formatValue(price.price),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 36,
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
                const SizedBox(height: 14),
                if (price.marketTime != null)
                  Text(
                    '🕐 기준 ${DateFormat('MM.dd HH:mm').format(price.marketTime!)}',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.38),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildChartCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dc = _loadingChart ? <_OHLC>[] : _displayCandles;
    final hasData = !_loadingChart && dc.length >= 2;
    final touched =
        hasData && _touchedIndex != null && _touchedIndex! < dc.length
        ? dc[_touchedIndex!]
        : null;
    final firstClose = hasData ? dc.first.close : 0.0;
    final lastClose = hasData ? dc.last.close : 0.0;
    final deltaPct = hasData
        ? ((lastClose - firstClose) / firstClose) * 100
        : 0.0;
    final deltaColor = deltaPct >= 0
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '차트',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (hasData)
                Text(
                  '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: deltaColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: hasData ? _openFullscreenChart : null,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.fullscreen,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
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
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                  _ohlcLabel(context, '시가', touched.open),
                  _ohlcLabel(context, '고가', touched.high, color: _kUpColor),
                  _ohlcLabel(context, '저가', touched.low, color: _kDownColor),
                  _ohlcLabel(
                    context,
                    '종가',
                    touched.close,
                    color: touched.close >= touched.open
                        ? _kUpColor
                        : _kDownColor,
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
                  color: Color(0xFF10B981),
                ),
              ),
            )
          else if (!hasData)
            SizedBox(
              height: 240,
              child: Center(
                child: Text(
                  '차트 데이터를 불러오지 못했습니다.',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final chartW = constraints.maxWidth;
                return GestureDetector(
                  onLongPressStart: (details) =>
                      _onTouch(details.localPosition.dx, chartW),
                  onLongPressMoveUpdate: (details) =>
                      _onTouch(details.localPosition.dx, chartW),
                  onLongPressEnd: (_) => setState(() => _touchedIndex = null),
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: (details) => _onScaleUpdate(details, chartW),
                  onScaleEnd: _onScaleEnd,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 240),
                    painter: _CandlePainter(
                      candles: dc,
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
                      allCandles: _candles,
                      visibleStart: _visibleRange.start.floor().clamp(
                        0,
                        _candles.length,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _onTouch(double localX, double width) {
    if (_candles.isEmpty) return;
    const yAxisW = 48.0;
    final chartWidth = width - yAxisW;
    if (chartWidth <= 0) return;
    final adjustedX = (localX - yAxisW).clamp(0.0, chartWidth);
    final visibleWidth = _visibleRange.width;
    if (visibleWidth <= 0) return;
    final fractionalIndex =
        _visibleRange.start + (adjustedX / chartWidth) * visibleWidth;
    final overallIndex = fractionalIndex.floor().clamp(0, _candles.length - 1);
    final displayStartIdx = _visibleRange.start.floor();
    final displayTouchedIdx = overallIndex - displayStartIdx;
    if (_touchedIndex != displayTouchedIdx) {
      setState(() => _touchedIndex = displayTouchedIdx);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _rangeAtScaleStart = _visibleRange;
    _focalPointAtScaleStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double chartWidth) {
    if (_rangeAtScaleStart == null ||
        _focalPointAtScaleStart == null ||
        _candles.isEmpty) {
      return;
    }
    const yAxisW = 48.0;
    final candleAreaW = chartWidth - yAxisW;
    if (candleAreaW <= 0) return;

    final newWidth = (_rangeAtScaleStart!.width / details.scale).clamp(
      5.0,
      _candles.length.toDouble(),
    );
    final focalFraction = ((_focalPointAtScaleStart!.dx - yAxisW) / candleAreaW)
        .clamp(0.0, 1.0);
    final anchorCandle =
        _rangeAtScaleStart!.start + focalFraction * _rangeAtScaleStart!.width;
    final panDeltaX = details.localFocalPoint.dx - _focalPointAtScaleStart!.dx;
    final panDeltaCandles = (panDeltaX / candleAreaW) * newWidth;

    var newStart = anchorCandle - (focalFraction * newWidth) - panDeltaCandles;
    if (newStart < 0) newStart = 0;
    if (newStart + newWidth > _candles.length) {
      newStart = _candles.length - newWidth;
    }
    setState(() {
      _visibleRange = ChartVisibleRange(newStart, newStart + newWidth);
      _touchedIndex = null;
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _rangeAtScaleStart = null;
    _focalPointAtScaleStart = null;
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
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? const Color(0xFF10B981)
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.55),
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
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
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

  // ignore: unused_element
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
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
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
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.42),
              fontSize: 11,
            ),
          ),
          TextSpan(
            text: _formatValue(value),
            style: TextStyle(
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

class _IndexFullscreenChartPage extends StatefulWidget {
  const _IndexFullscreenChartPage({
    required this.title,
    required this.symbol,
    required this.initialCandles,
    required this.initialPeriod,
    required this.initialRange,
    required this.formatValue,
  });

  final String title;
  final String symbol;
  final List<_OHLC> initialCandles;
  final _Period initialPeriod;
  final ChartVisibleRange initialRange;
  final String Function(double) formatValue;

  @override
  State<_IndexFullscreenChartPage> createState() =>
      _IndexFullscreenChartPageState();
}

class _IndexFullscreenChartPageState extends State<_IndexFullscreenChartPage> {
  late _Period _period;
  late List<_OHLC> _candles;
  bool _loading = false;
  int _fetchSeq = 0;
  int? _touchedIndex;
  late ChartVisibleRange _visibleRange;
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
    _period = widget.initialPeriod;
    _candles = widget.initialCandles;
    _visibleRange = widget.initialRange;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _fetchCandles(int seq) async {
    final data = await StockPriceService.fetchOHLC(
      widget.symbol,
      'US',
      interval: _period.interval,
      range: _period.range,
    );
    if (!mounted || _fetchSeq != seq) return;
    setState(() {
      _candles = data;
      _loading = false;
      _touchedIndex = null;
      final defaultView = _period == _Period.day1 ? 120 : data.length;
      final startIdx = (data.length - defaultView)
          .clamp(0, data.length)
          .toDouble();
      _visibleRange = ChartVisibleRange(startIdx, data.length.toDouble());
    });
  }

  void _selectPeriod(_Period period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _loading = true;
      _touchedIndex = null;
      _visibleRange = const ChartVisibleRange(0, 0);
    });
    _fetchCandles(++_fetchSeq);
  }

  void _onTouch(double localX, double width) {
    if (_candles.isEmpty) return;
    const yAxisW = 48.0;
    final chartWidth = width - yAxisW;
    if (chartWidth <= 0) return;
    final adjustedX = (localX - yAxisW).clamp(0.0, chartWidth);
    final visibleWidth = _visibleRange.width;
    if (visibleWidth <= 0) return;
    final fractionalIndex =
        _visibleRange.start + (adjustedX / chartWidth) * visibleWidth;
    final overallIndex = fractionalIndex.floor().clamp(0, _candles.length - 1);
    final displayStartIdx = _visibleRange.start.floor();
    final displayTouchedIdx = overallIndex - displayStartIdx;
    if (_touchedIndex != displayTouchedIdx) {
      setState(() => _touchedIndex = displayTouchedIdx);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _rangeAtScaleStart = _visibleRange;
    _focalPointAtScaleStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double chartWidth) {
    if (_rangeAtScaleStart == null ||
        _focalPointAtScaleStart == null ||
        _candles.isEmpty) {
      return;
    }
    const yAxisW = 48.0;
    final candleAreaW = chartWidth - yAxisW;
    if (candleAreaW <= 0) return;
    final newWidth = (_rangeAtScaleStart!.width / details.scale).clamp(
      5.0,
      _candles.length.toDouble(),
    );
    final focalFraction = ((_focalPointAtScaleStart!.dx - yAxisW) / candleAreaW)
        .clamp(0.0, 1.0);
    final anchorCandle =
        _rangeAtScaleStart!.start + focalFraction * _rangeAtScaleStart!.width;
    final panDeltaX = details.localFocalPoint.dx - _focalPointAtScaleStart!.dx;
    final panDeltaCandles = (panDeltaX / candleAreaW) * newWidth;

    var newStart = anchorCandle - (focalFraction * newWidth) - panDeltaCandles;
    if (newStart < 0) newStart = 0;
    if (newStart + newWidth > _candles.length) {
      newStart = _candles.length - newWidth;
    }
    setState(() {
      _visibleRange = ChartVisibleRange(newStart, newStart + newWidth);
      _touchedIndex = null;
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _rangeAtScaleStart = null;
    _focalPointAtScaleStart = null;
  }

  Widget _fsBtn(String label, bool active, ColorScheme cs, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF10B981).withValues(alpha: 0.14)
              : cs.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? const Color(0xFF10B981)
                : cs.onSurface.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _ohlcLabel(
    String label,
    double value,
    ColorScheme cs, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.38),
                fontSize: 10,
              ),
            ),
            TextSpan(
              text: widget.formatValue(value),
              style: TextStyle(
                color: color ?? cs.onSurface.withValues(alpha: 0.87),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _axisDate(DateTime date) {
    if (_period.isMinute) return DateFormat('HH:mm').format(date);
    if (_period == _Period.month) return DateFormat('yy/MM').format(date);
    return DateFormat('MM/dd').format(date);
  }

  String _formatDate(DateTime date) {
    if (_period.isMinute) {
      return DateFormat('MM.dd HH:mm').format(date);
    }
    if (_period == _Period.month) {
      return DateFormat('yyyy.MM').format(date);
    }
    return DateFormat('yyyy.MM.dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dc = _displayCandles;
    final touched = _touchedIndex != null && _touchedIndex! < dc.length
        ? dc[_touchedIndex!]
        : null;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: touched != null
                      ? Padding(
                          key: ValueKey(_touchedIndex),
                          padding: const EdgeInsets.only(
                            left: 10,
                            top: 4,
                            bottom: 4,
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Text(
                                  _formatDate(touched.date),
                                  style: TextStyle(
                                    color: cs.onSurface.withValues(alpha: 0.54),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _ohlcLabel('시', touched.open, cs),
                                _ohlcLabel(
                                  '고',
                                  touched.high,
                                  cs,
                                  color: _kUpColor,
                                ),
                                _ohlcLabel(
                                  '저',
                                  touched.low,
                                  cs,
                                  color: _kDownColor,
                                ),
                                _ohlcLabel(
                                  '종',
                                  touched.close,
                                  cs,
                                  color: touched.close >= touched.open
                                      ? _kUpColor
                                      : _kDownColor,
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox(key: ValueKey('empty'), height: 26),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF10B981),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final chartW = constraints.maxWidth;
                            return GestureDetector(
                              onLongPressStart: (details) =>
                                  _onTouch(details.localPosition.dx, chartW),
                              onLongPressMoveUpdate: (details) =>
                                  _onTouch(details.localPosition.dx, chartW),
                              onLongPressEnd: (_) =>
                                  setState(() => _touchedIndex = null),
                              onScaleStart: _onScaleStart,
                              onScaleUpdate: (details) =>
                                  _onScaleUpdate(details, chartW),
                              onScaleEnd: _onScaleEnd,
                              child: CustomPaint(
                                size: Size(chartW, constraints.maxHeight),
                                painter: _CandlePainter(
                                  candles: dc,
                                  touchedIndex: _touchedIndex,
                                  formatValue: widget.formatValue,
                                  formatDate: _axisDate,
                                  labelColor: cs.onSurface,
                                  allCandles: _candles,
                                  visibleStart: _visibleRange.start
                                      .floor()
                                      .clamp(0, _candles.length),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        alignment: Alignment.bottomCenter,
                        child: _period.isMinute
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children:
                                      [
                                            _Period.min1,
                                            _Period.min5,
                                            _Period.min60,
                                          ]
                                          .map(
                                            (p) => _fsBtn(
                                              p.label,
                                              _period == p,
                                              cs,
                                              () => _selectPeriod(p),
                                            ),
                                          )
                                          .toList(),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _fsBtn('분봉', _period.isMinute, cs, () {
                            if (!_period.isMinute) _selectPeriod(_Period.min1);
                          }),
                          ...[_Period.day1, _Period.week, _Period.month].map(
                            (p) => _fsBtn(
                              p.label,
                              _period == p,
                              cs,
                              () => _selectPeriod(p),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(
                  Icons.fullscreen_exit,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
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
  final List<_OHLC>? allCandles;
  final int visibleStart;

  const _CandlePainter({
    required this.candles,
    required this.touchedIndex,
    required this.formatValue,
    required this.formatDate,
    required this.labelColor,
    this.allCandles,
    this.visibleStart = 0,
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
      final candleColor = up ? _kUpColor : _kDownColor;
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

    // 이동평균선: 5 / 20 / 60 / 120
    if (allCandles != null && allCandles!.isNotEmpty) {
      const maConfigs = [
        (5, Color(0xFFFFA726)),
        (20, Color(0xFF42A5F5)),
        (60, Color(0xFFAB47BC)),
        (120, Color(0xFFEF5350)),
      ];
      for (final (period, color) in maConfigs) {
        final path = Path();
        var started = false;
        for (int i = 0; i < n; i++) {
          final globalIndex = visibleStart + i;
          if (globalIndex < period - 1) continue;
          if (globalIndex >= allCandles!.length) continue;
          var sum = 0.0;
          for (int k = globalIndex - period + 1; k <= globalIndex; k++) {
            sum += allCandles![k].close;
          }
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
              ..color = color.withValues(alpha: 0.85)
              ..strokeWidth = 1.2
              ..style = PaintingStyle.stroke,
          );
        }
      }
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

    final sourceCandles = allCandles ?? candles;
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
      final sourceIdx = (visibleStart + idx).clamp(0, sourceCandles.length - 1);
      final tp = TextPainter(
        text: TextSpan(
          text: formatDate(sourceCandles[sourceIdx].date),
          style: style,
        ),
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
        oldDelegate.labelColor != labelColor ||
        oldDelegate.allCandles != allCandles ||
        oldDelegate.visibleStart != visibleStart;
  }
}
