import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';
import '../services/stock_price_service.dart';

class StockCompareScreen extends StatefulWidget {
  final StockPick? basePick; // null = standalone tab (both stocks searchable)
  const StockCompareScreen({super.key, this.basePick});

  @override
  State<StockCompareScreen> createState() => _StockCompareScreenState();
}

// (label, range, interval)
const _comparePeriods = [
  ('1M', '1mo', '1d'),
  ('3M', '3mo', '1d'),
  ('6M', '6mo', '1d'),
  ('1Y', '1y', '1wk'),
  ('3Y', '3y', '1wk'),
  ('5Y', '5y', '1mo'),
];

class _StockCompareScreenState extends State<StockCompareScreen> {
  // 기간 선택
  int _periodIndex = 0;

  // Base stock data
  List<double> _baseHistory = [];
  PriceResult? _basePrice;
  bool _loadingBase = false;

  // Base stock search (standalone mode only)
  final _baseSearchCtrl = TextEditingController();
  StockSearchResult? _baseStockResult;
  List<StockSearchResult> _baseSearchResults = [];
  bool _searchingBase = false;

  // Compare stock
  final _searchCtrl = TextEditingController();
  StockSearchResult? _compareStock;
  List<StockSearchResult> _searchResults = [];
  bool _searching = false;
  List<double> _compareHistory = [];
  PriceResult? _comparePrice;
  bool _loadingCompare = false;

  String get _range => _comparePeriods[_periodIndex].$2;
  String get _interval => _comparePeriods[_periodIndex].$3;

