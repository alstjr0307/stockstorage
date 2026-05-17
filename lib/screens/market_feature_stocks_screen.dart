import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/market_feature_stock.dart';
import '../services/firestore_service.dart';
import 'market_feature_stock_detail_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const _kAccent = Color(0xFF00D68F); // 20일선 회복
const _kGold   = Color(0xFFF5B547); // 급등 후 재정비
const _kViolet = Color(0xFF9B7BFF); // 거래량 폭발
const _kRed    = Color(0xFFFF4E6A); // 신고가 / 급등
const _kBlue   = Color(0xFF4A9EFF); // 하락

// ── Per-pattern signal config ─────────────────────────────────────────────
class _SigCfg {
  const _SigCfg(this.color, this.icon, this.label);
  final Color  color;
  final String icon;
  final String label;
}

_SigCfg _getSig(MarketFeatureStock s) {
  switch (s.pattern) {
    case 'ma20_reclaim':
      return const _SigCfg(_kAccent, '↗', '20일선 회복');
    case 'volume_surge_cooldown':
    case 'volume_spike_breakout_dry_up_rise':
    case 'volume_spike_dry_up_pullback_support':
    case 'volume_surge_pullback_tail':
      return const _SigCfg(_kGold, '↻', '급등 후 재정비');
    case 'trading_value_spike':
      return const _SigCfg(_kViolet, '⚡', '거래량 폭발');
    case 'new_52w_high':
      return const _SigCfg(_kRed, '✦', '신고가 돌파');
    case 'prior_high_breakout':
      return const _SigCfg(_kRed, '↑', '전고점 돌파');
    case 'prior_high_retest':
      return const _SigCfg(_kBlue, '⟳', '전고점 재도전');
    case 'box_upper_approach':
      return const _SigCfg(_kGold, '◈', '박스권 상단');
    default:
      // 패턴 없는 종목 → 그룹 기반 폴백
      switch (s.group) {
        case 'gainers':
          return const _SigCfg(_kRed, '↑', '급등주');
        case 'top_trading_value':
          return const _SigCfg(_kViolet, '💰', '거래대금 상위');
        case 'volume_spike':
          return const _SigCfg(_kViolet, '⚡', '거래량 급증');
        case 'high_breakout':
          return const _SigCfg(_kRed, '✦', '신고가/돌파');
        default:
          return s.changeRate >= 0
              ? const _SigCfg(_kRed, '↑', '상승')
              : const _SigCfg(_kBlue, '↓', '하락');
      }
  }
}

// ── Signal filter chips ───────────────────────────────────────────────────
class _SigFilter {
  const _SigFilter(this.key, this.label, this.color);
  final String key;
  final String label;
  final Color  color;
}

const _kSigFilters = [
  _SigFilter('all',           '전체',   Color(0xFF8B92A8)),
  _SigFilter('ma20',          '20일선',  _kAccent),
  _SigFilter('consolidation', '재정비',  _kGold),
  _SigFilter('box',           '박스권',  _kGold),
  _SigFilter('retest',        '전고점',  _kBlue),
];

bool _passFilter(MarketFeatureStock s, String key) {
  switch (key) {
    case 'all': return true;
    case 'ma20': return s.pattern == 'ma20_reclaim';
    case 'consolidation': return const {
        'volume_surge_cooldown',
        'volume_spike_breakout_dry_up_rise',
        'volume_spike_dry_up_pullback_support',
        'volume_surge_pullback_tail',
      }.contains(s.pattern);
    case 'box':    return s.pattern == 'box_upper_approach';
    case 'volume': return s.pattern == 'trading_value_spike';
    case 'high':   return const {'new_52w_high', 'prior_high_breakout'}.contains(s.pattern);
    case 'retest': return s.pattern == 'prior_high_retest';
    default: return true;
  }
}

// ── Main screen ───────────────────────────────────────────────────────────
class MarketFeatureStocksScreen extends StatefulWidget {
  const MarketFeatureStocksScreen({super.key});

  @override
  State<MarketFeatureStocksScreen> createState() =>
      _MarketFeatureStocksScreenState();
}

