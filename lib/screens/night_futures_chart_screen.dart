import 'dart:async';
import '../utils/share_capture.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/analytics_service.dart';

class NightFuturesChartScreen extends StatefulWidget {
  final double initialPrice;
  final double initialChange;
  final double initialChangeRate;
  final String collection;
  final String title;
  final Color accent;

  const NightFuturesChartScreen({
    super.key,
    this.initialPrice = 0,
    this.initialChange = 0,
    this.initialChangeRate = 0,
    this.collection = 'night_futures_prices',
    this.title = '코스피 야간선물',
    this.accent = const Color(0xFF6366F1),
  });

  @override
  State<NightFuturesChartScreen> createState() =>
      _NightFuturesChartScreenState();
}

class _NightFuturesChartScreenState extends State<NightFuturesChartScreen> {
  StreamSubscription? _sub;
  final _captureKey = GlobalKey();
  bool _capturing = false;
  bool _showWatermark = false;
  final List<FlSpot> _spots = [];
  final List<double> _vols = [];
  final List<DateTime> _times = [];

  double _price = 0;
  double _change = 0;
  double _changeRate = 0;
  double _volume = 0;
  double _high = 0;
  double _low = 0;
  String _symbol = '';
  bool _loading = true;
  bool _empty = false;
  DateTime? _lastTime;

  static const _up = Color(0xFFFF5A5F);
  static const _down = Color(0xFF3B82F6);

  Color get _moveColor => _change >= 0 ? _up : _down;

  @override
  void initState() {
    super.initState();
    _price = widget.initialPrice;
    _change = widget.initialChange;
    _changeRate = widget.initialChangeRate;
    _subscribe();
    AnalyticsService.instance.logViewNightFutures();
  }

  void _subscribe() {
    _sub = FirebaseFirestore.instance
        .collection(widget.collection)
        .orderBy('timestamp', descending: true)
        .limit(720)
        .snapshots()
        .listen(
          _onSnapshot,
          onError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        );
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final docs = snap.docs.reversed.toList();
    if (docs.isEmpty) {
      setState(() {
        _loading = false;
        _empty = true;
      });
      return;
    }

    final spots = <FlSpot>[];
    final vols = <double>[];
    final times = <DateTime>[];
    double hi = -double.infinity;
    double lo = double.infinity;
    double? prevCum;

    // 최신 데이터가 속한 야간세션(18:00~익일 05:00)의 시작 시각(KST). 그 이전
    // 세션 데이터는 제외해서 어제 세션이 섞여 보이지 않게 한다.
    DateTime? sessionStartKst;
    final latestTs = docs.last.data()['timestamp'];
    if (latestTs is Timestamp) {
      sessionStartKst = _sessionStartKst(
        latestTs.toDate().toUtc().add(const Duration(hours: 9)),
      );
    }

    for (var i = 0; i < docs.length; i++) {
      final d = docs[i].data();
      final ts = d['timestamp'];
      final tsKst = ts is Timestamp
          ? ts.toDate().toUtc().add(const Duration(hours: 9))
          : DateTime.now().toUtc().add(const Duration(hours: 9));
      // 이전 세션 데이터는 건너뛴다.
      if (sessionStartKst != null && tsKst.isBefore(sessionStartKst)) continue;
      final p = (d['price'] as num?)?.toDouble();
      if (p == null || p <= 0) continue;
      spots.add(FlSpot(spots.length.toDouble(), p));
      if (p > hi) hi = p;
      if (p < lo) lo = p;

      final cum = (d['volume'] as num?)?.toDouble() ?? 0;
      double delta;
      if (prevCum == null) {
        delta = 0;
      } else if (cum >= prevCum) {
        delta = cum - prevCum;
      } else {
        delta = cum;
      }
      prevCum = cum;
      vols.add(delta < 0 ? 0 : delta);

      times.add(tsKst);
    }

    final latest = docs.last.data();
    final ts = latest['timestamp'];

    setState(() {
      _loading = false;
      _empty = spots.isEmpty;
      _spots
        ..clear()
        ..addAll(spots);
      _vols
        ..clear()
        ..addAll(vols);
      _times
        ..clear()
        ..addAll(times);
      _price = (latest['price'] as num?)?.toDouble() ?? _price;
      _change = (latest['change'] as num?)?.toDouble() ?? _change;
      _changeRate = (latest['changeRate'] as num?)?.toDouble() ?? _changeRate;
      _volume = (latest['volume'] as num?)?.toDouble() ?? _volume;
      _symbol = (latest['symbol'] as String?) ?? _symbol;
      if (hi.isFinite) _high = hi;
      if (lo.isFinite) _low = lo;
      if (ts is Timestamp) _lastTime = ts.toDate();
    });
  }

