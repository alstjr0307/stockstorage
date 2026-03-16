import 'dart:math';
import 'dart:ui' as ui show TextDirection;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stockstorage/screens/chart_visible_range.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../models/comment.dart';
import '../models/stock_pick.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import 'stock_compare_screen.dart';
import '../services/deep_link_service.dart';

typedef _OHLC = ({
  DateTime date,
  double open,
  double high,
  double low,
  double close,
});

enum _Period {
  min1('분봉', '1m', '1d'),
  day1('일봉', '1d', '2y'),
  week('주봉', '1wk', 'max'),
  month('월봉', '1mo', 'max');

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

class _StockDetailScreenState extends State<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  PriceResult? _livePrice;
  bool _loadingPrice = true;
  FundamentalsResult? _fundamentals;
  List<_OHLC> _candles = [];
  bool _loadingChart = true;
  int _fetchSeq = 0;
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

  final _shareButtonKey = GlobalKey();
  final _commentController = TextEditingController();
  final _memoController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _submitting = false;
  bool _memoSaving = false;
  bool _memoChanged = false;
  bool _showComments = false;
  final Set<String> _deletingCommentIds = {};

  // 투표
  String? _userVote; // 'up', 'down', null
  StockPick? _livePick;

  // 뉴스
  List<StockNews> _news = [];
  bool _loadingNews = true;