class _MarketFeatureStocksScreenState extends State<MarketFeatureStocksScreen> {
  static const _filters = [
    _FeatureStockFilter(
      'AI포착',
      group: 'chart_capture',
      description: '급등 이후 쉬어가거나 지지선 부근에서 버티는 흐름이 포착된 종목입니다.',
    ),
    _FeatureStockFilter(
      '급등주',
      group: 'gainers',
      description: '당일 상승률이 크게 나온 종목입니다.',
    ),
    _FeatureStockFilter(
      '거래대금 상위',
      group: 'top_trading_value',
      description: '오늘 실제로 돈이 많이 몰린 종목입니다.',
    ),
    _FeatureStockFilter(
      '거래량 급증',
      group: 'volume_spike',
      description: '평소보다 거래량과 거래대금이 동시에 튄 종목입니다.',
    ),
    _FeatureStockFilter(
      '신고가/돌파',
      group: 'high_breakout',
      description: '최근 고점 또는 신고가 구간을 돌파한 종목입니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;

    return DefaultTabController(
      length: _filters.length,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            '특징주',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            IconButton(
              tooltip: '설명',
              onPressed: () => _showFeatureInfoDialog(context),
              icon: Icon(
                Icons.info_outline_rounded,
                size: 21,
                color: cs.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(width: 6),
          ],
          // ① 탭 underline 스타일
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurface.withValues(alpha: 0.42),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _kAccent, width: 2.5),
                  ),
                ),
                dividerColor: Colors.transparent,
                tabs: [for (final f in _filters) Tab(text: f.label)],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            for (final filter in _filters) _FeatureStockList(filter: filter),
          ],
        ),
      ),
    );
  }
}

void _showFeatureInfoDialog(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(
        '특징주 설명',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _InfoLine(
              title: 'AI포착',
              body: '급등 이후 쉬어가거나 지지선 부근에서 버티는 흐름이 포착된 종목입니다.',
            ),
            SizedBox(height: 10),
            _InfoLine(title: '급등주', body: '당일 상승률이 크게 나온 종목입니다.'),
            SizedBox(height: 10),
            _InfoLine(title: '거래대금 상위', body: '오늘 실제로 돈이 많이 몰린 종목입니다.'),
            SizedBox(height: 10),
            _InfoLine(
              title: '거래량 급증',
              body: '평소보다 거래량과 거래대금이 동시에 튄 종목입니다.',
            ),
            SizedBox(height: 10),
            _InfoLine(
              title: '신고가/돌파',
              body: '최근 고점 또는 신고가 구간을 돌파한 종목입니다.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('닫기', style: TextStyle(color: cs.primary)),
        ),
      ],
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.72),
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FeatureStockFilter {
  const _FeatureStockFilter(
    this.label, {
    required this.group,
    required this.description,
  });

  final String label;
  final String group;
  final String description;
}

// ── List widget per tab ───────────────────────────────────────────────────
class _FeatureStockList extends StatefulWidget {
  const _FeatureStockList({required this.filter});

  final _FeatureStockFilter filter;

  @override
  State<_FeatureStockList> createState() => _FeatureStockListState();
}

