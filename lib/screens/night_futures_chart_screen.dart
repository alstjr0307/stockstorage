import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/analytics_service.dart';
import '../services/kis_websocket_service.dart';

class NightFuturesChartScreen extends StatefulWidget {
  final double initialPrice;
  final double initialChange;
  final double initialChangeRate;

  const NightFuturesChartScreen({
    super.key,
    this.initialPrice = 0,
    this.initialChange = 0,
    this.initialChangeRate = 0,
  });

  @override
  State<NightFuturesChartScreen> createState() =>
      _NightFuturesChartScreenState();
}

class _NightFuturesChartScreenState extends State<NightFuturesChartScreen> {
  final KisWebSocketService _ws = KisWebSocketService();
  final List<FlSpot> _spots = [];

  double _price = 0;
  double _change = 0;
  double _changeRate = 0;
  String _symbol = '';
  bool _loading = true;
  String? _error;
  DateTime? _lastTime;

  // x축 기준 시각 (ms)
  int _startMs = 0;

  @override
  void initState() {
    super.initState();
    _price = widget.initialPrice;
    _change = widget.initialChange;
    _changeRate = widget.initialChangeRate;
    _init();
    AnalyticsService.instance.logViewNightFutures();
  }

  Future<void> _init() async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable(
            'getKisNightFuturesConfig',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          );

      final res = await fn.call();
      final data = res.data as Map<String, dynamic>;

      final approvalKey = data['approvalKey'] as String;
      _symbol = data['symbol'] as String? ?? '';
      final history = (data['history'] as List<dynamic>? ?? []);

      if (history.isNotEmpty) {
        _startMs = (history.first['time'] as int);
        for (final h in history) {
          final ms = (h['time'] as int);
          final p = (h['price'] as num).toDouble();
          final x = (ms - _startMs) / 60000.0;
          _spots.add(FlSpot(x, p));
        }
        _lastTime = DateTime.fromMillisecondsSinceEpoch(
          history.last['time'] as int,
        );
        if (_price == 0 && _spots.isNotEmpty) {
          _price = _spots.last.y;
        }
      } else {
        _startMs = DateTime.now().millisecondsSinceEpoch;
      }

      if (mounted) setState(() => _loading = false);

      _ws.connect(approvalKey, _symbol);
      _ws.stream.listen((tick) {
        if (!mounted) return;
        final x = (tick.time.millisecondsSinceEpoch - _startMs) / 60000.0;
        setState(() {
          _price = tick.price;
          _change = tick.change;
          _changeRate = tick.changeRate;
          _lastTime = tick.time;
          _spots.add(FlSpot(x, tick.price));
          if (_spots.length > 3000) _spots.removeAt(0);
        });
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '데이터 로드 실패';
        });
      }
    }
  }

  @override
  void dispose() {
    _ws.dispose();
    super.dispose();
  }

  double _gridInterval() {
    if (_spots.length < 2) return 1;
    final prices = _spots.map((s) => s.y);
    final range = prices.reduce(math.max) - prices.reduce(math.min);
    if (range <= 0) return 1;
    final raw = range / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    return ((raw / mag).ceil() * mag).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUp = _change >= 0;
    final priceColor = isUp ? const Color(0xFF10B981) : const Color(0xFFFF6B6B);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 18, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'KOSPI200 야간선물',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            )
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            )
          : _buildBody(cs, priceColor, isUp),
    );
  }

  Widget _buildBody(ColorScheme cs, Color priceColor, bool isUp) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재가 & 등락
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _price > 0 ? _price.toStringAsFixed(2) : '-',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 5),
                child: Text(
                  'pt',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: priceColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isUp ? '+' : ''}${_changeRate.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: priceColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isUp ? '+' : ''}${_change.toStringAsFixed(2)}pt',
                    style: TextStyle(
                      color: priceColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _symbol.isNotEmpty
                    ? '$_symbol · 야간세션 18:00~05:00 KST'
                    : '야간세션 18:00~05:00 KST',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.38),
                  fontSize: 11,
                ),
              ),
              if (_lastTime != null) ...[
                const SizedBox(width: 8),
                Text(
                  '· 기준 ${DateFormat('HH:mm:ss').format(_lastTime!)} KST',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.38),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),

          // 차트
          Expanded(child: _buildChart(cs, priceColor)),
        ],
      ),
    );
  }

  Widget _buildChart(ColorScheme cs, Color priceColor) {
    if (_spots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: priceColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '체결 대기 중...',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final interval = _gridInterval();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.onSurface.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 58,
              interval: interval,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: priceColor,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: priceColor.withValues(alpha: 0.08),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.surface.withValues(alpha: 0.95),
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    s.y.toStringAsFixed(2),
                    TextStyle(
                      color: priceColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