  // 야간세션은 18:00~익일 05:00(KST). 주어진 KST 시각이 속한 세션의 시작(18:00)을 반환.
  DateTime _sessionStartKst(DateTime tKst) {
    final base = DateTime(tKst.year, tKst.month, tKst.day);
    // 18:00 이후면 당일 18:00, 그 외(00:00~05:00)면 전날 18:00.
    return tKst.hour >= 18
        ? base.add(const Duration(hours: 18))
        : base.subtract(const Duration(hours: 6));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
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
      final xfile = await pngToShareFile(
        data.buffer.asUint8List(),
        'night_futures_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await Share.shareXFiles(
        [xfile],
        text: '${widget.title} · 주식저장소 앱',
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('캡처에 실패했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _showWatermark = false;
        });
      }
    }
  }

  String _timeLabel(int index) {
    if (index < 0 || index >= _times.length) return '';
    return DateFormat('HH:mm').format(_times[index]);
  }

  String _volLabel(double v) {
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(0)}K';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;

    return Scaffold(
      body: RepaintBoundary(
        key: _captureKey,
        child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                accent.withValues(alpha: dark ? 0.26 : 0.14),
                cs.surface,
              ),
              cs.surface,
            ],
            stops: const [0.0, 0.42],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accent))
              : Column(
                  children: [
                    _header(cs),
                    Expanded(child: _body(cs, dark)),
                  ],
                ),
        ),
      ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    final hasData = _price > 0 && !_empty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          if (!_capturing)
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: cs.onSurface,
              ),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: cs.onSurface,
                  ),
                ),
                if (_showWatermark)
                  Text(
                    '주식저장소 앱',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: Color.alphaBlend(
                        widget.accent.withValues(alpha: 0.9),
                        cs.onSurface,
                      ).withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
          _statusPill(cs, hasData),
          if (!_capturing) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '캡처해서 공유',
              icon: Icon(Icons.ios_share, size: 20, color: cs.onSurface),
              onPressed: _captureAndShare,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(ColorScheme cs, bool live) {
    final c = live ? _up : cs.onSurface.withValues(alpha: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            live ? 'LIVE' : '대기',
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ColorScheme cs, bool dark) {
    final isUp = _change >= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(cs, isUp),
          const SizedBox(height: 18),
          _statsStrip(cs, dark),
          const SizedBox(height: 18),
          Expanded(child: _chartArea(cs, dark)),
          if (_showWatermark) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                '📈 주식저장소 앱 · 코스피/코스닥 야간선물',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hero(ColorScheme cs, bool isUp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_symbol.isNotEmpty) ...[
              _miniChip(cs, _symbol),
              const SizedBox(width: 6),
            ],
            _miniChip(cs, '야간 18:00~05:00'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _price > 0 ? _price.toStringAsFixed(2) : '–',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1,
                letterSpacing: -1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 6),
              child: Text(
                'pt',
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _moveColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUp
                        ? Icons.arrow_drop_up_rounded
                        : Icons.arrow_drop_down_rounded,
                    color: _moveColor,
                    size: 22,
                  ),
                  Text(
                    '${_changeRate.abs().toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: _moveColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${isUp ? '▲' : '▼'} ${_change.abs().toStringAsFixed(2)}pt',
              style: TextStyle(
                color: _moveColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_lastTime != null) ...[
              const SizedBox(width: 10),
              Text(
                '· ${DateFormat('MM/dd HH:mm').format(_lastTime!.toUtc().add(const Duration(hours: 9)))} 기준 (KST)',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _miniChip(ColorScheme cs, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Color.alphaBlend(
            widget.accent.withValues(alpha: 0.9),
            cs.onSurface,
          ),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statsStrip(ColorScheme cs, bool dark) {
    final hasData = _spots.isNotEmpty;
    return Row(
      children: [
        _statCard(cs, dark, '고가', hasData ? _high.toStringAsFixed(2) : '–', _up),
        const SizedBox(width: 10),
        _statCard(
          cs,
          dark,
          '저가',
          hasData ? _low.toStringAsFixed(2) : '–',
          _down,
        ),
        const SizedBox(width: 10),
        _statCard(
          cs,
          dark,
          '누적 거래량',
          hasData ? _volume.toStringAsFixed(0) : '–',
          cs.onSurface.withValues(alpha: 0.75),
        ),
      ],
    );
  }

  Widget _statCard(
    ColorScheme cs,
    bool dark,
    String label,
    String value,
    Color valueColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.45),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartArea(ColorScheme cs, bool dark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 10),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: (_empty || _spots.length < 2)
          ? _waiting(cs)
          : Column(
              children: [
                Expanded(flex: 3, child: _priceChart(cs)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Text(
                        '거래량 (분당)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(height: 76, child: _volumeChart(cs)),
              ],
            ),
    );
  }

  Widget _waiting(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.nightlight_round,
            size: 38,
            color: widget.accent.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text(
            '야간세션 데이터를 기다리는 중',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '평일 18:00~05:00에 1분 단위로 갱신됩니다',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.35),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceChart(ColorScheme cs) {
    final ys = _spots.map((s) => s.y).toList();
    double lo = ys.reduce(math.min);
    double hi = ys.reduce(math.max);
    if (hi - lo < 0.05) {
      lo -= 1.0;
      hi += 1.0;
    } else {
      final pad = (hi - lo) * 0.25;
      lo -= pad;
      hi += pad;
    }
    final interval = ((hi - lo) / 4).clamp(0.1, double.infinity).toDouble();
    final c = _moveColor;

    return LineChart(
      LineChartData(
        minY: lo,
        maxY: hi,
        minX: 0,
        maxX: (_spots.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.onSurface.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
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
            color: c,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                Color.alphaBlend(c.withValues(alpha: 0.12), cs.surface),
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(2)}\n${_timeLabel(s.x.toInt())}',
                    TextStyle(
                      color: c,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _volumeChart(ColorScheme cs) {
    final n = _vols.length;
    final maxVol = n == 0 ? 1.0 : _vols.reduce(math.max);
    final topY = maxVol <= 0 ? 1.0 : maxVol * 1.25;
    final xInterval = (n / 4).ceilToDouble().clamp(1.0, double.infinity);
    final c = widget.accent;

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: topY,
        alignment: BarChartAlignment.spaceBetween,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) =>
                Color.alphaBlend(c.withValues(alpha: 0.12), cs.surface),
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${rod.toY.toStringAsFixed(0)}\n${_timeLabel(group.x)}',
              TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: topY,
              getTitlesWidget: (v, _) {
                if (v <= 0) return const SizedBox.shrink();
                return Text(
                  _volLabel(v),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: xInterval,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i % xInterval.toInt() != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _timeLabel(i),
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _vols[i],
                  width: (((300 - 48) / (n == 0 ? 1 : n)) * 0.55).clamp(
                    0.5,
                    7.0,
                  ),
                  color: c.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(1),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
