import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_pick.dart';
import '../models/trading_journal.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/stock_price_service.dart';
import '../widgets/position_summary_card.dart';
import 'login_screen.dart';
import 'stock_detail_screen.dart';
import 'trading_journal_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131929) : const Color(0xFFF2F4F6),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(9999),
              ),
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.45),
              labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: '전체'),
                Tab(text: '종목별'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [TradingJournalTab(), _GroupedJournalTab()],
          ),
        ),
      ],
    );
  }
}

class _GroupedJournalTab extends StatefulWidget {
  const _GroupedJournalTab();

  @override
  State<_GroupedJournalTab> createState() => _GroupedJournalTabState();
}

class _GroupedJournalTabState extends State<_GroupedJournalTab> {
  final _fs = FirestoreService();
  final Map<String, PriceResult?> _prices = {};
  final Set<String> _loadingKeys = {};

  String _keyOf(TradingJournal journal) =>
      '${journal.market}:${journal.ticker.toUpperCase()}';

  void _fetchPriceIfNeeded(_GroupedStockJournal stock) {
    if (stock.ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(stock.market)) {
      return;
    }
    final key = '${stock.market}:${stock.ticker}';
    if (_prices.containsKey(key) || _loadingKeys.contains(key)) return;
    _loadingKeys.add(key);
    StockPriceService.fetchPrice(stock.ticker, stock.market).then((result) {
      if (!mounted) return;
      setState(() {
        _prices[key] = result;
        _loadingKeys.remove(key);
      });
    });
  }

  List<_GroupedStockJournal> _groupStocks(List<TradingJournal> journals) {
    final byStock = <String, List<TradingJournal>>{};
    for (final journal in journals) {
      final ticker = journal.ticker.trim().toUpperCase();
      if (ticker.isEmpty) continue;
      byStock
          .putIfAbsent(_keyOf(journal), () => <TradingJournal>[])
          .add(journal);
    }

    final grouped = <_GroupedStockJournal>[];
    for (final entry in byStock.entries) {
      final items = [...entry.value]
        ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
      final first = items.first;
      final buys = items.where((j) => j.action == '매수').toList();
      final sells = items.where((j) => j.action == '매도').toList();
      grouped.add(
        _GroupedStockJournal(
          stockName: first.stockName.trim().isEmpty
              ? first.ticker.toUpperCase()
              : first.stockName,
          ticker: first.ticker.toUpperCase(),
          market: first.market,
          latestTradeDate: items.first.tradeDate,
          count: items.length,
          buys: buys,
          sells: sells,
        ),
      );
    }
    grouped.sort((a, b) => b.latestTradeDate.compareTo(a.latestTradeDate));
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) return _NotLoggedIn();

    final cs = Theme.of(context).colorScheme;
    final uid = auth.user!.uid;

    return StreamBuilder<List<TradingJournal>>(
      stream: _fs.getMyJournals(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF10B981)),
          );
        }

        final journals = snapshot.data ?? [];
        final grouped = _groupStocks(journals);
        for (final stock in grouped) {
          _fetchPriceIfNeeded(stock);
        }
        final livePrices = <String, double>{};
        for (final entry in _prices.entries) {
          final value = entry.value;
          if (value != null) {
            livePrices[entry.key] = value.price;
          }
        }
        final holdingStocks = grouped
            .where((s) => s.remainingQty > 1e-6)
            .toList();
        final completedStocks = grouped
            .where((s) => s.remainingQty <= 1e-6)
            .toList();

        if (grouped.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  color: cs.onSurface.withValues(alpha: 0.2),
                  size: 56,
                ),
                const SizedBox(height: 12),
                Text(
                  '종목별 매매일지가 없습니다',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        Widget sectionHeader(String title, int count, {bool dim = false}) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: dim ? 0.48 : 0.82),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: dim ? 0.05 : 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: dim ? 0.45 : 0.72),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget stockRow(_GroupedStockJournal stock) {
          final price = _prices['${stock.market}:${stock.ticker}'];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TradingJournalTab(
                  filterTicker: stock.ticker,
                  filterStockName: stock.stockName,
                  pageTitle: stock.stockName,
                ),
              ),
            ),
            child: _GroupedStockRow(stock: stock, price: price),
          );
        }

        final children = <Widget>[
          PositionSummaryCard(
            journals: journals,
            livePrices: livePrices,
            margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
          ),
          if (holdingStocks.isNotEmpty) ...[
            sectionHeader('보유중 종목', holdingStocks.length),
            for (final stock in holdingStocks) ...[
              stockRow(stock),
              const SizedBox(height: 8),
            ],
          ],
          if (holdingStocks.isNotEmpty && completedStocks.isNotEmpty)
            const SizedBox(height: 14),
          if (completedStocks.isNotEmpty) ...[
            sectionHeader('완료 종목', completedStocks.length, dim: true),
            for (final stock in completedStocks) ...[
              stockRow(stock),
              const SizedBox(height: 8),
            ],
          ],
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: children,
        );
      },
    );
  }
}