class _FeatureStockListState extends State<_FeatureStockList> {
  late final FirestoreService _firestoreService;
  late Stream<List<MarketFeatureStock>> _stocksStream;
  DateTime? _selectedDate;
  String _signalFilter = 'all'; // ⑤ 시그널 필터 상태

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
    _stocksStream = _firestoreService.getMarketFeatureStocks(
      group: widget.filter.group,
    );
  }

  @override
  void didUpdateWidget(covariant _FeatureStockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter.group == widget.filter.group) return;
    _selectedDate = null;
    _signalFilter = 'all';
    _stocksStream = _firestoreService.getMarketFeatureStocks(
      group: widget.filter.group,
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    List<DateTime> availableDates,
  ) async {
    if (availableDates.isEmpty) return;
    final initial = _selectedDate ?? availableDates.first;
    final first = availableDates.last;
    final last = availableDates.first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (day) {
        final key = DateTime(day.year, day.month, day.day);
        return availableDates.any((d) => d == key);
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAiTab = widget.filter.group == 'chart_capture';

    return StreamBuilder<List<MarketFeatureStock>>(
      stream: _stocksStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF3182F6)),
          );
        }

        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                '${widget.filter.label}에 등록된 종목이 없습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.42),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }

        final grouped = _groupByDate(list);
        final availableDates = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        final fallbackDate = availableDates.first;
        final selectedDate =
            _selectedDate != null && availableDates.contains(_selectedDate)
            ? _selectedDate!
            : fallbackDate;

        final selectedItems = (grouped[selectedDate] ?? <MarketFeatureStock>[])
          ..sort((a, b) => _compareFeatureStocks(a, b));

        // ⑤ 시그널 필터 카운트 계산 (AI포착 탭)
        final filterCounts = <String, int>{'all': selectedItems.length};
        if (isAiTab) {
          for (final s in selectedItems) {
            for (final f in _kSigFilters.skip(1)) {
              if (_passFilter(s, f.key)) {
                filterCounts[f.key] = (filterCounts[f.key] ?? 0) + 1;
              }
            }
          }
        }

        // ⑤ 필터 적용
        final visibleItems = isAiTab
            ? selectedItems.where((s) => _passFilter(s, _signalFilter)).toList()
            : selectedItems;

        final currentIndex = availableDates.indexOf(selectedDate);
        final canPrev = currentIndex < availableDates.length - 1;
        final canNext = currentIndex > 0;
        final label = DateFormat('yyyy.MM.dd').format(selectedDate);

        return Column(
          children: [
            // ⑦ 날짜 stepper + 결과 카운트 한 줄
            _FeatureDateNavigator(
              label: label,
              count: visibleItems.length,
              tabLabel: widget.filter.label,
              onPick: () => _pickDate(context, availableDates),
              onPrev: canPrev
                  ? () => setState(
                      () => _selectedDate = availableDates[currentIndex + 1])
                  : null,
              onNext: canNext
                  ? () => setState(
                      () => _selectedDate = availableDates[currentIndex - 1])
                  : null,
            ),
            // ⑤ 시그널 필터 칩 (AI포착 탭만)
            if (isAiTab)
              _SignalFilterRow(
                active: _signalFilter,
                onChanged: (k) => setState(() => _signalFilter = k),
                counts: filterCounts,
              ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF3182F6),
                onRefresh: () async =>
                    Future<void>.delayed(const Duration(milliseconds: 250)),
                child: visibleItems.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 60,
                              horizontal: 28,
                            ),
                            child: Text(
                              '해당 시그널 종목이 없습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.42),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: visibleItems.length,
                        itemBuilder: (context, i) =>
                            _FeatureStockRow(item: visibleItems[i]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Map<DateTime, List<MarketFeatureStock>> _groupByDate(
    List<MarketFeatureStock> list,
  ) {
    final grouped = <DateTime, List<MarketFeatureStock>>{};
    for (final item in list) {
      final key = DateTime(
        item.sourceDate.year,
        item.sourceDate.month,
        item.sourceDate.day,
      );
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return {
      for (final entry in entries) entry.key: entry.value,
    };
  }

  int _compareFeatureStocks(MarketFeatureStock a, MarketFeatureStock b) {
    final primary = switch (widget.filter.group) {
      'top_trading_value' => b.tradingValue.compareTo(a.tradingValue),
      'gainers' => b.changeRate.compareTo(a.changeRate),
      'volume_spike' => b.volumeRatio.compareTo(a.volumeRatio),
      'high_breakout' => b.changeRate.compareTo(a.changeRate),
      _ => b.score.compareTo(a.score),
    };
    if (primary != 0) return primary;
    return b.tradingValue.compareTo(a.tradingValue);
  }
}

// ── ⑦ Date navigator + count ─────────────────────────────────────────────
class _FeatureDateNavigator extends StatelessWidget {
  const _FeatureDateNavigator({
    required this.label,
    required this.count,
    required this.tabLabel,
    required this.onPick,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final int count;
  final String tabLabel;
  final VoidCallback onPick;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          // 결과 카운트
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: _kAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$tabLabel ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          Text(
            '개',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const Spacer(),
          // Date stepper
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            visualDensity: VisualDensity.compact,
            color: cs.onSurface.withValues(alpha: onPrev == null ? 0.24 : 0.72),
          ),
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.onSurface.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            visualDensity: VisualDensity.compact,
            color: cs.onSurface.withValues(alpha: onNext == null ? 0.24 : 0.72),
          ),
        ],
      ),
    );
  }
}

// ── ⑤ Signal filter chips ────────────────────────────────────────────────
class _SignalFilterRow extends StatelessWidget {
  const _SignalFilterRow({
    required this.active,
    required this.onChanged,
    required this.counts,
  });

