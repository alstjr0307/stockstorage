import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/market_feature_stock.dart';
import '../services/firestore_service.dart';
import 'market_feature_stock_detail_screen.dart';

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
    final isDark = theme.brightness == Brightness.dark;

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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                labelColor: isDark ? const Color(0xFF0A0E1A) : cs.surface,
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
                indicator: BoxDecoration(
                  color: isDark ? Colors.white : cs.onSurface,
                  borderRadius: BorderRadius.circular(9999),
                ),
                dividerColor: Colors.transparent,
                tabs: [for (final filter in _filters) Tab(text: filter.label)],
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
            _InfoLine(title: '거래량 급증', body: '평소보다 거래량과 거래대금이 동시에 튄 종목입니다.'),
            SizedBox(height: 10),
            _InfoLine(title: '신고가/돌파', body: '최근 고점 또는 신고가 구간을 돌파한 종목입니다.'),
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

class _FeatureStockList extends StatefulWidget {
  const _FeatureStockList({required this.filter});

  final _FeatureStockFilter filter;

  @override
  State<_FeatureStockList> createState() => _FeatureStockListState();
}

class _FeatureStockListState extends State<_FeatureStockList> {
  DateTime? _selectedDate;

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
    final firestoreService = FirestoreService();

    return StreamBuilder<List<MarketFeatureStock>>(
      stream: firestoreService.getMarketFeatureStocks(
        group: widget.filter.group,
      ),
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
        if (_selectedDate != selectedDate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedDate = selectedDate;
            });
          });
        }

        final selectedItems = (grouped[selectedDate] ?? <MarketFeatureStock>[])
          ..sort((a, b) => _compareFeatureStocks(a, b));
        final rows = <Object>[...selectedItems];

        return RefreshIndicator(
          color: const Color(0xFF3182F6),
          onRefresh: () async {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            itemCount: rows.length + 1,
            separatorBuilder: (_, index) => index == 0
                ? const SizedBox(height: 10)
                : Container(
                    margin: const EdgeInsets.only(left: 2),
                    height: 1,
                    color: cs.onSurface.withValues(alpha: 0.07),
                  ),
            itemBuilder: (context, index) {
              if (index == 0) {
                final currentIndex = availableDates.indexOf(selectedDate);
                final canPrev = currentIndex < availableDates.length - 1;
                final canNext = currentIndex > 0;
                final label = DateFormat('yyyy.MM.dd').format(selectedDate);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FeatureDateNavigator(
                      label: label,
                      onPick: () => _pickDate(context, availableDates),
                      onPrev: canPrev
                          ? () {
                              final nextDate = availableDates[currentIndex + 1];
                              setState(() => _selectedDate = nextDate);
                            }
                          : null,
                      onNext: canNext
                          ? () {
                              final nextDate = availableDates[currentIndex - 1];
                              setState(() => _selectedDate = nextDate);
                            }
                          : null,
                    ),
                  ],
                );
              }
              final row = rows[index - 1];
              return _FeatureStockRow(item: row as MarketFeatureStock);
            },
          ),
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
      for (final entry in entries)
        entry.key: entry.value
          ..sort((a, b) {
            return _compareFeatureStocks(a, b);
          }),
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

class _FeatureDateNavigator extends StatelessWidget {
  const _FeatureDateNavigator({
    required this.label,
    required this.onPick,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPick;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
          visualDensity: VisualDensity.compact,
          color: cs.onSurface.withValues(alpha: onPrev == null ? 0.24 : 0.76),
        ),
        Expanded(
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          visualDensity: VisualDensity.compact,
          color: cs.onSurface.withValues(alpha: onNext == null ? 0.24 : 0.76),
        ),
      ],
    );
  }
}

class _FeatureStockRow extends StatelessWidget {
  const _FeatureStockRow({required this.item});

  final MarketFeatureStock item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUp = item.changeRate >= 0;
    final moveColor = isUp ? const Color(0xFFF04452) : const Color(0xFF1677FF);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MarketFeatureStockDetailScreen(item: item),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
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
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.ticker,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.38),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    featureSpecificLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.62),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MiniMetric(
                        label: _formatTradingValue(item.tradingValue),
                      ),
                      _MiniMetric(
                        label: '거래량 ${item.volumeRatio.toStringAsFixed(1)}x',
                      ),
                      if (featureShowsScore(item))
                        _MiniMetric(label: '점수 ${item.score}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
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

  String _formatTradingValue(int value) {
    if (value >= 1000000000000) {
      return '거래대금 ${(value / 1000000000000).toStringAsFixed(1)}조';
    }
    if (value >= 100000000) {
      return '거래대금 ${(value / 100000000).round()}억';
    }
    return '거래대금 ${NumberFormat('#,###').format(value)}';
  }
}

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
    case 'top_trading_value':
      return '거래대금 상위';
    case 'gainers':
      return '급등주';
    case 'volume_spike':
      return '거래량 급증';
    case 'high_breakout':
      return '신고가/돌파';
    case 'chart_capture':
      return 'AI포착';
    default:
      return group.isEmpty ? '특징주' : group;
  }
}

String? featurePatternLabel(String pattern) {
  switch (pattern) {
    case 'top_trading_value':
      return '거래대금 상위';
    case 'gainers':
      return '급등';
    case 'trading_value_spike':
      return '거래량/거래대금 급증';
    case 'new_52w_high':
      return '신고가 돌파';
    case 'prior_high_breakout':
      return '전고점 돌파';
    case 'ma20_reclaim':
      return '20일선 회복';
    case 'prior_high_retest':
      return '전고점 재도전';
    case 'volume_surge_cooldown':
      return '급등 후 재정비 구간';
    case 'box_upper_approach':
      return '박스권 상단 접근';
    case 'volume_surge_pullback_tail':
      return '급등 뒤 조정 후 반등 시도';
    case 'volume_spike_breakout_dry_up_rise':
      return '급등 후 재정비 구간';
    case 'volume_spike_dry_up_pullback_support':
      return '급등 후 재정비 구간';
    default:
      return null;
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

bool featureShowsScore(MarketFeatureStock item) {
  return item.group == 'chart_capture';
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.52),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

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
