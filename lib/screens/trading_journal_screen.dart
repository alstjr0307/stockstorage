import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/stock_pick.dart';
import '../models/trading_journal.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import '../widgets/position_summary_card.dart';
import '../widgets/stock_search_field.dart';
import 'login_screen.dart';
import 'journal_chart_screen.dart';

const _kQtyEpsilon = 1e-6;

/// 매도 시점(sellDate) 이전 매수들의 가중평균 단가를 반환
double _avgBuyPriceAt(List<TradingJournal> buys, DateTime sellDate) {
  double qty = 0, cost = 0;
  for (final b in buys) {
    if (!b.tradeDate.isAfter(sellDate)) {
      qty += b.quantity;
      cost += b.price * b.quantity;
    }
  }
  return qty > 0 ? cost / qty : 0;
}

class TradingJournalTab extends StatelessWidget {
  final String? filterTicker;
  final String? filterStockName;
  final String? pageTitle;

  const TradingJournalTab({
    super.key,
    this.filterTicker,
    this.filterStockName,
    this.pageTitle,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) {
      return _NotLoggedIn();
    }
    return _JournalContent(
      uid: auth.user!.uid,
      filterTicker: filterTicker,
      filterStockName: filterStockName,
      pageTitle: pageTitle,
    );
  }
}

class _ExpandableNotePreview extends StatefulWidget {
  final String content;
  final TextStyle style;
  final int maxLines;

  const _ExpandableNotePreview({
    required this.content,
    required this.style,
    this.maxLines = 3,
  });

  @override
  State<_ExpandableNotePreview> createState() => _ExpandableNotePreviewState();
}

class _ExpandableNotePreviewState extends State<_ExpandableNotePreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.content, style: widget.style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final hasOverflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.content,
              style: widget.style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (hasOverflow && !_expanded) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Text(
                  '더보기',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
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
            Icons.book_outlined,
            color: cs.onSurface.withValues(alpha: 0.2),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            '로그인이 필요합니다',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: Text(
              '로그인',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalContent extends StatefulWidget {
  final String uid;
  final String? filterTicker;
  final String? filterStockName;
  final String? pageTitle;

  const _JournalContent({
    required this.uid,
    this.filterTicker,
    this.filterStockName,
    this.pageTitle,
  });

  @override
  State<_JournalContent> createState() => _JournalContentState();
}

class _JournalContentState extends State<_JournalContent> {
  final _firestoreService = FirestoreService();

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _openForm({
    TradingJournal? existing,
    TradingJournal? linkedBuy,
    double remainingQty = 0,
    String? initialAction,
    String? initialStockName,
    String? initialTicker,
    String? initialRawMarket,
  }) async {
    final nickname = await _firestoreService.getNickname(widget.uid) ?? '익명';
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JournalFormSheet(
        uid: widget.uid,
        nickname: nickname,
        existing: existing,
        firestoreService: _firestoreService,
        initialLinkedBuyJournal: linkedBuy,
        initialRemainingQty: remainingQty,
        initialAction: initialAction,
        initialStockName: initialStockName,
        initialTicker: initialTicker,
        initialRawMarket: initialRawMarket,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: widget.pageTitle == null
          ? null
          : AppBar(
              backgroundColor: bg,
              elevation: 0,
              title: Text(
                widget.pageTitle!,
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'journal_add_fab',
        onPressed: _openForm,
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<TradingJournal>>(
        stream: _firestoreService.getMyJournals(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            );
          }
          final rawJournals = snapshot.data ?? [];
          final filterTicker = widget.filterTicker?.trim().toUpperCase();
          final journals = (filterTicker == null || filterTicker.isEmpty)
              ? rawJournals
              : rawJournals
                    .where((j) => j.ticker.toUpperCase() == filterTicker)
                    .toList();
          if (journals.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_note_outlined,
                    color: cs.onSurface.withValues(alpha: 0.2),
                    size: 60,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (filterTicker != null && filterTicker.isNotEmpty)
                        ? '${widget.filterStockName ?? filterTicker} 매매일지가 없습니다'
                        : '매매일지를 작성해보세요',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (filterTicker != null && filterTicker.isNotEmpty)
                        ? '전체보기에서 다른 종목을 확인해보세요'
                        : '우하단 + 버튼으로 추가',
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.25),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }
          final isStockDetail = filterTicker != null && filterTicker.isNotEmpty;

          Future<void> onDeleteLinkedSell(TradingJournal sell) async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('매도 내역 삭제'),
                content: const Text('이 매도 내역을 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      '삭제',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await _firestoreService.deleteJournal(sell.id);
            }
          }

          if (!isStockDetail) {
            final timeline = [...journals]
              ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
            final availableDates = <DateTime>[];
            for (final item in timeline) {
              final day = _dateOnly(item.tradeDate);
              if (!availableDates.any((d) => _isSameDay(d, day))) {
                availableDates.add(day);
              }
            }
            final buysByStock = <String, List<TradingJournal>>{};
            final sellsByStock = <String, List<TradingJournal>>{};
            for (final item in journals) {
              if (item.ticker.isEmpty) continue;
              final key = '${item.market}:${item.ticker}';
              if (item.action == '매수') {
                buysByStock
                    .putIfAbsent(key, () => <TradingJournal>[])
                    .add(item);
              } else if (item.action == '매도') {
                sellsByStock
                    .putIfAbsent(key, () => <TradingJournal>[])
                    .add(item);
              }
            }
            for (final buys in buysByStock.values) {
              buys.sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
            }
            for (final sells in sellsByStock.values) {
              sells.sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
              children: [
                _JournalOverviewSection(journals: journals),
                _JournalDateSection(
                  timeline: timeline,
                  buysByStock: buysByStock,
                  sellsByStock: sellsByStock,
                  firestoreService: _firestoreService,
                  onEdit: (j) => _openForm(existing: j),
                  onEditLinkedSell: (sell) => _openForm(existing: sell),
                  onDeleteLinkedSell: onDeleteLinkedSell,
                ),
              ],
            );
          }

          final buys = journals.where((j) => j.action == '매수').toList()
            ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
          final linkedSells = journals.where((j) => j.action == '매도').toList()
            ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
          final representative = ([
            ...journals,
          ]..sort((a, b) => b.tradeDate.compareTo(a.tradeDate))).first;

          return _StockJournalDetailView(
            representative: representative,
            journals: journals,
            buys: buys,
            sells: linkedSells,
            firestoreService: _firestoreService,
            onEdit: (journal) => _openForm(existing: journal),
            onAddBuy: () => _openForm(
              initialAction: '매수',
              initialStockName: representative.stockName,
              initialTicker: representative.ticker,
              initialRawMarket: representative.market,
            ),
            onAddSell: () => _openForm(
              initialAction: '매도',
              initialStockName: representative.stockName,
              initialTicker: representative.ticker,
              initialRawMarket: representative.market,
            ),
            onSellQuick: (buy, remainingQty) =>
                _openForm(linkedBuy: buy, remainingQty: remainingQty),
            onDeleteSell: onDeleteLinkedSell,
          );
        },
      ),
    );
  }
}

class _StockJournalDetailView extends StatefulWidget {
  final TradingJournal representative;
  final List<TradingJournal> journals;
  final List<TradingJournal> buys;
  final List<TradingJournal> sells;
  final FirestoreService firestoreService;
  final void Function(TradingJournal journal) onEdit;
  final VoidCallback onAddBuy;
  final VoidCallback onAddSell;
  final void Function(TradingJournal buy, double remainingQty) onSellQuick;
  final void Function(TradingJournal sell) onDeleteSell;

  const _StockJournalDetailView({
    required this.representative,
    required this.journals,
    required this.buys,
    required this.sells,
    required this.firestoreService,
    required this.onEdit,
    required this.onAddBuy,
    required this.onAddSell,
    required this.onSellQuick,
    required this.onDeleteSell,
  });

  @override
  State<_StockJournalDetailView> createState() =>
      _StockJournalDetailViewState();
}

class _StockJournalDetailViewState extends State<_StockJournalDetailView> {
  PriceResult? _price;
  bool _loadingPrice = false;
  String _tab = 'record';

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  @override
  void didUpdateWidget(covariant _StockJournalDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.representative.ticker != widget.representative.ticker ||
        oldWidget.representative.market != widget.representative.market) {
      _loadPrice();
    }
  }

  Future<void> _loadPrice() async {
    final ticker = widget.representative.ticker;
    final market = widget.representative.market;
    if (ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(market)) return;
    setState(() => _loadingPrice = true);
    final result = await StockPriceService.fetchPrice(ticker, market);
    if (!mounted) return;
    setState(() {
      _price = result;
      _loadingPrice = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = [...widget.journals]
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
    final position = _StockPositionMetrics.from(
      buys: widget.buys,
      sells: widget.sells,
      price: _price,
    );
    final tabBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF131929)
        : const Color(0xFFEEF2F7);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        _StockHoldingStatusCard(
          stock: widget.representative,
          metrics: position,
          loadingPrice: _loadingPrice,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: tabBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _DetailTabChip(
                label: '기록',
                selected: _tab == 'record',
                onTap: () => setState(() => _tab = 'record'),
              ),
              _DetailTabChip(
                label: '차트',
                selected: _tab == 'chart',
                onTap: () => setState(() => _tab = 'chart'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _tab == 'record'
              ? _StockTradeRecordsCard(
                  key: const ValueKey('record'),
                  events: events,
                  buys: widget.buys,
                  firestoreService: widget.firestoreService,
                  onEdit: widget.onEdit,
                  onDeleteSell: widget.onDeleteSell,
                )
              : _StockChartCard(
                  key: const ValueKey('chart'),
                  stock: widget.representative,
                  buys: widget.buys,
                  sells: widget.sells,
                  firestoreService: widget.firestoreService,
                  currentPrice: position.currentPrice,
                  hasLivePrice: position.hasLivePrice,
                ),
        ),
        const SizedBox(height: 14),
        _TradeAddActionsCard(
          onAddBuy: widget.onAddBuy,
          onAddSell: () {
            final quickBuy = position.quickSellBuy;
            if (quickBuy != null && position.quickSellQty > _kQtyEpsilon) {
              widget.onSellQuick(quickBuy, position.quickSellQty);
              return;
            }
            widget.onAddSell();
          },
        ),
      ],
    );
  }
}

class _DetailTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DetailTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: selected
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.35),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StockPositionMetrics {
  final double totalBuyQty;
  final double remainingQty;
  final double avgBuyPrice;
  final double currentPrice;
  final double evalAmount;
  final double evalPnl;
  final double? evalPnlRate;
  final double realizedPnl;
  final TradingJournal? quickSellBuy;
  final double quickSellQty;
  final bool hasLivePrice;

  const _StockPositionMetrics({
    required this.totalBuyQty,
    required this.remainingQty,
    required this.avgBuyPrice,
    required this.currentPrice,
    required this.evalAmount,
    required this.evalPnl,
    required this.evalPnlRate,
    required this.realizedPnl,
    required this.quickSellBuy,
    required this.quickSellQty,
    required this.hasLivePrice,
  });

  factory _StockPositionMetrics.from({
    required List<TradingJournal> buys,
    required List<TradingJournal> sells,
    PriceResult? price,
  }) {
    final buysAsc = [...buys]
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    final remainingByBuyId = <String, double>{};
    var soldLeft = sells.fold<double>(0, (sum, s) => sum + s.quantity);
    var remainingQty = 0.0;
    var remainingCost = 0.0;
    for (final buy in buysAsc) {
      final consumed = soldLeft > buy.quantity ? buy.quantity : soldLeft;
      final remain = (buy.quantity - consumed).clamp(0.0, buy.quantity);
      remainingByBuyId[buy.id] = remain;
      remainingQty += remain;
      remainingCost += buy.price * remain;
      soldLeft = soldLeft > consumed ? soldLeft - consumed : 0.0;
    }

    final totalBuyQty = buys.fold<double>(0, (sum, b) => sum + b.quantity);
    final avgBuyPrice = remainingQty > _kQtyEpsilon
        ? remainingCost / remainingQty
        : (totalBuyQty > _kQtyEpsilon
              ? buys.fold<double>(0, (sum, b) => sum + b.price * b.quantity) /
                    totalBuyQty
              : 0.0);
    final currentPrice = price?.price ?? avgBuyPrice;
    final evalAmount = currentPrice * remainingQty;
    final evalPnl = (currentPrice - avgBuyPrice) * remainingQty;
    final evalPnlRate = avgBuyPrice > 0 && remainingQty > _kQtyEpsilon
        ? (currentPrice - avgBuyPrice) / avgBuyPrice * 100
        : null;

    var realizedPnl = 0.0;
    final buysForAvg = [...buys]
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    for (final sell in sells) {
      final bp = sell.buyPrice > 0
          ? sell.buyPrice
          : _avgBuyPriceAt(buysForAvg, sell.tradeDate);
      if (bp > 0 && sell.price > 0 && sell.quantity > 0) {
        realizedPnl += (sell.price - bp) * sell.quantity;
      }
    }

    TradingJournal? quickSellBuy;
    var quickSellQty = 0.0;
    for (final buy in buysAsc.reversed) {
      final remain = remainingByBuyId[buy.id] ?? 0.0;
      if (remain > _kQtyEpsilon) {
        quickSellBuy = buy;
        quickSellQty = remain;
        break;
      }
    }

    return _StockPositionMetrics(
      totalBuyQty: totalBuyQty,
      remainingQty: remainingQty,
      avgBuyPrice: avgBuyPrice,
      currentPrice: currentPrice,
      evalAmount: evalAmount,
      evalPnl: evalPnl,
      evalPnlRate: evalPnlRate,
      realizedPnl: realizedPnl,
      quickSellBuy: quickSellBuy,
      quickSellQty: quickSellQty,
      hasLivePrice: price != null,
    );
  }
}

