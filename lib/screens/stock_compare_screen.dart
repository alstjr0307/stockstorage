import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/stock_pick.dart';
import '../services/stock_price_service.dart';

class StockCompareScreen extends StatefulWidget {
  final StockPick? basePick; // null = standalone tab
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

// 기준 + 비교 슬롯 색상
const _slotColors = [
  Color(0xFF4ADE80), // base (green)
  Color(0xFFFB923C), // compare 0 (orange)
  Color(0xFF60A5FA), // compare 1 (blue)
  Color(0xFFE879F9), // compare 2 (pink)
];

class _StockCompareScreenState extends State<StockCompareScreen> {
  // 기간 선택
  int _periodIndex = 0;
  bool _customSelected = false;
  int _customAmount = 3;
  String _customUnit = '개월';

  // Base stock
  List<double> _baseHistory = [];
  PriceResult? _basePrice;
  bool _loadingBase = false;

  // Base search (standalone)
  final _baseSearchCtrl = TextEditingController();
  StockSearchResult? _baseStockResult;
  List<StockSearchResult> _baseSearchResults = [];
  bool _searchingBase = false;

  // Compare slots (최대 3개, 기본 1개)
  static const _maxSlots = 3;
  int _slotCount = 1;
  final List<TextEditingController> _compareCtrl = [];
  final List<StockSearchResult?> _compareStock = [];
  final List<List<double>> _compareHistory = [];
  final List<PriceResult?> _comparePrice = [];
  final List<bool> _compareLoading = [];
  final List<List<StockSearchResult>> _compareResults = [];
  final List<bool> _compareSearching = [];

  String get _range => _comparePeriods[_periodIndex].$2;
  String get _interval => _comparePeriods[_periodIndex].$3;

  @override
  void initState() {
    super.initState();
    _initSlots(1);
    if (widget.basePick != null) {
      _loadingBase = true;
      _loadBase();
    }
  }

  /// 리스트를 count 개수만큼 확장 (이미 있는 건 건드리지 않음)
  void _initSlots(int count) {
    for (int i = _compareCtrl.length; i < count; i++) {
      _compareCtrl.add(TextEditingController());
      _compareStock.add(null);
      _compareHistory.add([]);
      _comparePrice.add(null);
      _compareLoading.add(false);
      _compareResults.add([]);
      _compareSearching.add(false);
    }
  }

  void _addSlot() {
    if (_slotCount >= _maxSlots) return;
    _initSlots(_slotCount + 1);
    setState(() => _slotCount++);
  }

  void _removeSlot(int idx) {
    if (_slotCount <= 1) return;
    // 뒤 슬롯을 앞으로 당기기
    setState(() {
      for (int i = idx; i < _slotCount - 1; i++) {
        _compareCtrl[i].text = _compareCtrl[i + 1].text;
        _compareStock[i] = _compareStock[i + 1];
        _compareHistory[i] = List.of(_compareHistory[i + 1]);
        _comparePrice[i] = _comparePrice[i + 1];
        _compareLoading[i] = _compareLoading[i + 1];
        _compareResults[i] = List.of(_compareResults[i + 1]);
        _compareSearching[i] = _compareSearching[i + 1];
      }
      final last = _slotCount - 1;
      _compareCtrl[last].clear();
      _compareStock[last] = null;
      _compareHistory[last] = [];
      _comparePrice[last] = null;
      _compareLoading[last] = false;
      _compareResults[last] = [];
      _compareSearching[last] = false;
      _slotCount--;
    });
  }