class _GroupedStockJournal {
  final String stockName;
  final String ticker;
  final String market;
  final DateTime latestTradeDate;
  final int count;
  final List<TradingJournal> buys;
  final List<TradingJournal> sells;

  const _GroupedStockJournal({
    required this.stockName,
    required this.ticker,
    required this.market,
    required this.latestTradeDate,
    required this.count,
    required this.buys,
    required this.sells,
  });

  double get remainingQty {
    final buyQty = buys.fold<double>(0, (sum, b) => sum + b.quantity);
    final sellQty = sells.fold<double>(0, (sum, s) => sum + s.quantity);
    return (buyQty - sellQty).clamp(0.0, buyQty);
  }

  double get avgRemainingPrice {
    final buysAsc = [...buys]
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    var soldLeft = sells.fold<double>(0, (sum, s) => sum + s.quantity);
    var qty = 0.0;
    var cost = 0.0;
    for (final buy in buysAsc) {
      final consumed = soldLeft > buy.quantity ? buy.quantity : soldLeft;
      final remain = (buy.quantity - consumed).clamp(0.0, buy.quantity);
      qty += remain;
      cost += remain * buy.price;
      soldLeft = soldLeft > consumed ? soldLeft - consumed : 0.0;
    }
    if (qty <= 1e-6) return 0;
    return cost / qty;
  }

  double get avgBuyPrice {
    final totalQty = buys.fold<double>(0, (sum, b) => sum + b.quantity);
    if (totalQty <= 1e-6) return 0;
    final totalCost = buys.fold<double>(
      0,
      (sum, b) => sum + (b.price * b.quantity),
    );
    return totalCost / totalQty;
  }

  double get avgSellPrice {
    final totalQty = sells.fold<double>(0, (sum, s) => sum + s.quantity);
    if (totalQty <= 1e-6) return 0;
    final totalAmount = sells.fold<double>(
      0,
      (sum, s) => sum + (s.price * s.quantity),
    );
    return totalAmount / totalQty;
  }

  double realizedPnl() {
    double avgBuyPriceAt(DateTime sellDate) {
      var qty = 0.0;
      var cost = 0.0;
      for (final buy in buys) {
        if (!buy.tradeDate.isAfter(sellDate)) {
          qty += buy.quantity;
          cost += buy.price * buy.quantity;
        }
      }
      return qty > 0 ? cost / qty : 0;
    }

    return sells.fold<double>(0, (sum, sell) {
      final bp = sell.buyPrice > 0
          ? sell.buyPrice
          : avgBuyPriceAt(sell.tradeDate);
      if (bp <= 0 || sell.price <= 0 || sell.quantity <= 0) return sum;
      return sum + (sell.price - bp) * sell.quantity;
    });
  }
}

class _GroupedStockRow extends StatelessWidget {
  final _GroupedStockJournal stock;
  final PriceResult? price;

  const _GroupedStockRow({required this.stock, required this.price});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isKrw = stock.market != 'US';
    final remainingQty = stock.remainingQty;
    final avgPrice = stock.avgRemainingPrice;
    final livePrice = price?.price;
    final hasHolding = remainingQty > 1e-6;
    final evalPnl = hasHolding && livePrice != null && avgPrice > 0
        ? (livePrice - avgPrice) * remainingQty
        : null;
    final evalRate = evalPnl != null
        ? (livePrice! - avgPrice) / avgPrice * 100
        : null;
    final realizedPnl = stock.realizedPnl();
    final displayPnl = evalPnl ?? realizedPnl;
    final isUp = displayPnl >= 0;
    final color = isUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);
    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';
    String fmtQty(double q) => q % 1 == 0 ? '${q.toInt()}주' : '$q주';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stock.stockName,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (hasHolding)
                  Text(
                    '보유 ${fmtQty(remainingQty)} · 평균단가 ${fmtP(avgPrice)}',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasHolding ? '평가손익' : '실현손익',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.35),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${isUp ? '+' : ''}${fmtP(displayPnl)}',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (hasHolding)
                Text(
                  evalRate != null
                      ? '${isUp ? '+' : ''}${evalRate.toStringAsFixed(1)}%'
                      : '-',
                  style: TextStyle(
                    color: (evalRate != null ? color : cs.onSurface).withValues(
                      alpha: 0.72,
                    ),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                const SizedBox(height: 14),
            ],
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withValues(alpha: 0.32),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class FavoritesPicksScreen extends StatelessWidget {
  const FavoritesPicksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('관심 추천주', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _FavoritesTab(),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) {
      return _NotLoggedIn();
    }
    return _PortfolioContent(uid: auth.user!.uid);
  }
}