class _StockHoldingStatusCard extends StatelessWidget {
  final TradingJournal stock;
  final _StockPositionMetrics metrics;
  final bool loadingPrice;

  const _StockHoldingStatusCard({
    required this.stock,
    required this.metrics,
    required this.loadingPrice,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isKrw = stock.market != 'US';
    final isHolding = metrics.remainingQty > _kQtyEpsilon;
    final pnlUp = metrics.evalPnl >= 0;
    final realizedUp = metrics.realizedPnl >= 0;
    final pnlColor = pnlUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);
    final realizedColor = realizedUp
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';
    String fmtQty(double q) => q % 1 == 0 ? '${q.toInt()}주' : '$q주';

    Widget statRow(
      String label,
      String value, {
      Color? valueColor,
      bool last = false,
      String? sub,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: last
                ? BorderSide.none
                : BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: GoogleFonts.robotoMono(
                    color: valueColor ?? Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: GoogleFonts.robotoMono(
                      color: (valueColor ?? Colors.white).withValues(
                        alpha: 0.75,
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '실현손익',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '${realizedUp ? '+' : ''}${fmtP(metrics.realizedPnl)}',
                      style: GoogleFonts.robotoMono(
                        color: realizedColor,
                        fontSize: 32,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isHolding
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF667085))
                              .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color:
                            (isHolding
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF667085))
                                .withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      isHolding ? '보유중' : '완료',
                      style: GoogleFonts.inter(
                        color: isHolding
                            ? const Color(0xFF34D399)
                            : Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          decoration: BoxDecoration(
            color: const Color(0xFF131929),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              statRow('평균단가', fmtP(metrics.avgBuyPrice)),
              statRow(
                '현재가',
                metrics.hasLivePrice ? fmtP(metrics.currentPrice) : '-',
                valueColor: metrics.hasLivePrice ? pnlColor : Colors.white54,
                sub: loadingPrice ? '불러오는 중' : null,
              ),
              statRow('수량', fmtQty(metrics.remainingQty)),
              statRow('평가금액', fmtP(metrics.evalAmount)),
              statRow(
                '수익률',
                metrics.evalPnlRate == null
                    ? '—'
                    : '${pnlUp ? '+' : ''}${metrics.evalPnlRate!.toStringAsFixed(2)}%',
                valueColor: metrics.evalPnlRate == null
                    ? Colors.white38
                    : pnlColor,
              ),
              statRow(
                '평가손익',
                '${pnlUp ? '+' : ''}${fmtP(metrics.evalPnl)}',
                valueColor: pnlColor,
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockTradeRecordsCard extends StatelessWidget {
  final List<TradingJournal> events;
  final List<TradingJournal> buys;
  final FirestoreService firestoreService;
  final void Function(TradingJournal journal) onEdit;
  final void Function(TradingJournal sell) onDeleteSell;

  const _StockTradeRecordsCard({
    super.key,
    required this.events,
    required this.buys,
    required this.firestoreService,
    required this.onEdit,
    required this.onDeleteSell,
  });

  @override
  Widget build(BuildContext context) {
    final isKrw = events.firstOrNull?.market != 'US';
    final buysAsc = [...buys]
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';
    String fmtQty(double q) => q % 1 == 0 ? '${q.toInt()}주' : '$q주';
    final grouped = <String, List<TradingJournal>>{};
    for (final trade in events) {
      final dateKey = DateFormat('yyyy.MM.dd').format(trade.tradeDate);
      grouped.putIfAbsent(dateKey, () => <TradingJournal>[]).add(trade);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '매매기록',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${events.length}건',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Row(
              children: [
                Text(
                  entry.key,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          for (final journal in entry.value)
            _StockTradeRow(
              journal: journal,
              buyAvgPrice: journal.action == '매도'
                  ? (journal.buyPrice > 0
                        ? journal.buyPrice
                        : _avgBuyPriceAt(buysAsc, journal.tradeDate))
                  : null,
              fmtP: fmtP,
              fmtQty: fmtQty,
              onEdit: () => onEdit(journal),
              onDelete: journal.action == '매도'
                  ? () => onDeleteSell(journal)
                  : null,
            ),
        ],
      ],
    );
  }
}

class _StockTradeRow extends StatelessWidget {
  final TradingJournal journal;
  final double? buyAvgPrice;
  final String Function(double value) fmtP;
  final String Function(double value) fmtQty;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _StockTradeRow({
    required this.journal,
    required this.buyAvgPrice,
    required this.fmtP,
    required this.fmtQty,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = journal.action == '매수';
    final color = isBuy ? const Color(0xFF10B981) : const Color(0xFFF04452);
    double? realizedPnl;
    if (!isBuy &&
        buyAvgPrice != null &&
        buyAvgPrice! > 0 &&
        journal.price > 0 &&
        journal.quantity > 0) {
      realizedPnl = (journal.price - buyAvgPrice!) * journal.quantity;
    }
    final pnlUp = realizedPnl == null || realizedPnl >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.045)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.24)),
            ),
            child: Text(
              journal.action,
              style: GoogleFonts.robotoMono(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtP(journal.price),
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtQty(journal.quantity)} · ${NumberFormat('#,###').format((journal.price * journal.quantity).toInt())}원',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (realizedPnl != null) ...[
            Text(
              '${pnlUp ? '+' : ''}${fmtP(realizedPnl)}',
              style: GoogleFonts.robotoMono(
                color: pnlUp
                    ? const Color(0xFFF04452)
                    : const Color(0xFF1677FF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            tooltip: '매매기록 메뉴',
            icon: Icon(
              Icons.more_vert,
              size: 18,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            color: const Color(0xFF1A2235),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete?.call();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('수정')),
              if (onDelete != null)
                const PopupMenuItem(value: 'delete', child: Text('삭제')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockChartCard extends StatelessWidget {
  final TradingJournal stock;
  final List<TradingJournal> buys;
  final List<TradingJournal> sells;
  final FirestoreService firestoreService;
  final double currentPrice;
  final bool hasLivePrice;

  const _StockChartCard({
    super.key,
    required this.stock,
    required this.buys,
    required this.sells,
    required this.firestoreService,
    required this.currentPrice,
    required this.hasLivePrice,
  });

  @override
  Widget build(BuildContext context) {
    final isKrw = stock.market != 'US';
    final canOpenChart =
        stock.ticker.isNotEmpty && {'KS', 'KQ', 'US'}.contains(stock.market);
    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '주가 차트',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasLivePrice ? '현재가 ${fmtP(currentPrice)}' : '현재가 -',
          style: GoogleFonts.robotoMono(
            color: Colors.white.withValues(alpha: 0.56),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (canOpenChart)
          _InlineStockChart(
            ticker: stock.ticker,
            market: stock.market,
            buys: buys,
            sells: sells,
          )
        else
          Text(
            '차트 지원 종목이 아닙니다',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.34),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (canOpenChart) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JournalChartScreen(
                    buy: buys.isNotEmpty ? buys.first : stock,
                    linkedSells: sells,
                    relatedBuys: buys,
                    relatedSells: sells,
                    fullscreenOnly: true,
                    firestoreService: firestoreService,
                  ),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                foregroundColor: Colors.white.withValues(alpha: 0.80),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.open_in_full_rounded, size: 16),
              label: Text(
                '차트 자세히',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineStockChart extends StatefulWidget {
  final String ticker;
  final String market;
  final List<TradingJournal> buys;
  final List<TradingJournal> sells;

  const _InlineStockChart({
    required this.ticker,
    required this.market,
    required this.buys,
    required this.sells,
  });

  @override
  State<_InlineStockChart> createState() => _InlineStockChartState();
}

class _InlineStockChartState extends State<_InlineStockChart> {
  List<({DateTime date, double open, double high, double low, double close})>
  _candles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _InlineStockChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticker != widget.ticker ||
        oldWidget.market != widget.market) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await StockPriceService.fetchOHLC(
      widget.ticker,
      widget.market,
      interval: '1d',
      range: '6mo',
    );
    if (!mounted) return;
    setState(() {
      _candles = result;
      _loading = false;
    });
  }

  int _closestIndex(DateTime date) {
    if (_candles.isEmpty) return -1;
    final target = DateTime(date.year, date.month, date.day);
    var bestIdx = -1;
    var bestDiff = 1 << 30;
    for (var i = 0; i < _candles.length; i++) {
      final d = _candles[i].date;
      final cd = DateTime(d.year, d.month, d.day);
      final diff = cd.difference(target).inDays.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIdx = i;
      }
    }
    return bestDiff <= 5 ? bestIdx : -1;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF34D399)),
        ),
      );
    }
    if (_candles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '차트 데이터를 불러올 수 없습니다',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final buyMarkers = widget.buys
        .map((b) => _closestIndex(b.tradeDate))
        .where((i) => i >= 0)
        .toSet();
    final sellMarkers = widget.sells
        .map((s) => _closestIndex(s.tradeDate))
        .where((i) => i >= 0)
        .toSet();

    return Column(
      children: [
        SizedBox(
          height: 185,
          width: double.infinity,
          child: CustomPaint(
            painter: _InlineStockChartPainter(
              candles: _candles,
              buyMarkerIndexes: buyMarkers,
              sellMarkerIndexes: sellMarkers,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _InlineLegendDot(color: const Color(0xFF34D399), label: '매수'),
            const SizedBox(width: 12),
            _InlineLegendDot(color: const Color(0xFFF04452), label: '매도'),
          ],
        ),
      ],
    );
  }
}

class _InlineLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _InlineLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TradeAddActionsCard extends StatelessWidget {
  final VoidCallback onAddBuy;
  final VoidCallback onAddSell;

  const _TradeAddActionsCard({required this.onAddBuy, required this.onAddSell});

  @override
  Widget build(BuildContext context) {
    Widget actionButton({
      required String label,
      required Color color,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        actionButton(
          label: '매수 기록 추가',
          color: const Color(0xFF10B981),
          icon: Icons.trending_up_rounded,
          onTap: onAddBuy,
        ),
        const SizedBox(width: 10),
        actionButton(
          label: '매도 기록 추가',
          color: const Color(0xFFF04452),
          icon: Icons.trending_down_rounded,
          onTap: onAddSell,
        ),
      ],
    );
  }
}

class _InlineStockChartPainter extends CustomPainter {
  final List<
    ({DateTime date, double open, double high, double low, double close})
  >
  candles;
  final Set<int> buyMarkerIndexes;
  final Set<int> sellMarkerIndexes;

  const _InlineStockChartPainter({
    required this.candles,
    required this.buyMarkerIndexes,
    required this.sellMarkerIndexes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final highs = candles.map((e) => e.high).toList();
    final lows = candles.map((e) => e.low).toList();
    final maxY = highs.reduce((a, b) => a > b ? a : b);
    final minY = lows.reduce((a, b) => a < b ? a : b);
    final range = (maxY - minY).abs() < 1e-9 ? 1.0 : (maxY - minY);

    double toY(double v) => size.height - ((v - minY) / range) * size.height;
    double toX(int i) =>
        candles.length <= 1 ? 0 : (i / (candles.length - 1)) * size.width;

    final line = Path();
    for (var i = 0; i < candles.length; i++) {
      final p = Offset(toX(i), toY(candles[i].close));
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF60A5FA).withValues(alpha: 0.16),
          const Color(0xFF60A5FA).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(area, areaPaint);
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF60A5FA)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );

    for (final idx in buyMarkerIndexes) {
      if (idx < 0 || idx >= candles.length) continue;
      final center = Offset(toX(idx), toY(candles[idx].close));
      canvas.drawCircle(
        center,
        4.4,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawCircle(center, 3.2, Paint()..color = const Color(0xFF22C55E));
    }
    for (final idx in sellMarkerIndexes) {
      if (idx < 0 || idx >= candles.length) continue;
      final center = Offset(toX(idx), toY(candles[idx].close));
      canvas.drawCircle(
        center,
        4.4,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawCircle(center, 3.2, Paint()..color = const Color(0xFFF04452));
    }
  }

  @override
  bool shouldRepaint(covariant _InlineStockChartPainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.buyMarkerIndexes != buyMarkerIndexes ||
      oldDelegate.sellMarkerIndexes != sellMarkerIndexes;
}

class _JournalDateNavigator extends StatelessWidget {
  final DateTime date;
  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _JournalDateNavigator({
    required this.date,
    required this.canGoPrev,
    required this.canGoNext,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoPrev ? onPrev : null,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: canGoPrev
                  ? cs.onSurface.withValues(alpha: 0.8)
                  : cs.onSurface.withValues(alpha: 0.2),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('yyyy.MM.dd').format(date),
                style: GoogleFonts.robotoMono(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: canGoNext
                  ? cs.onSurface.withValues(alpha: 0.8)
                  : cs.onSurface.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalDateSection extends StatefulWidget {
  final List<TradingJournal> timeline;
  final Map<String, List<TradingJournal>> buysByStock;
  final Map<String, List<TradingJournal>> sellsByStock;
  final FirestoreService firestoreService;
  final void Function(TradingJournal journal) onEdit;
  final void Function(TradingJournal journal)? onEditLinkedSell;
  final void Function(TradingJournal journal)? onDeleteLinkedSell;

  const _JournalDateSection({
    required this.timeline,
    required this.buysByStock,
    required this.sellsByStock,
    required this.firestoreService,
    required this.onEdit,
    this.onEditLinkedSell,
    this.onDeleteLinkedSell,
  });

  @override
  State<_JournalDateSection> createState() => _JournalDateSectionState();
}

class _JournalDateSectionState extends State<_JournalDateSection> {
  DateTime? _selectedDate;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final availableDates = <DateTime>[];
    for (final item in widget.timeline) {
      final day = _dateOnly(item.tradeDate);
      if (!availableDates.any((d) => _isSameDay(d, day))) {
        availableDates.add(day);
      }
    }
    if (availableDates.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedDate =
        (_selectedDate != null &&
            availableDates.any((d) => _isSameDay(d, _selectedDate!)))
        ? _selectedDate!
        : availableDates.first;
    final selectedIdx = availableDates.indexWhere(
      (d) => _isSameDay(d, selectedDate),
    );
    final filteredTimeline = widget.timeline
        .where((j) => _isSameDay(j.tradeDate, selectedDate))
        .toList();

    return Column(
      children: [
        _JournalDateNavigator(
          date: selectedDate,
          canGoPrev:
              selectedIdx >= 0 && selectedIdx < availableDates.length - 1,
          canGoNext: selectedIdx > 0,
          onPrev: selectedIdx >= 0 && selectedIdx < availableDates.length - 1
              ? () => setState(
                  () => _selectedDate = availableDates[selectedIdx + 1],
                )
              : null,
          onNext: selectedIdx > 0
              ? () => setState(
                  () => _selectedDate = availableDates[selectedIdx - 1],
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '총 거래 ${filteredTimeline.length}건',
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ...filteredTimeline.map((j) {
          final stockKey = '${j.market}:${j.ticker}';
          final linkedSellsForCard = j.action == '매수'
              ? (widget.sellsByStock[stockKey] ?? const <TradingJournal>[])
              : const <TradingJournal>[];
          final relatedBuysForCard =
              widget.buysByStock[stockKey] ?? const <TradingJournal>[];
          return _JournalCard(
            key: ValueKey(j.id),
            journal: j,
            showTradeDate: false,
            simpleTradeOnly: true,
            relatedBuys: relatedBuysForCard,
            linkedSells: linkedSellsForCard,
            firestoreService: widget.firestoreService,
            onEdit: () => widget.onEdit(j),
            onEditLinkedSell: widget.onEditLinkedSell,
            onDeleteLinkedSell: widget.onDeleteLinkedSell,
          );
        }),
      ],
    );
  }
}

class _JournalOverviewSection extends StatefulWidget {
  final List<TradingJournal> journals;

  const _JournalOverviewSection({required this.journals});

  @override
  State<_JournalOverviewSection> createState() =>
      _JournalOverviewSectionState();
}

class _JournalOverviewSectionState extends State<_JournalOverviewSection> {
  final Map<String, double> _livePrices = {};
  Set<String> _requestedKeys = const {};

  String _priceKey(String market, String ticker) => '$market:$ticker';

  @override
  void initState() {
    super.initState();
    _loadLivePrices();
  }

  @override
  void didUpdateWidget(covariant _JournalOverviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLivePrices();
  }

  Future<void> _loadLivePrices() async {
    final buyQtyByStock = <String, double>{};
    final sellQtyByStock = <String, double>{};
    for (final journal in widget.journals) {
      if (journal.ticker.isEmpty) continue;
      final key = '${journal.market}:${journal.ticker}';
      if (journal.action == '매수') {
        buyQtyByStock.update(
          key,
          (value) => value + journal.quantity,
          ifAbsent: () => journal.quantity,
        );
      } else if (journal.action == '매도') {
        sellQtyByStock.update(
          key,
          (value) => value + journal.quantity,
          ifAbsent: () => journal.quantity,
        );
      }
    }

    final requests = <({String ticker, String market})>{};
    for (final entry in buyQtyByStock.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 2) continue;
      final market = parts.first;
      final ticker = parts.sublist(1).join(':');
      if (!{'KS', 'KQ', 'US'}.contains(market)) continue;
      final soldQty = sellQtyByStock[entry.key] ?? 0;
      final remainingQty = (entry.value - soldQty).clamp(0.0, entry.value);
      if (remainingQty <= _kQtyEpsilon) continue;
      requests.add((ticker: ticker, market: market));
    }

    final nextKeys = requests
        .map((item) => '${item.market}:${item.ticker}')
        .toSet();
    if (setEquals(nextKeys, _requestedKeys)) return;

    _requestedKeys = nextKeys;
    if (requests.isEmpty) {
      if (mounted) {
        setState(() => _livePrices.clear());
      }
      return;
    }

    final results = await Future.wait(
      requests.map(
        (item) => StockPriceService.fetchPrice(item.ticker, item.market),
      ),
    );
    if (!mounted) return;

    final nextPrices = <String, double>{};
    final requestList = requests.toList();
    for (var i = 0; i < requestList.length; i++) {
      final result = results[i];
      if (result != null) {
        nextPrices[_priceKey(requestList[i].market, requestList[i].ticker)] =
            result.price;
      }
    }

    setState(() {
      _livePrices
        ..clear()
        ..addAll(nextPrices);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PositionSummaryCard(
      journals: widget.journals,
      livePrices: _livePrices,
    );
  }
}

// ─── 보유 포지션 요약 ─────────────────────────────────────────────────────

class _PortfolioSummarySection extends StatefulWidget {
  final List<({TradingJournal buy, double remainingQty})> holdings;
  const _PortfolioSummarySection({required this.holdings});

  @override
  State<_PortfolioSummarySection> createState() =>
      _PortfolioSummarySectionState();
}

class _PortfolioSummarySectionState extends State<_PortfolioSummarySection> {
  bool _expanded = false;
  final Map<String, PriceResult?> _prices = {};

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  @override
  void didUpdateWidget(_PortfolioSummarySection old) {
    super.didUpdateWidget(old);
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    final toFetch = widget.holdings
        .where(
          (h) =>
              h.buy.ticker.isNotEmpty &&
              {'KS', 'KQ', 'US'}.contains(h.buy.market) &&
              !_prices.containsKey(h.buy.id),
        )
        .toList();
    if (toFetch.isEmpty) return;

    // 병렬 요청 — 같은 심볼은 서비스 레이어 캐시에서 중복 차단
    final results = await Future.wait(
      toFetch.map(
        (h) => StockPriceService.fetchPrice(h.buy.ticker, h.buy.market),
      ),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < toFetch.length; i++) {
        _prices[toFetch[i].buy.id] = results[i];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.holdings.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    const usdToKrw = 1480.0;

    double totalEval = 0;
    double totalPnl = 0;
    bool hasAnyPrice = false;
    for (final h in widget.holdings) {
      final price = _prices[h.buy.id];
      if (price != null && h.buy.price > 0) {
        final rate = h.buy.market == 'US' ? usdToKrw : 1.0;
        totalEval += price.price * h.remainingQty * rate;
        totalPnl += (price.price - h.buy.price) * h.remainingQty * rate;
        hasAnyPrice = true;
      }
    }
    final isPnlUp = totalPnl >= 0;
    final pnlColor = isPnlUp
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    String fmtAmt(double v) => '₩${NumberFormat('#,###').format(v.toInt())}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 타이틀 + 종목 수
                Text(
                  '보유 포지션',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.holdings.length}',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                // 총 평가금액 + 총 손익 (가로 배치)
                if (hasAnyPrice) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '평가금액',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        fmtAmt(totalEval),
                        style: GoogleFonts.robotoMono(
                          color: cs.onSurface.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '평가손익',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        '${isPnlUp ? '+' : ''}${fmtAmt(totalPnl)}',
                        style: GoogleFonts.robotoMono(
                          color: pnlColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          ...widget.holdings.map(
            (h) => _HoldingRow(
              buy: h.buy,
              remainingQty: h.remainingQty,
              price: _prices[h.buy.id],
            ),
          ),
          const SizedBox(height: 4),
        ],
        Divider(
          height: 1,
          thickness: 1,
          color: cs.onSurface.withValues(alpha: 0.06),
        ),
      ],
    );
  }
}

class _HoldingRow extends StatelessWidget {
  final TradingJournal buy;
  final double remainingQty;
  final PriceResult? price;

  const _HoldingRow({
    required this.buy,
    required this.remainingQty,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isKrw = buy.market != 'US';

    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';

    double? pnl, pnlPct, evalAmt;
    if (price != null && buy.price > 0) {
      pnl = (price!.price - buy.price) * remainingQty;
      pnlPct = (price!.price - buy.price) / buy.price * 100;
      evalAmt = price!.price * remainingQty;
    }
    final isUp = pnl == null || pnl >= 0;
    final pnlColor = pnl == null
        ? cs.onSurface.withValues(alpha: 0.3)
        : (pnl >= 0 ? const Color(0xFFF04452) : const Color(0xFF1677FF));

    final qtyStr = remainingQty % 1 == 0
        ? '${remainingQty.toInt()}주'
        : '$remainingQty주';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // 좌: 종목명 + 수량
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  buy.stockName,
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  buy.ticker.isNotEmpty ? '$qtyStr  ·  ${buy.ticker}' : qtyStr,
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // 중: 평가금액
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '평가금액',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  evalAmt != null
                      ? fmtP(evalAmt)
                      : (price == null ? '...' : '-'),
                  style: GoogleFonts.robotoMono(
                    color: cs.onSurface.withValues(
                      alpha: evalAmt != null ? 0.8 : 0.3,
                    ),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 우: 평가손익
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '평가손익',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pnl != null
                      ? '${isUp ? '+' : ''}${fmtP(pnl)}'
                      : (price == null ? '...' : '-'),
                  style: GoogleFonts.robotoMono(
                    color: pnlColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (pnlPct != null)
                  Text(
                    '${isUp ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(
                      color: pnlColor.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 일지 카드 ─────────────────────────────────────────────────────────────

class _JournalCard extends StatefulWidget {
  final TradingJournal journal;
  final List<TradingJournal> relatedBuys;
  final List<TradingJournal> linkedSells;
  final bool showTradeDate;
  final bool simpleTradeOnly;
  final FirestoreService firestoreService;
  final VoidCallback onEdit;
  final void Function(TradingJournal)? onEditLinkedSell;
  final void Function(TradingJournal)? onDeleteLinkedSell;

  const _JournalCard({
    super.key,
    required this.journal,
    this.relatedBuys = const [],
    this.linkedSells = const [],
    this.showTradeDate = true,
    this.simpleTradeOnly = false,
    required this.firestoreService,
    required this.onEdit,
    this.onEditLinkedSell,
    this.onDeleteLinkedSell,
  });

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard> {
  PriceResult? _price;
  bool _fetchingPrice = false;
  static const _upColor = Color(0xFFF04452);
  static const _downColor = Color(0xFF1677FF);

  // build()에서 매번 재계산되지 않도록 캐시
  late List<TradingJournal> _groupedBuys;
  late Map<String, double> _remainingByBuyId;

  @override
  void initState() {
    super.initState();
    _computeDerived();
    _loadPrice();
  }

  @override
  void didUpdateWidget(covariant _JournalCard old) {
    super.didUpdateWidget(old);
    if (old.relatedBuys != widget.relatedBuys ||
        old.linkedSells != widget.linkedSells ||
        old.journal != widget.journal) {
      _computeDerived();
    }
  }

  void _computeDerived() {
    final journal = widget.journal;
    _groupedBuys = widget.relatedBuys.isNotEmpty
        ? ([...widget.relatedBuys]
            ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate)))
        : (journal.action == '매수' ? [journal] : <TradingJournal>[]);

    final result = <String, double>{};
    final hasLinkedLot = widget.linkedSells.any(
      (s) =>
          s.linkedBuyId.isNotEmpty &&
          _groupedBuys.any((b) => b.id == s.linkedBuyId),
    );
    if (hasLinkedLot) {
      for (final buy in _groupedBuys) {
        final sold = widget.linkedSells
            .where((s) => s.linkedBuyId == buy.id)
            .fold(0.0, (sum, s) => sum + s.quantity);
        result[buy.id] = (buy.quantity - sold).clamp(0.0, buy.quantity);
      }
    } else {
      final buysAsc = [..._groupedBuys]
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      var soldLeft = widget.linkedSells.fold<double>(
        0.0,
        (sum, s) => sum + s.quantity,
      );
      for (final buy in buysAsc) {
        final consumed = soldLeft > buy.quantity ? buy.quantity : soldLeft;
        result[buy.id] = (buy.quantity - consumed).clamp(0.0, buy.quantity);
        soldLeft = soldLeft > consumed ? soldLeft - consumed : 0.0;
      }
    }
    _remainingByBuyId = result;
  }

  Future<void> _loadPrice() async {
    final ticker = widget.journal.ticker;
    final market = widget.journal.market;
    // Only fetch for known raw markets (KS/KQ/US); skip 'KR'/'기타' (legacy)
    if (ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(market)) {
      return;
    }
    _fetchingPrice = true;
    final result = await StockPriceService.fetchPrice(ticker, market);
    if (mounted) {
      setState(() {
        _price = result;
        _fetchingPrice = false;
      });
    }
  }

  Color _actionColor() {
    if (widget.journal.action == '매수') return const Color(0xFF10B981);
    if (widget.journal.action == '매도') return _upColor;
    return Colors.orangeAccent;
  }

  Future<void> _openDetail(
    BuildContext context, {
    bool isClosed = false,
    required double remainingQty,
  }) async {
    final canOpenChart =
        widget.journal.ticker.isNotEmpty &&
        {'KS', 'KQ', 'US'}.contains(widget.journal.market);

    // 티커 기반 기록이면 매수/매도/기타 모두 차트 페이지로 이동한다.
    if (canOpenChart) {
      final sameStockJournals = await widget.firestoreService
          .getMyJournalsByUidOnce(widget.journal.uid);
      final relatedBuys =
          sameStockJournals
              .where(
                (j) =>
                    j.action == '매수' &&
                    j.ticker == widget.journal.ticker &&
                    j.market == widget.journal.market,
              )
              .toList()
            ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
      final relatedSells =
          sameStockJournals
              .where(
                (j) =>
                    j.action == '매도' &&
                    j.ticker == widget.journal.ticker &&
                    j.market == widget.journal.market,
              )
              .toList()
            ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
      final chartBuy = relatedBuys.isNotEmpty
          ? relatedBuys.first
          : widget.journal;
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JournalChartScreen(
            buy: chartBuy,
            linkedSells: widget.linkedSells,
            relatedBuys: relatedBuys,
            relatedSells: relatedSells,
            firestoreService: widget.firestoreService,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _JournalDetailSheet(
          journal: widget.journal,
          relatedBuys: widget.relatedBuys.isNotEmpty
              ? [...widget.relatedBuys]
              : (widget.journal.action == '매수'
                    ? [widget.journal]
                    : const <TradingJournal>[]),
          linkedSells: widget.linkedSells,
          remainingQty: remainingQty,
          price: _price,
          firestoreService: widget.firestoreService,
          onEdit: widget.onEdit,
          onEditSell: widget.onEditLinkedSell,
          onDeleteSell: widget.onDeleteLinkedSell,
          canEdit: !isClosed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final journal = widget.journal;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actionColor = _actionColor();
    final isKrw = journal.market != 'US';
    final tradeDateLabelColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : cs.onSurface.withValues(alpha: 0.52);
    final tradeDateValueColor = isDark ? Colors.white : const Color(0xFF111827);
    final tradeDateDividerColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : cs.onSurface.withValues(alpha: 0.14);

    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';

    final groupedBuys = _groupedBuys;
    final remainingByBuyId = _remainingByBuyId;

    final baseQty = groupedBuys.fold<double>(0, (sum, b) => sum + b.quantity);
    final remainingQty = journal.action == '매수'
        ? remainingByBuyId.values.fold<double>(0, (sum, r) => sum + r)
        : 0.0;
    final isClosed =
        journal.action == '매수' &&
        remainingQty <= _kQtyEpsilon &&
        widget.linkedSells.isNotEmpty;
    final avgBuyPrice = baseQty > 0
        ? groupedBuys.fold<double>(
                0,
                (sum, b) => sum + (b.price * b.quantity),
              ) /
              baseQty
        : journal.price;

    // 총 실현손익 (포지션 전체 종료 시) — avgBuyPrice 기준
    // 총 실현손익 — 각 매도 시점의 평균단가 기준
    double? totalRealizedPnl;
    if (isClosed) {
      double total = 0;
      for (final s in widget.linkedSells) {
        final bp = _avgBuyPriceAt(groupedBuys, s.tradeDate);
        if (s.price > 0 && s.quantity > 0 && bp > 0) {
          total += (s.price - bp) * s.quantity;
        }
      }
      totalRealizedPnl = total;
    }

    // 실현손익 (매도 카드) — 매도 시점 평균단가 기준
    final sellAvgBp = _avgBuyPriceAt(groupedBuys, journal.tradeDate);
    double? realizedPnl, realizedPnlPct;
    if (journal.action == '매도' &&
        sellAvgBp > 0 &&
        journal.price > 0 &&
        journal.quantity > 0) {
      realizedPnl = (journal.price - sellAvgBp) * journal.quantity;
      realizedPnlPct = (journal.price - sellAvgBp) / sellAvgBp * 100;
    }
    final isRealizedUp = realizedPnl != null && realizedPnl >= 0;

    final linkedRealizedTotal = widget.linkedSells.fold<double>(0, (sum, s) {
      final bp = _avgBuyPriceAt(groupedBuys, s.tradeDate);
      if (s.price > 0 && s.quantity > 0 && bp > 0) {
        return sum + ((s.price - bp) * s.quantity);
      }
      return sum;
    });
    final hasLinkedRealized = widget.linkedSells.any((s) {
      final bp = _avgBuyPriceAt(groupedBuys, s.tradeDate);
      return s.price > 0 && s.quantity > 0 && bp > 0;
    });
    final isLinkedTotalUp = linkedRealizedTotal >= 0;
    // 평가손익 (매수 + 잔량 > 0 + 현재가)
    double? pnl, pnlPct;
    if (journal.action != '매도' &&
        !isClosed &&
        remainingQty > 0 &&
        _price != null &&
        avgBuyPrice > 0) {
      pnl = (_price!.price - avgBuyPrice) * remainingQty;
      pnlPct = (_price!.price - avgBuyPrice) / avgBuyPrice * 100;
    }
    final isPnlUp = pnl != null && pnl >= 0;

    // 마켓 라벨
    final marketLabel = switch (journal.market) {
      'KS' => 'KOSPI',
      'KQ' => 'KOSDAQ',
      'US' => 'NYSE/NASDAQ',
      _ => journal.market,
    };
    final latestActivityDate = [
      journal.tradeDate,
      ...groupedBuys.map((b) => b.tradeDate),
      ...widget.linkedSells.map((s) => s.tradeDate),
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    final tradeDateText = DateFormat('yyyy.MM.dd').format(latestActivityDate);
    final showCombinedHistory = widget.relatedBuys.isNotEmpty;
    final simpleTradeOnly = widget.simpleTradeOnly;
    final historyEvents = <({TradingJournal journal, bool isBuy})>[
      ...groupedBuys.map((b) => (journal: b, isBuy: true)),
      ...widget.linkedSells.map((s) => (journal: s, isBuy: false)),
    ]..sort((a, b) => b.journal.tradeDate.compareTo(a.journal.tradeDate));

    Widget buildCardMenu() => PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz,
        size: 18,
        color: cs.onSurface.withValues(alpha: 0.35),
      ),
      color: isDark ? const Color(0xFF1A2035) : Colors.white,
      onSelected: (v) async {
        if (v == 'edit') {
          widget.onEdit();
        } else if (v == 'public') {
          await widget.firestoreService.toggleJournalPublic(
            journal.id,
            journal.isPublic,
          );
          AnalyticsService.instance.logToggleJournalPublic(!journal.isPublic);
        } else if (v == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1A2035) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                '삭제',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Text(
                '이 일지를 삭제할까요?',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    '취소',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white54 : Colors.black45,
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
          if (confirm == true) {
            await widget.firestoreService.deleteJournal(journal.id);
            AnalyticsService.instance.logDeleteJournal();
          }
        }
      },
      itemBuilder: (_) => [
        if (!isClosed)
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, size: 16),
                const SizedBox(width: 8),
                Text('수정', style: GoogleFonts.inter(fontSize: 13)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'public',
          child: Row(
            children: [
              Icon(
                journal.isPublic ? Icons.lock_outline : Icons.public_outlined,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                journal.isPublic ? '비공개로 전환' : '커뮤니티에 공유',
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                '삭제',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ],
    );

    if (simpleTradeOnly) {
      final headlineAmount = journal.action == '매도' ? realizedPnl : null;
      final headlineRate = journal.action == '매도' ? realizedPnlPct : null;
      final isHeadlineUp = journal.action == '매도' ? isRealizedUp : isPnlUp;
      final headlineColor = isHeadlineUp ? _upColor : _downColor;
      final qtyText = journal.quantity % 1 == 0
          ? '${journal.quantity.toInt()}주'
          : '${journal.quantity}주';
      final currentPriceText = journal.action == '매도'
          ? fmtP(journal.price)
          : (_price?.formattedPrice ?? '-');
      final isEtcCard = journal.action != '매수' && journal.action != '매도';
      final buyAmountText = avgBuyPrice > 0 && baseQty > 0
          ? fmtP(avgBuyPrice * baseQty)
          : '-';
      final sellAmountText = journal.price > 0 && journal.quantity > 0
          ? fmtP(journal.price * journal.quantity)
          : '-';
      final metricLines = <({String label, String value, Color color})>[
        (
          label: journal.action == '매도' ? '평균단가' : '매수가',
          value: fmtP(journal.action == '매도' ? sellAvgBp : avgBuyPrice),
          color: cs.onSurface,
        ),
        (
          label: journal.action == '매도' ? '매도가' : '현재가',
          value: currentPriceText,
          color: journal.action == '매수' && _price != null
              ? (isPnlUp ? _upColor : _downColor)
              : journal.action == '매도'
              ? (isRealizedUp ? _upColor : _downColor)
              : cs.onSurface,
        ),
        (
          label: journal.action == '매수' ? '매수수량' : '수량',
          value: qtyText,
          color: cs.onSurface,
        ),
        (
          label: journal.action == '매도' ? '매도금액' : '매수금액',
          value: journal.action == '매도' ? sellAmountText : buyAmountText,
          color: cs.onSurface,
        ),
      ];
      final isBuyCard = journal.action == '매수';
      final actionTone = isBuyCard
          ? const Color(0xFF34D399)
          : journal.action == '매도'
          ? _upColor
          : Colors.orangeAccent;
      final cardColor = isDark ? const Color(0xFF131929) : cs.surface;
      final headerGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          actionTone.withValues(alpha: isDark ? 0.1 : 0.075),
          actionTone.withValues(alpha: isDark ? 0.04 : 0.03),
          Colors.transparent,
        ],
        stops: const [0, 0.6, 1],
      );

      Widget infoChip(String text, Color color) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      Widget metricLine(({String label, String value, Color color}) metric) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.06),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  metric.label,
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: isDark ? 0.48 : 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                metric.value,
                style: GoogleFonts.robotoMono(
                  color: metric.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }

      Widget bottomActionRow() {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Row(
            children: [
              if (!isEtcCard)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _openDetail(
                      context,
                      isClosed: isClosed,
                      remainingQty: remainingQty,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: actionTone.withValues(
                          alpha: isDark ? 0.14 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: actionTone.withValues(
                            alpha: isDark ? 0.28 : 0.22,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.show_chart_rounded,
                            size: 16,
                            color: actionTone,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '매매기록 차트보기',
                            style: GoogleFonts.inter(
                              color: actionTone,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (!isEtcCard) const SizedBox(width: 10),
              if (!isEtcCard)
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: isDark ? 0.05 : 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cs.onSurface.withValues(
                        alpha: isDark ? 0.1 : 0.08,
                      ),
                    ),
                  ),
                  child: Center(child: buildCardMenu()),
                ),
            ],
          ),
        );
      }

      return GestureDetector(
        onTap: null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.08),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 10, 16),
                  decoration: BoxDecoration(gradient: headerGradient),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                            decoration: BoxDecoration(
                              color: actionTone.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: actionTone.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: actionTone,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  journal.action,
                                  style: GoogleFonts.inter(
                                    color: actionTone,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isEtcCard) ...[
                            const Spacer(),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(
                                  alpha: isDark ? 0.05 : 0.04,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: cs.onSurface.withValues(
                                    alpha: isDark ? 0.1 : 0.08,
                                  ),
                                ),
                              ),
                              child: Center(child: buildCardMenu()),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              journal.stockName,
                              style: GoogleFonts.inter(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (marketLabel.isNotEmpty)
                            infoChip(
                              marketLabel == 'NYSE/NASDAQ' ? 'US' : marketLabel,
                              marketLabel == 'KOSDAQ'
                                  ? const Color(0xFF00C4B4)
                                  : marketLabel == 'KOSPI'
                                  ? const Color(0xFF3182F6)
                                  : const Color(0xFF8B5CF6),
                            ),
                          if (journal.isPublic) ...[
                            const SizedBox(width: 6),
                            Text(
                              '🌐',
                              style: TextStyle(
                                fontSize: 19,
                                height: 1,
                                color: cs.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (journal.note.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _ExpandableNotePreview(
                      content: journal.note,
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.68),
                        fontSize: 13,
                        height: 1.55,
                      ),
                      maxLines: 2,
                    ),
                  ),
                ],
                if (headlineAmount != null && !isEtcCard) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                journal.action == '매도' ? '실현손익' : '평가손익',
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.24),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${isHeadlineUp ? '+' : ''}${fmtP(headlineAmount)}',
                                style: GoogleFonts.robotoMono(
                                  color: headlineColor,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (headlineRate != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: headlineColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${isHeadlineUp ? '+' : ''}${headlineRate.toStringAsFixed(2)}%',
                              style: GoogleFonts.robotoMono(
                                color: headlineColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (isEtcCard)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: metricLine((
                      label: '현재가',
                      value: currentPriceText,
                      color: cs.onSurface,
                    )),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Column(
                      children: [
                        for (final line in metricLines) metricLine(line),
                      ],
                    ),
                  ),
                bottomActionRow(),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isClosed ? cs.onSurface.withValues(alpha: 0.03) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isClosed
                ? cs.onSurface.withValues(alpha: 0.12)
                : cs.onSurface.withValues(alpha: 0.07),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 상단 컬러 바 / 종료 배너
                  if (isClosed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.onSurface.withValues(alpha: 0.1),
                            cs.onSurface.withValues(alpha: 0.04),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 12,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '포지션 종료',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            actionColor,
                            actionColor.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showTradeDate) ...[
                          Row(
                            children: [
                              Text(
                                '거래일',
                                style: GoogleFonts.inter(
                                  color: tradeDateLabelColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tradeDateText,
                                style: GoogleFonts.robotoMono(
                                  color: tradeDateValueColor,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const Spacer(),
                              if (journal.action == '매수')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: actionColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '매수',
                                    style: GoogleFonts.inter(
                                      color: actionColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 1,
                            width: double.infinity,
                            color: tradeDateDividerColor,
                          ),
                          const SizedBox(height: 10),
                        ] else ...[
                          Row(
                            children: [
                              const Spacer(),
                              if (journal.action == '매수')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: actionColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '매수',
                                    style: GoogleFonts.inter(
                                      color: actionColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        // ── 헤더 행
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          journal.stockName,
                                          style: GoogleFonts.inter(
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      if (journal.ticker.isNotEmpty) ...[
                                        Text(
                                          journal.ticker,
                                          style: GoogleFonts.robotoMono(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.45,
                                            ),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                      if (journal.ticker.isNotEmpty &&
                                          marketLabel.isNotEmpty)
                                        Text(
                                          '  ·  ',
                                          style: GoogleFonts.inter(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.2,
                                            ),
                                            fontSize: 10,
                                          ),
                                        ),
                                      if (marketLabel.isNotEmpty)
                                        Text(
                                          marketLabel,
                                          style: GoogleFonts.inter(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.35,
                                            ),
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (journal.isPublic)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2,
                                  right: 2,
                                ),
                                child: Icon(
                                  Icons.public,
                                  size: 13,
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.6),
                                ),
                              ),
                            buildCardMenu(),
                          ],
                        ),
                        // ── 메모 스니펫
                        if (journal.note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _ExpandableNotePreview(
                            content: journal.note,
                            maxLines: 3,
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.62),
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ],
                        // ── 거래 정보 그리드
                        if (journal.price > 0 || journal.quantity > 0) ...[
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final divCol = cs.onSurface.withValues(
                                alpha: 0.07,
                              );
                              final qtyBase = journal.action == '매수'
                                  ? baseQty
                                  : journal.quantity;
                              final qtyStr = qtyBase % 1 == 0
                                  ? '${qtyBase.toInt()}주'
                                  : '$qtyBase주';

                              Widget cell(
                                String label,
                                String value, {
                                Color? valueColor,
                              }) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface.withValues(
                                            alpha: 0.38,
                                          ),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        value,
                                        style: GoogleFonts.robotoMono(
                                          color: valueColor ?? cs.onSurface,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              Widget vd() => VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: divCol,
                              );
                              Widget hd() => Divider(
                                height: 1,
                                thickness: 1,
                                color: divCol,
                              );

                              List<Widget> rows = [];

                              if (journal.action == '매수') {
                                if (simpleTradeOnly) {
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '매수가',
                                            avgBuyPrice > 0
                                                ? fmtP(avgBuyPrice)
                                                : '-',
                                          ),
                                          vd(),
                                          cell('매수수량', qtyStr),
                                        ],
                                      ),
                                    ),
                                  );
                                } else if (!isClosed) {
                                  const upColor = Color(
                                    0xFFF04452,
                                  ); // DESIGN.md up
                                  const downColor = Color(
                                    0xFF1677FF,
                                  ); // DESIGN.md down
                                  final hasLive =
                                      _price != null && avgBuyPrice > 0;
                                  final isUpLive = hasLive
                                      ? _price!.price >= avgBuyPrice
                                      : false;
                                  final currentPrice =
                                      _price?.formattedPrice ?? '-';
                                  final remainingQtyStr = remainingQty % 1 == 0
                                      ? '${remainingQty.toInt()}주'
                                      : '$remainingQty주';
                                  final buyAmount =
                                      avgBuyPrice > 0 && remainingQty > 0
                                      ? fmtP(avgBuyPrice * remainingQty)
                                      : '-';
                                  final evalAmount =
                                      _price != null && remainingQty > 0
                                      ? fmtP(_price!.price * remainingQty)
                                      : '-';
                                  final evalPnlText = pnl != null
                                      ? '${isPnlUp ? '+' : ''}${fmtP(pnl)}'
                                      : '-';
                                  final evalPctText = pnlPct != null
                                      ? '${isPnlUp ? '+' : ''}${pnlPct.toStringAsFixed(2)}%'
                                      : '-';
                                  final realizedPnlText = hasLinkedRealized
                                      ? '${isLinkedTotalUp ? '+' : ''}${fmtP(linkedRealizedTotal)}'
                                      : '-';
                                  final totalPnl =
                                      (pnl ?? 0) +
                                      (hasLinkedRealized
                                          ? linkedRealizedTotal
                                          : 0);
                                  final hasTotalPnl =
                                      pnl != null || hasLinkedRealized;
                                  final isTotalPnlUp = totalPnl >= 0;
                                  final totalPnlText = hasTotalPnl
                                      ? '${isTotalPnlUp ? '+' : ''}${fmtP(totalPnl)}'
                                      : '-';

                                  // 1행: 매수가 | 현재가
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '매수가',
                                            avgBuyPrice > 0
                                                ? fmtP(avgBuyPrice)
                                                : '-',
                                          ),
                                          vd(),
                                          cell(
                                            '현재가',
                                            currentPrice,
                                            valueColor: hasLive
                                                ? (isUpLive
                                                      ? upColor
                                                      : downColor)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  // 2행: 매수수량 | 잔량
                                  rows.add(hd());
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell('매수수량', qtyStr),
                                          vd(),
                                          cell('잔량', remainingQtyStr),
                                        ],
                                      ),
                                    ),
                                  );

                                  // 3행: 매수금액 | 평가금액
                                  rows.add(hd());
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell('원금', buyAmount),
                                          vd(),
                                          cell(
                                            '평가금액',
                                            evalAmount,
                                            valueColor: _price != null
                                                ? (isPnlUp
                                                      ? upColor
                                                      : downColor)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  // 4행: 평가손익 | 수익률
                                  rows.add(hd());
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '평가손익',
                                            evalPnlText,
                                            valueColor: pnl != null
                                                ? (isPnlUp
                                                      ? upColor
                                                      : downColor)
                                                : null,
                                          ),
                                          vd(),
                                          cell(
                                            '수익률',
                                            evalPctText,
                                            valueColor: pnl != null
                                                ? (isPnlUp
                                                      ? upColor
                                                      : downColor)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  // 5행: 실현손익 | 총손익
                                  rows.add(hd());
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '실현손익',
                                            realizedPnlText,
                                            valueColor: hasLinkedRealized
                                                ? (isLinkedTotalUp
                                                      ? upColor
                                                      : downColor)
                                                : null,
                                          ),
                                          vd(),
                                          cell(
                                            '총손익',
                                            totalPnlText,
                                            valueColor: hasTotalPnl
                                                ? (isTotalPnlUp
                                                      ? upColor
                                                      : downColor)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                } else {
                                  // 종료된 매수 포지션 요약: 3행 구조
                                  final totalSellQty = widget.linkedSells.fold(
                                    0.0,
                                    (s, j) => s + j.quantity,
                                  );
                                  final totalSellAmount = widget.linkedSells
                                      .fold(
                                        0.0,
                                        (s, j) => s + j.price * j.quantity,
                                      );
                                  final avgSellPrice = totalSellQty > 0
                                      ? totalSellAmount / totalSellQty
                                      : 0.0;
                                  final investedAmount =
                                      (avgBuyPrice > 0 && baseQty > 0)
                                      ? avgBuyPrice * baseQty
                                      : 0.0;
                                  final totalPnlVal =
                                      totalRealizedPnl ??
                                      (totalSellAmount - investedAmount);
                                  final totalPct = investedAmount > 0
                                      ? (totalPnlVal / investedAmount) * 100
                                      : null;
                                  final isTotalUp = totalPnlVal >= 0;

                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '매수가',
                                            avgBuyPrice > 0
                                                ? fmtP(avgBuyPrice)
                                                : '-',
                                          ),
                                          vd(),
                                          cell(
                                            '평균매도가',
                                            totalSellQty > 0
                                                ? fmtP(avgSellPrice)
                                                : '-',
                                            valueColor: totalSellQty > 0
                                                ? (avgSellPrice >= avgBuyPrice
                                                      ? _upColor
                                                      : _downColor)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  rows.add(hd());
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '매입금액',
                                            investedAmount > 0
                                                ? fmtP(investedAmount)
                                                : '-',
                                          ),
                                          vd(),
                                          cell(
                                            '매도금액',
                                            totalSellAmount > 0
                                                ? fmtP(totalSellAmount)
                                                : '-',
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  rows.add(hd());
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '총 실현손익',
                                            '${isTotalUp ? '+' : ''}${fmtP(totalPnlVal)}',
                                            valueColor: isTotalUp
                                                ? _upColor
                                                : _downColor,
                                          ),
                                          vd(),
                                          cell(
                                            '수익률',
                                            totalPct != null
                                                ? '${isTotalUp ? '+' : ''}${totalPct.toStringAsFixed(2)}%'
                                                : '-',
                                            valueColor: totalPct != null
                                                ? (isTotalUp
                                                      ? _upColor
                                                      : _downColor)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              } else if (journal.action == '매도') {
                                rows.add(
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (sellAvgBp > 0) ...[
                                          cell('평균단가', fmtP(sellAvgBp)),
                                          vd(),
                                        ],
                                        if (journal.price > 0) ...[
                                          cell('매도가', fmtP(journal.price)),
                                          vd(),
                                        ],
                                        if (journal.quantity > 0)
                                          cell('수량', qtyStr),
                                      ],
                                    ),
                                  ),
                                );
                              } else {
                                rows.add(
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (journal.price > 0) ...[
                                          cell('가격', fmtP(journal.price)),
                                          if (journal.quantity > 0) vd(),
                                        ],
                                        if (journal.quantity > 0)
                                          cell('수량', qtyStr),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              return Container(
                                decoration: BoxDecoration(
                                  color: cs.onSurface.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: divCol),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(children: rows),
                                ),
                              );
                            },
                          ),
                        ],
                        // ── 실현손익 (매도)
                        if (!simpleTradeOnly && realizedPnl != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isRealizedUp
                                  ? _upColor.withValues(alpha: 0.1)
                                  : _downColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isRealizedUp
                                    ? _upColor.withValues(alpha: 0.25)
                                    : _downColor.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isRealizedUp
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                                  size: 14,
                                  color: isRealizedUp ? _upColor : _downColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '실현손익  ',
                                  style: GoogleFonts.inter(
                                    color: isRealizedUp ? _upColor : _downColor,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  '${isRealizedUp ? '+' : ''}${fmtP(realizedPnl)}',
                                  style: GoogleFonts.robotoMono(
                                    color: isRealizedUp ? _upColor : _downColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${isRealizedUp ? '+' : ''}${realizedPnlPct!.toStringAsFixed(2)}%)',
                                  style: GoogleFonts.inter(
                                    color: isRealizedUp
                                        ? _upColor.withValues(alpha: 0.8)
                                        : _downColor.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // ── 현재가 + 평가손익 (기타 액션 전용)
                        if (!simpleTradeOnly &&
                            journal.action == '기타' &&
                            !isClosed) ...[
                          if (_fetchingPrice)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '현재가 조회 중...',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.3,
                                      ),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (_price != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  '현재가  ',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface.withValues(alpha: 0.4),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  _price!.formattedPrice,
                                  style: GoogleFonts.robotoMono(
                                    color: cs.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _price!.formattedChange,
                                  style: GoogleFonts.inter(
                                    color: _price!.isUp
                                        ? const Color(0xFF10B981)
                                        : Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (pnl != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isPnlUp
                                      ? const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.1)
                                      : Colors.redAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isPnlUp
                                        ? const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.25)
                                        : Colors.redAccent.withValues(
                                            alpha: 0.25,
                                          ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isPnlUp
                                          ? Icons.trending_up
                                          : Icons.trending_down,
                                      size: 14,
                                      color: isPnlUp
                                          ? const Color(0xFF10B981)
                                          : Colors.redAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '평가손익  ',
                                      style: GoogleFonts.inter(
                                        color: isPnlUp
                                            ? const Color(0xFF10B981)
                                            : Colors.redAccent,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '${isPnlUp ? '+' : ''}${fmtP(pnl)}',
                                      style: GoogleFonts.robotoMono(
                                        color: isPnlUp
                                            ? const Color(0xFF10B981)
                                            : Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '(${isPnlUp ? '+' : ''}${pnlPct!.toStringAsFixed(2)}%)',
                                      style: GoogleFonts.inter(
                                        color: isPnlUp
                                            ? const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.8)
                                            : Colors.redAccent.withValues(
                                                alpha: 0.8,
                                              ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                        // ── 종목 상세: 매수/매도 통합 시간순 기록
                        if (showCombinedHistory &&
                            historyEvents.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    4,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.onSurface.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '매매 기록',
                                          style: GoogleFonts.inter(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${historyEvents.length}건',
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface.withValues(
                                            alpha: 0.45,
                                          ),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...historyEvents.map((e) {
                                  final t = e.journal;
                                  final isBuy = e.isBuy;
                                  final tradeDate = DateFormat(
                                    'MM/dd',
                                  ).format(t.tradeDate);
                                  final qtyStr = t.quantity % 1 == 0
                                      ? '${t.quantity.toInt()}주'
                                      : '${t.quantity}주';
                                  final priceStr = t.price > 0
                                      ? fmtP(t.price)
                                      : '-';
                                  double? tradePnl;
                                  if (!isBuy &&
                                      t.buyPrice > 0 &&
                                      t.price > 0 &&
                                      t.quantity > 0) {
                                    tradePnl =
                                        (t.price - t.buyPrice) * t.quantity;
                                  }
                                  final isTradePnlUp =
                                      tradePnl != null && tradePnl >= 0;
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      4,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isBuy
                                                ? const Color(0xFF10B981)
                                                : _upColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isBuy ? '매수' : '매도',
                                          style: GoogleFonts.inter(
                                            color: isBuy
                                                ? const Color(0xFF10B981)
                                                : _upColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          tradeDate,
                                          style: GoogleFonts.inter(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.4,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          qtyStr,
                                          style: GoogleFonts.inter(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          priceStr,
                                          style: GoogleFonts.robotoMono(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (tradePnl != null)
                                          Text(
                                            '${isTradePnlUp ? '+' : ''}${fmtP(tradePnl)}',
                                            style: GoogleFonts.robotoMono(
                                              color: isTradePnlUp
                                                  ? _upColor
                                                  : _downColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (!isBuy &&
                                            (widget.onEditLinkedSell != null ||
                                                widget.onDeleteLinkedSell !=
                                                    null)) ...[
                                          const SizedBox(width: 4),
                                          PopupMenuButton<String>(
                                            tooltip: '매도내역 메뉴',
                                            icon: Icon(
                                              Icons.more_vert,
                                              size: 16,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            onSelected: (value) {
                                              if (value == 'edit' &&
                                                  widget.onEditLinkedSell !=
                                                      null) {
                                                widget.onEditLinkedSell!(t);
                                              } else if (value == 'delete' &&
                                                  widget.onDeleteLinkedSell !=
                                                      null) {
                                                widget.onDeleteLinkedSell!(t);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (widget.onEditLinkedSell !=
                                                  null)
                                                const PopupMenuItem<String>(
                                                  value: 'edit',
                                                  child: Text('수정'),
                                                ),
                                              if (widget.onDeleteLinkedSell !=
                                                  null)
                                                const PopupMenuItem<String>(
                                                  value: 'delete',
                                                  child: Text('삭제'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                                if (hasLinkedRealized) ...[
                                  const SizedBox(height: 2),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      2,
                                      10,
                                      8,
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.04,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '총 실현손익',
                                            style: GoogleFonts.inter(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${isLinkedTotalUp ? '+' : ''}${fmtP(linkedRealizedTotal)}',
                                            style: GoogleFonts.robotoMono(
                                              color: isLinkedTotalUp
                                                  ? _upColor
                                                  : _downColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
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
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // ── 대각선 CLOSED 워터마크
              if (isClosed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Transform.rotate(
                        angle: -0.4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: cs.onSurface.withValues(alpha: 0.22),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'CLOSED',
                            style: GoogleFonts.robotoMono(
                              color: cs.onSurface.withValues(alpha: 0.13),
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 일지 상세 시트 ───────────────────────────────────────────────────────

class _JournalDetailSheet extends StatelessWidget {
  final TradingJournal journal;
  final List<TradingJournal> relatedBuys;
  final List<TradingJournal> linkedSells;
  final double remainingQty;
  final PriceResult? price;
  final FirestoreService firestoreService;
  final VoidCallback onEdit;
  final void Function(TradingJournal)? onEditSell;
  final void Function(TradingJournal)? onDeleteSell;
  final bool canEdit;

  const _JournalDetailSheet({
    required this.journal,
    this.relatedBuys = const [],
    required this.linkedSells,
    required this.remainingQty,
    required this.price,
    required this.firestoreService,
    required this.onEdit,
    this.onEditSell,
    this.onDeleteSell,
    this.canEdit = true,
  });

  Color _actionColor() {
    if (journal.action == '매수') return const Color(0xFF10B981);
    if (journal.action == '매도') return const Color(0xFFF04452);
    return Colors.orangeAccent;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;
    final actionColor = _actionColor();
    const upColor = Color(0xFFF04452); // DESIGN.md up
    const downColor = Color(0xFF1677FF); // DESIGN.md down
    final isKrw = journal.market != 'US';

    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';
    String fmtQty(double q) => q % 1 == 0 ? '${q.toInt()}주' : '$q주';

    final groupedBuys = relatedBuys.isNotEmpty
        ? relatedBuys
        : (journal.action == '매수' ? [journal] : <TradingJournal>[]);
    final baseQty = groupedBuys.fold<double>(0, (sum, b) => sum + b.quantity);
    final avgBuyPrice = baseQty > 0
        ? groupedBuys.fold<double>(
                0,
                (sum, b) => sum + (b.price * b.quantity),
              ) /
              baseQty
        : journal.price;
    final investedAmount = avgBuyPrice > 0 && baseQty > 0
        ? avgBuyPrice * baseQty
        : 0.0;

    final isClosed =
        journal.action == '매수' &&
        remainingQty <= _kQtyEpsilon &&
        linkedSells.isNotEmpty;

    // 실현손익 (매도) — 매도 시점 평균단가 기준
    final sellAvgBp = _avgBuyPriceAt(groupedBuys, journal.tradeDate);
    double? realizedPnl, realizedPnlPct;
    if (journal.action == '매도' &&
        sellAvgBp > 0 &&
        journal.price > 0 &&
        journal.quantity > 0) {
      realizedPnl = (journal.price - sellAvgBp) * journal.quantity;
      realizedPnlPct = (journal.price - sellAvgBp) / sellAvgBp * 100;
    }
    // 총 실현손익 (매수 종료 포지션) — 각 매도 시점 평균단가 기준
    double? totalRealizedPnl, totalRealizedPct;
    if (isClosed) {
      double total = 0;
      for (final s in linkedSells) {
        final bp = _avgBuyPriceAt(groupedBuys, s.tradeDate);
        if (s.price > 0 && s.quantity > 0 && bp > 0) {
          total += (s.price - bp) * s.quantity;
        }
      }
      totalRealizedPnl = total;
      if (investedAmount > 0) {
        totalRealizedPct = total / investedAmount * 100;
      }
    }
    // 평가손익 (매수 활성 포지션, remainingQty 기반)
    double? pnl, pnlPct;
    if (journal.action == '매수' &&
        !isClosed &&
        price != null &&
        avgBuyPrice > 0 &&
        remainingQty > 0) {
      pnl = (price!.price - avgBuyPrice) * remainingQty;
      pnlPct = (price!.price - avgBuyPrice) / avgBuyPrice * 100;
    }
    final isPnlUp = pnl != null && pnl >= 0;
    final isRealizedUp = realizedPnl != null && realizedPnl >= 0;
    final isTotalUp = totalRealizedPnl != null && totalRealizedPnl >= 0;

    final marketLabel = switch (journal.market) {
      'KS' => 'KOSPI',
      'KQ' => 'KOSDAQ',
      'US' => 'NYSE/NASDAQ',
      _ => journal.market,
    };

    Widget row(String label, String value, {Color? valueColor}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              color: valueColor ?? cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: cs.onSurface.withValues(alpha: 0.35),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );

    Widget divider() =>
        Divider(color: cs.onSurface.withValues(alpha: 0.07), height: 1);

    Widget pnlBox(String label, String amt, String pct, bool isUp) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isUp
            ? upColor.withValues(alpha: 0.09)
            : downColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUp
              ? upColor.withValues(alpha: 0.25)
              : downColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isUp ? upColor : downColor,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pct,
                style: GoogleFonts.inter(
                  color: (isUp ? upColor : downColor).withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            amt,
            style: GoogleFonts.inter(
              color: isUp ? upColor : downColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 헤더: 액션 배지 + 종목명 + 수정 버튼
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    journal.action,
                    style: GoogleFonts.inter(
                      color: actionColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isClosed) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '종료',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    journal.stockName,
                    style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onEdit();
                    },
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
            if (journal.ticker.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${journal.ticker}  ·  $marketLabel',
                style: GoogleFonts.robotoMono(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            divider(),

            // ── 거래 정보
            sectionLabel('거래 정보'),
            row('거래일', DateFormat('yyyy년 MM월 dd일').format(journal.tradeDate)),
            if (journal.action == '매도') ...[
              if (sellAvgBp > 0) row('평균단가', fmtP(sellAvgBp)),
              if (journal.price > 0) row('매도가', fmtP(journal.price)),
            ] else if (journal.action == '매수') ...[
              if (avgBuyPrice > 0) row('평균매수가', fmtP(avgBuyPrice)),
            ],
            if (journal.action == '매수' && baseQty > 0)
              row('누적수량', fmtQty(baseQty))
            else if (journal.quantity > 0)
              row('수량', fmtQty(journal.quantity)),
            if (journal.action == '매수' && investedAmount > 0)
              row('총 매입금액', fmtP(investedAmount))
            else if (journal.price > 0 && journal.quantity > 0)
              row('거래금액', fmtP(journal.price * journal.quantity)),

            // 매수 전용: 잔량 + 평가금액
            if (journal.action == '매수') ...[
              divider(),
              sectionLabel('포지션'),
              row(
                '잔량',
                fmtQty(remainingQty),
                valueColor: isClosed
                    ? cs.onSurface.withValues(alpha: 0.35)
                    : Colors.orangeAccent,
              ),
              if (!isClosed && price != null)
                row('평가금액', fmtP(price!.price * remainingQty)),
              if (!isClosed && price != null) ...[
                row('현재가', price!.formattedPrice),
                row(
                  '오늘 변동',
                  price!.formattedChange,
                  valueColor: price!.isUp
                      ? const Color(0xFF10B981)
                      : Colors.redAccent,
                ),
              ],
            ],

            // 실현손익 박스 (매도)
            if (realizedPnl != null)
              pnlBox(
                '실현손익',
                '${isRealizedUp ? '+' : ''}${fmtP(realizedPnl)}',
                '${isRealizedUp ? '+' : ''}${realizedPnlPct!.toStringAsFixed(2)}%',
                isRealizedUp,
              ),

            // 평가손익 박스 (활성 매수)
            if (pnl != null)
              pnlBox(
                '평가손익',
                '${isPnlUp ? '+' : ''}${fmtP(pnl)}',
                '${isPnlUp ? '+' : ''}${pnlPct!.toStringAsFixed(2)}%',
                isPnlUp,
              ),

            // 총 실현손익 박스 (종료 포지션)
            if (totalRealizedPnl != null)
              pnlBox(
                '총 실현손익',
                '${isTotalUp ? '+' : ''}${fmtP(totalRealizedPnl)}',
                totalRealizedPct != null
                    ? '${isTotalUp ? '+' : ''}${totalRealizedPct.toStringAsFixed(2)}%'
                    : '',
                isTotalUp,
              ),

            // ── 매도 내역 (매수 카드 + linkedSells 있을 때)
            if (journal.action == '매수' && linkedSells.isNotEmpty) ...[
              divider(),
              sectionLabel('매도 내역  (${linkedSells.length}건)'),
              ...linkedSells.map((s) {
                final sBp = _avgBuyPriceAt(groupedBuys, s.tradeDate);
                final sIsUp = sBp <= 0 || s.price >= sBp;
                final sPnl = sBp > 0 && s.price > 0
                    ? (s.price - sBp) * s.quantity
                    : null;
                final sPnlPct = sBp > 0 && s.price > 0
                    ? (s.price - sBp) / sBp * 100
                    : null;
                return Padding(
                  padding: EdgeInsets.zero,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: upColor.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF04452),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('yyyy.MM.dd').format(s.tradeDate),
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              fmtQty(s.quantity),
                              style: GoogleFonts.inter(
                                color: cs.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (onEditSell != null || onDeleteSell != null) ...[
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                tooltip: '매도내역 메뉴',
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 16,
                                  color: cs.onSurface.withValues(alpha: 0.45),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                onSelected: (value) {
                                  if (value == 'edit' && onEditSell != null) {
                                    Navigator.pop(context);
                                    onEditSell!(s);
                                  } else if (value == 'delete' &&
                                      onDeleteSell != null) {
                                    Navigator.pop(context);
                                    onDeleteSell!(s);
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (onEditSell != null)
                                    const PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Text('수정'),
                                    ),
                                  if (onDeleteSell != null)
                                    const PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Text('삭제'),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '매도가',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.35,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    fmtP(s.price),
                                    style: GoogleFonts.robotoMono(
                                      color: cs.onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (sPnl != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '실현손익',
                                      style: GoogleFonts.inter(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.35,
                                        ),
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sIsUp ? '+' : ''}${fmtP(sPnl)}',
                                      style: GoogleFonts.robotoMono(
                                        color: sIsUp ? upColor : downColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (sPnlPct != null)
                                      Text(
                                        '${sIsUp ? '+' : ''}${sPnlPct.toStringAsFixed(2)}%',
                                        style: GoogleFonts.inter(
                                          color: (sIsUp ? upColor : downColor)
                                              .withValues(alpha: 0.7),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
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
                );
              }),
            ],

            // ── 메모
            if (journal.note.isNotEmpty) ...[
              divider(),
              sectionLabel('메모'),
              Text(
                journal.note,
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ],

            // 공개 여부
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  journal.isPublic ? Icons.public : Icons.lock_outline,
                  size: 14,
                  color: journal.isPublic
                      ? const Color(0xFF10B981).withValues(alpha: 0.7)
                      : cs.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 6),
                Text(
                  journal.isPublic ? '커뮤니티에 공개됨' : '나만 볼 수 있음',
                  style: GoogleFonts.inter(
                    color: journal.isPublic
                        ? const Color(0xFF10B981).withValues(alpha: 0.7)
                        : cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 일지 작성/수정 시트 ──────────────────────────────────────────────────

class _JournalFormSheet extends StatefulWidget {
  final String uid;
  final String nickname;
  final TradingJournal? existing;
  final FirestoreService firestoreService;
  final TradingJournal? initialLinkedBuyJournal;
  final double initialRemainingQty;
  final String? initialAction;
  final String? initialStockName;
  final String? initialTicker;
  final String? initialRawMarket;

  const _JournalFormSheet({
    required this.uid,
    required this.nickname,
    required this.firestoreService,
    this.existing,
    this.initialLinkedBuyJournal,
    this.initialRemainingQty = 0,
    this.initialAction,
    this.initialStockName,
    this.initialTicker,
    this.initialRawMarket,
  });

  @override
  State<_JournalFormSheet> createState() => _JournalFormSheetState();
}

class _JournalFormSheetState extends State<_JournalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _priceCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _noteCtrl;

  StockPick? _selectedPick; // 추천주에서 선택
  double _remainingQty = 0; // 종목 기준 보유 잔량 (매수-매도)
  String? _qtyError; // 수량 초과 에러 메시지
  String _stockName = '';
  String _ticker = '';
  String _market = 'KR';
  String _rawMarket = ''; // fetchPrice용 원본 코드 (KS/KQ/US)
  String _action = '매수';
  DateTime _tradeDate = DateTime.now();
  bool _isPublic = false;
  bool _saving = false;
  bool _manualMode = false; // 직접 입력 모드

  PriceResult? _priceResult;
  bool _fetchingPrice = false;

  static const _actions = ['매수', '매도', '기타'];

  String _marketFromPick(StockPick p) => p.market == 'US' ? 'US' : 'KR';

  Future<void> _fetchPrice() async {
    if (_ticker.isEmpty || _rawMarket.isEmpty) return;
    setState(() {
      _fetchingPrice = true;
      _priceResult = null;
    });
    final result = await StockPriceService.fetchPrice(_ticker, _rawMarket);
    if (mounted) {
      setState(() {
        _priceResult = result;
        _fetchingPrice = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _priceCtrl = TextEditingController(
      text: e != null
          ? (e.price == e.price.truncate()
                ? e.price.toInt().toString()
                : e.price.toString())
          : '',
    );
    _quantityCtrl = TextEditingController(
      text: e != null
          ? (e.quantity == e.quantity.truncate()
                ? e.quantity.toInt().toString()
                : e.quantity.toString())
          : '',
    );
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    if (e != null) {
      _stockName = e.stockName;
      _ticker = e.ticker;
      _market = e.market;
      _rawMarket = {'KS', 'KQ', 'US'}.contains(e.market) ? e.market : '';
      _action = e.action;
      _tradeDate = e.tradeDate;
      _isPublic = e.isPublic;
      _manualMode = true;
      if (e.action == '매도') {
        _refreshRemainingForSelectedStock();
      }
    } else if (widget.initialLinkedBuyJournal != null) {
      final buy = widget.initialLinkedBuyJournal!;
      _action = '매도';
      _stockName = buy.stockName;
      _ticker = buy.ticker;
      _market = buy.market == 'US' ? 'US' : 'KR';
      _rawMarket = {'KS', 'KQ', 'US'}.contains(buy.market) ? buy.market : '';
      _manualMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchPrice();
        _refreshRemainingForSelectedStock();
      });
    } else if (widget.initialAction != null &&
        _actions.contains(widget.initialAction)) {
      _action = widget.initialAction!;
      final initialTicker = (widget.initialTicker ?? '').trim().toUpperCase();
      final initialName = (widget.initialStockName ?? '').trim();
      final initialRawMarket = (widget.initialRawMarket ?? '')
          .trim()
          .toUpperCase();
      if (initialTicker.isNotEmpty) {
        _ticker = initialTicker;
        _stockName = initialName.isEmpty ? initialTicker : initialName;
        _rawMarket = {'KS', 'KQ', 'US'}.contains(initialRawMarket)
            ? initialRawMarket
            : '';
        _market = _rawMarket == 'US' ? 'US' : 'KR';
        _manualMode = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchPrice();
          if (_action == '매도') {
            _refreshRemainingForSelectedStock();
          }
        });
      }
    }
  }

  Future<double> _computeRemainingQtyForStock({
    required String ticker,
    required String market,
    String? excludingSellId,
  }) async {
    if (ticker.trim().isEmpty) return 0;
    final allJournals = await widget.firestoreService.getMyJournalsByUidOnce(
      widget.uid,
    );
    final buys = allJournals
        .where(
          (j) => j.action == '매수' && j.ticker == ticker && j.market == market,
        )
        .fold(0.0, (sum, j) => sum + j.quantity);
    final sells = allJournals
        .where(
          (j) =>
              j.action == '매도' &&
              j.ticker == ticker &&
              j.market == market &&
              (excludingSellId == null || j.id != excludingSellId),
        )
        .fold(0.0, (sum, j) => sum + j.quantity);
    return (buys - sells).clamp(0.0, buys);
  }

  Future<void> _refreshRemainingForSelectedStock() async {
    if (_ticker.trim().isEmpty) return;
    final remaining = await _computeRemainingQtyForStock(
      ticker: _ticker,
      market: _rawMarket.isNotEmpty ? _rawMarket : _market,
      excludingSellId: widget.existing?.id,
    );
    if (mounted) {
      setState(() => _remainingQty = remaining);
    }
  }

  Future<void> _openStockPicker() async {
    final picked = await showModalBottomSheet<StockPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StockPickerSheet(firestoreService: widget.firestoreService),
    );
    if (picked != null) {
      setState(() {
        _selectedPick = picked;
        _manualMode = false;
        _stockName = picked.name;
        _ticker = picked.ticker;
        _market = _marketFromPick(picked);
        _rawMarket = picked.market; // KS/KQ/US
        _priceResult = null;
      });
      _fetchPrice();
    }
  }

  Future<void> _openSellStockPicker() async {
    final picked = await showModalBottomSheet<_SellStockSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SellStockPickerSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
      ),
    );
    if (picked != null) {
      if (!mounted) return;
      setState(() {
        _remainingQty = picked.remainingQty;
        _stockName = picked.stockName;
        _ticker = picked.ticker;
        _rawMarket = {'KS', 'KQ', 'US'}.contains(picked.market)
            ? picked.market
            : '';
        _market = picked.market == 'US' ? 'US' : 'KR';
        _priceResult = null;
      });
      if (_rawMarket.isNotEmpty) _fetchPrice();
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedPick = null;
      _manualMode = false;
      _stockName = '';
      _ticker = '';
      _rawMarket = '';
      _priceResult = null;
    });
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _quantityCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tradeDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: const Color(0xFF10B981),
            onPrimary: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _tradeDate = picked);
  }

  Future<void> _save() async {
    if (_stockName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종목을 선택하거나 입력하세요')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    // 매수 수정 시, 종목 기준 누적 매도수량보다 총 매수수량이 작아지면 안 된다.
    if (widget.existing != null &&
        widget.existing!.action == '매수' &&
        _action == '매수') {
      final nextQty = double.tryParse(_quantityCtrl.text.trim()) ?? 0;
      if (nextQty > 0) {
        final existing = widget.existing!;
        final allJournals = await widget.firestoreService
            .getMyJournalsByUidOnce(widget.uid);
        final soldQtyByStock = allJournals
            .where(
              (j) =>
                  j.action == '매도' &&
                  j.ticker == existing.ticker &&
                  j.market == existing.market,
            )
            .fold(0.0, (sum, j) => sum + j.quantity);
        final otherBuyQty = allJournals
            .where(
              (j) =>
                  j.action == '매수' &&
                  j.ticker == existing.ticker &&
                  j.market == existing.market &&
                  j.id != existing.id,
            )
            .fold(0.0, (sum, j) => sum + j.quantity);
        final totalBuyAfterEdit = otherBuyQty + nextQty;
        if (totalBuyAfterEdit + _kQtyEpsilon < soldQtyByStock) {
          if (!mounted) return;
          final soldStr = soldQtyByStock % 1 == 0
              ? soldQtyByStock.toInt().toString()
              : soldQtyByStock.toString();
          setState(
            () => _qtyError = '해당 종목은 이미 총 $soldStr주 매도되어 수량을 더 줄일 수 없습니다',
          );
          return;
        }
      }
    }
    // 매도 수량 초과 검증 (새 매도 및 수정 모두)
    if (_action == '매도') {
      if (_ticker.trim().isNotEmpty) {
        final latestRemaining = await _computeRemainingQtyForStock(
          ticker: _ticker,
          market: _rawMarket.isNotEmpty ? _rawMarket : _market,
          excludingSellId: widget.existing?.id,
        );
        if (mounted) setState(() => _remainingQty = latestRemaining);
      }
      final enteredQty = double.tryParse(_quantityCtrl.text.trim()) ?? 0;
      if (enteredQty > _remainingQty + _kQtyEpsilon) {
        final maxStr = _remainingQty % 1 == 0
            ? _remainingQty.toInt().toString()
            : _remainingQty.toString();
        setState(() => _qtyError = '$maxStr주 이상 매도할 수 없습니다');
        return;
      }
    }
    setState(() => _qtyError = null);
    setState(() => _saving = true);
    try {
      final journal = TradingJournal(
        id: widget.existing?.id ?? '',
        uid: widget.uid,
        nickname: widget.nickname,
        stockName: _stockName,
        ticker: _ticker.toUpperCase(),
        market: _rawMarket.isNotEmpty ? _rawMarket : _market,
        action: _action,
        price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
        quantity: double.tryParse(_quantityCtrl.text.trim()) ?? 0,
        tradeDate: _tradeDate,
        note: _noteCtrl.text.trim(),
        isPublic: _isPublic,
        likes: widget.existing?.likes ?? 0,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        buyPrice: widget.existing?.action == '매도'
            ? widget.existing!.buyPrice
            : 0,
        linkedBuyId: widget.existing?.action == '매도'
            ? widget.existing!.linkedBuyId
            : '',
      );
      if (widget.existing != null) {
        await widget.firestoreService.updateJournal(journal);
        AnalyticsService.instance.logEditJournal();
      } else {
        await widget.firestoreService.addJournal(journal);
        AnalyticsService.instance.logWriteJournal(_action);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    final inputFill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);

    InputDecoration inputDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: isDark ? Colors.white30 : Colors.black26,
        fontSize: 14,
      ),
      filled: true,
      fillColor: inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── 수량 초과 에러 배너
                if (_qtyError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _qtyError!,
                            softWrap: true,
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  widget.existing != null ? '매매일지 수정' : '매매일지 작성',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 18),
                // 매매 구분
                Text(
                  '매매 구분',
                  style: GoogleFonts.inter(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: _actions.map((a) {
                    final selected = _action == a;
                    final color = a == '매수'
                        ? const Color(0xFF10B981)
                        : a == '매도'
                        ? Colors.redAccent
                        : Colors.orangeAccent;
                    // 기존 항목 수정 시 액션 변경 불가
                    final isLocked =
                        widget.existing != null && a != widget.existing!.action;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (a == _action || isLocked) return;
                          setState(() {
                            _action = a;
                            if (a == '매도' && widget.existing == null) {
                              _selectedPick = null;
                              _stockName = '';
                              _ticker = '';
                              _rawMarket = '';
                              _market = 'KR';
                              _remainingQty = 0;
                              _priceResult = null;
                              _manualMode = false;
                            }
                          });
                        },
                        child: Container(
                          margin: EdgeInsets.only(
                            right: a == _actions.last ? 0 : 8,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isLocked
                                ? cs.onSurface.withValues(alpha: 0.02)
                                : selected
                                ? color.withValues(alpha: 0.15)
                                : inputFill,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? color.withValues(alpha: 0.5)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              a,
                              style: GoogleFonts.inter(
                                color: isLocked
                                    ? cs.onSurface.withValues(alpha: 0.2)
                                    : selected
                                    ? color
                                    : (isDark
                                          ? Colors.white54
                                          : Colors.black45),
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                // 종목 / 매수포지션 선택
                if (widget.existing != null || _action != '매도') ...[
                  // 매도 수정 시 종목 변경 불가 — 잠긴 표시
                  if (widget.existing != null && _action == '매도') ...[
                    Text(
                      '종목',
                      style: GoogleFonts.inter(
                        color: labelColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _stockName,
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_ticker.isNotEmpty)
                            Text(
                              _ticker,
                              style: GoogleFonts.robotoMono(
                                color: cs.onSurface.withValues(alpha: 0.3),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '종목',
                          style: GoogleFonts.inter(
                            color: labelColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_stockName.isNotEmpty || _manualMode)
                          GestureDetector(
                            onTap: _clearSelection,
                            child: Text(
                              '다시 선택',
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.4),
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // ① 아무것도 선택 안 됐을 때: 두 버튼 노출
                    if (_stockName.isEmpty && !_manualMode)
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _openStockPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.star_outline,
                                      size: 15,
                                      color: Color(0xFF10B981),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '추천주에서 선택',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF10B981),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _manualMode = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: inputFill,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.onSurface.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 15,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '직접 입력',
                                      style: GoogleFonts.inter(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    // ② 추천주에서 선택된 경우
                    else if (_selectedPick != null && !_manualMode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _stockName,
                                    style: GoogleFonts.inter(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (_ticker.isNotEmpty)
                                    Text(
                                      _ticker,
                                      style: GoogleFonts.robotoMono(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _market,
                                style: GoogleFonts.inter(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    // ②-1 상세페이지에서 자동 주입된 종목
                    else if (_stockName.isNotEmpty && !_manualMode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _stockName,
                                    style: GoogleFonts.inter(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (_ticker.isNotEmpty)
                                    Text(
                                      _ticker,
                                      style: GoogleFonts.robotoMono(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _market,
                                style: GoogleFonts.inter(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    // ③ 직접 입력 모드 (전체 종목 검색)
                    else
                      StockSearchField(
                        initialTicker: _ticker,
                        initialName: _stockName,
                        onSelected: (ticker, name, market) {
                          setState(() {
                            _ticker = ticker;
                            _stockName = name;
                            _rawMarket = market; // KS/KQ/US
                            _market = market == 'US' ? 'US' : 'KR';
                            _priceResult = null;
                          });
                          _fetchPrice();
                        },
                      ),
                    // 현재가 표시 (종목 선택 후)
                    if (_ticker.isNotEmpty &&
                        (_priceResult != null || _fetchingPrice))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _fetchingPrice
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '현재가 조회 중...',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.35,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Text(
                                    '현재가:',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _priceResult!.formattedPrice,
                                    style: GoogleFonts.robotoMono(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _priceResult!.formattedChange,
                                    style: GoogleFonts.inter(
                                      color: _priceResult!.isUp
                                          ? const Color(0xFF10B981)
                                          : Colors.redAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ], // else (일반 종목 선택)
                ] else ...[
                  // 매도 신규: 종목 기준으로 선택
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '종목',
                        style: GoogleFonts.inter(
                          color: labelColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_stockName.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() {
                            _stockName = '';
                            _ticker = '';
                            _rawMarket = '';
                            _market = 'KR';
                            _remainingQty = 0;
                            _priceResult = null;
                          }),
                          child: Text(
                            '다시 선택',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_stockName.isEmpty)
                    GestureDetector(
                      onTap: _openSellStockPicker,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.list_alt,
                              size: 15,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '보유 종목 선택',
                              style: GoogleFonts.inter(
                                color: Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.sell_outlined,
                                size: 13,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _stockName,
                                  style: GoogleFonts.inter(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (_ticker.isNotEmpty)
                                Text(
                                  _ticker,
                                  style: GoogleFonts.robotoMono(
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '보유 잔량 ${_remainingQty % 1 == 0 ? _remainingQty.toInt() : _remainingQty}주',
                            style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_ticker.isNotEmpty &&
                      (_priceResult != null || _fetchingPrice))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _fetchingPrice
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '현재가 조회 중...',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface.withValues(alpha: 0.35),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Text(
                                  '현재가:',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface.withValues(alpha: 0.4),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _priceResult!.formattedPrice,
                                  style: GoogleFonts.robotoMono(
                                    color: cs.onSurface.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _priceResult!.formattedChange,
                                  style: GoogleFonts.inter(
                                    color: _priceResult!.isUp
                                        ? const Color(0xFF10B981)
                                        : Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
                const SizedBox(height: 12),
                // 가격, 수량 (기타는 생략)
                if (_action != '기타')
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _action == '매수'
                                  ? '매수가'
                                  : _action == '매도'
                                  ? '매도가'
                                  : '가격 (선택)',
                              style: GoogleFonts.inter(
                                color: labelColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _priceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: inputDeco('0'),
                              validator: (v) {
                                if (v != null &&
                                    v.trim().isNotEmpty &&
                                    double.tryParse(v.trim()) == null) {
                                  return '숫자 입력';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _action == '매도' && _remainingQty > 0
                                  ? '수량 (최대 ${_remainingQty % 1 == 0 ? _remainingQty.toInt() : _remainingQty}주)'
                                  : '수량',
                              style: GoogleFonts.inter(
                                color: labelColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _quantityCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: inputDeco('0'),
                              onChanged: (_) {
                                if (_qtyError != null) {
                                  setState(() => _qtyError = null);
                                }
                              },
                              validator: (v) {
                                final text = v?.trim() ?? '';
                                if (text.isEmpty) return '수량 입력';
                                final qty = double.tryParse(text);
                                if (qty == null) return '숫자 입력';
                                if (qty <= 0) return '0보다 크게 입력';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                // 거래일 (기타는 생략)
                if (_action != '기타') ...[
                  const SizedBox(height: 12),
                  Text(
                    '거래일',
                    style: GoogleFonts.inter(
                      color: labelColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: inputFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('yyyy년 MM월 dd일').format(_tradeDate),
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // 메모
                Text(
                  '메모 (선택)',
                  style: GoogleFonts.inter(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                  decoration: inputDeco(
                    '매매 이유, 전략, 느낀 점 등을 적어보세요',
                  ).copyWith(contentPadding: const EdgeInsets.all(14)),
                ),
                const SizedBox(height: 14),
                // 공개 여부
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: inputFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.public_outlined,
                        size: 18,
                        color: _isPublic
                            ? const Color(0xFF10B981)
                            : (isDark ? Colors.white38 : Colors.black38),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '커뮤니티에 공유',
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '다른 유저들이 볼 수 있습니다',
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isPublic,
                        onChanged: (v) => setState(() => _isPublic = v),
                        activeThumbColor: const Color(0xFF10B981),
                        activeTrackColor: const Color(
                          0xFF10B981,
                        ).withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
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
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            widget.existing != null ? '수정 완료' : '저장',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 추천주 선택 시트 ──────────────────────────────────────────────────────

class _StockPickerSheet extends StatefulWidget {
  final FirestoreService firestoreService;
  const _StockPickerSheet({required this.firestoreService});

  @override
  State<_StockPickerSheet> createState() => _StockPickerSheetState();
}

class _StockPickerSheetState extends State<_StockPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  List<StockPick> _allPicks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.firestoreService.getAllStockPicksOnce().then((picks) {
      if (mounted) {
        setState(() {
          _allPicks = picks;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<StockPick> get _filtered {
    if (_query.isEmpty) return _allPicks;
    final q = _query.toLowerCase();
    return _allPicks
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.ticker.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '종목 선택',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: '종목명 또는 티커 검색',
                    hintStyle: GoogleFonts.inter(
                      color: isDark ? Colors.white30 : Colors.black26,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark ? Colors.white38 : Colors.black38,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)),
                  )
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      '검색 결과가 없습니다',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final pick = _filtered[i];
                      final isCompleted = pick.isCompleted;
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, pick),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.onSurface.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.onSurface.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  pick.ticker,
                                  style: GoogleFonts.robotoMono(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pick.name,
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (isCompleted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '종료',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  pick.market,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF10B981),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── 매도 종목 선택 시트 ────────────────────────────────────────────────────

class _SellStockSelection {
  final String stockName;
  final String ticker;
  final String market;
  final double remainingQty;

  const _SellStockSelection({
    required this.stockName,
    required this.ticker,
    required this.market,
    required this.remainingQty,
  });
}

class _SellStockPickerSheet extends StatelessWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _SellStockPickerSheet({
    required this.uid,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '매도할 종목 선택',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<TradingJournal>>(
              stream: firestoreService.getMyJournals(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)),
                  );
                }
                final allJournals = snapshot.data ?? [];
                final stockMap = <String, _SellStockSelection>{};
                for (final j in allJournals) {
                  if (j.ticker.isEmpty) continue;
                  final key = '${j.market}:${j.ticker}';
                  final existing = stockMap[key];
                  final nextQty =
                      (existing?.remainingQty ?? 0) +
                      (j.action == '매수'
                          ? j.quantity
                          : j.action == '매도'
                          ? -j.quantity
                          : 0);
                  stockMap[key] = _SellStockSelection(
                    stockName: j.stockName,
                    ticker: j.ticker,
                    market: j.market,
                    remainingQty: nextQty,
                  );
                }
                final candidates =
                    stockMap.values
                        .where((s) => s.remainingQty > _kQtyEpsilon)
                        .toList()
                      ..sort(
                        (a, b) => b.remainingQty.compareTo(a.remainingQty),
                      );
                if (candidates.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          color: cs.onSurface.withValues(alpha: 0.2),
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '매도 가능한 종목이 없습니다',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '보유 잔량이 있는 종목이 없습니다',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.25),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: candidates.length,
                  itemBuilder: (ctx, i) {
                    final item = candidates[i];
                    final qtyStr = item.remainingQty % 1 == 0
                        ? '${item.remainingQty.toInt()}주'
                        : '${item.remainingQty}주';
                    final marketLabel = switch (item.market) {
                      'KS' => 'KOSPI',
                      'KQ' => 'KOSDAQ',
                      'US' => 'US',
                      _ => item.market,
                    };
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, item),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.onSurface.withValues(alpha: 0.07),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.sell_outlined,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        item.stockName,
                                        style: GoogleFonts.inter(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.ticker}  ·  $marketLabel  ·  잔량 $qtyStr',
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.45,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
