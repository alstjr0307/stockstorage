import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/market_feature_stock.dart';
import '../services/stock_price_service.dart';

typedef _FeatureCandle = ({
  DateTime date,
  double open,
  double high,
  double low,
  double close,
});

class MarketFeatureStockDetailScreen extends StatelessWidget {
  const MarketFeatureStockDetailScreen({super.key, required this.item});

  final MarketFeatureStock item;

  static final _dateFormat = DateFormat('yyyy.MM.dd');
  static final _timeFormat = DateFormat('MM.dd HH:mm');
  static final _numberFormat = NumberFormat('#,###');

  static const _accent = Color(0xFF10B981);
  static const _up = Color(0xFFF04452);
  static const _down = Color(0xFF1677FF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final isUp = item.changeRate >= 0;
    final moveColor = isUp ? _up : _down;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              item.ticker,
              style: TextStyle(
                fontFamily: 'RobotoMono',
                color: cs.onSurface.withValues(alpha: 0.38),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: [
          _Header(
            item: item,
            moveColor: moveColor,
            isUp: isUp,
            featureTitle: _featureTitle(item),
          ),
          const SizedBox(height: 28),
          _FeaturePriceChart(item: item, lineColor: moveColor),
          const SizedBox(height: 28),
          _ReasonBlock(reason: _localizedReason, accent: _accent),
          const SizedBox(height: 30),
          _SectionHeader(title: '핵심 지표'),
          const SizedBox(height: 6),
          _MetricRow(label: '현재가', value: _formatPrice(item.price)),
          _MetricRow(
            label: '등락률',
            value: '${isUp ? '+' : ''}${item.changeRate.toStringAsFixed(2)}%',
            valueColor: moveColor,
          ),
          _MetricRow(
            label: '거래대금',
            value: _formatTradingValue(item.tradingValue),
          ),
          _MetricRow(
            label: '거래량 배수',
            value: item.volumeRatio > 0
                ? '${item.volumeRatio.toStringAsFixed(1)}x'
                : '-',
          ),
          if (_showsScore(item))
            _MetricRow(label: '포착 점수', value: '${item.score}'),
          const SizedBox(height: 28),
          _SectionHeader(title: '포착 정보'),
          const SizedBox(height: 6),
          _MetricRow(label: '분류', value: _groupLabel(item.group)),
          _MetricRow(label: '패턴', value: _featureTitle(item)),
          _MetricRow(label: '기준일', value: _dateFormat.format(item.sourceDate)),
          _MetricRow(label: '등록', value: _timeFormat.format(item.createdAt)),
          const SizedBox(height: 22),
          Text(
            '특징주는 시장 데이터 기반 포착 정보이며, 매수·매도 권유가 아닙니다.',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.34),
              fontSize: 11,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String get _localizedReason {
    final reason = item.reason.replaceAll('\n', ' ').trim();
    if (reason.isNotEmpty && !_looksEnglish(reason)) return reason;

    final title = item.title.trim();
    if (title.isNotEmpty && !_looksEnglish(title)) return title;

    final parts = <String>[];
    parts.add('${_groupLabel(item.group)} 기준으로 포착된 종목입니다.');
    if (item.changeRate != 0) {
      final direction = item.changeRate > 0 ? '상승' : '하락';
      parts.add(
        '당일 등락률은 ${item.changeRate.abs().toStringAsFixed(2)}% $direction했습니다.',
      );
    }
    if (item.tradingValue > 0) {
      parts.add('거래대금은 ${_formatTradingValue(item.tradingValue)} 수준입니다.');
    }
    if (item.volumeRatio > 0) {
      parts.add('평소 대비 거래량은 ${item.volumeRatio.toStringAsFixed(1)}배로 집계됐습니다.');
    }
    final pattern = _patternLabel(item.pattern);
    if (pattern != null) {
      parts.add('$pattern 흐름이 함께 감지됐습니다.');
    }
    return parts.join(' ');
  }

  static String _featureTitle(MarketFeatureStock item) {
    if (item.title.isNotEmpty && !_looksEnglish(item.title)) return item.title;
    return _patternLabel(item.pattern) ?? _groupLabel(item.group);
  }

  static bool _showsScore(MarketFeatureStock item) {
    return item.group == 'chart_capture';
  }

  static String? _patternLabel(String pattern) {
    switch (pattern) {
      case 'top_trading_value':
        return '거래대금 상위';
      case 'gainers':
        return '급등주';
      case 'trading_value_spike':
        return '거래량/거래대금 급증';
      case 'new_52w_high':
        return '신고가 돌파';
      case 'prior_high_breakout':
        return '전고점 돌파';
      case 'volume_surge_pullback_tail':
        return '급등 후 U자 눌림';
      case 'volume_spike_breakout_dry_up_rise':
        return '거래량 감소 상승';
      case 'volume_spike_dry_up_pullback_support':
        return '거래량 감소 눌림 지지';
      default:
        return null;
    }
  }

  static String _groupLabel(String group) {
    switch (group) {
      case 'top_trading_value':
        return '거래대금 상위';
      case 'gainers':
        return '급등주';
      case 'volume_spike':
        return '거래량 급증';
      case 'high_breakout':
        return '신고가/돌파';
      case 'chart_capture':
        return '차트 포착';
      default:
        return group.isEmpty ? '-' : group;
    }
  }

  static String _formatPrice(double price) {
    if (price <= 0) return '-';
    return _numberFormat.format(price.round());
  }

  static String _formatTradingValue(int value) {
    if (value <= 0) return '-';
    if (value >= 1000000000000) {
      return '${(value / 1000000000000).toStringAsFixed(1)}조';
    }
    if (value >= 100000000) {
      return '${(value / 100000000).round()}억';
    }
    return _numberFormat.format(value);
  }

  static bool _looksEnglish(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    final hasKorean = RegExp(r'[가-힣]').hasMatch(text);
    if (hasKorean) return false;
    return RegExp(r'[A-Za-z]').hasMatch(text);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.moveColor,
    required this.isUp,
    required this.featureTitle,
  });

  final MarketFeatureStock item;
  final Color moveColor;
  final bool isUp;
  final String featureTitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                featureTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.48),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.ticker,
          style: TextStyle(
            fontFamily: 'RobotoMono',
            color: cs.onSurface.withValues(alpha: 0.38),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                NumberFormat('#,###').format(item.price.round()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'RobotoMono',
                  color: cs.onSurface,
                  fontSize: 34,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: moveColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                '${isUp ? '+' : ''}${item.changeRate.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontFamily: 'RobotoMono',
                  color: moveColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePriceChart extends StatefulWidget {
  const _FeaturePriceChart({required this.item, required this.lineColor});

  final MarketFeatureStock item;
  final Color lineColor;

  @override
  State<_FeaturePriceChart> createState() => _FeaturePriceChartState();
}

class _FeaturePriceChartState extends State<_FeaturePriceChart> {
  late Future<List<_FeatureCandle>> _future;
  bool _showCandles = true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _FeaturePriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.ticker != widget.item.ticker ||
        oldWidget.item.market != widget.item.market) {
      _future = _load();
    }
  }

  Future<List<_FeatureCandle>> _load() {
    return StockPriceService.fetchOHLC(
      widget.item.ticker,
      widget.item.market,
      range: '3mo',
      interval: '1d',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader(title: '최근 흐름')),
            _ChartModeButton(
              label: '캔들',
              selected: _showCandles,
              onTap: () => setState(() => _showCandles = true),
            ),
            const SizedBox(width: 6),
            _ChartModeButton(
              label: '선',
              selected: !_showCandles,
              onTap: () => setState(() => _showCandles = false),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<_FeatureCandle>>(
          future: _future,
          builder: (context, snapshot) {
            final data = (snapshot.data ?? const <_FeatureCandle>[])
                .where(
                  (c) =>
                      c.open.isFinite &&
                      c.high.isFinite &&
                      c.low.isFinite &&
                      c.close.isFinite &&
                      c.open > 0 &&
                      c.high > 0 &&
                      c.low > 0 &&
                      c.close > 0,
                )
                .toList();
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(
                height: 190,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              );
            }
            if (data.length < 2) {
              return SizedBox(
                height: 190,
                child: Center(
                  child: Text(
                    '차트 데이터를 불러오지 못했습니다.',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.42),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, progress, child) {
                return SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _showCandles
                        ? _FeatureCandleChartPainter(
                            candles: data,
                            markerDate: widget.item.sourceDate,
                            upColor: MarketFeatureStockDetailScreen._up,
                            downColor: MarketFeatureStockDetailScreen._down,
                            labelColor: cs.onSurface.withValues(alpha: 0.42),
                            markerColor: MarketFeatureStockDetailScreen._accent,
                            gridColor: cs.onSurface.withValues(alpha: 0.06),
                            progress: progress,
                          )
                        : _FeatureLineChartPainter(
                            data: [
                              for (final candle in data)
                                (candle.date, candle.close),
                            ],
                            markerDate: widget.item.sourceDate,
                            color: widget.lineColor,
                            labelColor: cs.onSurface.withValues(alpha: 0.42),
                            markerColor: MarketFeatureStockDetailScreen._accent,
                            gridColor: cs.onSurface.withValues(alpha: 0.06),
                            progress: progress,
                          ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _ChartModeButton extends StatelessWidget {
  const _ChartModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.onSurface.withValues(alpha: 0.1)
              : cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.46),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FeatureCandleChartPainter extends CustomPainter {
  const _FeatureCandleChartPainter({
    required this.candles,
    required this.markerDate,
    required this.upColor,
    required this.downColor,
    required this.labelColor,
    required this.markerColor,
    required this.gridColor,
    required this.progress,
  });

  final List<_FeatureCandle> candles;
  final DateTime markerDate;
  final Color upColor;
  final Color downColor;
  final Color labelColor;
  final Color markerColor;
  final Color gridColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2) return;

    const leftPad = 0.0;
    const rightPad = 40.0;
    const topPad = 8.0;
    const bottomPad = 24.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    final visibleCount = (candles.length * progress.clamp(0.08, 1.0))
        .ceil()
        .clamp(2, candles.length);
    final data = candles.take(visibleCount).toList();

    var minValue = data.first.low;
    var maxValue = data.first.high;
    for (final c in data) {
      if (c.low < minValue) minValue = c.low;
      if (c.high > maxValue) maxValue = c.high;
    }
    final padding = (maxValue - minValue).abs() * 0.08;
    minValue -= padding;
    maxValue += padding;
    final span = (maxValue - minValue).abs() < 0.001
        ? 1.0
        : maxValue - minValue;

    double toX(int index) => leftPad + chartW * (index + 0.5) / data.length;
    double toY(double value) =>
        topPad + chartH - ((value - minValue) / span * chartH);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
    }

    final candleSlot = chartW / data.length;
    final bodyW = (candleSlot * 0.58).clamp(3.0, 10.0);
    for (var i = 0; i < data.length; i++) {
      final c = data[i];
      final x = toX(i);
      final color = c.close >= c.open ? upColor : downColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, toY(c.high)), Offset(x, toY(c.low)), paint);

      final top = toY(c.open > c.close ? c.open : c.close);
      final bottom = toY(c.open > c.close ? c.close : c.open);
      final rect = Rect.fromLTRB(
        x - bodyW / 2,
        top,
        x + bodyW / 2,
        bottom == top ? top + 1 : bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        paint,
      );
    }

    final markerIndex = _findMarkerIndex(data, markerDate);
    if (markerIndex != null) {
      _drawFeatureMarker(
        canvas,
        x: toX(markerIndex),
        top: topPad,
        bottom: topPad + chartH,
        color: markerColor,
        labelColor: labelColor,
      );
    }

    _drawYAxisLabel(canvas, size, maxValue, topPad);
    _drawYAxisLabel(canvas, size, minValue, topPad + chartH - 14);
    _drawDateLabel(
      canvas,
      data.first.date,
      Offset(leftPad, topPad + chartH + 7),
    );
    _drawDateLabel(
      canvas,
      data.last.date,
      Offset(leftPad + chartW - 42, topPad + chartH + 7),
    );
  }

  void _drawYAxisLabel(Canvas canvas, Size size, double value, double y) {
    final text = NumberFormat.compact(locale: 'ko_KR').format(value.round());
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'RobotoMono',
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: 52);
    painter.paint(canvas, Offset(size.width - 40, y));
  }

  void _drawDateLabel(Canvas canvas, DateTime date, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: DateFormat('M.d').format(date),
        style: TextStyle(
          fontFamily: 'RobotoMono',
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FeatureCandleChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.markerDate != markerDate ||
        oldDelegate.upColor != upColor ||
        oldDelegate.downColor != downColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.markerColor != markerColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.progress != progress;
  }
}

class _FeatureLineChartPainter extends CustomPainter {
  const _FeatureLineChartPainter({
    required this.data,
    required this.markerDate,
    required this.color,
    required this.labelColor,
    required this.markerColor,
    required this.gridColor,
    required this.progress,
  });

  final List<(DateTime, double)> data;
  final DateTime markerDate;
  final Color color;
  final Color labelColor;
  final Color markerColor;
  final Color gridColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    const leftPad = 0.0;
    const rightPad = 40.0;
    const topPad = 8.0;
    const bottomPad = 24.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    var minValue = data.first.$2;
    var maxValue = data.first.$2;
    for (final point in data) {
      if (point.$2 < minValue) minValue = point.$2;
      if (point.$2 > maxValue) maxValue = point.$2;
    }
    final padding = (maxValue - minValue).abs() * 0.08;
    minValue -= padding;
    maxValue += padding;
    final span = (maxValue - minValue).abs() < 0.001
        ? 1.0
        : maxValue - minValue;

    double toX(int index) => leftPad + chartW * index / (data.length - 1);
    double toY(double value) =>
        topPad + chartH - ((value - minValue) / span * chartH);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
    }

    final points = <Offset>[
      for (var i = 0; i < data.length; i++) Offset(toX(i), toY(data[i].$2)),
    ];
    final visible = _visiblePoints(points);
    if (visible.length < 2) return;

    final linePath = Path()..moveTo(visible.first.dx, visible.first.dy);
    for (final point in visible.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(visible.last.dx, topPad + chartH)
      ..lineTo(visible.first.dx, topPad + chartH)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, topPad, chartW, chartH)),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final markerIndex = _findMarkerIndex([
      for (final point in data)
        (
          date: point.$1,
          open: point.$2,
          high: point.$2,
          low: point.$2,
          close: point.$2,
        ),
    ], markerDate);
    if (markerIndex != null && markerIndex < visible.length) {
      _drawFeatureMarker(
        canvas,
        x: toX(markerIndex),
        top: topPad,
        bottom: topPad + chartH,
        color: markerColor,
        labelColor: labelColor,
      );
    }

    _drawYAxisLabel(canvas, size, maxValue, topPad);
    _drawYAxisLabel(canvas, size, minValue, topPad + chartH - 14);
    _drawDateLabel(canvas, data.first.$1, Offset(leftPad, topPad + chartH + 7));
    _drawDateLabel(
      canvas,
      data.last.$1,
      Offset(leftPad + chartW - 42, topPad + chartH + 7),
    );
  }

  List<Offset> _visiblePoints(List<Offset> points) {
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped >= 1) return points;
    final end = (points.length - 1) * clamped;
    final whole = end.floor();
    final fraction = end - whole;
    final shown = <Offset>[points.first];
    for (var i = 1; i <= whole && i < points.length; i++) {
      shown.add(points[i]);
    }
    if (whole + 1 < points.length) {
      shown.add(Offset.lerp(points[whole], points[whole + 1], fraction)!);
    }
    return shown;
  }

  void _drawYAxisLabel(Canvas canvas, Size size, double value, double y) {
    final text = NumberFormat.compact(locale: 'ko_KR').format(value.round());
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'RobotoMono',
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: 52);
    painter.paint(canvas, Offset(size.width - 40, y));
  }