class _NotLoggedIn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_circle_outlined,
            color: cs.onSurface.withValues(alpha: 0.2),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            '로그인이 필요합니다',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '추천주를 추가하고 수익률을 확인하세요',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.25),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: Text('로그인', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _PortfolioContent extends StatefulWidget {
  final String uid;
  const _PortfolioContent({required this.uid});

  @override
  State<_PortfolioContent> createState() => _PortfolioContentState();
}

class _PortfolioContentState extends State<_PortfolioContent> {
  final _firestoreService = FirestoreService();
  final Map<String, PriceResult?> _prices = {};
  final Set<String> _loadingIds = {};
  final GlobalKey _shareCardKey = GlobalKey();
  final bool _capturing = false;

  void _fetchPriceIfNeeded(StockPick pick) {
    if (_loadingIds.contains(pick.id) || _prices.containsKey(pick.id)) return;
    _loadingIds.add(pick.id);
    StockPriceService.fetchPrice(pick.ticker, pick.market).then((result) {
      if (mounted) {
        setState(() {
          _prices[pick.id] = result;
          _loadingIds.remove(pick.id);
        });
        if (result != null) {
          final returnRate =
              ((result.price - pick.buyPrice) / pick.buyPrice) * 100;
          _checkAlertThreshold(pick, returnRate);
        }
      }
    });
  }

  Future<void> _checkAlertThreshold(StockPick pick, double returnRate) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'portfolio_alert_${pick.id}';
    final lastThreshold = prefs.getInt(key) ?? 0;
    final currentThreshold = (returnRate / 10).truncate().toInt() * 10;

    if (currentThreshold != 0 && currentThreshold != lastThreshold) {
      await prefs.setInt(key, currentThreshold);
      await NotificationService.showPortfolioAlert(pick.name, returnRate);
    }
  }

  Future<void> _shareCard(
    int total,
    int positive,
    int withPrice,
    double avgReturn,
    List<StockPick> picks,
  ) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ShareCardSheet(
        shareCardKey: _shareCardKey,
        total: total,
        positive: positive,
        withPrice: withPrice,
        avgReturn: avgReturn,
        picks: picks,
        prices: Map.from(_prices),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<String>>(
      stream: _firestoreService.getFavoriteIds(widget.uid),
      builder: (context, favSnapshot) {
        final favIds = favSnapshot.data?.toSet() ?? <String>{};

        return StreamBuilder<List<StockPick>>(
          stream: _firestoreService.getStockPicks(),
          builder: (context, picksSnapshot) {
            if (picksSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF10B981)),
              );
            }

            final allPicks = picksSnapshot.data ?? [];
            final favPicks = allPicks
                .where((p) => favIds.contains(p.id))
                .toList();

            for (final pick in favPicks) {
              _fetchPriceIfNeeded(pick);
            }

            if (favPicks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      color: cs.onSurface.withValues(alpha: 0.2),
                      size: 52,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '추천주를 추가해보세요',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.4),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '종목 카드의 ♡ 버튼을 눌러 추가',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.25),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Aggregate stats
            final withPrice = favPicks
                .where((p) => _prices[p.id] != null)
                .toList();
            double totalReturn = 0;
            int positiveCount = 0;
            for (final p in withPrice) {
              final ret =
                  ((_prices[p.id]!.price - p.buyPrice) / p.buyPrice) * 100;
              totalReturn += ret;
              if (ret > 0) positiveCount++;
            }
            final avgReturn = withPrice.isEmpty
                ? 0.0
                : totalReturn / withPrice.length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
              children: [
                _buildStatsHeader(
                  context,
                  favPicks.length,
                  positiveCount,
                  withPrice.length,
                  avgReturn,
                  favPicks,
                ),
                const SizedBox(height: 20),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.onSurface.withValues(alpha: 0.07),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < favPicks.length; i++) ...[
                  _buildPickCard(context, favPicks[i]),
                  if (i < favPicks.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.onSurface.withValues(alpha: 0.07),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatsHeader(
    BuildContext context,
    int total,
    int positive,
    int withPrice,
    double avgReturn,
    List<StockPick> picks,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = avgReturn >= 0;
    final avgColor = isPositive
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFF04452),
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              '관심추천주 현황',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _capturing
                  ? null
                  : () => _shareCard(
                      total,
                      positive,
                      withPrice,
                      avgReturn,
                      picks,
                    ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded, size: 14),
              label: Text(
                '공유',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _statItem(
                context,
                '추천주 평균 수익률',
                withPrice == 0
                    ? '--'
                    : '${isPositive ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
                avgColor,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: cs.onSurface.withValues(alpha: 0.1),
            ),
            Expanded(
              child: _statItem(
                context,
                '수익 중',
                '$positive개',
                const Color(0xFFF04452),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: cs.onSurface.withValues(alpha: 0.1),
            ),
            Expanded(
              child: _statItem(
                context,
                '손실 중',
                '${withPrice - positive}개',
                const Color(0xFF1677FF),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statItem(
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

  Widget _buildPickCard(BuildContext context, StockPick pick) {
    final cs = Theme.of(context).colorScheme;
    final priceResult = _prices[pick.id];
    final isLoading = _loadingIds.contains(pick.id) && priceResult == null;
    final livePrice = priceResult?.price;
    final returnRate = livePrice != null
        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
        : pick.returnRate;
    final isPositive = returnRate >= 0;
    final isKrw = pick.market != 'US';

    String formatPrice(double p) {
      if (isKrw) return '₩${NumberFormat('#,###').format(p.toInt())}';
      return '\$${p.toStringAsFixed(2)}';
    }

    return InkWell(
      onTap: () => Navigator.push(context, stockDetailRoute(pick)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                pick.ticker,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pick.name,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '매수 ${formatPrice(pick.buyPrice)}',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ] else if (livePrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '현재 ${formatPrice(livePrice)}',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPositive
                    ? const Color(0xFFF04452).withValues(alpha: 0.12)
                    : const Color(0xFF1677FF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: isPositive
                      ? const Color(0xFFF04452)
                      : const Color(0xFF1677FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 공유 카드 바텀시트 ───────────────────────────────────────────────────────

class _ShareCardSheet extends StatefulWidget {
  final GlobalKey shareCardKey;
  final int total;
  final int positive;
  final int withPrice;
  final double avgReturn;
  final List<StockPick> picks;
  final Map<String, PriceResult?> prices;

  const _ShareCardSheet({
    required this.shareCardKey,
    required this.total,
    required this.positive,
    required this.withPrice,
    required this.avgReturn,
    required this.picks,
    required this.prices,
  });

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  bool _sharing = false;

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  Future<void> _captureAndShare() async {
    setState(() => _sharing = true);
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      final boundary =
          widget.shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final file = File(
        '${Directory.systemTemp.path}/portfolio_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '📊 주식저장소 관심추천주 현황',
        sharePositionOrigin: _shareOrigin(),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = widget.avgReturn >= 0;
    final sign = isPositive ? '+' : '';
    final color = isPositive
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // 공유 카드 (캡처 대상)
          RepaintBoundary(
            key: widget.shareCardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '주식저장소',
                            style: TextStyle(
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        DateFormat('yyyy.MM.dd').format(DateTime.now()),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // 추천주 평균 수익률 (메인)
                  Text(
                    '추천주 평균 수익률',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.withPrice == 0
                        ? '--'
                        : '$sign${widget.avgReturn.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 42,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 구분선
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 20),
                  // 통계 3개
                  Row(
                    children: [
                      _shareStatItem('보유 종목', '${widget.total}개', Colors.white),
                      _shareStatItem(
                        '수익 중',
                        '${widget.positive}개',
                        const Color(0xFFF04452),
                      ),
                      _shareStatItem(
                        '손실 중',
                        '${widget.withPrice - widget.positive}개',
                        const Color(0xFF1677FF),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 종목 리스트
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 12),
                  ...widget.picks.map((pick) {
                    final priceResult = widget.prices[pick.id];
                    final livePrice = priceResult?.price;
                    final returnRate = livePrice != null
                        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
                        : pick.returnRate;
                    final isPos = returnRate >= 0;
                    final retColor = isPos
                        ? const Color(0xFFF04452)
                        : const Color(0xFF1677FF);
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        final navigator = Navigator.of(
                          context,
                          rootNavigator: true,
                        );
                        Navigator.pop(context);
                        navigator.push(stockDetailRoute(pick));
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pick.ticker,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pick.name,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${isPos ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: retColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // 하단 워터마크
                  Center(
                    child: Text(
                      '주식저장소 앱에서 확인하세요',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 공유 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _captureAndShare,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: const Color(
                  0xFF10B981,
                ).withValues(alpha: 0.4),
              ),
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(
                _sharing ? '처리 중...' : '이미지로 공유',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
