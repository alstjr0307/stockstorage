import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trading_journal.dart';
import '../services/firestore_service.dart';
import '../services/journal_ledger.dart';
import '../services/journal_v2_repository.dart';
import '../services/stock_price_service.dart';
import '../widgets/stock_search_field.dart';
import '../widgets/journal_visual_style.dart';

String journalMoney(double value, String market) {
  if (!value.isFinite) return '—';
  final number = NumberFormat(
    market == 'US' ? '#,##0.00' : '#,##0.##',
  ).format(value.abs());
  final unit = market == 'US'
      ? '\$'
      : {'KR', 'KS', 'KQ'}.contains(market)
      ? '₩'
      : '';
  return '${value < 0 ? '−' : ''}$unit$number';
}

String _qty(double n) =>
    n.isFinite ? NumberFormat('#,##0.##########').format(n) : '—';
Color _kindColor(JournalBuyKind k, BuildContext context) => switch (k) {
  JournalBuyKind.averageDown =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF1677FF),
  JournalBuyKind.averageUp =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF59E0B)
        : const Color(0xFFB45309),
  JournalBuyKind.sell => const Color(0xFFF04452),
  _ => const Color(0xFF10B981),
};
IconData _kindIcon(JournalBuyKind k) => switch (k) {
  JournalBuyKind.averageDown => Icons.water_drop_outlined,
  JournalBuyKind.averageUp => Icons.local_fire_department_outlined,
  JournalBuyKind.sell => Icons.remove_rounded,
  _ => Icons.add_rounded,
};

class JournalV2Screen extends StatefulWidget {
  const JournalV2Screen({
    super.key,
    required this.uid,
    this.filterTicker,
    this.filterStockName,
    this.pageTitle,
  });
  final String uid;
  final String? filterTicker, filterStockName, pageTitle;
  @override
  State<JournalV2Screen> createState() => _JournalV2ScreenState();
}

class _JournalV2ScreenState extends State<JournalV2Screen> {
  late final JournalV2Repository _repo;
  late final Stream<List<TradingJournal>> _stream;
  final Map<String, PriceResult> _prices = {};
  final Set<String> _requested = {};
  String _filter = '전체', _search = '';
  @override
  void initState() {
    super.initState();
    _repo = JournalV2Repository(widget.uid);
    _stream = _repo.watch();
  }

  void _requestPrices(List<JournalPosition> positions) {
    for (final p
        in positions
            .where((p) => p.reliable && p.quantity > JournalLedger.epsilon)
            .take(30)) {
      if (!{'KS', 'KQ', 'US'}.contains(p.stock.market) ||
          !_requested.add(p.key)) {
        continue;
      }
      StockPriceService.fetchPrice(p.stock.ticker, p.stock.market)
          .then((price) {
            if (mounted && price != null) {
              setState(() => _prices[p.key] = price);
            }
          })
          .catchError((Object _) {});
    }
  }

