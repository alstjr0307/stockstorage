import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/user_level_avatar.dart';
import 'stock_ai_analysis_result_screen.dart';
import 'stock_compare_screen.dart';
import '../services/deep_link_service.dart';

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

Route<dynamic> stockDetailRoute(
  StockPick pick, {
  bool enablePickFeatures = true,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoPageRoute(
      builder: (_) =>
          StockDetailScreen(pick: pick, enablePickFeatures: enablePickFeatures),
    );
  }
  return MaterialPageRoute(
    builder: (_) =>
        StockDetailScreen(pick: pick, enablePickFeatures: enablePickFeatures),
  );
}

StockPick stockPickFromSearchResult(
  StockSearchResult result, {
  String reason = '종목 검색에서 선택한 종목입니다.',
  String category = 'STOCK',
}) {
  final market = result.market.trim().toUpperCase();
  final ticker = result.ticker.trim().toUpperCase();
  return StockPick(
    id: 'stock_${market}_$ticker',
    ticker: ticker,
    name: result.name.trim().isEmpty ? ticker : result.name.trim(),
    buyPrice: 0,
    targetPrice: 0,
    reason: reason,
    category: category,
    market: market,
    isPremium: false,
    createdAt: DateTime.now(),
    status: 'active',
  );
}

StockPick stockPickForGeneralDetail({
  required String ticker,
  required String name,
  required String market,
  String reason = '종목 상세에서 선택한 종목입니다.',
  String category = 'STOCK',
}) {
  final normalizedMarket = market.trim().toUpperCase();
  final normalizedTicker = ticker.trim().toUpperCase();
  return StockPick(
    id: 'stock_${normalizedMarket}_$normalizedTicker',
    ticker: normalizedTicker,
    name: name.trim().isEmpty ? normalizedTicker : name.trim(),
    buyPrice: 0,
    targetPrice: 0,
    reason: reason,
    category: category,
    market: normalizedMarket,
    isPremium: false,
    createdAt: DateTime.now(),
    status: 'active',
  );
}

class StockDetailScreen extends StatefulWidget {
  final StockPick pick;
  final bool enablePickFeatures;

  const StockDetailScreen({
    super.key,
    required this.pick,
    this.enablePickFeatures = true,
  });

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
  final _captureKey = GlobalKey();
  bool _capturing = false;
  bool _showCaptureWatermark = false;
  final _commentController = TextEditingController();
  final _memoController = TextEditingController();
  final _firestoreService = FirestoreService();
  late final Stream<List<Comment>> _commentsStream;
  StreamSubscription<StockPick>? _pickSub;
  bool _submitting = false;
  bool _memoSaving = false;
  bool _memoChanged = false;
  bool _adminCommentsOnly = false;
  final Set<String> _deletingCommentIds = {};
  bool _revealReady = false;

  // 투표
  String? _userVote; // 'up', 'down', null
  StockPick? _livePick;

  // 관심종목 로컬 상태 (낙관적 업데이트용)
  bool? _isFavoriteStock;
  StreamSubscription<bool>? _favoriteStockSub;

  // 뉴스
  List<StockNews> _news = [];
  bool _loadingNews = true;

  // 종목토론방
  List<DiscussionPost> _discussionPosts = [];
  bool _loadingDiscussion = true;

  // AI 종목 분석

  User? get _currentUser => FirebaseAuth.instance.currentUser;
  bool get _isPickMode => widget.enablePickFeatures;
  String get _memoDocId {
    if (_isPickMode) return widget.pick.id;
    final market = widget.pick.market.trim().toUpperCase();
    final ticker = widget.pick.ticker.trim().toUpperCase();
    return 'stock_${market}_$ticker';
  }