  // 종목토론방
  List<DiscussionPost> _discussionPosts = [];
  bool _loadingDiscussion = true;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (Random().nextBool()) {
      AdService.instance.showInterstitialIfReady();
    }
    AdService.instance.loadInterstitial();
    AnalyticsService.instance.logViewStock(
      ticker: widget.pick.ticker,
      name: widget.pick.name,
      market: widget.pick.market,
    );
    _fetchPrice();
    _fetchChart(++_fetchSeq);
    _fetchFundamentals();
    _loadMemo();
    _loadVote();
    _loadNews();
    _loadDiscussion();
    _subscribePick();
  }

  late final _pickSub = _firestoreService.getPickStream(widget.pick.id).listen((
    p,
  ) {
    if (mounted) setState(() => _livePick = p);
  });

  @override
  void dispose() {
    _tabController.dispose();
    _pickSub.cancel();
    _commentController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _subscribePick() {
    _livePick = widget.pick;
    // late field를 접근해 구독 시작 (lazy initialization 트리거)
    _pickSub; // ignore: unnecessary_statements
  }

  Future<void> _loadVote() async {
    final user = _currentUser;
    if (user == null) return;
    final vote = await _firestoreService.getUserVote(user.uid, widget.pick.id);
    if (mounted) setState(() => _userVote = vote);
  }

  Future<void> _loadNews() async {
    final items = await StockPriceService.fetchNews(
      widget.pick.ticker,
      widget.pick.market,
      name: widget.pick.name,
    );
    if (mounted)
      setState(() {
        _news = items;
        _loadingNews = false;
      });
  }

  Future<void> _loadDiscussion() async {
    final posts = await StockPriceService.fetchDiscussionPosts(
      widget.pick.ticker,
      widget.pick.market,
    );
    if (mounted)
      setState(() {
        _discussionPosts = posts;
        _loadingDiscussion = false;
      });
  }

  Future<void> _castVote(String? newVote) async {
    final user = _currentUser;
    if (user == null) return;
    final prev = _userVote;
    setState(() => _userVote = newVote);
    await _firestoreService.setVote(user.uid, widget.pick.id, newVote, prev);
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
      user.uid,
      widget.pick.id,
      _memoController.text.trim(),
    );
    AnalyticsService.instance.logSaveMemo(widget.pick.ticker);
    if (mounted) {
      setState(() {
        _memoSaving = false;
        _memoChanged = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '메모가 저장되었습니다',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF4ADE80).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
    if (mounted)
      setState(() {
        _livePrice = result;
        _loadingPrice = false;
      });
  }

  Future<void> _fetchFundamentals() async {
    // 현재가가 준비된 후 호출되도록 가격 먼저 기다림
    if (_loadingPrice) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 200));
        return _loadingPrice && mounted;
      });
    }
    if (!mounted) return;
    final result = await StockPriceService.fetchFundamentals(
      widget.pick.ticker,
      widget.pick.market,
      currentPrice: _livePrice?.price ?? widget.pick.currentPrice,
    );
    if (mounted) setState(() => _fundamentals = result);
  }

  Future<void> _fetchChart(int seq) async {
    final data = await StockPriceService.fetchOHLC(
      widget.pick.ticker,
      widget.pick.market,
      interval: _selectedPeriod.interval,
      range: _selectedPeriod.range,
    );
    if (mounted && _fetchSeq == seq) {
      setState(() {
        _candles = data;
        _loadingChart = false;
        final defaultView = _selectedPeriod == _Period.day1 ? 120 : data.length;
        final startIdx = (data.length - defaultView).clamp(0, data.length).toDouble();
        _visibleRange = ChartVisibleRange(startIdx, data.length.toDouble());
      });
    }
  }

  void _selectPeriod(_Period period) {
    if (_selectedPeriod == period) return;
    setState(() {
      _selectedPeriod = period;
      _loadingChart = true;
      _touchedIndex = null;
      _visibleRange = const ChartVisibleRange(0, 0);
    });
    _fetchChart(++_fetchSeq);
  }

  void _onTouch(double localX, double chartW) {
    if (_candles.isEmpty) return;

    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    final adjustedX = (localX - yAxisW).clamp(0.0, candleAreaW);

    // Convert screen x to a candle index within the visible range
    final visibleWidth = _visibleRange.width;
    if (visibleWidth <= 0) return;
    final fractionalIndex =
        _visibleRange.start + (adjustedX / candleAreaW) * visibleWidth;

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
    if (_rangeAtScaleStart == null ||
        _focalPointAtScaleStart == null ||
        _candles.isEmpty)
      return;

    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;

    // 1. Calculate new width from zoom
    final newWidth = (_rangeAtScaleStart!.width / d.scale).clamp(
      5.0,
      _candles.length.toDouble(),
    );

    // 2. Find the anchor candle (the one that should stay under the focal point)
    final focalFraction = ((_focalPointAtScaleStart!.dx - yAxisW) / candleAreaW)
        .clamp(0.0, 1.0);
    final anchorCandle =
        _rangeAtScaleStart!.start + focalFraction * _rangeAtScaleStart!.width;

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
    // 현재가 기준 수익률 (현재가 없으면 목표가 기준)
    final liveP = _livePrice?.price;
    final double currentReturn = liveP != null
        ? ((liveP - pick.buyPrice) / pick.buyPrice) * 100
        : pick.returnRate;
    final double targetReturn = pick.returnRate;
    final isLiveUp = currentReturn >= 0;
    final isTargetUp = targetReturn >= 0;
    final divider = '━━━━━━━━━━━━━━━━━━';
    final text =
        '📊 StockStorage 추천 종목\n'
        '$divider\n'
        '${pick.market == 'US' ? '🇺🇸' : '🇰🇷'} ${pick.name}  (${pick.ticker})\n'
        '📂 ${pick.market}\n'
        '$divider\n'
        '💰 매수가: ${_formatPrice(pick.buyPrice, pick.market)}\n'
        '🎯 목표가: ${_formatPrice(pick.targetPrice, pick.market)}\n'
        '${isTargetUp ? '📈' : '📉'} 목표 수익률: ${isTargetUp ? '+' : ''}${targetReturn.toStringAsFixed(1)}%\n'
        '${liveP != null ? '${isLiveUp ? '🟢' : '🔴'} 현재 수익률: ${isLiveUp ? '+' : ''}${currentReturn.toStringAsFixed(1)}%\n' : ''}'
        '$divider\n'
        '📝 매수 근거:\n${pick.reason}\n'
        '$divider\n'
        'StockStorage 앱에서 더 많은 종목을 확인하세요! 🚀\n'
        '👉 ${DeepLinkService.pickUrl(pick)}';
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromLTWH(0, 0, 100, 100);
    Share.share(text, sharePositionOrigin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final formatter = NumberFormat('#,###');
    final cs = Theme.of(context).colorScheme;

    final livePrice = _livePrice?.price;
    final returnRate = livePrice != null
        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
        : pick.returnRate;
    final isPositive = returnRate >= 0;
    final isKorean = pick.market == 'KS' || pick.market == 'KQ';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          pick.ticker,
          style: GoogleFonts.robotoMono(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StockCompareScreen(basePick: widget.pick),
              ),
            ),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.compare_arrows, color: Color(0xFF4ADE80), size: 15),
                  const SizedBox(width: 4),
                  Text(
                    '종목비교',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4ADE80),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: _shareButtonKey,
            icon: Icon(Icons.share_outlined, color: cs.onSurface.withValues(alpha: 0.54), size: 20),
            onPressed: _shareStock,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: cs.onSurface.withValues(alpha: 0.38), size: 20),
            onPressed: () {
              setState(() {
                _loadingPrice = true;
                _loadingChart = true;
              });
              _fetchPrice();
              _fetchChart(++_fetchSeq);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 상단 고정 영역 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                              color: cs.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _marketBadge(pick.market),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('yyyy.MM.dd').format(pick.createdAt),
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.38),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
                            : Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isPositive
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                              : Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '매수가 대비',
                            style: GoogleFonts.inter(
                              color: isPositive
                                  ? const Color(0xFF4ADE80).withValues(alpha: 0.7)
                                  : Colors.redAccent.withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                            style: GoogleFonts.inter(
                              color: isPositive ? const Color(0xFF4ADE80) : Colors.redAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 실시간 현재가 카드 (PER/PBR 통합)
                _livePriceCard(pick, formatter),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── 탭바 ────────────────────────────────────────────────
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4ADE80),
            unselectedLabelColor: cs.onSurface.withValues(alpha: 0.4),
            indicatorColor: const Color(0xFF4ADE80),
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
            tabs: [
              const Tab(text: '개요'),
              const Tab(text: '관련 뉴스'),
              Tab(text: isKorean ? '종목토론방' : ''),
            ],
          ),
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08)),

          // ── 탭 콘텐츠 ────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ① 개요 탭
                Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 차트
                            _chartCard(),
                            // 매수가 / 현재가 / 목표가
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _priceItem(context, '매수가', _formatPrice(pick.buyPrice, pick.market), cs.onSurface.withValues(alpha: 0.6))),
                                      Container(width: 1, height: 40, color: cs.onSurface.withValues(alpha: 0.1)),
                                      Expanded(
                                        child: _priceItem(
                                          context,
                                          '현재가',
                                          _livePrice != null ? _livePrice!.formattedPrice : (_loadingPrice ? '로딩중' : '--'),
                                          isPositive ? const Color(0xFF4ADE80) : Colors.redAccent,
                                        ),
                                      ),
                                      Container(width: 1, height: 40, color: cs.onSurface.withValues(alpha: 0.1)),
                                      Expanded(child: _priceItem(context, '목표가', _formatPrice(pick.targetPrice, pick.market), const Color(0xFF4ADE80))),
                                    ],
                                  ),
                                  if (_livePrice != null && pick.targetPrice > pick.buyPrice) ...[
                                    const SizedBox(height: 12),
                                    _priceProgressBar(pick.buyPrice, _livePrice!.price, pick.targetPrice, isPositive),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // 매수 근거
                            _sectionLabel('매수 근거'),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                pick.reason,
                                style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.7), fontSize: 14, height: 1.8),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 투표
                            _voteSection(),
                            const SizedBox(height: 20),
                            // 메모
                            if (_currentUser != null) ...[
                              _memoSection(),
                              const SizedBox(height: 20),
                            ],
                            // 댓글
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

                // ② 관련 뉴스 탭
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: _newsSection(),
                ),

                // ③ 종목토론방 탭
                isKorean
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: _discussionSection(),
                      )
                    : Center(
                        child: Text(
                          '한국 주식에서만 제공됩니다',
                          style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3)),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final cs = Theme.of(context).colorScheme;
    final dc = _loadingChart ? <_OHLC>[] : _displayCandles;
    final hasData = !_loadingChart && dc.length >= 2;
    final firstClose = hasData ? dc.first.close : 0.0;
    final lastClose = hasData ? dc.last.close : 0.0;
    final changePct =
        hasData ? ((lastClose - firstClose) / firstClose) * 100 : 0.0;
    final sign = changePct >= 0 ? '+' : '';
    final touched = hasData && _touchedIndex != null && _touchedIndex! < dc.length
        ? dc[_touchedIndex!]
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 기간 선택 — 로딩 중에도 항상 표시
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Row(
              children: [
                ..._Period.values.map(
                  (p) => GestureDetector(
                    onTap: () => _selectPeriod(p),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedPeriod == p
                            ? const Color(0xFF4ADE80).withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _selectedPeriod == p
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
                              : cs.onSurface.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        p.label,
                        style: GoogleFonts.inter(
                          color: _selectedPeriod == p
                              ? const Color(0xFF4ADE80)
                              : cs.onSurface.withValues(alpha: 0.38),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (hasData) ...[
                  Text(
                    '$sign${changePct.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      color: changePct >= 0
                          ? const Color(0xFF4ADE80)
                          : Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: hasData
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => _FullscreenCandleChartPage(
                                ticker: widget.pick.ticker,
                                market: widget.pick.market,
                                initialPeriod: _selectedPeriod,
                                initialCandles: _candles,
                                formatValue: (v) =>
                                    _formatPrice(v, widget.pick.market),
                                labelColor: cs.onSurface,
                                initialRange: _visibleRange,
                              ),
                            ),
                          )
                      : null,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.15)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.fullscreen,
                        size: 16,
                        color: cs.onSurface.withValues(alpha: 0.45)),
                  ),
                ),
              ],
            ),
          ),

          // 차트 영역
          if (_loadingChart)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4ADE80)),
              ),
            )
          else if (!hasData)
            const SizedBox(height: 200)
          else ...[
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
                                  ? DateFormat('yyyy년 MM월')
                                      .format(touched.date)
                                  : DateFormat('MM월 dd일').format(touched.date),
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.54),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _ohlcLabel('시', touched.open),
                            _ohlcLabel('고', touched.high,
                                color: const Color(0xFF4ADE80)),
                            _ohlcLabel('저', touched.low,
                                color: Colors.redAccent),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final chartW = constraints.maxWidth;
                return GestureDetector(
                  onLongPressStart: (d) =>
                      _onTouch(d.localPosition.dx, chartW),
                  onLongPressMoveUpdate: (d) =>
                      _onTouch(d.localPosition.dx, chartW),
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
                      labelColor: cs.onSurface,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _ohlcLabel(String label, double value, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.38),
                fontSize: 10,
              ),
            ),
            TextSpan(
              text: _formatPrice(value, widget.pick.market),
              style: GoogleFonts.robotoMono(
                color: color ?? cs.onSurface.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _livePriceCard(StockPick pick, NumberFormat formatter) {
    final cs = Theme.of(context).colorScheme;
    final f = _fundamentals;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.show_chart, color: Color(0xFF4ADE80), size: 18),
          const SizedBox(width: 10),
          Text(
            '현재가',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.38),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _loadingPrice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4ADE80),
                    ),
                  )
                : _livePrice == null
                ? Text(
                    '조회 불가',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.24),
                      fontSize: 13,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _livePrice!.formattedPrice,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
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
          // PER / PBR
          if (f != null && (f.per != null || f.pbr != null)) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (f.per != null)
                  _perPbrLabel('PER', f.per!.toStringAsFixed(1), cs),
                if (f.per != null && f.pbr != null)
                  const SizedBox(height: 4),
                if (f.pbr != null)
                  _perPbrLabel('PBR', f.pbr!.toStringAsFixed(2), cs),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _perPbrLabel(String label, String value, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.35),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.75),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
      child: Text(
        info.$1,
        style: GoogleFonts.inter(
          color: info.$2,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatPrice(double price, String market) {
    final formatter = NumberFormat('#,###');
    if (market == 'US') return '\$${price.toStringAsFixed(2)}';
    return '₩${formatter.format(price.toInt())}';
  }


  Widget _priceItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.38),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _priceProgressBar(
    double buyPrice,
    double currentPrice,
    double targetPrice,
    bool isPositive,
  ) {
    final cs = Theme.of(context).colorScheme;
    final total = targetPrice - buyPrice;
    final progress = ((currentPrice - buyPrice) / total).clamp(0.0, 1.0);
    final accentColor = isPositive ? const Color(0xFF4ADE80) : Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(
              accentColor.withValues(alpha: 0.8),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '매수가',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
            Text(
              '목표까지 ${((1 - progress) * 100).toStringAsFixed(1)}% 남음',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
            Text(
              '목표가',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: GoogleFonts.inter(
        color: cs.onSurface.withValues(alpha: 0.54),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── 투표 ──────────────────────────────────────────────────────────────────
  Widget _voteSection() {
    final cs = Theme.of(context).colorScheme;
    final pick = _livePick ?? widget.pick;
    final upCount = pick.upVotes;
    final downCount = pick.downVotes;
    final isUp = _userVote == 'up';
    final isDown = _userVote == 'down';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('커뮤니티 의견'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _currentUser == null
                    ? null
                    : () => _castVote(isUp ? null : 'up'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isUp
                        ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isUp
                          ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
                          : cs.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.thumb_up_outlined,
                        color: isUp
                            ? const Color(0xFF4ADE80)
                            : cs.onSurface.withValues(alpha: 0.38),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '상승 $upCount',
                        style: GoogleFonts.inter(
                          color: isUp
                              ? const Color(0xFF4ADE80)
                              : cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _currentUser == null
                    ? null
                    : () => _castVote(isDown ? null : 'down'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isDown
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDown
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : cs.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.thumb_down_outlined,
                        color: isDown
                            ? Colors.redAccent
                            : cs.onSurface.withValues(alpha: 0.38),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '하락 $downCount',
                        style: GoogleFonts.inter(
                          color: isDown
                              ? Colors.redAccent
                              : cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_currentUser == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '로그인 후 투표할 수 있습니다',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  // ── 뉴스 ──────────────────────────────────────────────────────────────────
  Widget _newsSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('관련 뉴스'),
        const SizedBox(height: 8),
        if (_loadingNews)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF4ADE80),
              ),
            ),
          )
        else if (_news.isEmpty)
          Text(
            '관련 뉴스가 없습니다',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.3),
              fontSize: 13,
            ),
          )
        else
          ...(_news.map(
            (n) => GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(n.url),
                mode: LaunchMode.externalApplication,
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.onSurface.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          n.publisher,
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeago.format(n.publishedAt, locale: 'ko'),
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.open_in_new,
                          size: 12,
                          color: cs.onSurface.withValues(alpha: 0.25),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )),
      ],
    );
  }

  // ── 종목토론방 ────────────────────────────────────────────────────────────
  Widget _discussionSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('종목토론방'),
            const Spacer(),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(
                    'https://finance.naver.com/item/board.nhn?code=${widget.pick.ticker}'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                '네이버에서 보기',
                style: GoogleFonts.inter(
                  color: const Color(0xFF4ADE80),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingDiscussion)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF4ADE80),
              ),
            ),
          )
        else if (_discussionPosts.isEmpty)
          Text(
            '게시글이 없습니다',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.3),
              fontSize: 13,
            ),
          )
        else
          ...(_discussionPosts.take(10).map(
                (p) => GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse(p.readUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.title,
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${p.date.month}/${p.date.day} ${p.date.hour.toString().padLeft(2, '0')}:${p.date.minute.toString().padLeft(2, '0')}',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.visibility_outlined,
                            size: 11,
                            color: cs.onSurface.withValues(alpha: 0.25)),
                        const SizedBox(width: 2),
                        Text(
                          '${p.viewCount}',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
      ],
    );
  }

  // ── 투자 메모 ─────────────────────────────────────────────────────────────
  Widget _memoSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('내 투자 메모'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _memoChanged
                  ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                  : cs.onSurface.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _memoController,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.7,
                ),
                maxLines: 5,
                minLines: 3,
                scrollPadding: const EdgeInsets.only(bottom: 300),
                onChanged: (_) {
                  if (!_memoChanged) setState(() => _memoChanged = true);
                },
                decoration: InputDecoration(
                  hintText: '이 종목에 대한 나만의 메모를 남겨보세요\n(매수 이유, 목표, 주의사항 등)',
                  hintStyle: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.24),
                    fontSize: 13,
                    height: 1.6,
                  ),
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _memoSaving ? null : _saveMemo,
                      child: _memoSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              '저장',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _showComments = !_showComments),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              color: cs.onSurface.withValues(alpha: 0.38),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              '코멘트',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.54),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(
              _showComments ? Icons.expand_less : Icons.expand_more,
              color: cs.onSurface.withValues(alpha: 0.38),
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
                    strokeWidth: 2,
                    color: Color(0xFF4ADE80),
                  ),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.24),
                    fontSize: 13,
                  ),
                ),
              );
            }
            return Column(
              children: comments.map((c) => _commentItem(c)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _commentItem(Comment comment) {
    final isOwn = _currentUser?.uid == comment.uid;
    final isAdmin = _currentUser?.uid == AuthService.adminUid;
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                  color: cs.onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeago.format(comment.createdAt, locale: 'ko'),
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.24),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              if (isOwn || isAdmin)
                GestureDetector(
                  onTap: _deletingCommentIds.contains(comment.id)
                      ? null
                      : () async {
                          if (_deletingCommentIds.contains(comment.id)) return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              title: Text(
                                '댓글 삭제',
                                style: GoogleFonts.inter(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              content: Text(
                                '이 댓글을 삭제하시겠습니까?',
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(
                                    '취소',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.54,
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(
                                    '삭제',
                                    style: GoogleFonts.inter(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          setState(() => _deletingCommentIds.add(comment.id));
                          await _firestoreService.deleteComment(
                            widget.pick.id,
                            comment.id,
                            uid: comment.uid,
                          );
                          if (mounted)
                            setState(
                              () => _deletingCommentIds.remove(comment.id),
                            );
                        },
                  child: _deletingCommentIds.contains(comment.id)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFF4ADE80),
                          ),
                        )
                      : Icon(
                          Icons.close,
                          color: cs.onSurface.withValues(alpha: 0.24),
                          size: 16,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.text,
            style: GoogleFonts.inter(
              color: cs.onSurface,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── 코멘트 입력창 (하단 고정) ────────────────────────────────────────────
  Widget _commentInput() {
    final user = _currentUser;
    final cs = Theme.of(context).colorScheme;
    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Text(
          '로그인 후 코멘트를 남길 수 있습니다',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.24),
            fontSize: 13,
          ),
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
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: GoogleFonts.inter(color: cs.onSurface, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitComment(user),
              decoration: InputDecoration(
                hintText: '코멘트를 입력하세요...',
                hintStyle: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.24),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.black,
                      size: 18,
                    ),
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
    try {
      final nickname =
          await _firestoreService.getNickname(user.uid) ??
          user.email?.split('@').first ??
          '익명';
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
      AnalyticsService.instance.logAddComment(widget.pick.ticker);
      if (mounted) _commentController.clear();
    } catch (_) {
      // 권한 오류 등 — 실패해도 UI 잠김 방지
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _StockCandlePainter extends CustomPainter {
  final List<_OHLC> candles;
  final int? touchedIndex;
  final String Function(double) formatValue;
  final String Function(DateTime) formatDate;
  final Color labelColor;

  _StockCandlePainter({
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
      ..color = labelColor.withValues(alpha: 0.05)
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
      final color = touchedIndex == i ? labelColor : baseColor;

      final totalCandleW = chartW / n;
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
      final bodyH = (bottom - top).abs().clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
        Paint()..color = color,
      );
    }

    // 십자선
    if (touchedIndex != null) {
      final cx = toX(touchedIndex!, n);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, chartH),
        Paint()
          ..color = labelColor.withValues(alpha: 0.2)
          ..strokeWidth = 1,
      );
    }

    canvas.restore();

    // Y축 레이블
    for (int i = 1; i <= 3; i++) {
      final v = minY + yRange * (1 - i / 4);
      final tp = TextPainter(
        text: TextSpan(
          text: formatValue(v),
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.35),
            fontSize: 8,
            fontFamily: 'RobotoMono',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final y = (chartH * i / 4 - tp.height / 2).clamp(0.0, chartH - tp.height);
      tp.paint(canvas, Offset(0, y));
    }

    // X축 레이블
    const labelCount = 5;
    final labelStyle = TextStyle(
      color: labelColor.withValues(alpha: 0.35),
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
      old.candles != candles ||
      old.touchedIndex != touchedIndex ||
      old.labelColor != labelColor;
}

// ── 가로 전체화면 차트 페이지 ──────────────────────────────────────────────
class _FullscreenCandleChartPage extends StatefulWidget {
  final String ticker;
  final String market;
  final _Period initialPeriod;
  final List<_OHLC> initialCandles;
  final String Function(double) formatValue;
  final Color labelColor;
  final ChartVisibleRange initialRange;

  const _FullscreenCandleChartPage({
    required this.ticker,
    required this.market,
    required this.initialPeriod,
    required this.initialCandles,
    required this.formatValue,
    required this.labelColor,
    required this.initialRange,
  });

  @override
  State<_FullscreenCandleChartPage> createState() =>
      _FullscreenCandleChartPageState();
}

class _FullscreenCandleChartPageState
    extends State<_FullscreenCandleChartPage> {
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
      widget.ticker,
      widget.market,
      interval: _period.interval,
      range: _period.range,
    );
    if (mounted && _fetchSeq == seq) {
      setState(() {
        _candles = data;
        _loading = false;
        final defaultView = _period == _Period.day1 ? 120 : data.length;
        final startIdx =
            (data.length - defaultView).clamp(0, data.length).toDouble();
        _visibleRange = ChartVisibleRange(startIdx, data.length.toDouble());
      });
    }
  }

  void _selectPeriod(_Period p) {
    if (_period == p) return;
    setState(() {
      _period = p;
      _loading = true;
      _touchedIndex = null;
      _visibleRange = const ChartVisibleRange(0, 0);
    });
    _fetchCandles(++_fetchSeq);
  }

  void _onTouch(double localX, double chartW) {
    if (_candles.isEmpty) return;
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    final adjustedX = (localX - yAxisW).clamp(0.0, candleAreaW);
    final visibleWidth = _visibleRange.width;
    if (visibleWidth <= 0) return;
    final fractionalIndex =
        _visibleRange.start + (adjustedX / candleAreaW) * visibleWidth;
    final overallIndex =
        fractionalIndex.floor().clamp(0, _candles.length - 1);
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
    if (_rangeAtScaleStart == null ||
        _focalPointAtScaleStart == null ||
        _candles.isEmpty) return;
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    final newWidth = (_rangeAtScaleStart!.width / d.scale)
        .clamp(5.0, _candles.length.toDouble());
    final focalFraction =
        ((_focalPointAtScaleStart!.dx - yAxisW) / candleAreaW).clamp(0.0, 1.0);
    final anchorCandle =
        _rangeAtScaleStart!.start + focalFraction * _rangeAtScaleStart!.width;
    final panDeltaX = d.localFocalPoint.dx - _focalPointAtScaleStart!.dx;
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

  String _formatDate(DateTime d) {
    if (_period == _Period.min1) return DateFormat('HH:mm').format(d);
    if (_period == _Period.month) return DateFormat('yy/MM').format(d);
    return DateFormat('MM/dd').format(d);
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
                // 상단 정보 행 (터치 OHLC 또는 빈 공간)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: touched != null
                      ? Padding(
                          key: ValueKey(_touchedIndex),
                          padding:
                              const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              Text(
                                _formatDate(touched.date),
                                style: GoogleFonts.inter(
                                    color:
                                        cs.onSurface.withValues(alpha: 0.54),
                                    fontSize: 11),
                              ),
                              const SizedBox(width: 12),
                              _ohlcLabel('시', touched.open, cs),
                              _ohlcLabel('고', touched.high, cs,
                                  color: const Color(0xFF4ADE80)),
                              _ohlcLabel('저', touched.low, cs,
                                  color: Colors.redAccent),
                              _ohlcLabel('종', touched.close, cs,
                                  color: touched.close >= touched.open
                                      ? const Color(0xFF4ADE80)
                                      : Colors.redAccent),
                            ]),
                          ),
                        )
                      : SizedBox(key: const ValueKey('empty'), height: 26),
                ),
                // 차트 영역
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(builder: (ctx, constraints) {
                          final chartW = constraints.maxWidth;
                          return GestureDetector(
                            onLongPressStart: (d) =>
                                _onTouch(d.localPosition.dx, chartW),
                            onLongPressMoveUpdate: (d) =>
                                _onTouch(d.localPosition.dx, chartW),
                            onLongPressEnd: (_) =>
                                setState(() => _touchedIndex = null),
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: (d) => _onScaleUpdate(d, chartW),
                            onScaleEnd: _onScaleEnd,
                            child: CustomPaint(
                              size: Size(chartW, constraints.maxHeight),
                              painter: _StockCandlePainter(
                                candles: dc,
                                touchedIndex: _touchedIndex,
                                formatValue: widget.formatValue,
                                formatDate: _formatDate,
                                labelColor: widget.labelColor,
                              ),
                            ),
                          );
                        }),
                ),
                // 기간 선택 버튼
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _Period.values.map((p) {
                      final selected = _period == p;
                      return GestureDetector(
                        onTap: () => _selectPeriod(p),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF4ADE80)
                                : cs.onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            p.label,
                            style: GoogleFonts.inter(
                              color: selected
                                  ? Colors.black
                                  : cs.onSurface.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            // 닫기 버튼
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

  Widget _ohlcLabel(String label, double value, ColorScheme cs, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$label ',
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.38), fontSize: 10),
          ),
          TextSpan(
            text: widget.formatValue(value),
            style: GoogleFonts.inter(
              color: color ?? cs.onSurface.withValues(alpha: 0.87),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
    );
  }
}