  Future<void> _edit(
    BuildContext target,
    List<TradingJournal> all, {
    TradingJournal? stock,
    TradingJournal? original,
    String action = '매수',
  }) async {
    final nickname = await FirestoreService().getNickname(widget.uid) ?? '익명';
    if (!target.mounted) return;
    await showModalBottomSheet<void>(
      context: target,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => JournalVisualStyle(
        child: JournalV2Editor(
          repo: _repo,
          journals: all,
          nickname: nickname,
          stock: stock,
          original: original,
          action: action,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.pageTitle == null
        ? null
        : AppBar(title: Text(widget.pageTitle!)),
    floatingActionButton: FloatingActionButton(
      heroTag: 'journal_v2_add',
      onPressed: () => _edit(context, const []),
      backgroundColor: JournalVisualStyle.mint,
      foregroundColor: Colors.black,
      tooltip: '거래 기록',
      child: const Icon(Icons.add),
    ),
    body: StreamBuilder<List<TradingJournal>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('기록을 불러오지 못했어요. 연결을 확인해주세요.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final positions = JournalLedger.project(all);
        _requestPrices(positions);
        final visible = positions.where((p) {
          if (widget.filterTicker?.isNotEmpty == true &&
              p.stock.ticker != widget.filterTicker) {
            return false;
          }
          if (widget.filterTicker?.isNotEmpty != true &&
              widget.filterStockName?.isNotEmpty == true &&
              p.stock.stockName != widget.filterStockName) {
            return false;
          }
          if (_filter == '보유 중' &&
              (p.quantity <= JournalLedger.epsilon || !p.reliable)) {
            return false;
          }
          if (_filter == '종료' &&
              (p.quantity > JournalLedger.epsilon || !p.reliable)) {
            return false;
          }
          return '${p.stock.stockName} ${p.stock.ticker}'
              .toLowerCase()
              .contains(_search.toLowerCase());
        }).toList();
        return RefreshIndicator(
          onRefresh: () async {
            for (final p in positions) {
              StockPriceService.invalidateCache(p.stock.ticker);
            }
            setState(() {
              _prices.clear();
              _requested.clear();
            });
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                '내 종목 ${visible.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .55),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '종목명 또는 종목코드',
                ),
                onChanged: (s) => setState(() => _search = s),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: ['전체', '보유 중', '종료']
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              if (positions.any((p) => !p.reliable))
                const _Notice(
                  '확인이 필요한 기록이 있어요. 해당 종목은 손익 대신 확인 안내를 표시합니다. 저장된 기록은 그대로 유지됩니다.',
                ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 42),
                  child: Column(
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 40),
                      const SizedBox(height: 12),
                      Text(all.isEmpty ? '첫 거래를 기록해보세요' : '조건에 맞는 기록이 없어요'),
                      const SizedBox(height: 8),
                      const Text(
                        '매수·매도 내역과 그때의 판단을 남겨보세요.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final p in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: JournalPositionCard(
                    position: p,
                    price: _prices[p.key]?.price,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _JournalStockPage(
                            stockKey: p.key,
                            repo: _repo,
                            prices: _prices,
                            edit: (ctx, journals, original, action) => _edit(
                              ctx,
                              journals,
                              stock: p.stock,
                              original: original,
                              action: action,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .04),
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6),
      ),
    ),
  );
}

/// The same card is used by the list, detail and visual preview.
class JournalPositionCard extends StatelessWidget {
  const JournalPositionCard({
    super.key,
    required this.position,
    this.price,
    this.onTap,
  });
  final JournalPosition position;
  final double? price;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = position, cs = Theme.of(context).colorScheme;
    final holding = p.quantity > JournalLedger.epsilon;
    final pnl = holding
        ? (price == null ? null : (price! - p.average) * p.quantity)
        : p.realized;
    final muted = cs.onSurface.withValues(alpha: .5);
    Widget stat(String title, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.stock.stockName.isEmpty
                          ? '주'
                          : p.stock.stockName.characters.first,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.stock.stockName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${p.stock.ticker} · ${p.stock.market}',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  JournalKindBadge(
                    label: !p.reliable
                        ? '확인 필요'
                        : holding
                        ? '보유중'
                        : '완료',
                    color: holding && p.reliable
                        ? JournalVisualStyle.mint
                        : const Color(0xFF8892A4),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 18, color: muted),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              if (!p.reliable)
                Text(
                  '날짜·수량 확인 후 손익을 계산합니다.',
                  style: TextStyle(color: muted, fontSize: 12),
                )
              else ...[
                Text(
                  holding ? '평가손익' : '실현손익',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 5),
                Text(
                  pnl == null
                      ? '시세 확인 중'
                      : '${pnl > 0 ? '+' : ''}${journalMoney(pnl, p.stock.market)}',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    letterSpacing: -.6,
                    fontWeight: FontWeight.w800,
                    color: pnl == null || pnl == 0
                        ? cs.onSurface
                        : pnl > 0
                        ? JournalVisualStyle.up
                        : JournalVisualStyle.down,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, box) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: (box.maxWidth - 12) / 2,
                        child: stat(
                          '평균단가',
                          holding
                              ? journalMoney(p.average, p.stock.market)
                              : '—',
                        ),
                      ),
                      SizedBox(
                        width: (box.maxWidth - 12) / 2,
                        child: stat('보유수량', '${_qty(p.quantity)}주'),
                      ),
                    ],
                  ),
                ),
                if (holding && p.realized != 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '실현손익 ${journalMoney(p.realized, p.stock.market)}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
                if (!holding && p.realizedRate != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '실현수익률 ${p.realizedRate!.toStringAsFixed(2)}%',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ],
              if (p.reliable &&
                  p.events.any(
                    (e) =>
                        e.kind == JournalBuyKind.averageDown ||
                        e.kind == JournalBuyKind.averageUp,
                  )) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    color: cs.onSurface.withValues(alpha: .07),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in [
                      JournalBuyKind.averageDown,
                      JournalBuyKind.averageUp,
                    ])
                      if (p.events.any((e) => e.kind == k))
                        JournalKindBadge(
                          label:
                              '${k.label} ${p.events.where((e) => e.kind == k).length}회',
                          color: _kindColor(k, context),
                          icon: _kindIcon(k),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

typedef _EditJournal =
    Future<void> Function(
      BuildContext,
      List<TradingJournal>,
      TradingJournal?,
      String,
    );

class _JournalStockPage extends StatefulWidget {
  const _JournalStockPage({
    required this.stockKey,
    required this.repo,
    required this.prices,
    required this.edit,
  });
  final String stockKey;
  final JournalV2Repository repo;
  final Map<String, PriceResult> prices;
  final _EditJournal edit;
  @override
  State<_JournalStockPage> createState() => _JournalStockPageState();
}

class _JournalStockPageState extends State<_JournalStockPage> {
  late final _stream = widget.repo.watch();
  bool _priceRequested = false;
  double? _price;
  bool _deleting = false;
  Future<void> _remove(TradingJournal trade) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거래 기록 삭제'),
        content: const Text('이 기록을 삭제할까요? 이후 매도 수량이 맞지 않으면 삭제할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.repo.remove(trade);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is JournalWriteException ? e.message : '삭제하지 못했어요. 연결을 확인해주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<TradingJournal>>(
    stream: _stream,
    builder: (context, snapshot) {
      final all = snapshot.data ?? const <TradingJournal>[];
      final matches = JournalLedger.project(
        all,
      ).where((p) => p.key == widget.stockKey);
      if (!snapshot.hasData || matches.isEmpty || snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('거래 내역')),
          body: Center(
            child: Text(
              snapshot.hasError
                  ? '기록을 불러오지 못했어요.'
                  : !snapshot.hasData
                  ? '불러오는 중…'
                  : '남은 거래 기록이 없어요.',
            ),
          ),
        );
      }
      final p = matches.first;
      if (!_priceRequested && {'KS', 'KQ', 'US'}.contains(p.stock.market)) {
        _priceRequested = true;
        StockPriceService.fetchPrice(p.stock.ticker, p.stock.market)
            .then((quote) {
              if (mounted && quote != null) {
                setState(() => _price = quote.price);
              }
            })
            .catchError((Object _) {});
      }
      return JournalVisualStyle(
        child: Scaffold(
          appBar: AppBar(title: Text(p.stock.stockName)),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _deleting
                          ? null
                          : () => widget.edit(context, all, null, '매수'),
                      icon: const Icon(Icons.add),
                      label: Text(
                        p.quantity > JournalLedger.epsilon
                            ? '추가 매수 기록'
                            : '신규 매수 기록',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _deleting ||
                              !p.reliable ||
                              p.quantity <= JournalLedger.epsilon
                          ? null
                          : () => widget.edit(context, all, null, '매도'),
                      icon: const Icon(Icons.remove),
                      label: const Text('매도 기록'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              JournalPositionCard(
                position: p,
                price: _price ?? widget.prices[p.key]?.price,
              ),
              const SizedBox(height: 16),
              if (!p.reliable)
                const _Notice(
                  '기록은 수정하지 않았어요. 같은 시각 거래는 실제 순서를 확인해 시각을 수정해주세요. 누락된 매수나 초과 매도도 확인해주세요.',
                ),
              Text(
                '매매 내역',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('평단·손익은 이동평균 기준입니다. 금액은 종목 통화로 표시합니다.'),
              const SizedBox(height: 12),
              for (final e in p.events.reversed)
                _TradeTimelineTile(
                  effect: e,
                  reliable: p.reliable,
                  onEdit: _deleting
                      ? null
                      : () =>
                            widget.edit(context, all, e.trade, e.trade.action),
                  onDelete: _deleting ? null : () => _remove(e.trade),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _TradeTimelineTile extends StatelessWidget {
  const _TradeTimelineTile({
    required this.effect,
    required this.reliable,
    this.onEdit,
    this.onDelete,
  });
  final JournalEffect effect;
  final bool reliable;
  final VoidCallback? onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    final e = effect, t = effect.trade;
    final label = reliable
        ? '${e.kind.label}${t.action == '매수' ? ' · ${e.buyNumber}차' : ''}'
        : t.action;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  reliable ? _kindIcon(e.kind) : Icons.info_outline,
                  color: _kindColor(e.kind, context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (s) =>
                      s == 'edit' ? onEdit?.call() : onDelete?.call(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      enabled: onEdit != null,
                      child: const Text('수정'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: onDelete != null,
                      child: const Text('삭제'),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              DateFormat('yyyy.MM.dd HH:mm:ss').format(t.tradeDate),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .45),
              ),
            ),
            const SizedBox(height: 8),
            if (t.action != '기타')
              Text(
                '${journalMoney(t.price, t.market)} × ${_qty(t.quantity)}주 · ${journalMoney(t.price * t.quantity, t.market)}',
              ),
            if (reliable && t.action == '매수')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '평단 ${e.beforeQuantity <= JournalLedger.epsilon ? '—' : journalMoney(e.beforeAverage, t.market)} → ${journalMoney(e.afterAverage, t.market)}',
                ),
              ),
            if (reliable && t.action == '매도')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '실현손익 ${journalMoney(e.realized, t.market)} · 남은 수량 ${_qty(e.afterQuantity)}주',
                ),
              ),
            if (e.issue != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  e.issue!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (t.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  t.note,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .7),
                  ),
                ),
              ),
            if (t.isPublic)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('공개 기록', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class JournalV2Editor extends StatefulWidget {
  const JournalV2Editor({
    super.key,
    required this.repo,
    required this.journals,
    required this.nickname,
    this.stock,
    this.original,
    this.action = '매수',
  });
  final JournalV2Repository repo;
  final List<TradingJournal> journals;
  final String nickname, action;
  final TradingJournal? stock, original;
  @override
  State<JournalV2Editor> createState() => _JournalV2EditorState();
}

class _JournalV2EditorState extends State<JournalV2Editor> {
  late final String _id;
  late final DateTime _createdAt;
  late DateTime _date;
  late String _action, _ticker, _name, _market;
  late final TextEditingController _price, _quantity, _note;
  late final Stream<List<TradingJournal>> _stream;
  bool _public = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final original = widget.original, stock = original ?? widget.stock;
    _id = original?.id ?? widget.repo.newId();
    _createdAt = original?.createdAt ?? DateTime.now();
    _date = original?.tradeDate ?? DateTime.now();
    _action = original?.action ?? widget.action;
    _ticker = stock?.ticker ?? '';
    _name = stock?.stockName ?? '';
    _market = stock?.market ?? 'KS';
    _public = original?.isPublic ?? false;
    _price = TextEditingController(
      text: original == null ? '' : '${original.price}',
    );
    _quantity = TextEditingController(
      text: original == null ? '' : '${original.quantity}',
    );
    _note = TextEditingController(text: original?.note ?? '');
    _price.addListener(_refresh);
    _quantity.addListener(_refresh);
    _stream = widget.repo.watch();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _price.dispose();
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  double _number(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;
  TradingJournal _draft() => TradingJournal(
    id: _id,
    uid: widget.repo.uid,
    nickname: widget.original?.nickname ?? widget.nickname,
    stockName: _name,
    ticker: _ticker,
    market: _market,
    action: _action,
    price: _number(_price),
    quantity: _number(_quantity),
    tradeDate: _date,
    note: _note.text.trim(),
    isPublic: _public,
    likes: widget.original?.likes ?? 0,
    createdAt: _createdAt,
    publishedAt: widget.original?.publishedAt,
    buyPrice: widget.original?.buyPrice ?? 0,
    linkedBuyId: widget.original?.linkedBuyId ?? '',
  );

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().isAfter(_date) ? DateTime.now() : _date,
    );
    if (chosen == null || !mounted) return;
    setState(
      () => _date = DateTime(
        chosen.year,
        chosen.month,
        chosen.day,
        _date.hour,
        _date.minute,
        _date.second,
        _date.millisecond,
        _date.microsecond,
      ),
    );
  }

  Future<void> _chooseTime() async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (chosen == null || !mounted) return;
    setState(
      () => _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        chosen.hour,
        chosen.minute,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.trim().isEmpty) {
      setState(() => _error = '종목을 선택해주세요.');
      return;
    }
    final draft = _draft();
    if (_action != '기타' &&
        (!draft.price.isFinite ||
            !draft.quantity.isFinite ||
            draft.price <= 0 ||
            draft.quantity <= 0)) {
      setState(() => _error = '올바른 가격과 수량을 입력해주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.save(draft, original: widget.original);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is JournalWriteException
              ? e.message
              : '저장하지 못했어요. 연결을 확인한 뒤 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.original == null ? '거래 기록하기' : '거래 기록 수정',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (widget.stock != null || widget.original != null)
            Text(
              '$_name · $_ticker',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            )
          else if (_name.isNotEmpty)
            InputChip(
              label: Text('$_name · $_ticker'),
              onDeleted: _saving
                  ? null
                  : () => setState(() {
                      _ticker = '';
                      _name = '';
                    }),
            )
          else
            StockSearchField(
              initialTicker: _ticker,
              initialName: _name,
              onSelected: (ticker, name, market) => setState(() {
                _ticker = ticker;
                _name = name;
                _market = market;
              }),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: ['매수', '매도', '기타']
                .map(
                  (a) => ChoiceChip(
                    label: Text(a == '기타' ? '메모' : a),
                    selected: _action == a,
                    onSelected: _saving || widget.original != null
                        ? null
                        : (_) => setState(() => _action = a),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _chooseDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(DateFormat('yyyy.MM.dd').format(_date)),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _chooseTime,
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(DateFormat('HH:mm:ss').format(_date)),
              ),
            ],
          ),
          if (_action != '기타') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '$_action 단가 (${_market == 'US' ? 'USD' : 'KRW'})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '수량 (주)'),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<TradingJournal>>(
              stream: _stream,
              initialData: widget.journals,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _Notice('기존 거래 기록을 확인하고 있어요…');
                }
                final draft = _draft();
                if (_name.isEmpty ||
                    draft.price <= 0 ||
                    draft.quantity <= 0 ||
                    !draft.price.isFinite ||
                    !draft.quantity.isFinite) {
                  return const SizedBox.shrink();
                }
                final records = [
                  ...(snapshot.data ?? const <TradingJournal>[]).where(
                    (j) => j.id != _id,
                  ),
                  draft,
                ];
                final p = JournalLedger.project(
                  records,
                ).firstWhere((p) => p.key == JournalLedger.stockKey(draft));
                final e = p.events.firstWhere((e) => e.trade.id == _id);
                return JournalTradePreview(
                  effect: e,
                  reliable: p.reliable && !snapshot.hasError,
                );
              },
            ),
          ],
          TextField(
            controller: _note,
            enabled: !_saving,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '매매 이유 · 메모'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('커뮤니티에 공개'),
            subtitle: const Text('공개하면 다른 사용자가 이 기록을 볼 수 있어요.'),
            value: _public,
            onChanged: _saving ? null : (v) => setState(() => _public = v),
          ),
          if (_error != null) _Notice(_error!),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? '저장 중…'
                    : widget.original == null
                    ? '기록 저장'
                    : '수정 저장',
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Pure preview widget also used by layout tests with synthetic trades.
class JournalTradePreview extends StatelessWidget {
  const JournalTradePreview({
    super.key,
    required this.effect,
    required this.reliable,
  });
  final JournalEffect effect;
  final bool reliable;
  @override
  Widget build(BuildContext context) {
    final e = effect, t = e.trade;
    if (!reliable) {
      return _Notice(e.issue ?? '이 종목에 확인이 필요한 기록이 있어요. 날짜·시각·수량을 확인해주세요.');
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JournalVisualStyle.surface(context),
        border: Border.all(
          color: _kindColor(e.kind, context).withValues(alpha: .3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_kindIcon(e.kind), color: _kindColor(e.kind, context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${e.kind.label}${t.action == '매수' ? ' · ${e.buyNumber}차 매수' : ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '평단 ${e.beforeQuantity <= JournalLedger.epsilon ? '—' : journalMoney(e.beforeAverage, t.market)} → ${e.afterQuantity <= JournalLedger.epsilon ? '—' : journalMoney(e.afterAverage, t.market)}',
          ),
          Text('보유 ${_qty(e.beforeQuantity)} → ${_qty(e.afterQuantity)}주'),
          Text('거래금액 ${journalMoney(t.price * t.quantity, t.market)}'),
          if (t.action == '매도')
            Text('실현손익 ${journalMoney(e.realized, t.market)}'),
        ],
      ),
    );
  }
}
