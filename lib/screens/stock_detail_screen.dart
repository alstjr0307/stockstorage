import 'dart:math';
import 'dart:ui' as ui show TextDirection;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stockstorage/screens/chart_visible_range.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/comment.dart';
import '../models/stock_pick.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';

typedef _OHLC = ({DateTime date, double open, double high, double low, double close});

enum _Period {
  day1('1일봉', '1d', '1mo'),
  week('주봉', '1wk', '6mo'),
  month('월봉', '1mo', '2y');

  const _Period(this.label, this.interval, this.range);
  final String label;
  final String interval;
  final String range;
}

class StockDetailScreen extends StatefulWidget {
  final StockPick pick;
  const StockDetailScreen({super.key, required this.pick});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  PriceResult? _livePrice;
  bool _loadingPrice = true;
  List<_OHLC> _candles = [];
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

  final _commentController = TextEditingController();
  final _memoController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _submitting = false;
  bool _memoSaving = false;
  bool _memoChanged = false;
  bool _showComments = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    if (Random().nextBool()) {
      AdService.instance.showRewardedInterstitialIfReady();
    }
    AdService.instance.loadRewardedInterstitial();
    _fetchPrice();
    _fetchChart();
    _loadMemo();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadMemo() async {
    final user = _currentUser;
    if (user == null) return;
    final text = await _firestoreService.getMemo(user.uid, widget.pick.id);
    if (mounted && text != null) {
      _memoController.text = text;
    }
  }