  @override
  void initState() {
    super.initState();
    if (widget.basePick != null) {
      _loadingBase = true;
      _loadBase();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _baseSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final pick = widget.basePick!;
    final results = await Future.wait([
      StockPriceService.fetchHistory(pick.ticker, pick.market,
          range: _range, interval: _interval),
      StockPriceService.fetchPrice(pick.ticker, pick.market),
    ]);
    if (mounted) {
      setState(() {
        _baseHistory = results[0] as List<double>;
        _basePrice = results[1] as PriceResult?;
        _loadingBase = false;
      });
    }
  }

  Future<void> _searchBase(String query) async {
    if (query.isEmpty) { setState(() => _baseSearchResults = []); return; }
    setState(() => _searchingBase = true);
    final results = await StockPriceService.searchStocks(query);
    if (mounted) setState(() { _baseSearchResults = results; _searchingBase = false; });
  }

  Future<void> _selectBase(StockSearchResult stock) async {
    setState(() {
      _baseStockResult = stock;
      _baseSearchResults = [];
      _baseSearchCtrl.text = '${stock.name} (${stock.ticker})';
      _loadingBase = true;
    });
    final results = await Future.wait([
      StockPriceService.fetchHistory(stock.ticker, stock.market,
          range: _range, interval: _interval),
      StockPriceService.fetchPrice(stock.ticker, stock.market),
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
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
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
      StockPriceService.fetchHistory(stock.ticker, stock.market,
          range: _range, interval: _interval),
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

  Future<void> _changePeriod(int index) async {
    if (_periodIndex == index) return;
    setState(() => _periodIndex = index);
    final futures = <Future>[];
    // base 재로드
    final baseTicker = widget.basePick?.ticker ?? _baseStockResult?.ticker;
    final baseMarket = widget.basePick?.market ?? _baseStockResult?.market;
    if (baseTicker != null) {
      setState(() => _loadingBase = true);
      futures.add(
        StockPriceService.fetchHistory(baseTicker, baseMarket!,
                range: _range, interval: _interval)
            .then((h) { if (mounted) setState(() { _baseHistory = h; _loadingBase = false; }); }),
      );
    }
    // compare 재로드
    if (_compareStock != null) {
      setState(() => _loadingCompare = true);
      futures.add(
        StockPriceService.fetchHistory(_compareStock!.ticker, _compareStock!.market,
                range: _range, interval: _interval)
            .then((h) { if (mounted) setState(() { _compareHistory = h; _loadingCompare = false; }); }),
      );
    }
    await Future.wait(futures);
  }

  List<double> _toPercent(List<double> prices) {
    if (prices.isEmpty) return [];
    final base = prices.first;
    if (base == 0) return prices.map((_) => 0.0).toList();
    return prices.map((p) => ((p - base) / base) * 100).toList();
  }

  String get _baseName => widget.basePick?.name ?? _baseStockResult?.name ?? '—';
  String get _baseTicker => widget.basePick?.ticker ?? _baseStockResult?.ticker ?? '—';
  bool get _isStandalone => widget.basePick == null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final basePct = _toPercent(_baseHistory);
    final comparePct = _toPercent(_compareHistory);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _isStandalone
          ? null
          : AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios, color: cs.onSurface, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text('종목 비교',
                  style: GoogleFonts.inter(
                      color: cs.onSurface, fontWeight: FontWeight.w700)),
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, _isStandalone ? 20 : 0, 20, 100),
        children: [
          // ── 기준 종목 검색 (standalone) ──
          if (_isStandalone) ...[
            _buildSearchField(
              controller: _baseSearchCtrl,
              label: '기준 종목',
              hint: '기준 종목명 또는 티커 검색...',
              searching: _searchingBase,
              onChanged: _searchBase,
              onClear: () {
                _baseSearchCtrl.clear();
                setState(() {
                  _baseStockResult = null;
                  _baseHistory = [];
                  _basePrice = null;
                  _baseSearchResults = [];
                });
              },
              cs: cs,
            ),
            if (_baseSearchResults.isNotEmpty)
              _buildResultsList(_baseSearchResults, _selectBase, cs),
            const SizedBox(height: 12),
          ],

          // ── 비교 종목 검색 ──
          _buildSearchField(
            controller: _searchCtrl,
            label: '비교할 종목',
            hint: '비교 종목명 또는 티커 검색...',
            searching: _searching,
            onChanged: _search,
            onClear: () {
              _searchCtrl.clear();
              setState(() {
                _compareStock = null;
                _compareHistory = [];
                _comparePrice = null;
                _searchResults = [];
              });
            },
            cs: cs,
          ),
          if (_searchResults.isNotEmpty)
            _buildResultsList(_searchResults, _selectCompare, cs),
          const SizedBox(height: 20),

          // ── 가격 요약 ──
          _buildPriceSummary(cs),
          const SizedBox(height: 12),

          // ── 수익률 수치 ──
          _buildReturnSummary(basePct, comparePct, cs),
          const SizedBox(height: 16),

          // ── 기간 선택 ──
          _buildPeriodSelector(cs),
          const SizedBox(height: 12),

          // ── 비교 차트 ──
          _buildChart(basePct, comparePct, cs),
          const SizedBox(height: 16),

          // ── 범례 ──
          _buildLegend(cs),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool searching,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
    required ColorScheme cs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: GoogleFonts.inter(color: cs.onSurface, fontSize: 14),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14),
            filled: true,
            fillColor: cs.surface,
            prefixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF4ADE80))))
                : Icon(Icons.search,
                    color: cs.onSurface.withValues(alpha: 0.4), size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        color: cs.onSurface.withValues(alpha: 0.4), size: 18),
                    onPressed: onClear)
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

  Widget _buildResultsList(List<StockSearchResult> results,
      void Function(StockSearchResult) onSelect, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: results.take(5).map((r) {
          return ListTile(
            dense: true,
            title: Text(r.name,
                style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13)),
            subtitle: Text('${r.ticker} · ${r.exchange}',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.4), fontSize: 11)),
            onTap: () => onSelect(r),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodSelector(ColorScheme cs) {
    return Row(
      children: List.generate(_comparePeriods.length, (i) {
        final selected = _periodIndex == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => _changePeriod(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF4ADE80)
                    : cs.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF4ADE80)
                      : cs.onSurface.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                _comparePeriods[i].$1,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: selected ? Colors.black : cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildReturnSummary(
      List<double> basePct, List<double> comparePct, ColorScheme cs) {
    final hasBase = widget.basePick != null || _baseStockResult != null;
    if (!hasBase && _compareStock == null) return const SizedBox.shrink();

    Widget returnBadge(String label, List<double> pct, Color accent, bool loading) {
      if (loading) {
        return const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF4ADE80)));
      }
      if (pct.isEmpty) return const SizedBox.shrink();
      final ret = pct.last;
      final isUp = ret >= 0;
      final color = isUp ? const Color(0xFF4ADE80) : Colors.redAccent;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.54), fontSize: 12)),
        const SizedBox(width: 6),
        Text('${isUp ? '+' : ''}${ret.toStringAsFixed(2)}%',
            style: GoogleFonts.inter(
                color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ]);
    }

    return Row(
      children: [
        if (hasBase)
          returnBadge(_baseName, basePct, const Color(0xFF4ADE80), _loadingBase),
        if (hasBase && _compareStock != null) const SizedBox(width: 20),
        if (_compareStock != null)
          returnBadge(_compareStock!.name, comparePct, Colors.orangeAccent, _loadingCompare),
      ],
    );
  }

  Widget _buildPriceSummary(ColorScheme cs) {
    final hasBase = widget.basePick != null || _baseStockResult != null;
    return Row(
      children: [
        Expanded(
          child: hasBase
              ? _buildPriceCard(cs, _baseName, _baseTicker, _basePrice,
                  const Color(0xFF4ADE80), _loadingBase)
              : _emptyCard(cs, '기준 종목\n선택하세요'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compareStock == null
              ? _emptyCard(cs, '비교 종목\n선택하세요')
              : _buildPriceCard(cs, _compareStock!.name, _compareStock!.ticker,
                  _comparePrice, Colors.orangeAccent, _loadingCompare),
        ),
      ],
    );
  }

  Widget _emptyCard(ColorScheme cs, String text) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3), fontSize: 12)),
      ),
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
                width: 8, height: 8,
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(ticker,
                    style: GoogleFonts.robotoMono(
                        color: accentColor, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.7), fontSize: 11)),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)))
          else if (price != null) ...[
            Text(price.formattedPrice,
                style: GoogleFonts.inter(
                    color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 15)),
            Text(price.formattedChange,
                style: GoogleFonts.inter(
                    color: price.isUp ? const Color(0xFF4ADE80) : Colors.redAccent,
                    fontSize: 11)),
          ] else
            Text('—',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildChart(List<double> basePct, List<double> comparePct, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text('1개월 수익률 비교 (%)',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.54),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          if (_loadingBase)
            const SizedBox(
              height: 200,
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4ADE80))),
            )
          else if (basePct.isEmpty)
            SizedBox(
              height: 200,
              child: Center(
                child: Text('기준 종목을 선택하세요',
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.24), fontSize: 13)),
              ),
            )
          else
            CustomPaint(
              size: const Size(double.infinity, 200),
              painter: _CompareLinePainter(
                basePct: basePct,
                comparePct: (_compareStock != null && !_loadingCompare && comparePct.isNotEmpty)
                    ? comparePct
                    : null,
                labelColor: cs.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend(ColorScheme cs) {
    final hasBase = widget.basePick != null || _baseStockResult != null;
    return Row(
      children: [
        if (hasBase) _legendDot(const Color(0xFF4ADE80), _baseName, cs),
        if (hasBase && _compareStock != null) const SizedBox(width: 16),
        if (_compareStock != null)
          _legendDot(Colors.orangeAccent, _compareStock!.name, cs),
      ],
    );
  }

  Widget _legendDot(Color color, String label, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.7), fontSize: 12)),
      ],
    );
  }
}