  @override
  void dispose() {
    _baseSearchCtrl.dispose();
    for (final c in _compareCtrl) {
      c.dispose();
    }
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
    if (query.isEmpty) {
      setState(() => _baseSearchResults = []);
      return;
    }
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

  Future<void> _searchCompare(int idx, String query) async {
    if (query.isEmpty) {
      setState(() => _compareResults[idx] = []);
      return;
    }
    setState(() => _compareSearching[idx] = true);
    final results = await StockPriceService.searchStocks(query);
    if (mounted) setState(() { _compareResults[idx] = results; _compareSearching[idx] = false; });
  }

  Future<void> _selectCompare(int idx, StockSearchResult stock) async {
    setState(() {
      _compareStock[idx] = stock;
      _compareResults[idx] = [];
      _compareCtrl[idx].text = '${stock.name} (${stock.ticker})';
      _compareLoading[idx] = true;
    });
    List<double> history;
    PriceResult? price;
    if (_customSelected) {
      final now = DateTime.now();
      final start = now.subtract(Duration(days: _toDays(_customAmount, _customUnit)));
      final r = await Future.wait([
        StockPriceService.fetchHistoryByDates(stock.ticker, stock.market, start, now),
        StockPriceService.fetchPrice(stock.ticker, stock.market),
      ]);
      history = r[0] as List<double>;
      price = r[1] as PriceResult?;
    } else {
      final r = await Future.wait([
        StockPriceService.fetchHistory(stock.ticker, stock.market,
            range: _range, interval: _interval),
        StockPriceService.fetchPrice(stock.ticker, stock.market),
      ]);
      history = r[0] as List<double>;
      price = r[1] as PriceResult?;
    }
    if (mounted) {
      setState(() {
        _compareHistory[idx] = history;
        _comparePrice[idx] = price;
        _compareLoading[idx] = false;
      });
    }
  }

  Future<void> _changePeriod(int index) async {
    if (_periodIndex == index && !_customSelected) return;
    setState(() { _periodIndex = index; _customSelected = false; });
    final futures = <Future>[];
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
    for (int i = 0; i < _slotCount; i++) {
      final stock = _compareStock[i];
      if (stock != null) {
        setState(() => _compareLoading[i] = true);
        final ci = i;
        futures.add(
          StockPriceService.fetchHistory(stock.ticker, stock.market,
                  range: _range, interval: _interval)
              .then((h) { if (mounted) setState(() { _compareHistory[ci] = h; _compareLoading[ci] = false; }); }),
        );
      }
    }
    await Future.wait(futures);
  }

  int _toDays(int amount, String unit) {
    switch (unit) {
      case '일': return amount;
      case '주': return amount * 7;
      case '개월': return amount * 30;
      case '년': return amount * 365;
      default: return amount * 30;
    }
  }

  int _maxAmount(String unit) {
    switch (unit) {
      case '일': return 365;
      case '주': return 52;
      case '개월': return 60;
      case '년': return 20;
      default: return 60;
    }
  }

  Future<void> _showCustomDatePicker() async {
    int tempAmount = _customAmount;
    String tempUnit = _customUnit;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('기간 직접 입력',
                style: GoogleFonts.inter(
                    color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepBtn(Icons.remove, () {
                      if (tempAmount > 1) setLocal(() => tempAmount--);
                    }, cs),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 52,
                      child: Text('$tempAmount',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: const Color(0xFF4ADE80),
                              fontSize: 28,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    _stepBtn(Icons.add, () {
                      if (tempAmount < _maxAmount(tempUnit)) setLocal(() => tempAmount++);
                    }, cs),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: ['일', '주', '개월', '년'].map((u) {
                    final sel = tempUnit == u;
                    return GestureDetector(
                      onTap: () => setLocal(() {
                        tempUnit = u;
                        final mx = _maxAmount(u);
                        if (tempAmount > mx) tempAmount = mx;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF4ADE80)
                              : cs.onSurface.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(u,
                            style: GoogleFonts.inter(
                              color: sel ? Colors.black : cs.onSurface.withValues(alpha: 0.6),
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                              fontSize: 13,
                            )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Text('최근 $tempAmount$tempUnit 기준',
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.4), fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('취소',
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.5))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('적용',
                    style: GoogleFonts.inter(
                        color: const Color(0xFF4ADE80), fontWeight: FontWeight.w700)),
              ),
            ],
          );
        });
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _customSelected = true;
      _customAmount = tempAmount;
      _customUnit = tempUnit;
    });

    final now = DateTime.now();
    final start = now.subtract(Duration(days: _toDays(tempAmount, tempUnit)));
    final futures = <Future>[];
    final baseTicker = widget.basePick?.ticker ?? _baseStockResult?.ticker;
    final baseMarket = widget.basePick?.market ?? _baseStockResult?.market;
    if (baseTicker != null) {
      setState(() => _loadingBase = true);
      futures.add(
        StockPriceService.fetchHistoryByDates(baseTicker, baseMarket!, start, now)
            .then((h) { if (mounted) setState(() { _baseHistory = h; _loadingBase = false; }); }),
      );
    }
    for (int i = 0; i < _slotCount; i++) {
      final stock = _compareStock[i];
      if (stock != null) {
        setState(() => _compareLoading[i] = true);
        final ci = i;
        futures.add(
          StockPriceService.fetchHistoryByDates(stock.ticker, stock.market, start, now)
              .then((h) { if (mounted) setState(() { _compareHistory[ci] = h; _compareLoading[ci] = false; }); }),
        );
      }
    }
    await Future.wait(futures);
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.07), shape: BoxShape.circle),
        child: Icon(icon, color: cs.onSurface.withValues(alpha: 0.7), size: 18),
      ),
    );
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

  void _shareCompare() {
    final basePct = _toPercent(_baseHistory);
    if (basePct.isEmpty) return;
    final period = _customSelected
        ? '최근 $_customAmount$_customUnit'
        : _comparePeriods[_periodIndex].$1;
    String sign(double v) => v >= 0 ? '+' : '';
    final buf = StringBuffer()
      ..writeln('📊 주식저장소 수익률 비교')
      ..writeln('━━━━━━━━━━━━━━━━━━')
      ..writeln('기간: $period')
      ..writeln('━━━━━━━━━━━━━━━━━━')
      ..writeln('$_baseName ($_baseTicker)  ${sign(basePct.last)}${basePct.last.toStringAsFixed(2)}%');
    for (int i = 0; i < _slotCount; i++) {
      final stock = _compareStock[i];
      if (stock == null) continue;
      final pct = _toPercent(_compareHistory[i]);
      if (pct.isEmpty) continue;
      buf.writeln('${stock.name} (${stock.ticker})  ${sign(pct.last)}${pct.last.toStringAsFixed(2)}%');
    }
    buf
      ..writeln('━━━━━━━━━━━━━━━━━━')
      ..write('주식저장소 앱에서 더 비교해보세요 📈');
    Share.share(buf.toString());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final basePct = _toPercent(_baseHistory);
    final comparePcts = List.generate(_slotCount, (i) =>
        (_compareStock[i] != null && !_compareLoading[i])
            ? _toPercent(_compareHistory[i])
            : <double>[]);

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

          // ── 비교 종목 슬롯 ──
          ...List.generate(_slotCount, (i) => _buildCompareSlot(i, cs)),

          // ── 종목 추가 버튼 ──
          if (_slotCount < _maxSlots)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: _addSlot,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF4ADE80).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, color: Color(0xFF4ADE80), size: 16),
                      const SizedBox(width: 6),
                      Text('종목 추가 (${_slotCount + 1}/4)',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF4ADE80),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // ── 가격 요약 ──
          _buildPriceSummary(cs),
          const SizedBox(height: 12),

          // ── 수익률 수치 ──
          _buildReturnSummary(basePct, comparePcts, cs),
          const SizedBox(height: 16),

          // ── 기간 선택 ──
          _buildPeriodSelector(cs),
          const SizedBox(height: 8),
          _buildCustomDateButton(cs),
          const SizedBox(height: 12),

          // ── 비교 차트 ──
          _buildChart(basePct, comparePcts, cs),
          const SizedBox(height: 16),

          // ── 범례 ──
          _buildLegend(cs),
          const SizedBox(height: 20),

          // ── 공유 버튼 ──
          if (basePct.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _shareCompare,
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('친구에게 공유하기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4ADE80),
                  side: const BorderSide(color: Color(0xFF4ADE80), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompareSlot(int idx, ColorScheme cs) {
    return Column(
      children: [
        _buildSearchField(
          controller: _compareCtrl[idx],
          label: _slotCount > 1 ? '비교 종목 ${idx + 1}' : '비교할 종목',
          hint: '종목명 또는 티커 검색...',
          searching: _compareSearching[idx],
          onChanged: (q) => _searchCompare(idx, q),
          onClear: () {
            _compareCtrl[idx].clear();
            setState(() {
              _compareStock[idx] = null;
              _compareHistory[idx] = [];
              _comparePrice[idx] = null;
              _compareResults[idx] = [];
            });
          },
          cs: cs,
          accentColor: _slotColors[idx + 1],
          showRemove: _slotCount > 1,
          onRemove: () => _removeSlot(idx),
        ),
        if (_compareResults[idx].isNotEmpty)
          _buildResultsList(
              _compareResults[idx], (s) => _selectCompare(idx, s), cs),
        const SizedBox(height: 12),
      ],
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
    Color? accentColor,
    bool showRemove = false,
    VoidCallback? onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (accentColor != null) ...[
              Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: accentColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            if (showRemove) ...[
              const Spacer(),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close,
                    size: 16, color: cs.onSurface.withValues(alpha: 0.35)),
              ),
            ],
          ],
        ),
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
                        width: 16,
                        height: 16,
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

  Widget _buildCustomDateButton(ColorScheme cs) {
    final label = _customSelected
        ? '최근 $_customAmount$_customUnit'
        : '기간 직접 입력';
    return GestureDetector(
      onTap: _showCustomDatePicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _customSelected
              ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
              : cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _customSelected
                ? const Color(0xFF4ADE80)
                : cs.onSurface.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.date_range_rounded,
                size: 14,
                color: _customSelected
                    ? const Color(0xFF4ADE80)
                    : cs.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                  color: _customSelected
                      ? const Color(0xFF4ADE80)
                      : cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight:
                      _customSelected ? FontWeight.w700 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(ColorScheme cs) {
    return Row(
      children: List.generate(_comparePeriods.length, (i) {
        final selected = !_customSelected && _periodIndex == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => _changePeriod(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF4ADE80) : cs.surface,
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
                  color: selected
                      ? Colors.black
                      : cs.onSurface.withValues(alpha: 0.6),
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
      List<double> basePct, List<List<double>> comparePcts, ColorScheme cs) {
    final hasBase = widget.basePick != null || _baseStockResult != null;
    final hasAny =
        hasBase || comparePcts.any((p) => p.isNotEmpty);
    if (!hasAny) return const SizedBox.shrink();

    Widget badge(
        String label, List<double> pct, Color accent, bool loading) {
      if (loading) {
        return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Color(0xFF4ADE80)));
      }
      if (pct.isEmpty) return const SizedBox.shrink();
      final ret = pct.last;
      final isUp = ret >= 0;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: accent, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.54),
                fontSize: 12)),
        const SizedBox(width: 6),
        Text('${isUp ? '+' : ''}${ret.toStringAsFixed(2)}%',
            style: GoogleFonts.inter(
                color: isUp
                    ? const Color(0xFF4ADE80)
                    : Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ]);
    }

    final items = <Widget>[];
    if (hasBase) {
      items.add(badge(_baseName, basePct, _slotColors[0], _loadingBase));
    }
    for (int i = 0; i < _slotCount; i++) {
      if (_compareStock[i] != null) {
        items.add(badge(_compareStock[i]!.name, comparePcts[i],
            _slotColors[i + 1], _compareLoading[i]));
      }
    }
    return Wrap(spacing: 12, runSpacing: 6, children: items);
  }

  Widget _buildPriceSummary(ColorScheme cs) {
    final hasBase = widget.basePick != null || _baseStockResult != null;
    final cards = <Widget>[
      hasBase
          ? _buildPriceCard(cs, _baseName, _baseTicker, _basePrice,
              _slotColors[0], _loadingBase)
          : _emptyCard(cs, '기준 종목\n선택하세요'),
      ...List.generate(
        _slotCount,
        (i) => _compareStock[i] == null
            ? _emptyCard(cs, '비교 종목\n선택하세요')
            : _buildPriceCard(
                cs,
                _compareStock[i]!.name,
                _compareStock[i]!.ticker,
                _comparePrice[i],
                _slotColors[i + 1],
                _compareLoading[i]),
      ),
    ];

    // 2열로 배치
    final rows = <Widget>[];
    for (int i = 0; i < cards.length; i += 2) {
      final pair = cards.sublist(i, (i + 2).clamp(0, cards.length));
      rows.add(Row(children: [
        Expanded(child: pair[0]),
        if (pair.length > 1) ...[
          const SizedBox(width: 10),
          Expanded(child: pair[1]),
        ],
      ]));
      if (i + 2 < cards.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
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
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 12)),
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
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: accentColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(ticker,
                  style: GoogleFonts.robotoMono(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.7),
                  fontSize: 11)),
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
      List<double> basePct, List<List<double>> comparePcts, ColorScheme cs) {
    // 실제로 데이터 있는 compare만 추출 (색상 대응)
    final activeCompare = <(List<double>, Color)>[];
    for (int i = 0; i < _slotCount; i++) {
      if (comparePcts[i].isNotEmpty) {
        activeCompare.add((comparePcts[i], _slotColors[i + 1]));
      }
    }

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
            padding: const EdgeInsets.only(left: 8, bottom: 10, right: 4),
            child: Row(
              children: [
                Text(
                  _customSelected
                      ? '최근 $_customAmount$_customUnit 수익률 비교 (%)'
                      : '${_comparePeriods[_periodIndex].$1} 수익률 비교 (%)',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.54),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => _FullscreenCompareChartPage(
                        basePct: basePct,
                        comparePcts: activeCompare.map((e) => e.$1).toList(),
                        compareColors: activeCompare.map((e) => e.$2).toList(),
                        labelColor: cs.onSurface,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.fullscreen,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
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
                        color: cs.onSurface.withValues(alpha: 0.24),
                        fontSize: 13)),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(double.infinity, 200),
                    painter: _CompareLinePainter(
                      basePct: basePct,
                      comparePcts: activeCompare.map((e) => e.$1).toList(),
                      compareColors: activeCompare.map((e) => e.$2).toList(),
                      labelColor: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend(ColorScheme cs) {
    final hasBase = widget.basePick != null || _baseStockResult != null;
    final dots = <Widget>[];
    if (hasBase) dots.add(_legendDot(_slotColors[0], _baseName, cs));
    for (int i = 0; i < _slotCount; i++) {
      if (_compareStock[i] != null) {
        dots.add(
            _legendDot(_slotColors[i + 1], _compareStock[i]!.name, cs));
      }
    }
    return Wrap(spacing: 12, runSpacing: 6, children: dots);
  }

  Widget _legendDot(Color color, String label, ColorScheme cs) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.7), fontSize: 12)),
    ]);
  }
}

