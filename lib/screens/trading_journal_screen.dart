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
import '../widgets/stock_search_field.dart';
import 'login_screen.dart';
import 'journal_chart_screen.dart';

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

  void _openForm({
    TradingJournal? existing,
    TradingJournal? linkedBuy,
    double remainingQty = 0,
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
          // 매도 항목을 linkedBuyId 기준으로 그룹핑
          final linkedSellMap = <String, List<TradingJournal>>{};
          final linkedSellIds = <String>{};
          for (final j in journals) {
            if (j.action == '매도' && j.linkedBuyId.isNotEmpty) {
              linkedSellMap.putIfAbsent(j.linkedBuyId, () => []).add(j);
              linkedSellIds.add(j.id);
            }
          }
          // 상위 레벨 항목: 연결된 매도 제외
          final topLevel = journals
              .where((j) => !linkedSellIds.contains(j.id))
              .toList();

          // 보유 종목 계산 (잔량 > 0인 매수 포지션)
          final holdings = <({TradingJournal buy, double remainingQty})>[];
          for (final j in journals) {
            if (j.action == '매수') {
              final sells = linkedSellMap[j.id] ?? [];
              final soldQty = sells.fold(0.0, (s, sell) => s + sell.quantity);
              final remaining = (j.quantity - soldQty).clamp(0.0, j.quantity);
              if (remaining > 0)
                holdings.add((buy: j, remainingQty: remaining));
            }
          }

          return Column(
            children: [
              _PortfolioSummarySection(holdings: holdings),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: topLevel.length,
                  itemBuilder: (ctx, i) {
                    final j = topLevel[i];
                    return _JournalCard(
                      key: ValueKey(j.id),
                      journal: j,
                      linkedSells: linkedSellMap[j.id] ?? [],
                      firestoreService: _firestoreService,
                      onEdit: () => _openForm(existing: j),
                      onEditLinkedSell: (sell) => _openForm(existing: sell),
                      onSellQuick: (buy, remainingQty) =>
                          _openForm(linkedBuy: buy, remainingQty: remainingQty),
                      onDeleteLinkedSell: (sell) async {
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
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
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
  final List<TradingJournal> linkedSells;
  final FirestoreService firestoreService;
  final VoidCallback onEdit;
  final void Function(TradingJournal)? onEditLinkedSell;
  final void Function(TradingJournal)? onDeleteLinkedSell;
  final void Function(TradingJournal buy, double remainingQty)? onSellQuick;

  const _JournalCard({
    super.key,
    required this.journal,
    this.linkedSells = const [],
    required this.firestoreService,
    required this.onEdit,
    this.onEditLinkedSell,
    this.onDeleteLinkedSell,
    this.onSellQuick,
  });

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard> {
  PriceResult? _price;
  bool _fetchingPrice = false;
  static const _upColor = Color(0xFFF04452); // DESIGN.md up
  static const _downColor = Color(0xFF1677FF); // DESIGN.md down

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    final ticker = widget.journal.ticker;
    final market = widget.journal.market;
    // Only fetch for known raw markets (KS/KQ/US); skip 'KR'/'기타' (legacy)
    if (ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(market)) return;
    setState(() => _fetchingPrice = true);
    final result = await StockPriceService.fetchPrice(ticker, market);
    if (mounted)
      setState(() {
        _price = result;
        _fetchingPrice = false;
      });
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
    // 매수 카드이고 ticker가 있으면 차트 페이지로
    if (widget.journal.action == '매수' &&
        widget.journal.ticker.isNotEmpty &&
        {'KS', 'KQ', 'US'}.contains(widget.journal.market)) {
      final sameStockJournals = await widget.firestoreService
          .getMyJournalsByUidOnce(widget.journal.uid);
      final relatedBuys = sameStockJournals
          .where(
            (j) =>
                j.action == '매수' &&
                j.ticker == widget.journal.ticker &&
                j.market == widget.journal.market,
          )
          .toList();
      final relatedSells = sameStockJournals
          .where(
            (j) =>
                j.action == '매도' &&
                j.ticker == widget.journal.ticker &&
                j.market == widget.journal.market,
          )
          .toList();
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JournalChartScreen(
            buy: widget.journal,
            linkedSells: widget.linkedSells,
            relatedBuys: relatedBuys,
            relatedSells: relatedSells,
            firestoreService: widget.firestoreService,
            onEdit: widget.onEdit,
            onEditSell: widget.onEditLinkedSell,
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

    // 잔량 계산 (매수 카드)
    final soldQty = widget.linkedSells.fold(0.0, (s, j) => s + j.quantity);
    final remainingQty = journal.action == '매수'
        ? (journal.quantity - soldQty).clamp(0.0, journal.quantity)
        : 0.0;
    final isClosed =
        journal.action == '매수' &&
        remainingQty == 0 &&
        widget.linkedSells.isNotEmpty;

    // 총 실현손익 (포지션 전체 종료 시)
    double? totalRealizedPnl;
    if (isClosed) {
      double total = 0;
      for (final s in widget.linkedSells) {
        if (s.buyPrice > 0 && s.price > 0) {
          total += (s.price - s.buyPrice) * s.quantity;
        }
      }
      totalRealizedPnl = total;
    }

    // 실현손익 (독립 매도 카드용)
    double? realizedPnl, realizedPnlPct;
    if (journal.action == '매도' &&
        journal.buyPrice > 0 &&
        journal.price > 0 &&
        journal.quantity > 0) {
      realizedPnl = (journal.price - journal.buyPrice) * journal.quantity;
      realizedPnlPct =
          (journal.price - journal.buyPrice) / journal.buyPrice * 100;
    }
    final isRealizedUp = realizedPnl != null && realizedPnl >= 0;

    final linkedRealizedTotal = widget.linkedSells.fold<double>(0, (sum, s) {
      if (s.buyPrice > 0 && s.price > 0 && s.quantity > 0) {
        return sum + ((s.price - s.buyPrice) * s.quantity);
      }
      return sum;
    });
    final hasLinkedRealized = widget.linkedSells.any(
      (s) => s.buyPrice > 0 && s.price > 0 && s.quantity > 0,
    );
    final isLinkedTotalUp = linkedRealizedTotal >= 0;
    // 평가손익 (매수 + 잔량 > 0 + 현재가)
    double? pnl, pnlPct;
    if (journal.action != '매도' &&
        !isClosed &&
        remainingQty > 0 &&
        _price != null &&
        journal.price > 0) {
      pnl = (_price!.price - journal.price) * remainingQty;
      pnlPct = (_price!.price - journal.price) / journal.price * 100;
    }
    final isPnlUp = pnl != null && pnl >= 0;

    // 마켓 라벨
    final marketLabel = switch (journal.market) {
      'KS' => 'KOSPI',
      'KQ' => 'KOSDAQ',
      'US' => 'NYSE/NASDAQ',
      _ => journal.market,
    };
    final tradeDateText = DateFormat('yyyy.MM.dd').format(journal.tradeDate);

    return GestureDetector(
      onTap: () =>
          _openDetail(context, isClosed: isClosed, remainingQty: remainingQty),
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
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.35),
                              ),
                              color: isDark
                                  ? const Color(0xFF1A2035)
                                  : Colors.white,
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  widget.onEdit();
                                } else if (v == 'public') {
                                  await widget.firestoreService
                                      .toggleJournalPublic(
                                        journal.id,
                                        journal.isPublic,
                                      );
                                  AnalyticsService.instance
                                      .logToggleJournalPublic(
                                        !journal.isPublic,
                                      );
                                } else if (v == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: isDark
                                          ? const Color(0xFF1A2035)
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      title: Text(
                                        '삭제',
                                        style: GoogleFonts.inter(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      content: Text(
                                        '이 일지를 삭제할까요?',
                                        style: GoogleFonts.inter(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(
                                            '취소',
                                            style: GoogleFonts.inter(
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
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
                                    await widget.firestoreService.deleteJournal(
                                      journal.id,
                                    );
                                    AnalyticsService.instance
                                        .logDeleteJournal();
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                if (!isClosed)
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.edit_outlined,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '수정',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'public',
                                  child: Row(
                                    children: [
                                      Icon(
                                        journal.isPublic
                                            ? Icons.lock_outline
                                            : Icons.public_outlined,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        journal.isPublic
                                            ? '비공개로 전환'
                                            : '커뮤니티에 공유',
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
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
                              final qtyStr = journal.quantity % 1 == 0
                                  ? '${journal.quantity.toInt()}주'
                                  : '${journal.quantity}주';

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
                                if (!isClosed) {
                                  const upColor = Color(
                                    0xFFF04452,
                                  ); // DESIGN.md up
                                  const downColor = Color(
                                    0xFF1677FF,
                                  ); // DESIGN.md down
                                  final hasLive =
                                      _price != null && journal.price > 0;
                                  final isUpLive = hasLive
                                      ? _price!.price >= journal.price
                                      : false;
                                  final currentPrice =
                                      _price?.formattedPrice ?? '-';
                                  final remainingQtyStr = remainingQty % 1 == 0
                                      ? '${remainingQty.toInt()}주'
                                      : '$remainingQty주';
                                  final buyAmount =
                                      journal.price > 0 && remainingQty > 0
                                      ? fmtP(journal.price * remainingQty)
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

                                  // 1행: 매수가 | 현재가
                                  rows.add(
                                    IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          cell(
                                            '매수가',
                                            journal.price > 0
                                                ? fmtP(journal.price)
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
                                      (journal.price > 0 &&
                                          journal.quantity > 0)
                                      ? journal.price * journal.quantity
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
                                            journal.price > 0
                                                ? fmtP(journal.price)
                                                : '-',
                                          ),
                                          vd(),
                                          cell(
                                            '평균매도가',
                                            totalSellQty > 0
                                                ? fmtP(avgSellPrice)
                                                : '-',
                                            valueColor: totalSellQty > 0
                                                ? (avgSellPrice >= journal.price
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
                                        if (journal.buyPrice > 0) ...[
                                          cell('매수가', fmtP(journal.buyPrice)),
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
                        if (realizedPnl != null) ...[
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
                        if (journal.action == '기타' && !isClosed) ...[
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
                        // ── 매도 내역 (linked sells)
                        if (widget.linkedSells.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: _upColor.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _upColor.withValues(alpha: 0.12),
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
                                          color: _upColor.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '매도',
                                          style: GoogleFonts.inter(
                                            color: _upColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${widget.linkedSells.length}건',
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
                                ...widget.linkedSells.map((sell) {
                                  final sellDate = DateFormat(
                                    'MM/dd',
                                  ).format(sell.tradeDate);
                                  final qtyStr = sell.quantity % 1 == 0
                                      ? '${sell.quantity.toInt()}주'
                                      : '${sell.quantity}주';
                                  final sellPriceStr = sell.price > 0
                                      ? fmtP(sell.price)
                                      : '-';
                                  double? spnl;
                                  if (sell.buyPrice > 0 && sell.price > 0) {
                                    spnl =
                                        (sell.price - sell.buyPrice) *
                                        sell.quantity;
                                  }
                                  final isSpnlUp = spnl != null && spnl >= 0;
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      0,
                                    ),
                                    child: Row(
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
                                          sellDate,
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
                                          sellPriceStr,
                                          style: GoogleFonts.robotoMono(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (spnl != null)
                                          Text(
                                            '${isSpnlUp ? '+' : ''}${fmtP(spnl)}',
                                            style: GoogleFonts.robotoMono(
                                              color: isSpnlUp
                                                  ? _upColor
                                                  : _downColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (widget.onEditLinkedSell != null ||
                                            widget.onDeleteLinkedSell !=
                                                null) ...[
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
                                                widget.onEditLinkedSell!(sell);
                                              } else if (value == 'delete' &&
                                                  widget.onDeleteLinkedSell !=
                                                      null) {
                                                widget.onDeleteLinkedSell!(
                                                  sell,
                                                );
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
                  // ── 빠른 매도 행
                  if (journal.action == '매수' &&
                      !isClosed &&
                      widget.onSellQuick != null) ...[
                    Divider(
                      height: 1,
                      color: cs.onSurface.withValues(alpha: 0.07),
                    ),
                    GestureDetector(
                      onTap: () => widget.onSellQuick!(journal, remainingQty),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: _upColor.withValues(alpha: 0.04),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.trending_down_rounded,
                              size: 15,
                              color: _upColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '매도',
                              style: GoogleFonts.inter(
                                color: _upColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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

    final isClosed =
        journal.action == '매수' && remainingQty == 0 && linkedSells.isNotEmpty;

    // 실현손익 (매도)
    double? realizedPnl, realizedPnlPct;
    if (journal.action == '매도' &&
        journal.buyPrice > 0 &&
        journal.price > 0 &&
        journal.quantity > 0) {
      realizedPnl = (journal.price - journal.buyPrice) * journal.quantity;
      realizedPnlPct =
          (journal.price - journal.buyPrice) / journal.buyPrice * 100;
    }
    // 총 실현손익 (매수 종료 포지션)
    double? totalRealizedPnl, totalRealizedPct;
    if (isClosed) {
      double total = 0;
      bool hasData = false;
      for (final s in linkedSells) {
        if (s.buyPrice > 0 && s.price > 0) {
          total += (s.price - s.buyPrice) * s.quantity;
          hasData = true;
        }
      }
      if (hasData) {
        totalRealizedPnl = total;
        if (journal.price > 0 && journal.quantity > 0) {
          totalRealizedPct = total / (journal.price * journal.quantity) * 100;
        }
      }
    }
    // 평가손익 (매수 활성 포지션, remainingQty 기반)
    double? pnl, pnlPct;
    if (journal.action == '매수' &&
        !isClosed &&
        price != null &&
        journal.price > 0 &&
        remainingQty > 0) {
      pnl = (price!.price - journal.price) * remainingQty;
      pnlPct = (price!.price - journal.price) / journal.price * 100;
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
              if (journal.buyPrice > 0) row('매수가', fmtP(journal.buyPrice)),
              if (journal.price > 0) row('매도가', fmtP(journal.price)),
            ] else if (journal.action == '매수') ...[
              if (journal.price > 0) row('매수가', fmtP(journal.price)),
            ],
            if (journal.quantity > 0) row('수량', fmtQty(journal.quantity)),
            if (journal.price > 0 && journal.quantity > 0)
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
                final sIsUp = s.buyPrice > 0 && s.price >= s.buyPrice;
                final sPnl = s.buyPrice > 0 && s.price > 0
                    ? (s.price - s.buyPrice) * s.quantity
                    : null;
                final sPnlPct = s.buyPrice > 0 && s.price > 0
                    ? (s.price - s.buyPrice) / s.buyPrice * 100
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

  const _JournalFormSheet({
    required this.uid,
    required this.nickname,
    required this.firestoreService,
    this.existing,
    this.initialLinkedBuyJournal,
    this.initialRemainingQty = 0,
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
  TradingJournal? _linkedBuyJournal; // 매도 시 연결된 매수 포지션
  double _remainingQty = 0; // 매수 잔량 (이미 매도된 수량 차감 후)
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
    if (mounted)
      setState(() {
        _priceResult = result;
        _fetchingPrice = false;
      });
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
      _action = e.action;
      _tradeDate = e.tradeDate;
      _isPublic = e.isPublic;
      _manualMode = true;
      if (e.action == '매도' && e.linkedBuyId.isNotEmpty) {
        _loadRemainingForEdit(e);
      }
    } else if (widget.initialLinkedBuyJournal != null) {
      final buy = widget.initialLinkedBuyJournal!;
      _action = '매도';
      _linkedBuyJournal = buy;
      _remainingQty = widget.initialRemainingQty;
      _stockName = buy.stockName;
      _ticker = buy.ticker;
      _market = buy.market == 'US' ? 'US' : 'KR';
      _rawMarket = {'KS', 'KQ', 'US'}.contains(buy.market) ? buy.market : '';
      _manualMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPrice());
    }
  }

  Future<void> _loadRemainingForEdit(TradingJournal sell) async {
    final allJournals = await widget.firestoreService
        .getMyJournals(widget.uid)
        .first;
    // 매수 찾기
    final buy = allJournals.where((j) => j.id == sell.linkedBuyId).firstOrNull;
    if (buy == null) return;
    // 다른 매도들의 수량 합계 (이 sell 제외)
    final otherSoldQty = allJournals
        .where(
          (j) =>
              j.action == '매도' &&
              j.linkedBuyId == sell.linkedBuyId &&
              j.id != sell.id,
        )
        .fold(0.0, (sum, j) => sum + j.quantity);
    final remaining = buy.quantity - otherSoldQty;
    if (mounted) setState(() => _remainingQty = remaining > 0 ? remaining : 0);
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

  Future<void> _openBuyPositionPicker() async {
    final picked = await showModalBottomSheet<TradingJournal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BuyPositionPickerSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
      ),
    );
    if (picked != null) {
      final mkt = picked.market;
      // 이미 매도된 수량 계산해서 잔량 구하기
      final allJournals = await widget.firestoreService
          .getMyJournals(widget.uid)
          .first;
      final soldQty = allJournals
          .where((j) => j.action == '매도' && j.linkedBuyId == picked.id)
          .fold(0.0, (sum, j) => sum + j.quantity);
      final remaining = picked.quantity - soldQty;
      if (!mounted) return;
      setState(() {
        _linkedBuyJournal = picked;
        _remainingQty = remaining > 0 ? remaining : 0;
        _stockName = picked.stockName;
        _ticker = picked.ticker;
        _rawMarket = {'KS', 'KQ', 'US'}.contains(mkt) ? mkt : '';
        _market = mkt == 'US' ? 'US' : 'KR';
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
    // 매도 수량 초과 검증 (새 매도 및 수정 모두)
    final hasBuyLink =
        _linkedBuyJournal != null ||
        (widget.existing?.linkedBuyId ?? '').isNotEmpty;
    if (_action == '매도' && hasBuyLink) {
      final enteredQty = double.tryParse(_quantityCtrl.text.trim()) ?? 0;
      if (enteredQty > _remainingQty) {
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
        buyPrice: _linkedBuyJournal?.price ?? widget.existing?.buyPrice ?? 0,
        linkedBuyId:
            _linkedBuyJournal?.id ?? widget.existing?.linkedBuyId ?? '',
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
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _qtyError!,
                          style: GoogleFonts.inter(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
                              _linkedBuyJournal = null;
                              _stockName = '';
                              _ticker = '';
                              _rawMarket = '';
                              _market = 'KR';
                              _priceResult = null;
                              _manualMode = false;
                            } else if (a != '매도') {
                              _linkedBuyJournal = null;
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
                  // 매도: 기존 매수 포지션에서 선택
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '매수 포지션',
                        style: GoogleFonts.inter(
                          color: labelColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_linkedBuyJournal != null)
                        GestureDetector(
                          onTap: () => setState(() {
                            _linkedBuyJournal = null;
                            _stockName = '';
                            _ticker = '';
                            _rawMarket = '';
                            _market = 'KR';
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
                  if (_linkedBuyJournal == null)
                    GestureDetector(
                      onTap: _openBuyPositionPicker,
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
                              Icons.trending_down,
                              size: 15,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '매수 포지션에서 선택',
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
                                Icons.arrow_upward,
                                size: 13,
                                color: Color(0xFF10B981),
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
                          Builder(
                            builder: (_) {
                              final buy = _linkedBuyJournal!;
                              final isUs = buy.market == 'US';
                              final priceStr = buy.price > 0
                                  ? (isUs
                                        ? '\$${buy.price.toStringAsFixed(2)}'
                                        : '₩${NumberFormat('#,###').format(buy.price.toInt())}')
                                  : '-';
                              final qtyStr = buy.quantity > 0
                                  ? '${buy.quantity % 1 == 0 ? buy.quantity.toInt() : buy.quantity}주 보유'
                                  : '';
                              return Text(
                                '매수가 $priceStr${qtyStr.isNotEmpty ? "  ·  $qtyStr" : ""}',
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                              );
                            },
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
                                    double.tryParse(v.trim()) == null)
                                  return '숫자 입력';
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
                                  : '수량 (선택)',
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
                                if (_qtyError != null)
                                  setState(() => _qtyError = null);
                              },
                              validator: (v) {
                                if (v != null &&
                                    v.trim().isNotEmpty &&
                                    double.tryParse(v.trim()) == null)
                                  return '숫자 입력';
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
      if (mounted)
        setState(() {
          _allPicks = picks;
          _loading = false;
        });
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

// ─── 매수 포지션 선택 시트 ─────────────────────────────────────────────────

class _BuyPositionPickerSheet extends StatelessWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _BuyPositionPickerSheet({
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
                  '매도할 포지션 선택',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '기존 매수 일지에서 선택하세요',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 12,
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
                final buys = allJournals
                    .where((j) => j.action == '매수')
                    .toList();
                // 각 매수 포지션의 잔량 계산
                double remainingFor(String buyId, double buyQty) {
                  final sold = allJournals
                      .where((j) => j.action == '매도' && j.linkedBuyId == buyId)
                      .fold(0.0, (sum, j) => sum + j.quantity);
                  return (buyQty - sold).clamp(0.0, buyQty);
                }

                // 잔량이 0인 포지션은 숨기기
                final availableBuys = buys
                    .where((b) => remainingFor(b.id, b.quantity) > 0)
                    .toList();
                if (availableBuys.isEmpty) {
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
                          buys.isEmpty ? '매수 일지가 없습니다' : '매도 가능한 포지션이 없습니다',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          buys.isEmpty
                              ? '먼저 매수 일지를 작성해주세요'
                              : '모든 포지션이 전량 매도되었습니다',
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
                  itemCount: availableBuys.length,
                  itemBuilder: (ctx, i) {
                    final buy = availableBuys[i];
                    final remaining = remainingFor(buy.id, buy.quantity);
                    final isUs = buy.market == 'US';
                    final priceStr = buy.price > 0
                        ? (isUs
                              ? '\$${buy.price.toStringAsFixed(2)}'
                              : '₩${NumberFormat('#,###').format(buy.price.toInt())}')
                        : '-';
                    final qtyStr = remaining % 1 == 0
                        ? '${remaining.toInt()}주'
                        : '$remaining주';
                    final isPartial = remaining < buy.quantity;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, buy),
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
                                Icons.arrow_upward,
                                size: 18,
                                color: Color(0xFF10B981),
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
                                        buy.stockName,
                                        style: GoogleFonts.inter(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (isPartial) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orangeAccent
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '부분매도',
                                            style: GoogleFonts.inter(
                                              color: Colors.orangeAccent,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${buy.ticker.isNotEmpty ? "${buy.ticker}  ·  " : ""}$priceStr  ·  잔량 $qtyStr',
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
                            Text(
                              DateFormat('MM/dd').format(buy.tradeDate),
                              style: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.3),
                                fontSize: 12,
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
