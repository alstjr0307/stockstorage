import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/stock_pick.dart';
import '../services/ad_service.dart';
import '../services/ai_analysis_ad_gate.dart';
import '../services/ai_analysis_quota_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../services/stock_price_service.dart'
    show PriceResult, StockPriceService, StockSearchResult;
import '../services/subscription_service.dart';
import 'stock_ai_analysis_result_screen.dart';
import 'stock_detail_screen.dart' show stockPickFromSearchResult;
import 'stock_search_screen.dart';

/// 검색 → 광고 게이트 → AI 분석 결과 화면 으로 이어지는 새 분석 흐름.
/// 홈 카드, 리스트 화면 FAB 등 어디서든 동일 동작을 재사용한다.
Future<void> startAiAnalysisFromSearch(BuildContext context, String uid) async {
  final picked = await Navigator.push<StockSearchResult>(
    context,
    MaterialPageRoute(
      builder: (pickerCtx) => StockSearchScreen(
        title: '분석할 종목',
        subtitle: '선택하면 AI 분석을 새로 시작해요.',
        onPick: (result) => Navigator.pop<StockSearchResult>(pickerCtx, result),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;

  final passed = await AiAnalysisAdGate.run(context, uid);
  if (!passed || !context.mounted) return;

  final pick = stockPickFromSearchResult(picked);
  final analysisId = FirestoreService.favoriteStockKey(
    pick.market,
    pick.ticker,
  );
  await Navigator.push(
    context,
    MaterialPageRoute(
      settings: RouteSettings(name: 'stock-ai-analysis:$analysisId'),
      builder: (_) => StockAiAnalysisResultScreen(pick: pick, forceFresh: true),
    ),
  );
}

enum _SortMode { recent, scoreHigh, scoreLow, name }

extension _SortModeLabel on _SortMode {
  String get label => switch (this) {
    _SortMode.recent => '최신순',
    _SortMode.scoreHigh => '점수 높은순',
    _SortMode.scoreLow => '점수 낮은순',
    _SortMode.name => '종목명순',
  };
}

const _kMarketFilters = <String, String>{
  '': '전체 시장',
  'KS': 'KOSPI',
  'KQ': 'KOSDAQ',
  'US': '미국',
};

const _kScoreFilters = <String, String>{
  '': '전체 점수',
  'good': '우호적',
  'neutral': '중립',
  'bad': '주의',
};

const _kReanalyzeAfterDays = 14;

class StockAiAnalysisListScreen extends StatefulWidget {
  const StockAiAnalysisListScreen({super.key});

  @override
  State<StockAiAnalysisListScreen> createState() =>
      _StockAiAnalysisListScreenState();
}

class _StockAiAnalysisListScreenState extends State<StockAiAnalysisListScreen> {
  final _firestore = FirestoreService();
  final _searchCtrl = TextEditingController();

  _SortMode _sort = _SortMode.recent;
  String _marketFilter = '';
  String _scoreFilter = '';
  bool _searchOpen = false;
  String _query = '';
  bool _staleOnly = false;

  final Map<String, PriceResult?> _prices = {};
  final Set<String> _loadingPrices = {};

  // Firestore 스트림은 uid별로 1회만 만들어 캐시한다.
  // 매 빌드마다 새 Stream을 만들면 StreamBuilder가 ConnectionState.waiting로
  // 리셋되면서 리스트가 깜빡인다.
  String? _streamUid;
  Stream<List<StockAiAnalysisSummary>>? _analysesStream;

  Stream<List<StockAiAnalysisSummary>> _analysesStreamFor(String uid) {
    if (_streamUid != uid || _analysesStream == null) {
      _streamUid = uid;
      _analysesStream = _firestore.watchStockAiAnalyses(uid);
    }
    return _analysesStream!;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _priceKey(String market, String ticker) =>
      '${market.toUpperCase()}:${ticker.toUpperCase()}';

  void _fetchPriceIfNeeded(String market, String ticker) {
    if (ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(market.toUpperCase())) {
      return;
    }
    final key = _priceKey(market, ticker);
    if (_prices.containsKey(key) || _loadingPrices.contains(key)) return;
    _loadingPrices.add(key);
    StockPriceService.fetchPrice(ticker, market)
        .then((result) {
          if (!mounted) return;
          setState(() {
            _prices[key] = result;
            _loadingPrices.remove(key);
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _prices[key] = null;
            _loadingPrices.remove(key);
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '종목명 또는 티커 검색',
                  hintStyle: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              )
            : Text(
                'AI 분석 기록',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
        centerTitle: !_searchOpen,
        actions: [
          if (user != null && AuthService.adminUids.contains(user.uid))
            IconButton(
              tooltip: '데모 분석 추가 (관리자)',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => _seedDemoReanalysisItem(user.uid),
            ),
          IconButton(
            tooltip: _searchOpen ? '닫기' : '검색',
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
          ),
        ],
      ),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startNewAnalysisFlow(user.uid),
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.auto_awesome),
              label: const Text(
                '새로 분석',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: user == null
          ? _CenterMessage(
              icon: Icons.lock_outline,
              title: '로그인이 필요해요',
              description: '저장된 AI 분석을 보려면 로그인하세요.',
              isDark: isDark,
            )
          : _buildBody(user.uid, isDark),
    );
  }

  Widget _buildBody(String uid, bool isDark) {
    return Column(
      children: [
        _QuotaBanner(uid: uid, isDark: isDark, firestore: _firestore),
        _FilterBar(
          sort: _sort,
          market: _marketFilter,
          score: _scoreFilter,
          staleOnly: _staleOnly,
          isDark: isDark,
          onSort: (v) => setState(() => _sort = v),
          onMarket: (v) => setState(() => _marketFilter = v),
          onScore: (v) => setState(() => _scoreFilter = v),
          onStaleOnly: () => setState(() => _staleOnly = !_staleOnly),
        ),
        Expanded(
          child: StreamBuilder<List<StockAiAnalysisSummary>>(
            stream: _analysesStreamFor(uid),
            builder: (context, analysesSnap) {
              // 최초 진입 때만 스피너. 이미 데이터를 받은 뒤에는
              // 스트림이 잠깐 waiting로 돌아가도 직전 데이터를 유지해
              // 화면이 깜빡이지 않도록 한다.
              if (!analysesSnap.hasData && !analysesSnap.hasError) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                );
              }
              if (analysesSnap.hasError) {
                return _CenterMessage(
                  icon: Icons.error_outline,
                  title: '불러오지 못했어요',
                  description: '네트워크 상태를 확인하고 다시 시도해주세요.',
                  isDark: isDark,
                );
              }
              final all = analysesSnap.data ?? const <StockAiAnalysisSummary>[];
              if (all.isEmpty) {
                return _CenterMessage(
                  icon: Icons.auto_awesome,
                  title: '아직 저장된 분석이 없어요',
                  description: '아래 "새로 분석" 버튼으로 시작해보세요.',
                  isDark: isDark,
                );
              }
              final filtered = _applyFilters(all);
              if (filtered.isEmpty) {
                return _CenterMessage(
                  icon: Icons.filter_alt_off_outlined,
                  title: '조건에 맞는 분석이 없어요',
                  description: '필터나 검색어를 바꿔보세요.',
                  isDark: isDark,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                itemCount: filtered.length,
                cacheExtent: 800,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final key = _priceKey(item.market, item.ticker);
                  return _AiAnalysisCard(
                    summary: item,
                    isDark: isDark,
                    needsReanalysis: _needsReanalysis(item),
                    livePrice: _prices[key],
                    onRequestPrice: () =>
                        _fetchPriceIfNeeded(item.market, item.ticker),
                    onTap: () => _openDetail(item),
                    onDelete: () => _confirmDelete(uid, item),
                  );
                },
              );
            },
          ),
        ),
        BannerAdWidget(
          slotId: 'ai_analysis_list_bottom',
          adUnitId: AdService.aiAnalysisListBannerAdUnitId,
          fallbackAdUnitId: AdService.bannerAdUnitId,
        ),
      ],
    );
  }

  List<StockAiAnalysisSummary> _applyFilters(
    List<StockAiAnalysisSummary> input,
  ) {
    Iterable<StockAiAnalysisSummary> out = input;

    if (_staleOnly) {
      out = out.where(_needsReanalysis);
    }
    if (_marketFilter.isNotEmpty) {
      out = out.where((s) => s.market.toUpperCase() == _marketFilter);
    }
    if (_scoreFilter.isNotEmpty) {
      out = out.where((s) {
        final v = s.score;
        if (v == null) return _scoreFilter == 'bad';
        return switch (_scoreFilter) {
          'good' => v >= 70,
          'neutral' => v >= 50 && v < 70,
          'bad' => v < 50,
          _ => true,
        };
      });
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out.where(
        (s) =>
            s.name.toLowerCase().contains(q) ||
            s.ticker.toLowerCase().contains(q),
      );
    }

    final list = out.toList();
    switch (_sort) {
      case _SortMode.recent:
        list.sort((a, b) {
          final ax = a.updatedAt?.millisecondsSinceEpoch ?? 0;
          final bx = b.updatedAt?.millisecondsSinceEpoch ?? 0;
          return bx.compareTo(ax);
        });
        break;
      case _SortMode.scoreHigh:
        list.sort((a, b) {
          final ax = a.score ?? -1;
          final bx = b.score ?? -1;
          return bx.compareTo(ax);
        });
        break;
      case _SortMode.scoreLow:
        list.sort((a, b) {
          final ax = a.score ?? 1e9;
          final bx = b.score ?? 1e9;
          return ax.compareTo(bx);
        });
        break;
      case _SortMode.name:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    return list;
  }

  bool _needsReanalysis(StockAiAnalysisSummary s) {
    final t = s.updatedAt;
    if (t == null) return false;
    return DateTime.now().difference(t).inDays >= _kReanalyzeAfterDays;
  }

  /// 관리자 전용 디버그: "재분석 권장" 뱃지 확인용 더미 분석 1건 삽입.
  /// 14일 임계값보다 충분히 오래된 updatedAt(20일 전)으로 기록.
  Future<void> _seedDemoReanalysisItem(String uid) async {
    final old = DateTime.now().subtract(const Duration(days: 20));
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('stock_ai_analyses')
          .doc('KS_005930')
          .set({
            'ticker': '005930',
            'name': '삼성전자',
            'market': 'KS',
            'summary': '재분석 권장 뱃지 확인용 데모 데이터입니다.',
            'score': 58,
            'scoreLabel': '중립',
            'updatedAt': Timestamp.fromDate(old),
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('데모 분석 추가됨: 삼성전자 (20일 전 기록)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _startNewAnalysisFlow(String uid) =>
      startAiAnalysisFromSearch(context, uid);

  void _openDetail(StockAiAnalysisSummary item) {
    AdService.instance.showAiAnalysisDetailInterstitialIfReady();
    final pick = StockPick(
      id: item.analysisId,
      ticker: item.ticker,
      name: item.name,
      buyPrice: 0,
      targetPrice: 0,
      reason: '',
      category: '단기',
      market: item.market.isEmpty ? 'KS' : item.market,
      isPremium: false,
      createdAt: item.updatedAt ?? DateTime.now(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: 'stock-ai-analysis:${item.analysisId}'),
        builder: (_) => StockAiAnalysisResultScreen(pick: pick),
      ),
    );
  }

  Future<void> _confirmDelete(String uid, StockAiAnalysisSummary item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A2035) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '분석 기록 삭제',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          '${item.name.isEmpty ? item.ticker : item.name} 의 AI 분석 기록을 삭제할까요?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '취소',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
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
    if (confirmed != true) return;
    try {
      await _firestore.deleteStockAiAnalysis(uid, item.analysisId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제에 실패했어요. 다시 시도해주세요.')));
    }
  }
}

class _QuotaBanner extends StatefulWidget {
  const _QuotaBanner({
    required this.uid,
    required this.isDark,
    required this.firestore,
  });
  final String uid;
  final bool isDark;
  final FirestoreService firestore;

  @override
  State<_QuotaBanner> createState() => _QuotaBannerState();
}

class _QuotaBannerState extends State<_QuotaBanner> {
  // uid가 바뀔 때만 새로 만들고, 그 외 빌드에서는 같은 Stream 인스턴스를
  // 반환해야 StreamBuilder가 initialData로 리셋되지 않는다.
  late Stream<int> _levelStream = widget.firestore.watchPublicUserLevel(widget.uid);
  late Stream<int> _usedStream =
      AiAnalysisQuotaService.instance.watchUsedToday(widget.uid);

  @override
  void didUpdateWidget(covariant _QuotaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _levelStream = widget.firestore.watchPublicUserLevel(widget.uid);
      _usedStream = AiAnalysisQuotaService.instance.watchUsedToday(widget.uid);
    }
  }

  bool get isDark => widget.isDark;

  @override
  Widget build(BuildContext context) {
    if (!AiAnalysisAdGate.isQuotaActive) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: _levelStream,
      initialData: 1,
      builder: (context, levelSnap) {
        final level = levelSnap.data ?? 1;
        final isPremium = SubscriptionService.instance.isPremium;
        final limit = isPremium
            ? SubscriptionService.premiumDailyAiLimit
            : AiAnalysisQuotaService.dailyLimitForLevel(level);
        return StreamBuilder<int>(
          stream: _usedStream,
          initialData: 0,
          builder: (context, usedSnap) {
            final used = usedSnap.data ?? 0;
            final remaining = (limit - used).clamp(0, limit);
            final progress = limit == 0 ? 0.0 : used / limit;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A2035) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          color: Color(0xFF10B981),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '오늘 남은 AI 분석',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        RichText(
                          textAlign: TextAlign.right,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '$remaining',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                              TextSpan(
                                text: ' / $limit회',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isPremium ? 'PREMIUM' : 'Lv.$level',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sort,
    required this.market,
    required this.score,
    required this.staleOnly,
    required this.isDark,
    required this.onSort,
    required this.onMarket,
    required this.onScore,
    required this.onStaleOnly,
  });

  final _SortMode sort;
  final String market;
  final String score;
  final bool staleOnly;
  final bool isDark;
  final ValueChanged<_SortMode> onSort;
  final ValueChanged<String> onMarket;
  final ValueChanged<String> onScore;
  final VoidCallback onStaleOnly;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        children: [
          _FilterDropdown<_SortMode>(
            current: sort,
            options: {for (final m in _SortMode.values) m: m.label},
            icon: Icons.sort_rounded,
            label: sort.label,
            active: sort != _SortMode.recent,
            isDark: isDark,
            onChanged: onSort,
          ),
          const SizedBox(width: 6),
          _FilterDropdown<String>(
            current: market,
            options: _kMarketFilters,
            icon: Icons.public,
            label: _kMarketFilters[market] ?? _kMarketFilters.values.first,
            active: market.isNotEmpty,
            isDark: isDark,
            onChanged: onMarket,
          ),
          const SizedBox(width: 6),
          _FilterDropdown<String>(
            current: score,
            options: _kScoreFilters,
            icon: Icons.insights,
            label: _kScoreFilters[score] ?? _kScoreFilters.values.first,
            active: score.isNotEmpty,
            isDark: isDark,
            onChanged: onScore,
          ),
          const SizedBox(width: 6),
          _FilterToggle(
            icon: Icons.refresh_rounded,
            label: '재분석 권장',
            active: staleOnly,
            isDark: isDark,
            onTap: onStaleOnly,
          ),
        ],
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: _chipShell(
        isDark: isDark,
        icon: icon,
        label: label,
        active: active,
        showCaret: false,
      ),
    );
  }
}

PopupMenuItem<T> _styledMenuItem<T>({
  required T value,
  required String label,
  required bool selected,
  required bool isDark,
}) {
  final color = selected
      ? const Color(0xFF10B981)
      : (isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87);
  return PopupMenuItem<T>(
    value: value,
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        SizedBox(
          width: 18,
          child: selected
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Color(0xFF10B981),
                )
              : null,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ],
    ),
  );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.current,
    required this.options,
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.onChanged,
  });

  final T current;
  final Map<T, String> options;
  final IconData icon;
  final String label;
  final bool active;
  final bool isDark;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onChanged,
      color: isDark ? const Color(0xFF1A2035) : Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      itemBuilder: (_) => options.entries
          .map(
            (e) => _styledMenuItem<T>(
              value: e.key,
              label: e.value,
              selected: e.key == current,
              isDark: isDark,
            ),
          )
          .toList(),
      child: _chipShell(
        isDark: isDark,
        icon: icon,
        label: label,
        active: active,
      ),
    );
  }
}

Widget _chipShell({
  required bool isDark,
  required IconData icon,
  required String label,
  required bool active,
  bool showCaret = true,
}) {
  final bg = active
      ? const Color(0xFF10B981).withValues(alpha: 0.15)
      : isDark
      ? const Color(0xFF1A2035)
      : Colors.white;
  final fg = active
      ? const Color(0xFF10B981)
      : isDark
      ? Colors.white70
      : Colors.black87;
  final borderColor = active
      ? const Color(0xFF10B981).withValues(alpha: 0.4)
      : isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (showCaret) ...[
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 16, color: fg),
        ],
      ],
    ),
  );
}