  void _drawDateLabel(Canvas canvas, DateTime date, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: DateFormat('M.d').format(date),
        style: TextStyle(
          fontFamily: 'RobotoMono',
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FeatureLineChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.markerDate != markerDate ||
        oldDelegate.color != color ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.markerColor != markerColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.progress != progress;
  }
}

int? _findMarkerIndex(List<_FeatureCandle> candles, DateTime markerDate) {
  if (candles.isEmpty) return null;
  final marker = DateTime(markerDate.year, markerDate.month, markerDate.day);
  for (var i = 0; i < candles.length; i++) {
    final d = candles[i].date;
    if (DateTime(d.year, d.month, d.day).isAtSameMomentAs(marker)) {
      return i;
    }
  }
  return null;
}

void _drawFeatureMarker(
  Canvas canvas, {
  required double x,
  required double top,
  required double bottom,
  required Color color,
  required Color labelColor,
}) {
  final markerPaint = Paint()
    ..color = color.withValues(alpha: 0.72)
    ..strokeWidth = 1.2;
  canvas.drawLine(Offset(x, top), Offset(x, bottom), markerPaint);
  canvas.drawCircle(Offset(x, top + 6), 3.2, Paint()..color = color);

  const label = '포착';
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: labelColor,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final labelX = x - painter.width / 2;
  painter.paint(canvas, Offset(labelX, top + 11));
}

class _ReasonBlock extends StatelessWidget {
  const _ReasonBlock({required this.reason, required this.accent});

  final String reason;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '포착 사유',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.82),
              fontSize: 15,
              height: 1.65,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: cs.onSurface.withValues(alpha: 0.06),
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    color: valueColor ?? cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.onSurface.withValues(alpha: 0.06),
        ),
      ],
    );
  }
}

