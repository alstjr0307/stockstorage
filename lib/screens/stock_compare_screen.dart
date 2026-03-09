import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';
import '../services/stock_price_service.dart';

class StockCompareScreen extends StatefulWidget {
  final StockPick basePick;
  const StockCompareScreen({super.key, required this.basePick});

  @override
  State<StockCompareScreen> createState() => _StockCompareScreenState();
}

class _StockCompareScreenState extends State<StockCompareScreen> {
  // Base stock data
  List<double> _baseHistory = [];
  PriceResult? _basePrice;

  // Compare stock
  final _searchCtrl = TextEditingController();
  StockSearchResult? _compareStock;
  List<StockSearchResult> _searchResults = [];
  bool _searching = false;
  List<double> _compareHistory = [];
  PriceResult? _comparePrice;
  bool _loadingCompare = false;

  bool _loadingBase = true;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final results = await Future.wait([
      StockPriceService.fetchHistory(
          widget.basePick.ticker, widget.basePick.market),
      StockPriceService.fetchPrice(
          widget.basePick.ticker, widget.basePick.market),
    ]);
    if (mounted) {
      setState(() {
        _baseHistory = results[0] as List<double>;
        _basePrice = results[1] as PriceResult?;
        _loadingBase = false;
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    final results = await StockPriceService.searchStocks(query);
    if (mounted) setState(() { _searchResults = results; _searching = false; });
  }

  Future<void> _selectCompare(StockSearchResult stock) async {
    setState(() {
      _compareStock = stock;
      _searchResults = [];
      _searchCtrl.text = '${stock.name} (${stock.ticker})';
      _loadingCompare = true;
    });
    final results = await Future.wait([
      StockPriceService.fetchHistory(stock.ticker, stock.market),
      StockPriceService.fetchPrice(stock.ticker, stock.market),
    ]);
    if (mounted) {
      setState(() {
        _compareHistory = results[0] as List<double>;
        _comparePrice = results[1] as PriceResult?;
        _loadingCompare = false;
      });
    }
  }

  List<double> _toPercent(List<double> prices) {
    if (prices.isEmpty) return [];
    final base = prices.first;
    if (base == 0) return prices.map((_) => 0.0).toList();
    return prices.map((p) => ((p - base) / base) * 100).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final basePct = _toPercent(_baseHistory);
    final comparePct = _toPercent(_compareHistory);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('종목 비교',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 검색창 ──
          _buildSearchField(isDark, cs),
          if (_searchResults.isNotEmpty) _buildSearchResults(isDark, cs),
          const SizedBox(height: 20),

          // ── 가격 요약 ──
          _buildPriceSummary(isDark, cs),
          const SizedBox(height: 16),

          // ── 비교 차트 ──
          _buildChart(isDark, basePct, comparePct),
          const SizedBox(height: 16),

          // ── 범례 ──
          _buildLegend(cs),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('비교할 종목',
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          style: GoogleFonts.inter(color: cs.onSurface, fontSize: 14),
          onChanged: _search,
          decoration: InputDecoration(
            hintText: '종목명 또는 티커 검색...',
            hintStyle: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14),
            filled: true,
            fillColor: cs.surface,
            prefixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF4ADE80))),
                  )
                : Icon(Icons.search,
                    color: cs.onSurface.withValues(alpha: 0.4), size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        color: cs.onSurface.withValues(alpha: 0.4), size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _compareStock = null;
                        _compareHistory = [];
                        _comparePrice = null;
                        _searchResults = [];
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(bool isDark, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: _searchResults.take(5).map((r) {
          return ListTile(
            dense: true,
            title: Text(r.name,
                style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13)),
            subtitle: Text('${r.ticker} · ${r.exchange}',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11)),
            onTap: () => _selectCompare(r),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriceSummary(bool isDark, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: _buildPriceCard(
            cs,
            widget.basePick.name,
            widget.basePick.ticker,
            _basePrice,
            const Color(0xFF4ADE80),
            _loadingBase,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compareStock == null
              ? Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.08),
                        style: BorderStyle.solid),
                  ),
                  child: Center(
                    child: Text('비교 종목\n선택하세요',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 12)),
                  ),
                )
              : _buildPriceCard(
                  cs,
                  _compareStock!.name,
                  _compareStock!.ticker,
                  _comparePrice,
                  Colors.orangeAccent,
                  _loadingCompare,
                ),
        ),
      ],
    );
  }

  Widget _buildPriceCard(ColorScheme cs, String name, String ticker,
      PriceResult? price, Color accentColor, bool loading) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: accentColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(ticker,
                    style: GoogleFonts.robotoMono(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.7), fontSize: 11)),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)))
          else if (price != null) ...[
            Text(price.formattedPrice,
                style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            Text(price.formattedChange,
                style: GoogleFonts.inter(
                    color: price.isUp
                        ? const Color(0xFF4ADE80)
                        : Colors.redAccent,
                    fontSize: 11)),
          ] else
            Text('—',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildChart(
      bool isDark, List<double> basePct, List<double> comparePct) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2035) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text('1개월 수익률 비교 (%)',
                style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          if (_loadingBase)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)),
              ),
            )
          else if (basePct.isEmpty)
            SizedBox(
              height: 200,
              child: Center(
                child: Text('데이터 없음',
                    style: GoogleFonts.inter(
                        color: Colors.white24, fontSize: 13)),
              ),
            )
          else
            CustomPaint(
              size: const Size(double.infinity, 200),
              painter: _CompareLinePainter(
                basePct: basePct,
                comparePct:
                    (_compareStock != null && !_loadingCompare && comparePct.isNotEmpty)
                        ? comparePct
                        : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend(ColorScheme cs) {
    return Row(
      children: [
        _legendDot(const Color(0xFF4ADE80), widget.basePick.name),
        const SizedBox(width: 16),
        if (_compareStock != null)
          _legendDot(Colors.orangeAccent, _compareStock!.name),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.inter(
                color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _CompareLinePainter extends CustomPainter {
  final List<double> basePct;
  final List<double>? comparePct;

  const _CompareLinePainter({required this.basePct, this.comparePct});

  @override
  void paint(Canvas canvas, Size size) {
    if (basePct.isEmpty) return;

    const yAxisW = 46.0;
    const xLabelH = 18.0;
    final chartH = size.height - xLabelH;
    final chartW = size.width - yAxisW;

    // Combine both series to find min/max
    final allValues = [
      ...basePct,
      ...?comparePct,
    ];
    final minV = allValues.reduce((a, b) => a < b ? a : b);
    final maxV = allValues.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();
    final pad = range == 0 ? 1.0 : range * 0.1;
    final minY = minV - pad;
    final maxY = maxV + pad;
    final yRange = maxY - minY;

    double toY(double v) => chartH - ((v - minY) / yRange) * chartH;
    double toX(int i, int n) =>
        yAxisW + (n <= 1 ? chartW / 2 : chartW * i / (n - 1));

    // Grid + zero line
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      canvas.drawLine(Offset(yAxisW, chartH * i / 4),
          Offset(size.width, chartH * i / 4), gridPaint);
    }
    // Zero line
    if (minY < 0 && maxY > 0) {
      final zeroY = toY(0);
      canvas.drawLine(
        Offset(yAxisW, zeroY),
        Offset(size.width, zeroY),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
    }

    void drawLine(List<double> pcts, Color color) {
      if (pcts.length < 2) return;
      final path = Path();
      for (int i = 0; i < pcts.length; i++) {
        final x = toX(i, pcts.length);
        final y = toY(pcts[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }

    drawLine(basePct, const Color(0xFF4ADE80));
    if (comparePct != null) drawLine(comparePct!, Colors.orangeAccent);

    // Y-axis labels
    for (int i = 0; i <= 3; i++) {
      final v = minY + yRange * (1 - i / 4);
      final sign = v >= 0 ? '+' : '';
      final tp = TextPainter(
        text: TextSpan(
          text: '$sign${v.toStringAsFixed(1)}%',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 8,
              fontFamily: 'RobotoMono'),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final y = (chartH * i / 4 - tp.height / 2).clamp(0.0, chartH - tp.height);
      tp.paint(canvas, Offset(0, y));
    }

    // X-axis date labels (approximate — just show count markers)
    final n = basePct.length;
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 8,
      fontFamily: 'RobotoMono',
    );
    const labelCount = 4;
    for (int i = 0; i < labelCount; i++) {
      final idx = ((n - 1) * i / (labelCount - 1)).round().clamp(0, n - 1);
      final daysAgo = n - 1 - idx;
      final label = daysAgo == 0
          ? '오늘'
          : DateFormat('MM/dd').format(
              DateTime.now().subtract(Duration(days: daysAgo)));
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final x = (toX(idx, n) - tp.width / 2)
          .clamp(yAxisW, size.width - tp.width);
      tp.paint(canvas, Offset(x, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(_CompareLinePainter old) =>
      old.basePct != basePct || old.comparePct != comparePct;
}