  @override
  void initState() {
    super.initState();
    _commentsStream = widget.enablePickFeatures
        ? _firestoreService.getComments(widget.pick.id)
        : Stream.value(const <Comment>[]);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      const tabNames = ['정보', '뉴스', '댓글'];
      AnalyticsService.instance.logTabChange(
        'stock_detail_${tabNames[_tabController.index]}',
      );
    });
    if (_isPickMode) {
      AdService.instance.loadInterstitial();
      AdService.instance.showInterstitialIfReady();
    } else {
      AdService.instance.cancelPendingStockInterstitial();
    }
    AnalyticsService.instance.logViewStock(
      ticker: widget.pick.ticker,
      name: widget.pick.name,
      market: widget.pick.market,
    );
    _fetchPrice();
    _fetchChart(++_fetchSeq);
    _fetchFundamentals();
    if (_currentUser != null) {
      _loadMemo();
    }
    if (widget.enablePickFeatures) {
      _loadVote();
    }
    _loadNews();
    _loadDiscussion();
    _subscribePick();
    // 관심종목 탭에서 열리면 이미 등록된 상태 — 스트림 응답 전 깜빡임 방지
    if (!widget.enablePickFeatures) _isFavoriteStock = true;
    _subscribeFavoriteStock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _revealReady = true);
    });
  }

  void _subscribeFavoriteStock() {
    final user = _currentUser;
    if (user == null) return;
    final stockKey = FirestoreService.favoriteStockKey(
      widget.pick.market,
      widget.pick.ticker,
    );
    _favoriteStockSub = _firestoreService
        .watchIsFavoriteStock(user.uid, stockKey)
        .listen((isFav) {
          if (mounted && _isFavoriteStock != isFav) {
            setState(() => _isFavoriteStock = isFav);
          }
        });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pickSub?.cancel();
    _favoriteStockSub?.cancel();
    _commentController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _subscribePick() {
    _livePick = widget.pick;
    if (!widget.enablePickFeatures) return;
    // late field를 접근해 구독 시작 (lazy initialization 트리거)
    _pickSub = _firestoreService.getPickStream(widget.pick.id).listen((p) {
      if (mounted) setState(() => _livePick = p);
    });
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
    if (mounted) {
      setState(() {
        _news = items;
        _loadingNews = false;
      });
    }
  }

  Future<void> _loadDiscussion() async {
    final posts = await StockPriceService.fetchDiscussionPosts(
      widget.pick.ticker,
      widget.pick.market,
    );
    if (mounted) {
      setState(() {
        _discussionPosts = posts;
        _loadingDiscussion = false;
      });
    }
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
    final text = await _firestoreService.getMemo(user.uid, _memoDocId);
    if (mounted && text != null) {
      _memoController.text = text;
    }
  }

  Future<void> _togglePickCommentNotification(bool enabled) async {
    final user = _currentUser;
    if (user == null) return;
    await _firestoreService.setPickCommentNotificationEnabled(
      user.uid,
      widget.pick.id,
      enabled,
    );
  }

  Future<void> _toggleFavorite(bool isFavorite) async {
    final user = _currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인 후 관심추천주에 등록할 수 있습니다.')));
      return;
    }

    await _firestoreService.toggleFavorite(
      user.uid,
      widget.pick.id,
      isFavorite,
    );
    AnalyticsService.instance.logToggleFavorite(
      ticker: widget.pick.ticker,
      name: widget.pick.name,
      added: !isFavorite,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFavorite ? '관심 추천주에서 해제했습니다.' : '관심 추천주에 등록했습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleFavoriteStock() async {
    final user = _currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인 후 관심종목에 등록할 수 있습니다.')));
      return;
    }

    final wasSelected = _isFavoriteStock ?? false;
    // 낙관적 업데이트: 즉시 UI 반전
    setState(() => _isFavoriteStock = !wasSelected);

    try {
      await _firestoreService.toggleFavoriteStock(
        user.uid,
        widget.pick,
        wasSelected,
      );
      AnalyticsService.instance.logToggleFavorite(
        ticker: widget.pick.ticker,
        name: widget.pick.name,
        added: !wasSelected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasSelected ? '관심종목에서 해제했습니다.' : '관심종목에 등록했습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // 실패 시 원상복구
      if (mounted) setState(() => _isFavoriteStock = wasSelected);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('오류가 발생했습니다. 다시 시도해주세요.')));
    }
  }

  Widget _favoriteButton(ColorScheme cs) {
    final user = _currentUser;
    if (user == null) {
      return OutlinedButton.icon(
        onPressed: () => _toggleFavorite(false),
        icon: const Icon(Icons.favorite_border_rounded, size: 16),
        label: const Text('관심추천주'),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface.withValues(alpha: 0.7),
          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.16)),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      );
    }

    return StreamBuilder<List<String>>(
      stream: _firestoreService.getFavoriteIds(user.uid),
      builder: (context, snapshot) {
        final favoriteIds = snapshot.data ?? const <String>[];
        final isFavorite = favoriteIds.contains(widget.pick.id);
        return OutlinedButton.icon(
          onPressed: () => _toggleFavorite(isFavorite),
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 16,
          ),
          label: const Text('관심추천주'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isFavorite
                ? Colors.redAccent
                : cs.onSurface.withValues(alpha: 0.7),
            side: BorderSide(
              color: isFavorite
                  ? Colors.redAccent.withValues(alpha: 0.42)
                  : cs.onSurface.withValues(alpha: 0.16),
            ),
            backgroundColor: isFavorite
                ? Colors.redAccent.withValues(alpha: 0.08)
                : Colors.transparent,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  Widget _favoriteActions(ColorScheme cs) {
    if (!_isPickMode) return _favoriteStockButton(cs);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [_favoriteButton(cs), _favoriteStockButton(cs)],
    );
  }

  Widget _favoriteStockButton(ColorScheme cs) {
    final isFavorite = _isFavoriteStock ?? false;
    return OutlinedButton.icon(
      onPressed: _currentUser == null ? null : _toggleFavoriteStock,
      icon: Icon(
        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
        size: 16,
      ),
      label: const Text('관심종목'),
      style: OutlinedButton.styleFrom(
        foregroundColor: isFavorite
            ? const Color(0xFFF5B547)
            : cs.onSurface.withValues(alpha: 0.7),
        side: BorderSide(
          color: isFavorite
              ? const Color(0xFFF5B547).withValues(alpha: 0.46)
              : cs.onSurface.withValues(alpha: 0.16),
        ),
        backgroundColor: isFavorite
            ? const Color(0xFFF5B547).withValues(alpha: 0.10)
            : Colors.transparent,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _saveMemo() async {
    final user = _currentUser;
    if (user == null) return;
    setState(() => _memoSaving = true);
    await _firestoreService.saveMemo(
      user.uid,
      _memoDocId,
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
          content: Text('메모가 저장되었습니다', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.9),
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
    if (mounted) {
      setState(() {
        _livePrice = result;
        _loadingPrice = false;
      });
    }
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
        final startIdx = (data.length - defaultView)
            .clamp(0, data.length)
            .toDouble();
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

  List<Map<String, dynamic>> _analysisCandles([List<_OHLC>? source]) {
    final list = source ?? _candles;
    final start = max(0, list.length - 140);
    return list
        .skip(start)
        .map(
          (c) => {
            'date': DateFormat('yyyy-MM-dd').format(c.date),
            'open': c.open,
            'high': c.high,
            'low': c.low,
            'close': c.close,
          },
        )
        .toList();
  }

  Future<void> _openAiAnalysisScreen() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인 후 AI 분석을 사용할 수 있습니다.')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockAiAnalysisResultScreen(
          pick: widget.pick,
          price: _livePrice,
          fundamentals: _fundamentals,
          candles: _analysisCandles(),
          news: _news,
        ),
      ),
    );
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
        _candles.isEmpty) {
      return;
    }

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
    if (!_isPickMode) {
      final liveP = _livePrice?.price;
      final divider = '━━━━━━━━━━━━━━━━━━';
      final priceLine = liveP != null
          ? '현재가: ${_formatPrice(liveP, pick.market)}\n'
          : '';
      final changeLine = _livePrice != null
          ? '등락률: ${_livePrice!.changeRate >= 0 ? '+' : ''}${_livePrice!.changeRate.toStringAsFixed(2)}%\n'
          : '';
      final text =
          '펨코 HOT 종목\n'
          '$divider\n'
          '${pick.market == 'US' ? '미국' : '국내'} ${pick.name} (${pick.ticker})\n'
          '시장: ${pick.market}\n'
          '$priceLine'
          '$changeLine'
          '$divider\n'
          '주식저장소 앱에서 확인하세요.';
      final box =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromLTWH(0, 0, 100, 100);
      Share.share(text, sharePositionOrigin: origin);
      return;
    }

    // 현재가 기준 수익률 (현재가 없으면 목표가 기준)
    final liveP = _livePrice?.price;
    final double currentReturn = liveP != null
        ? ((liveP - pick.buyPrice) / pick.buyPrice) * 100
        : pick.currentReturnRate;
    final double targetReturn = pick.targetReturnRate;
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
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromLTWH(0, 0, 100, 100);
    Share.share(text, sharePositionOrigin: origin);
  }

  Future<void> _captureAndShare() async {
    setState(() {
      _capturing = true;
      _showCaptureWatermark = true;
    });
    await Future.delayed(const Duration(milliseconds: 80));
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final file = File(
        '${Directory.systemTemp.path}/pick_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      final size = MediaQuery.sizeOf(context);
      final origin = Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: _isPickMode ? '📈 주식저장소 추천 종목' : '펨코 HOT 종목',
        sharePositionOrigin: origin,
      );
    } finally {
      if (mounted)
        setState(() {
          _capturing = false;
          _showCaptureWatermark = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pick = _livePick ?? widget.pick;
    final formatter = NumberFormat('#,###');
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final livePrice = _livePrice?.price;
    final hasClosedPrice = pick.isCompleted && pick.closedPrice != null;
    final returnRate = pick.buyPrice <= 0
        ? 0.0
        : hasClosedPrice
        ? ((pick.closedPrice! - pick.buyPrice) / pick.buyPrice) * 100
        : livePrice != null
        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
        : pick.currentReturnRate;
    final isPositive = returnRate >= 0;
    final isKorean = pick.market == 'KS' || pick.market == 'KQ';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
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
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          ),
          actions: [
            if (_isPickMode)
              IconButton(
                icon: StreamBuilder<bool>(
                  stream: _currentUser == null
                      ? null
                      : _firestoreService.watchPickCommentNotificationEnabled(
                          _currentUser!.uid,
                          widget.pick.id,
                        ),
                  builder: (context, snap) {
                    final enabled = snap.data ?? true;
                    return Icon(
                      enabled
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: enabled
                          ? const Color(0xFF10B981)
                          : cs.onSurface.withValues(alpha: 0.54),
                      size: 20,
                    );
                  },
                ),
                onPressed: () async {
                  final user = _currentUser;
                  if (user == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('로그인 후 설정할 수 있습니다.')),
                    );
                    return;
                  }
                  final current = await _firestoreService
                      .getPickCommentNotificationEnabled(
                        user.uid,
                        widget.pick.id,
                      );
                  final next = !current;
                  await _togglePickCommentNotification(next);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        next ? '이 추천주 댓글 알림이 켜졌습니다.' : '이 추천주 댓글 알림이 꺼졌습니다.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            if (_isPickMode)
              IconButton(
                key: _shareButtonKey,
                icon: Icon(
                  Icons.share_outlined,
                  color: cs.onSurface.withValues(alpha: 0.54),
                  size: 20,
                ),
                onPressed: _shareStock,
              ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: cs.onSurface.withValues(alpha: 0.38),
                size: 20,
              ),
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
            _DetailReveal(
              show: _revealReady,
              delayMs: 30,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 종목 헤더
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pick.name,
                                style: TextStyle(
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
                                    DateFormat(
                                      'yyyy.MM.dd',
                                    ).format(pick.createdAt),
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.38,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (_isPickMode) ...[
                                const SizedBox(height: 8),
                                _favoriteActions(cs),
                              ],
                            ],
                          ),
                        ),
                        if (!_isPickMode) ...[
                          const SizedBox(width: 8),
                          _favoriteStockButton(cs),
                        ],
                        if (_isPickMode)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isPositive
                                  ? const Color(
                                      0xFFF04452,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFF1677FF,
                                    ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isPositive
                                    ? const Color(
                                        0xFFF04452,
                                      ).withValues(alpha: 0.4)
                                    : const Color(
                                        0xFF1677FF,
                                      ).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  hasClosedPrice ? '종료 수익률' : '매수가 대비',
                                  style: TextStyle(
                                    color: isPositive
                                        ? const Color(
                                            0xFFF04452,
                                          ).withValues(alpha: 0.75)
                                        : const Color(
                                            0xFF1677FF,
                                          ).withValues(alpha: 0.75),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    color: isPositive
                                        ? const Color(0xFFF04452)
                                        : const Color(0xFF1677FF),
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
            ),

            // ── 탭바 ────────────────────────────────────────────────
            _DetailReveal(
              show: _revealReady,
              delayMs: 140,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    labelColor: isDark
                        ? const Color(0xFF0A0E1A)
                        : const Color(0xFF191F28),
                    unselectedLabelColor: cs.onSurface.withValues(
                      alpha: isDark ? 0.62 : 0.68,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: [
                      Tab(text: widget.enablePickFeatures ? '개요' : '차트'),
                      const Tab(text: '관련 뉴스'),
                      Tab(text: isKorean ? '종목토론방' : ''),
                    ],
                  ),
                ),
              ),
            ),
            // ── 탭 콘텐츠 ────────────────────────────────────────────
            Expanded(
              child: _DetailReveal(
                show: _revealReady,
                delayMs: 220,
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // ① 차트 탭
                    Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              20,
                              20,
                              20,
                              8 + MediaQuery.of(context).viewInsets.bottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── 캡처 영역 시작 ──
                                RepaintBoundary(
                                  key: _captureKey,
                                  child: Container(
                                    color: _capturing ? Colors.black : null,
                                    padding: _capturing
                                        ? const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 16,
                                          )
                                        : EdgeInsets.zero,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 종목명 + 수익률 (캡처 시에만 표시)
                                        if (_capturing) ...[
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      pick.name,
                                                      style: TextStyle(
                                                        color: _capturing
                                                            ? Colors.white
                                                            : cs.onSurface,
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        _marketBadge(
                                                          pick.market,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          DateFormat(
                                                            'yyyy.MM.dd',
                                                          ).format(
                                                            pick.createdAt,
                                                          ),
                                                          style: TextStyle(
                                                            color: _capturing
                                                                ? Colors.white
                                                                      .withValues(
                                                                        alpha:
                                                                            0.72,
                                                                      )
                                                                : cs.onSurface
                                                                      .withValues(
                                                                        alpha:
                                                                            0.38,
                                                                      ),
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_isPickMode)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isPositive
                                                        ? _kUpColor.withValues(
                                                            alpha: 0.12,
                                                          )
                                                        : _kDownColor
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: isPositive
                                                          ? _kUpColor
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                )
                                                          : _kDownColor
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                                                    style: TextStyle(
                                                      color: isPositive
                                                          ? _kUpColor
                                                          : _kDownColor,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 20,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          // 현재가 카드
                                          _livePriceCard(pick, formatter),
                                          const SizedBox(height: 12),
                                        ],
                                        // 일봉 차트
                                        _chartCard(),
                                        if (_isPickMode) ...[
                                          // 매수가 / 현재가 / 목표가 (카드리스)
                                          Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: _priceItem(
                                                      context,
                                                      '매수가',
                                                      _formatPrice(
                                                        pick.buyPrice,
                                                        pick.market,
                                                      ),
                                                      cs.onSurface.withValues(
                                                        alpha: 0.6,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    width: 1,
                                                    height: 40,
                                                    color: cs.onSurface
                                                        .withValues(alpha: 0.1),
                                                  ),
                                                  Expanded(
                                                    child: _priceItem(
                                                      context,
                                                      hasClosedPrice
                                                          ? '종료가'
                                                          : '현재가',
                                                      hasClosedPrice
                                                          ? _formatPrice(
                                                              pick.closedPrice!,
                                                              pick.market,
                                                            )
                                                          : (_livePrice != null
                                                                ? _livePrice!
                                                                      .formattedPrice
                                                                : (_loadingPrice
                                                                      ? '로딩중'
                                                                      : '--')),
                                                      isPositive
                                                          ? const Color(
                                                              0xFFF04452,
                                                            )
                                                          : const Color(
                                                              0xFF1677FF,
                                                            ),
                                                    ),
                                                  ),
                                                  Container(
                                                    width: 1,
                                                    height: 40,
                                                    color: cs.onSurface
                                                        .withValues(alpha: 0.1),
                                                  ),
                                                  Expanded(
                                                    child: _priceItem(
                                                      context,
                                                      hasClosedPrice
                                                          ? '현재가'
                                                          : '목표가',
                                                      hasClosedPrice
                                                          ? (_livePrice != null
                                                                ? _livePrice!
                                                                      .formattedPrice
                                                                : (_loadingPrice
                                                                      ? '로딩중'
                                                                      : '--'))
                                                          : _formatPrice(
                                                              pick.targetPrice,
                                                              pick.market,
                                                            ),
                                                      hasClosedPrice
                                                          ? (_livePrice != null
                                                                ? (((_livePrice!.price -
                                                                                  pick.buyPrice) /
                                                                              pick.buyPrice) >=
                                                                          0
                                                                      ? const Color(
                                                                          0xFFF04452,
                                                                        )
                                                                      : const Color(
                                                                          0xFF1677FF,
                                                                        ))
                                                                : cs.onSurface
                                                                      .withValues(
                                                                        alpha:
                                                                            0.45,
                                                                      ))
                                                          : const Color(
                                                              0xFF10B981,
                                                            ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (!hasClosedPrice &&
                                                  _livePrice != null &&
                                                  pick.targetPrice >
                                                      pick.buyPrice) ...[
                                                const SizedBox(height: 12),
                                                _priceProgressBar(
                                                  pick.buyPrice,
                                                  _livePrice!.price,
                                                  pick.targetPrice,
                                                  isPositive,
                                                ),
                                              ],
                                              const SizedBox(height: 12),
                                              Divider(
                                                height: 16,
                                                thickness: 1,
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.07,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          // 매수 근거
                                          Text(
                                            '매수 근거',
                                            style: TextStyle(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            pick.reason,
                                            style: TextStyle(
                                              color: cs.onSurface,
                                              fontSize: 14,
                                              height: 1.8,
                                            ),
                                          ),
                                        ],
                                        // 워터마크
                                        if (_showCaptureWatermark) ...[
                                          const SizedBox(height: 14),
                                          Center(
                                            child: RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: '주식저장소',
                                                    style: TextStyle(
                                                      color: const Color(
                                                        0xFF10B981,
                                                      ),
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: ' 앱에서 확인하세요 📈',
                                                    style: TextStyle(
                                                      color: cs.onSurface
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                // ── 캡처 영역 끝 ──
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _stockActionChip(
                                        cs: cs,
                                        icon: Icons.compare_arrows_rounded,
                                        label: '종목 비교',
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => StockCompareScreen(
                                              basePick: widget.pick,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _stockActionChip(
                                        cs: cs,
                                        icon: Icons.ios_share_rounded,
                                        label: _capturing ? '캡처 중...' : '캡처 공유',
                                        onTap: _capturing
                                            ? null
                                            : _captureAndShare,
                                        loading: _capturing,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                if (widget.enablePickFeatures) ...[
                                  // 투표
                                  _voteSection(),
                                  const SizedBox(height: 20),
                                  // 메모
                                  if (_currentUser != null) ...[
                                    _aiAnalysisSection(),
                                    const SizedBox(height: 20),
                                    _memoSection(),
                                    const SizedBox(height: 20),
                                  ],
                                  // 댓글
                                  _commentSectionV2(),
                                  const SizedBox(height: 8),
                                ] else if (_currentUser != null) ...[
                                  _aiAnalysisSection(),
                                  const SizedBox(height: 20),
                                  _memoSection(),
                                  const SizedBox(height: 80),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (widget.enablePickFeatures) _commentInput(),
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
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiAnalysisLastAtLabel(ColorScheme cs) {
    final user = _currentUser;
    final defaultLabel = Text(
      '분석 결과는 별도 화면에서 정리됩니다',
      style: TextStyle(
        color: cs.onSurface.withValues(alpha: 0.42),
        fontSize: 11,
      ),
    );
    if (user == null) return defaultLabel;
    final analysisKey = FirestoreService.favoriteStockKey(
      widget.pick.market,
      widget.pick.ticker,
    );
    return StreamBuilder<DateTime?>(
      stream: _firestoreService.watchStockAiAnalysisUpdatedAt(
        user.uid,
        analysisKey,
      ),
      builder: (context, snap) {
        final at = snap.data;
        if (at == null) return defaultLabel;
        final label = DateFormat('yyyy.MM.dd HH:mm').format(at);
        return Row(
          children: [
            Icon(
              Icons.schedule,
              size: 11,
              color: cs.onSurface.withValues(alpha: 0.42),
            ),
            const SizedBox(width: 4),
            Text(
              '마지막 분석 $label',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _aiAnalysisSection() {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF10B981);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openAiAnalysisScreen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.32)),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 22,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '종목 AI 분석',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _aiAnalysisLastAtLabel(cs),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '보기',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chartCard() {
    final cs = Theme.of(context).colorScheme;
    final dc = _loadingChart ? <_OHLC>[] : _displayCandles;
    final hasData = !_loadingChart && dc.length >= 2;
    final firstClose = hasData ? dc.first.close : 0.0;
    final lastClose = hasData ? dc.last.close : 0.0;
    final changePct = hasData
        ? ((lastClose - firstClose) / firstClose) * 100
        : 0.0;
    final sign = changePct >= 0 ? '+' : '';
    final touched =
        hasData && _touchedIndex != null && _touchedIndex! < dc.length
        ? dc[_touchedIndex!]
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 기간 선택 — 로딩 중에도 항상 표시
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 행: 분봉/일봉/주봉/월봉 + 등락률 + 확대버튼
                Row(
                  children: [
                    _periodBtn('분봉', _selectedPeriod.isMinute, cs, () {
                      if (!_selectedPeriod.isMinute)
                        _selectPeriod(_Period.min1);
                    }),
                    ...[_Period.day1, _Period.week, _Period.month].map(
                      (p) => _periodBtn(
                        p.label,
                        _selectedPeriod == p,
                        cs,
                        () => _selectPeriod(p),
                      ),
                    ),
                    const Spacer(),
                    if (hasData) ...[
                      Text(
                        '$sign${changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: changePct >= 0 ? _kUpColor : _kDownColor,
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
                            color: cs.onSurface.withValues(alpha: 0.15),
                          ),
                          borderRadius: BorderRadius.circular(6),
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
                // 분봉 서브 선택: 1분 / 5분 / 60분
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _selectedPeriod.isMinute
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children:
                                [_Period.min1, _Period.min5, _Period.min60]
                                    .map(
                                      (p) => _periodBtn(
                                        p.label,
                                        _selectedPeriod == p,
                                        cs,
                                        () => _selectPeriod(p),
                                        small: true,
                                      ),
                                    )
                                    .toList(),
                          ),
                        )
                      : const SizedBox.shrink(),
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
                  strokeWidth: 2,
                  color: Color(0xFF10B981),
                ),
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
                              _selectedPeriod.isMinute
                                  ? DateFormat(
                                      'MM월 dd일 HH:mm',
                                    ).format(touched.date)
                                  : _selectedPeriod == _Period.month
                                  ? DateFormat('yyyy년 MM월').format(touched.date)
                                  : DateFormat('MM월 dd일').format(touched.date),
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.54),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _ohlcLabel('시', touched.open),
                            _ohlcLabel('고', touched.high, color: _kUpColor),
                            _ohlcLabel('저', touched.low, color: _kDownColor),
                            _ohlcLabel(
                              '종',
                              touched.close,
                              color: touched.close >= touched.open
                                  ? _kUpColor
                                  : _kDownColor,
                            ),
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
                  onLongPressStart: (d) => _onTouch(d.localPosition.dx, chartW),
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
                      formatDate: _selectedPeriod.isMinute
                          ? (d) => DateFormat('HH:mm').format(d)
                          : _selectedPeriod == _Period.month
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

  Widget _periodBtn(
    String label,
    bool active,
    ColorScheme cs,
    VoidCallback onTap, {
    bool small = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10,
          vertical: small ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF10B981).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? const Color(0xFF10B981).withValues(alpha: 0.5)
                : cs.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? const Color(0xFF10B981)
                : cs.onSurface.withValues(alpha: 0.38),
            fontSize: small ? 10 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
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
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.38),
                fontSize: 10,
              ),
            ),
            TextSpan(
              text: _formatPrice(value, widget.pick.market),
              style: TextStyle(
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
    final hasClosedPrice = pick.isCompleted && pick.closedPrice != null;
    final closedReturnRate = hasClosedPrice
        ? ((pick.closedPrice! - pick.buyPrice) / pick.buyPrice) * 100
        : 0.0;
    final isClosedPositive = closedReturnRate >= 0;
    final hasLivePrice = _livePrice != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.show_chart, color: Color(0xFF10B981), size: 18),
          const SizedBox(width: 10),
          Text(
            '현재가',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.38),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: hasClosedPrice
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasLivePrice
                            ? _livePrice!.formattedPrice
                            : _formatPrice(pick.closedPrice!, pick.market),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        hasLivePrice
                            ? _livePrice!.formattedChange
                            : '${isClosedPositive ? '+' : ''}${closedReturnRate.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: hasLivePrice
                              ? (_livePrice!.isUp
                                    ? const Color(0xFFF04452)
                                    : const Color(0xFF1677FF))
                              : (isClosedPositive
                                    ? const Color(0xFFF04452)
                                    : const Color(0xFF1677FF)),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : _loadingPrice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  )
                : _livePrice == null
                ? Text(
                    '조회 불가',
                    style: TextStyle(
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
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        _livePrice!.formattedChange,
                        style: TextStyle(
                          color: _livePrice!.isUp
                              ? const Color(0xFFF04452)
                              : const Color(0xFF1677FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),
          // 시총 / PER / PBR
          if (f != null &&
              (f.marketCap != null || f.per != null || f.pbr != null)) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (f.marketCap != null)
                  _perPbrLabel('시총', _formatMarketCap(f.marketCap!), cs),
                if (f.marketCap != null && (f.per != null || f.pbr != null))
                  const SizedBox(height: 4),
                if (f.per != null)
                  _perPbrLabel('PER', f.per!.toStringAsFixed(1), cs),
                if (f.per != null && f.pbr != null) const SizedBox(height: 4),
                if (f.pbr != null)
                  _perPbrLabel('PBR', f.pbr!.toStringAsFixed(2), cs),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatMarketCap(int value) {
    if (value >= 1000000000000) {
      return '${(value / 1000000000000).toStringAsFixed(1)}조';
    }
    if (value >= 100000000) {
      return '${(value / 100000000).round()}억';
    }
    return NumberFormat('#,###').format(value);
  }

  Widget _perPbrLabel(String label, String value, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.35),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
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
      'KS' => ('KOSPI', const Color(0xFF3182F6)),
      'KQ' => ('KOSDAQ', const Color(0xFF00C4B4)),
      _ => ('US', const Color(0xFFF59E0B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.$2.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: info.$2.withValues(alpha: 0.4)),
      ),
      child: Text(
        info.$1,
        style: TextStyle(
          color: info.$2,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _stockActionChip({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    final fg = cs.onSurface.withValues(alpha: onTap == null ? 0.35 : 0.78);
    return Material(
      color: cs.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF10B981),
                  ),
                )
              else
                Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
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
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.38),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
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
    final accentColor = isPositive ? _kUpColor : _kDownColor;

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
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.3),
                fontSize: 10,
              ),
            ),
            Text(
              '목표까지 ${((1 - progress) * 100).toStringAsFixed(1)}% 남음',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
            Text(
              '목표가',
              style: TextStyle(
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
      style: TextStyle(
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
    final total = upCount + downCount;
    final isUp = _userVote == 'up';
    final isDown = _userVote == 'down';
    final upRatio = total > 0 ? upCount / total : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('커뮤니티 의견'),
            const Spacer(),
            if (total > 0)
              Text(
                '$total명 참여',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  Flexible(
                    flex: (upRatio * 100).round(),
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                  Flexible(
                    flex: ((1 - upRatio) * 100).round(),
                    child: Container(
                      color: const Color(0xFF1677FF).withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              flex: total > 0 ? (upRatio * 10).round().clamp(3, 7) : 5,
              child: GestureDetector(
                onTap: _currentUser == null
                    ? null
                    : () => _castVote(isUp ? null : 'up'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isUp
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isUp
                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                          : cs.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.thumb_up_outlined,
                        color: isUp
                            ? const Color(0xFF10B981)
                            : cs.onSurface.withValues(alpha: 0.38),
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '상승  $upCount',
                        style: TextStyle(
                          color: isUp
                              ? const Color(0xFF10B981)
                              : cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w700,
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
              flex: total > 0 ? ((1 - upRatio) * 10).round().clamp(3, 7) : 5,
              child: GestureDetector(
                onTap: _currentUser == null
                    ? null
                    : () => _castVote(isDown ? null : 'down'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isDown
                        ? const Color(0xFF1677FF).withValues(alpha: 0.12)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDown
                          ? const Color(0xFF1677FF).withValues(alpha: 0.4)
                          : cs.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.thumb_down_outlined,
                        color: isDown
                            ? const Color(0xFF1677FF)
                            : cs.onSurface.withValues(alpha: 0.38),
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '하락  $downCount',
                        style: TextStyle(
                          color: isDown
                              ? const Color(0xFF1677FF)
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
              style: TextStyle(
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
    final borderColor = cs.outlineVariant.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('관련 뉴스'),
        const SizedBox(height: 8),
        if (_loadingNews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF10B981),
              ),
            ),
          )
        else if (_news.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '관련 뉴스가 없습니다',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          ...List.generate(_news.length, (index) {
            final n = _news[index];
            return InkWell(
              onTap: () => launchUrl(
                Uri.parse(n.url),
                mode: LaunchMode.externalApplication,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${n.publisher} · ${timeago.format(n.publishedAt, locale: 'ko')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.open_in_new,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.32),
                        ),
                      ],
                    ),
                  ),
                  if (index != _news.length - 1)
                    Divider(height: 1, thickness: 1, color: borderColor),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── 종목토론방 ────────────────────────────────────────────────────────────
  Widget _discussionSection() {
    final cs = Theme.of(context).colorScheme;
    final borderColor = cs.outlineVariant.withValues(alpha: 0.6);
    final posts = _discussionPosts.take(10).toList();

    String formatDate(DateTime date) {
      return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('종목토론방'),
            const Spacer(),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://m.stock.naver.com/domestic/stock/${widget.pick.ticker}/discussion',
                ),
                mode: LaunchMode.externalApplication,
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '네이버 바로가기',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingDiscussion)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF10B981),
              ),
            ),
          )
        else if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '게시글이 없습니다',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          ...List.generate(posts.length, (index) {
            final post = posts[index];
            return InkWell(
              onTap: () => launchUrl(
                Uri.parse(post.mobileReadUrl),
                mode: LaunchMode.externalApplication,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${formatDate(post.date)} · 조회 ${post.viewCount}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: cs.onSurface.withValues(alpha: 0.32),
                        ),
                      ],
                    ),
                  ),
                  if (index != posts.length - 1)
                    Divider(height: 1, thickness: 1, color: borderColor),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── 투자 메모 ─────────────────────────────────────────────────────────────
  Widget _memoSection() {
    final cs = Theme.of(context).colorScheme;
    final label = _isPickMode ? '내 투자 메모' : '내 종목 메모';
    final hint = _isPickMode
        ? '이 종목에 대한 나만의 메모를 남겨보세요\n(매수 이유, 목표, 주의사항 등)'
        : '이 종목에 대한 나만의 메모를 남겨보세요\n(관심 이유, 체크할 뉴스, 주의사항 등)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _memoChanged
                  ? const Color(0xFF10B981).withValues(alpha: 0.4)
                  : cs.onSurface.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _memoController,
                style: TextStyle(
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
                  hintText: hint,
                  hintStyle: TextStyle(
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
                        backgroundColor: const Color(0xFF10B981),
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
                              style: TextStyle(fontWeight: FontWeight.w700),
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

  // ── 코멘트 목록 ──────────────────────────────────────────────────────────
  Widget _commentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<List<Comment>>(
          stream: _firestoreService.getComments(widget.pick.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('코멘트'),
                  const SizedBox(height: 10),
                  const SizedBox(
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              );
            }
            final comments = snapshot.data ?? [];
            final cs = Theme.of(context).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _sectionLabel('코멘트'),
                    const SizedBox(width: 6),
                    Text(
                      '${comments.length}',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.38),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '첫 번째 코멘트를 남겨보세요',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.24),
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ...comments.map((c) => _commentItem(c)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _commentSectionV2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<List<Comment>>(
          stream: _commentsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('댓글'),
                  const SizedBox(height: 10),
                  const SizedBox(
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              );
            }
            final comments = snapshot.data ?? [];
            final adminComments = comments
                .where((c) => AuthService.adminUids.contains(c.uid))
                .toList();
            final visibleComments = _adminCommentsOnly
                ? adminComments
                : comments;
            final cs = Theme.of(context).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _sectionLabel('댓글'),
                    const SizedBox(width: 6),
                    Text(
                      '${visibleComments.length}',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.38),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _commentFilterChip(
                      label: '전체',
                      selected: !_adminCommentsOnly,
                      onTap: () => setState(() => _adminCommentsOnly = false),
                    ),
                    const SizedBox(width: 8),
                    _commentFilterChip(
                      label: '운영자',
                      selected: _adminCommentsOnly,
                      onTap: () => setState(() => _adminCommentsOnly = true),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (visibleComments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _adminCommentsOnly
                          ? '운영자 댓글이 아직 없습니다.'
                          : '첫 번째 댓글을 남겨보세요.',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.24),
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ...visibleComments.map((c) => _commentItem(c)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _commentFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.18)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : cs.onSurface.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? const Color(0xFF10B981)
                : cs.onSurface.withValues(alpha: 0.65),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _commentItem(Comment comment) {
    final isOwn = _currentUser?.uid == comment.uid;
    final isAdmin = AuthService.adminUids.contains(_currentUser?.uid);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UserLevelAvatar(
                    uid: comment.uid,
                    radius: 10,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.07),
                    textStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.nickname,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          timeago.format(comment.createdAt, locale: 'ko'),
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isOwn || isAdmin)
                    GestureDetector(
                      onTap: _deletingCommentIds.contains(comment.id)
                          ? null
                          : () async {
                              if (_deletingCommentIds.contains(comment.id)) {
                                return;
                              }
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
                                  title: Text(
                                    '댓글 삭제',
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  content: Text(
                                    '이 댓글을 삭제하시겠습니까?',
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(
                                        '취소',
                                        style: TextStyle(
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
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                              setState(
                                () => _deletingCommentIds.add(comment.id),
                              );
                              await _firestoreService.deleteComment(
                                widget.pick.id,
                                comment.id,
                                uid: comment.uid,
                              );
                              if (mounted) {
                                setState(
                                  () => _deletingCommentIds.remove(comment.id),
                                );
                              }
                            },
                      child: _deletingCommentIds.contains(comment.id)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFF10B981),
                              ),
                            )
                          : Icon(
                              Icons.close,
                              color: cs.onSurface.withValues(alpha: 0.2),
                              size: 16,
                            ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 8),
                child: Text(
                  comment.content,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.onSurface.withValues(alpha: 0.05),
        ),
      ],
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
          style: TextStyle(
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
        bottom:
            max(
              MediaQuery.of(context).viewInsets.bottom,
              MediaQuery.of(context).padding.bottom,
            ) +
            10,
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
              style: TextStyle(color: cs.onSurface, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitComment(user),
              decoration: InputDecoration(
                hintText: '코멘트를 입력하세요...',
                hintStyle: TextStyle(
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
                color: const Color(0xFF10B981),
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
    final focusScope = FocusScope.of(context);
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
          nickname: nickname,
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      AnalyticsService.instance.logAddComment(widget.pick.ticker);
      if (mounted) {
        _commentController.clear();
        focusScope.unfocus();
      }
    } catch (_) {
      // 권한 오류 등 — 실패해도 UI 잠김 방지
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _DetailReveal extends StatefulWidget {
  const _DetailReveal({
    required this.show,
    required this.child,
    this.delayMs = 0,
  });

  final bool show;
  final Widget child;
  final int delayMs;

  @override
  State<_DetailReveal> createState() => _DetailRevealState();
}

class _DetailRevealState extends State<_DetailReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.show) _startReveal();
  }

  @override
  void didUpdateWidget(covariant _DetailReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _startReveal();
    }
  }

  Future<void> _startReveal() async {
    if (widget.delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: widget.delayMs));
    }
    if (!mounted) return;
    setState(() => _visible = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutQuart,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.05),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutQuart,
        child: AnimatedScale(
          scale: _visible ? 1 : 0.985,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutQuart,
          child: widget.child,
        ),
      ),
    );
  }
}

class _StockCandlePainter extends CustomPainter {
  final List<_OHLC> candles;
  final int? touchedIndex;
  final String Function(double) formatValue;
  final String Function(DateTime) formatDate;
  final Color labelColor;
  final List<_OHLC>? allCandles; // MA 계산용 전체 데이터
  final int visibleStart; // 전체 데이터 내 visible 시작 인덱스

  _StockCandlePainter({
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
      final isUp = c.close >= c.open;
      final baseColor = isUp ? _kUpColor : _kDownColor;
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

      final top = toY(isUp ? c.close : c.open);
      final bottom = toY(isUp ? c.open : c.close);
      final bodyH = (bottom - top).abs().clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyH),
        Paint()..color = color,
      );
    }

    // 이동평균선 (allCandles가 있을 때만)
    if (allCandles != null && allCandles!.isNotEmpty) {
      const maConfigs = [
        (5, Color(0xFFFFA726)), // MA5  - 주황
        (20, Color(0xFF42A5F5)), // MA20 - 파랑
        (60, Color(0xFFAB47BC)), // MA60 - 보라
        (120, Color(0xFFEF5350)), // MA120 - 빨강
      ];
      for (final (period, color) in maConfigs) {
        final path = Path();
        bool started = false;
        for (int i = 0; i < n; i++) {
          final g = visibleStart + i;
          if (g < period - 1) continue;
          double sum = 0;
          for (int k = g - period + 1; k <= g; k++) {
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
      old.labelColor != labelColor ||
      old.allCandles != allCandles ||
      old.visibleStart != visibleStart;
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
        final startIdx = (data.length - defaultView)
            .clamp(0, data.length)
            .toDouble();
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
    final overallIndex = fractionalIndex.floor().clamp(0, _candles.length - 1);
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
        _candles.isEmpty) {
      return;
    }
    const yAxisW = 46.0;
    final candleAreaW = chartW - yAxisW;
    final newWidth = (_rangeAtScaleStart!.width / d.scale).clamp(
      5.0,
      _candles.length.toDouble(),
    );
    final focalFraction = ((_focalPointAtScaleStart!.dx - yAxisW) / candleAreaW)
        .clamp(0.0, 1.0);
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
    if (_period.isMinute) return DateFormat('HH:mm').format(d);
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
                          padding: const EdgeInsets.only(
                            left: 8,
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
                      : SizedBox(key: const ValueKey('empty'), height: 26),
                ),
                // 차트 영역
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (ctx, constraints) {
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
                // 기간 선택 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      // 서브: 1분 / 5분 / 60분 — 위로 슬라이드
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
                      // 메인: 분봉 / 일봉 / 주봉 / 월봉
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
            // 닫기 버튼
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

  Widget _fsBtn(String label, bool active, ColorScheme cs, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF10B981)
              : cs.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : cs.onSurface.withValues(alpha: 0.6),
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
}