class _AiAnalysisCard extends StatefulWidget {
  const _AiAnalysisCard({
    required this.summary,
    required this.isDark,
    required this.needsReanalysis,
    required this.livePrice,
    required this.onRequestPrice,
    required this.onTap,
    required this.onDelete,
  });

  final StockAiAnalysisSummary summary;
  final bool isDark;
  final bool needsReanalysis;
  final PriceResult? livePrice;
  final VoidCallback onRequestPrice;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_AiAnalysisCard> createState() => _AiAnalysisCardState();
}

class _AiAnalysisCardState extends State<_AiAnalysisCard> {
  @override
  void initState() {
    super.initState();
    if (widget.summary.analysisPrice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRequestPrice();
      });
    }
  }

  StockAiAnalysisSummary get summary => widget.summary;
  bool get isDark => widget.isDark;
  bool get needsReanalysis => widget.needsReanalysis;

  String get _marketLabel => switch (summary.market.toUpperCase()) {
    'KS' => 'KOSPI',
    'KQ' => 'KOSDAQ',
    'US' => 'US',
    _ => summary.market.toUpperCase(),
  };

  Color get _scoreColor {
    final s = summary.score;
    if (s == null) return const Color(0xFF64748B);
    if (s >= 70) return const Color(0xFF10B981);
    if (s >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFF04452);
  }

  String get _scoreCaption {
    final s = summary.score;
    if (s == null) return '대기';
    if (s >= 70) return '우호적';
    if (s >= 50) return '중립';
    return '주의';
  }

  ({double pct, Color color})? get _priceDiff {
    final baseline = summary.analysisPrice;
    final live = widget.livePrice?.price;
    if (baseline == null || baseline <= 0 || live == null || live <= 0) {
      return null;
    }
    final pct = (live / baseline - 1) * 100;
    final color = pct >= 0 ? const Color(0xFFF04452) : const Color(0xFF4D9BFF);
    return (pct: pct, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final updated = summary.updatedAt;
    final updatedLabel = updated == null
        ? '시간 정보 없음'
        : DateFormat('yyyy.MM.dd HH:mm').format(updated);

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onLongPress: widget.onDelete,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name.isEmpty ? summary.ticker : summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.ticker}  ·  $_marketLabel',
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.black.withValues(alpha: 0.45),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 11,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              updatedLabel,
                              style: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (_priceDiff != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _priceDiff!.color.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _priceDiff!.pct >= 0
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  size: 12,
                                  color: _priceDiff!.color,
                                ),
                                Text(
                                  '분석 후 ${_priceDiff!.pct >= 0 ? '+' : ''}${_priceDiff!.pct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: _priceDiff!.color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (needsReanalysis)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFB923C,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 10,
                                  color: Color(0xFFFB923C),
                                ),
                                SizedBox(width: 3),
                                Text(
                                  '재분석 권장',
                                  style: TextStyle(
                                    color: Color(0xFFFB923C),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ScoreRing(
                score: summary.score,
                color: _scoreColor,
                caption: _scoreCaption,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.color,
    required this.caption,
    required this.isDark,
  });

  final double? score;
  final Color color;
  final String caption;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final value = score == null ? 0.0 : score!.clamp(0, 100) / 100;
    final text = score == null ? '--' : score!.round().toString();
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 5.5,
              color: color,
              backgroundColor: trackColor,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.icon,
    required this.title,
    required this.description,
    required this.isDark,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