  final String active;
  final ValueChanged<String> onChanged;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final f in _kSigFilters) ...[
            _SigChip(
              filter: f,
              isActive: active == f.key,
              count: counts[f.key] ?? 0,
              onTap: () => onChanged(f.key),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _SigChip extends StatelessWidget {
  const _SigChip({
    required this.filter,
    required this.isActive,
    required this.count,
    required this.onTap,
  });

  final _SigFilter filter;
  final bool isActive;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = filter.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? c.withValues(alpha: 0.18)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? c.withValues(alpha: 0.4)
                : cs.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filter.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isActive ? c : cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isActive ? c : cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ① ③ ④ Stock card ─────────────────────────────────────────────────────
class _FeatureStockRow extends StatelessWidget {
  const _FeatureStockRow({required this.item});

  final MarketFeatureStock item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sig = _getSig(item);
    final isUp = item.changeRate >= 0;
    final moveColor = isUp ? _kRed : _kBlue;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MarketFeatureStockDetailScreen(item: item),
        ),
      ),
      child: Container(
        // ① 시그널 컬러 왼쪽 바
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: sig.color.withValues(alpha: 0.75), width: 3),
            bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ① 시그널 pill + ticker
                  Row(
                    children: [
                      _SignalPill(sig: sig),
                      const SizedBox(width: 8),
                      Text(
                        item.ticker,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 종목명
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // 비 AI포착 탭: 그룹별 컨텍스트 서브타이틀 복원
                  if (item.group != 'chart_capture') ...[
                    const SizedBox(height: 4),
                    Text(
                      featureSpecificLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // ④ 거래대금 + 거래량 바
                  Row(
                    children: [
                      Text(
                        _fmtTradingValue(item.tradingValue),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(width: 14),
                      _VolumeBar(
                        x: item.volumeRatio,
                        color: item.volumeRatio >= 3 ? sig.color : cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 가격 + 등락률
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  NumberFormat('#,###').format(item.price.round()),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                _ChangeRateBadge(
                  color: moveColor,
                  isUp: isUp,
                  value: item.changeRate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTradingValue(int value) {
    if (value >= 1000000000000) {
      return '거래대금 ${(value / 1000000000000).toStringAsFixed(1)}조';
    }
    if (value >= 100000000) {
      return '거래대금 ${(value / 100000000).round()}억';
    }
    return '거래대금 ${NumberFormat('#,###').format(value)}';
  }
}

// ── ① Signal pill badge ───────────────────────────────────────────────────
class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.sig});

  final _SigCfg sig;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: sig.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: sig.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sig.icon,
            style: TextStyle(
              fontSize: 9,
              color: sig.color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            sig.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: sig.color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── ④ Volume bar ──────────────────────────────────────────────────────────
class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.x, required this.color});

  final double x;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const max = 10.0;
    final pct = (x / max).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: pct,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '${x.toStringAsFixed(1)}x',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

// ── Change rate badge ─────────────────────────────────────────────────────
class _ChangeRateBadge extends StatelessWidget {
  const _ChangeRateBadge({
    required this.color,
    required this.isUp,
    required this.value,
  });

  final Color color;
  final bool isUp;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${isUp ? '+' : ''}${value.toStringAsFixed(2)}%',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── Exported helpers (used in detail screen / home) ───────────────────────
String featureSpecificLabel(MarketFeatureStock item) {
  final pattern = featurePatternLabel(item.pattern);
  switch (item.group) {
    case 'top_trading_value':
      return '거래대금 상위 · ${formatFeatureTradingValue(item.tradingValue)}';
    case 'gainers':
      return '급등주 · ${item.changeRate >= 0 ? '+' : ''}${item.changeRate.toStringAsFixed(2)}%';
    case 'volume_spike':
      return '거래량 급증 · 20일 평균 대비 ${item.volumeRatio.toStringAsFixed(1)}배';
    case 'high_breakout':
      return pattern ?? '신고가/돌파';
    case 'chart_capture':
      return pattern ?? 'AI포착';
    default:
      return pattern ?? featureGroupLabel(item.group);
  }
}

String featureGroupLabel(String group) {
  switch (group) {
    case 'top_trading_value': return '거래대금 상위';
    case 'gainers':           return '급등주';
    case 'volume_spike':      return '거래량 급증';
    case 'high_breakout':     return '신고가/돌파';
    case 'chart_capture':     return 'AI포착';
    default: return group.isEmpty ? '특징주' : group;
  }
}

String? featurePatternLabel(String pattern) {
  switch (pattern) {
    case 'trading_value_spike':                 return '거래량/거래대금 급증';
    case 'new_52w_high':                        return '신고가 돌파';
    case 'prior_high_breakout':                 return '전고점 돌파';
    case 'ma20_reclaim':                        return '20일선 회복';
    case 'prior_high_retest':                   return '전고점 재도전';
    case 'volume_surge_cooldown':               return '급등 후 재정비 구간';
    case 'box_upper_approach':                  return '박스권 상단 접근';
    case 'volume_surge_pullback_tail':          return '급등 뒤 조정 후 반등 시도';
    case 'volume_spike_breakout_dry_up_rise':   return '급등 후 재정비 구간';
    case 'volume_spike_dry_up_pullback_support': return '급등 후 재정비 구간';
    default: return null;
  }
}

String formatFeatureTradingValue(int value) {
  if (value >= 1000000000000) {
    return '${(value / 1000000000000).toStringAsFixed(1)}조';
  }
  if (value >= 100000000) {
    return '${(value / 100000000).round()}억';
  }
  return NumberFormat('#,###').format(value);
}

bool featureShowsScore(MarketFeatureStock item) => item.group == 'chart_capture';