  Future<void> _saveMemo() async {
    final user = _currentUser;
    if (user == null) return;
    setState(() => _memoSaving = true);
    await _firestoreService.saveMemo(
        user.uid, widget.pick.id, _memoController.text.trim());
    if (mounted) {
      setState(() {
        _memoSaving = false;
        _memoChanged = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('메모가 저장되었습니다',
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: const Color(0xFF4ADE80).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchPrice() async {
    final result = await StockPriceService.fetchPrice(
      widget.pick.ticker,
      widget.pick.market,
    );
    if (mounted) setState(() { _livePrice = result; _loadingPrice = false; });
  }

  Future<void> _fetchChart() async {
    final data = await StockPriceService.fetchOHLC(
      widget.pick.ticker,
      widget.pick.market,
      interval: _selectedPeriod.interval,
      range: _selectedPeriod.range,
    );
    if (mounted) setState(() {
      _candles = data;
      _loadingChart = false;
      _visibleRange = ChartVisibleRange(0, data.length.toDouble());
    });
  }

  void _selectPeriod(_Period period) {
    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
      _loadingChart = true;
      _touchedIndex = null;
      _visibleRange = const ChartVisibleRange(0, 0);
    });
    _fetchChart();
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

  void _shareStock() {
    final pick = widget.pick;
    final returnRate = pick.returnRate;
    final isPositive = returnRate >= 0;
    final text = '📈 [StockStorage] ${pick.name} (${pick.ticker})\n\n'
        '매수가: ${_formatPrice(pick.buyPrice, pick.market)}\n'
        '목표가: ${_formatPrice(pick.targetPrice, pick.market)}\n'
        '예상 수익률: ${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%\n'
        '투자 기간: ${pick.category}\n\n'
        '매수 근거:\n${pick.reason}\n\n'
        'StockStorage 앱에서 더 많은 매수 관심종목을 확인하세요!';
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final formatter = NumberFormat('#,###');

    final livePrice = _livePrice?.price;
    final returnRate = livePrice != null
        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
        : pick.returnRate;
    final isPositive = returnRate >= 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          pick.ticker,
          style: GoogleFonts.robotoMono(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white54, size: 20),
            onPressed: _shareStock,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white38, size: 20),
            onPressed: () {
              setState(() { _loadingPrice = true; _loadingChart = true; });
              _fetchPrice();
              _fetchChart();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // 종목 헤더
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pick.name,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _marketBadge(pick.market),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('yyyy.MM.dd HH:mm').format(pick.createdAt),
                            style: GoogleFonts.inter(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                            : Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isPositive
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                              : Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                        style: GoogleFonts.inter(
                          color: isPositive
                              ? const Color(0xFF4ADE80)
                              : Colors.redAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '매수가 대비',
                      style: GoogleFonts.inter(
                          color: Colors.white24, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 실시간 현재가 카드
            _livePriceCard(pick, formatter),
            const SizedBox(height: 12),

            // 1개월 차트
            _chartCard(),

            // 매수가 / 목표가 카드
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _priceItem(
                      '매수가',
                      _formatPrice(pick.buyPrice, pick.market),
                      Colors.white70,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Expanded(
                    child: _priceItem(
                      '목표가',
                      _formatPrice(pick.targetPrice, pick.market),
                      const Color(0xFF4ADE80),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 카테고리
            _sectionLabel('투자 기간'),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(pick.category,
                  style: GoogleFonts.inter(color: Colors.white70)),
            ),
            const SizedBox(height: 20),

            // 매수 근거
            _sectionLabel('매수 근거'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                pick.reason,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 14, height: 1.8),
              ),
            ),
            const SizedBox(height: 24),

            // 투자 메모 섹션
            if (_currentUser != null) ...[
              _memoSection(),
              const SizedBox(height: 24),
            ],

            // 코멘트 섹션
            _commentToggleButton(),
            if (_showComments) ...[
              const SizedBox(height: 10),
              _commentSection(),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
          ),
          _commentInput(),
        ],
      ),
    );
  }

  Widget _chartCard() {
    if (_loadingChart) {
      return Container(
        height: 280,
        margin: const EdgeInsets.only(bottom: 12),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 기간 선택 + 변동률
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
                            : Colors.white12,
                      ),
                    ),
                    child: Text(
                      p.label,
                      style: GoogleFonts.inter(
                        color: _selectedPeriod == p
                            ? const Color(0xFF4ADE80)
                            : Colors.white38,
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
                            _selectedPeriod == _Period.month
                                ? DateFormat('yyyy년 MM월').format(touched.date)
                                : DateFormat('MM월 dd일').format(touched.date),
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
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
                  painter: _StockCandlePainter(
                    candles: dc,
                    touchedIndex: _touchedIndex,
                    formatValue: (v) => _formatPrice(v, widget.pick.market),
                    formatDate: _selectedPeriod == _Period.month
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
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$label ',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10)),
            TextSpan(
                text: _formatPrice(value, widget.pick.market),
                style: GoogleFonts.robotoMono(
                    color: color ?? Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _livePriceCard(StockPick pick, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.show_chart, color: Color(0xFF4ADE80), size: 18),
          const SizedBox(width: 10),
          Text('현재가',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: _loadingPrice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF4ADE80)),
                  )
                : _livePrice == null
                    ? Text('조회 불가',
                        style: GoogleFonts.inter(
                            color: Colors.white24, fontSize: 13))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _livePrice!.formattedPrice,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            _livePrice!.formattedChange,
                            style: GoogleFonts.inter(
                              color: _livePrice!.isUp
                                  ? const Color(0xFF4ADE80)
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _marketBadge(String market) {
    final info = switch (market) {
      'KS' => ('KOSPI', Colors.blueAccent),
      'KQ' => ('KOSDAQ', Colors.purpleAccent),
      _ => ('US', Colors.orangeAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: info.$2.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: info.$2.withValues(alpha: 0.4)),
      ),
      child: Text(info.$1,
          style: GoogleFonts.inter(
              color: info.$2, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  String _formatPrice(double price, String market) {
    final formatter = NumberFormat('#,###');
    if (market == 'US') return '\$${price.toStringAsFixed(2)}';
    return '₩${formatter.format(price.toInt())}';
  }

  Widget _priceItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.inter(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5),
    );
  }

  // ── 투자 메모 ─────────────────────────────────────────────────────────────
  Widget _memoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('내 투자 메모'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _memoChanged
                  ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _memoController,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 14, height: 1.7),
                maxLines: 5,
                minLines: 3,
                onChanged: (_) {
                  if (!_memoChanged) setState(() => _memoChanged = true);
                },
                decoration: InputDecoration(
                  hintText: '이 종목에 대한 나만의 메모를 남겨보세요\n(매수 이유, 목표, 주의사항 등)',
                  hintStyle: GoogleFonts.inter(
                      color: Colors.white24, fontSize: 13, height: 1.6),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              if (_memoChanged)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ADE80),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _memoSaving ? null : _saveMemo,
                      child: _memoSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : Text('저장',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 코멘트 토글 버튼 ─────────────────────────────────────────────────────
  Widget _commentToggleButton() {
    return GestureDetector(
      onTap: () => setState(() => _showComments = !_showComments),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline,
                color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Text(
              '코멘트',
              style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(
              _showComments ? Icons.expand_less : Icons.expand_more,
              color: Colors.white38,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ── 코멘트 목록 ──────────────────────────────────────────────────────────
  Widget _commentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('코멘트'),
        const SizedBox(height: 10),
        StreamBuilder<List<Comment>>(
          stream: _firestoreService.getComments(widget.pick.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 48,
                child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4ADE80)),
                ),
              );
            }
            final comments = snapshot.data ?? [];
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '첫 번째 코멘트를 남겨보세요',
                  style: GoogleFonts.inter(
                      color: Colors.white24, fontSize: 13),
                ),
              );
            }
            return Column(
              children: comments
                  .map((c) => _commentItem(c))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _commentItem(Comment comment) {
    final isOwn = _currentUser?.uid == comment.uid;
    final isAdmin = _currentUser?.uid == AuthService.adminUid;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                comment.displayName,
                style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                timeago.format(comment.createdAt, locale: 'ko'),
                style: GoogleFonts.inter(
                    color: Colors.white24, fontSize: 11),
              ),
              const Spacer(),
              if (isOwn || isAdmin)
                GestureDetector(
                  onTap: () => _firestoreService.deleteComment(
                      widget.pick.id, comment.id),
                  child: const Icon(Icons.close,
                      color: Colors.white24, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.text,
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── 코멘트 입력창 (하단 고정) ────────────────────────────────────────────
  Widget _commentInput() {
    final user = _currentUser;
    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: const Color(0xFF0A0E1A),
        child: Text(
          '로그인 후 코멘트를 남길 수 있습니다',
          style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitComment(user),
              decoration: InputDecoration(
                hintText: '코멘트를 입력하세요...',
                hintStyle:
                    GoogleFonts.inter(color: Colors.white24, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF1A2035),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _submitting ? null : () => _submitComment(user),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.black, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment(User user) async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final nickname = await _firestoreService.getNickname(user.uid)
        ?? user.email?.split('@').first
        ?? '익명';
    await _firestoreService.addComment(
      widget.pick.id,
      Comment(
        id: '',
        uid: user.uid,
        displayName: nickname,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
    if (mounted) {
      _commentController.clear();
      setState(() => _submitting = false);
    }
  }
}

class _StockCandlePainter extends CustomPainter {
  final List<_OHLC> candles;
  final int? touchedIndex;
  final String Function(double) formatValue;
  final String Function(DateTime) formatDate;

  _StockCandlePainter({
    required this.candles,
    required this.touchedIndex,
    required this.formatValue,
    required this.formatDate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const xLabelH = 18.0;
    const yAxisW = 46.0;
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

    double toY(double v) => chartH - ((v - minY) / yRange) * chartH;
    double toX(int i, int n) => yAxisW + chartW * i / n + chartW / n / 2;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(yAxisW, 0, chartW, chartH));

    // 그리드
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
      final color = touchedIndex == i ? Colors.white : baseColor;

      final totalCandleW = chartW / n;
      final bodyW = (totalCandleW * 0.6).clamp(2.0, 10.0);
      final cx = toX(i, n);

      canvas.drawLine(Offset(cx, toY(c.high)), Offset(cx, toY(c.low)),
          Paint()..color = color..strokeWidth = 1);

      final top = toY(isGreen ? c.close : c.open);
      final bottom = toY(isGreen ? c.open : c.close);
      final bodyH = (bottom - top).abs().clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
        Paint()..color = color,
      );
    }

    // 십자선
    if (touchedIndex != null) {
      final cx = toX(touchedIndex!, n);
      canvas.drawLine(Offset(cx, 0), Offset(cx, chartH),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.2)
            ..strokeWidth = 1);
    }

    canvas.restore();

    // Y축 레이블
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
  bool shouldRepaint(_StockCandlePainter old) =>
      old.candles != candles || old.touchedIndex != touchedIndex;
}