class _CompareLinePainter extends CustomPainter {
  final List<double> basePct;
  final List<List<double>> comparePcts;
  final List<Color> compareColors;
  final Color labelColor;

  const _CompareLinePainter({
    required this.basePct,
    required this.comparePcts,
    required this.compareColors,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (basePct.isEmpty) return;

    const yAxisW = 46.0;
    const xLabelH = 18.0;
    final chartH = size.height - xLabelH;
    final chartW = size.width - yAxisW;

    final allValues = [...basePct, ...comparePcts.expand((p) => p)];
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
        Offset(yAxisW, zeroY),
        Offset(size.width, zeroY),
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
    for (int i = 0; i < comparePcts.length; i++) {
      drawLine(comparePcts[i], compareColors[i]);
    }

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
      final y =
          (chartH * i / 4 - tp.height / 2).clamp(0.0, chartH - tp.height);
      tp.paint(canvas, Offset(0, y));
    }

    // X-axis labels
    final n = basePct.length;
    const labelCount = 4;
    for (int i = 0; i < labelCount; i++) {
      final idx =
          ((n - 1) * i / (labelCount - 1)).round().clamp(0, n - 1);
      final daysAgo = n - 1 - idx;
      final label = daysAgo == 0
          ? '오늘'
          : DateFormat('MM/dd')
              .format(DateTime.now().subtract(Duration(days: daysAgo)));
      final tp = TextPainter(
        text: TextSpan(text: label, style: axisStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final x =
          (toX(idx, n) - tp.width / 2).clamp(yAxisW, size.width - tp.width);
      tp.paint(canvas, Offset(x, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(_CompareLinePainter old) =>
      old.basePct != basePct ||
      old.comparePcts != comparePcts ||
      old.labelColor != labelColor;
}

// ── 가로 전체화면 비교 차트 페이지 ────────────────────────────────────────
class _FullscreenCompareChartPage extends StatefulWidget {
  final List<double> basePct;
  final List<List<double>> comparePcts;
  final List<Color> compareColors;
  final Color labelColor;

  const _FullscreenCompareChartPage({
    required this.basePct,
    required this.comparePcts,
    required this.compareColors,
    required this.labelColor,
  });

  @override
  State<_FullscreenCompareChartPage> createState() =>
      _FullscreenCompareChartPageState();
}

class _FullscreenCompareChartPageState
    extends State<_FullscreenCompareChartPage> {
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            CustomPaint(
              size: Size(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).size.height,
              ),
              painter: _CompareLinePainter(
                basePct: widget.basePct,
                comparePcts: widget.comparePcts,
                compareColors: widget.compareColors,
                labelColor: widget.labelColor,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(Icons.fullscreen_exit,
                    color: cs.onSurface.withValues(alpha: 0.6)),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