class _CompareLinePainter extends CustomPainter {
  final List<double> basePct;
  final List<double>? comparePct;
  final Color labelColor;

  const _CompareLinePainter(
      {required this.basePct, this.comparePct, required this.labelColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (basePct.isEmpty) return;

    const yAxisW = 46.0;
    const xLabelH = 18.0;
    final chartH = size.height - xLabelH;
    final chartW = size.width - yAxisW;

    final allValues = [...basePct, ...?comparePct];
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

    // Grid
    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      canvas.drawLine(Offset(yAxisW, chartH * i / 4),
          Offset(size.width, chartH * i / 4), gridPaint);
    }
    // Zero line
    if (minY < 0 && maxY > 0) {
      final zeroY = toY(0);
      canvas.drawLine(
        Offset(yAxisW, zeroY), Offset(size.width, zeroY),
        Paint()
          ..color = labelColor.withValues(alpha: 0.2)
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
        if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
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

    final axisStyle = TextStyle(
      color: labelColor.withValues(alpha: 0.35),
      fontSize: 8,
      fontFamily: 'RobotoMono',
    );

    // Y-axis labels
    for (int i = 0; i <= 3; i++) {
      final v = minY + yRange * (1 - i / 4);
      final sign = v >= 0 ? '+' : '';
      final tp = TextPainter(
        text: TextSpan(text: '$sign${v.toStringAsFixed(1)}%', style: axisStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final y = (chartH * i / 4 - tp.height / 2).clamp(0.0, chartH - tp.height);
      tp.paint(canvas, Offset(0, y));
    }

    // X-axis labels
    final n = basePct.length;
    const labelCount = 4;
    for (int i = 0; i < labelCount; i++) {
      final idx = ((n - 1) * i / (labelCount - 1)).round().clamp(0, n - 1);
      final daysAgo = n - 1 - idx;
      final label = daysAgo == 0
          ? '오늘'
          : DateFormat('MM/dd')
              .format(DateTime.now().subtract(Duration(days: daysAgo)));
      final tp = TextPainter(
        text: TextSpan(text: label, style: axisStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final x = (toX(idx, n) - tp.width / 2).clamp(yAxisW, size.width - tp.width);
      tp.paint(canvas, Offset(x, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(_CompareLinePainter old) =>
      old.basePct != basePct ||
      old.comparePct != comparePct ||
      old.labelColor != labelColor;
}
