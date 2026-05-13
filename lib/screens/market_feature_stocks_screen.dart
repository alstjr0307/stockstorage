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
      '거래대금 상위',
      group: 'top_trading_value',
      description: '오늘 실제로 돈이 많이 몰린 종목입니다.',
    ),
    _FeatureStockFilter(
      '급등주',
      group: 'gainers',
      description: '당일 상승률이 크게 나온 종목입니다.',
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
    _FeatureStockFilter(
      '차트 포착',
      group: 'chart_capture',
      description: '거래량·이평선·눌림 패턴이 포착된 종목입니다.',
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

class _FeatureStockList extends StatelessWidget {
  const _FeatureStockList({required this.filter});

  final _FeatureStockFilter filter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firestoreService = FirestoreService();

    return StreamBuilder<List<MarketFeatureStock>>(
      stream: firestoreService.getMarketFeatureStocks(group: filter.group),
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
                '${filter.label}에 등록된 종목이 없습니다.',
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
        final rows = <Object>[];
        for (final entry in grouped.entries) {
          rows.add(entry.key);
          rows.addAll(entry.value);
        }

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
                return _FeatureFilterHint(filter: filter);
              }
              final row = rows[index - 1];
              if (row is DateTime) {
                return _FeatureDateHeader(
                  date: row,
                  count: grouped[row]?.length ?? 0,
                );
              }
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
            final scoreCompare = b.score.compareTo(a.score);
            if (scoreCompare != 0) return scoreCompare;
            return b.tradingValue.compareTo(a.tradingValue);
          }),
    };
  }
}

class _FeatureFilterHint extends StatelessWidget {
  const _FeatureFilterHint({required this.filter});

  final _FeatureStockFilter filter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        filter.description,
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.56),
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeatureDateHeader extends StatelessWidget {
  const _FeatureDateHeader({required this.date, required this.count});

  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final isToday = today.difference(target).inDays == 0;
    final formattedDate = DateFormat('yyyy.MM.dd').format(date);

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Text(
            isToday ? '오늘' : formattedDate,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 8),
            Text(
              formattedDate,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.38),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '$count개',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.42),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
    final subtitle = featureDisplayReason(item);

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
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.market,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                    item.title.isNotEmpty ? item.title : _featureTitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.62),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.46),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
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

  String _featureTitle(MarketFeatureStock item) {
    if (item.title.isNotEmpty && !featureLooksEnglish(item.title)) {
      return item.title;
    }
    switch (item.pattern) {
      case 'top_trading_value':
        return '거래대금 상위';
      case 'gainers':
        return '급등주';
      case 'trading_value_spike':
        return '거래량/거래대금 급증';
      case 'new_52w_high':
        return '신고가 돌파';
      case 'prior_high_breakout':
        return '전고점 돌파';
      case 'volume_surge_pullback_tail':
        return '급등 후 U자 눌림';
      case 'volume_spike_breakout_dry_up_rise':
        return '거래량 감소 상승';
      case 'volume_spike_dry_up_pullback_support':
        return '거래량 감소 눌림 지지';
      default:
        return item.group;
    }
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

String featureDisplayReason(MarketFeatureStock item) {
  final reason = item.reason.replaceAll('\n', ' ').trim();
  if (reason.isNotEmpty && !featureLooksEnglish(reason)) return reason;

  final parts = <String>[];
  parts.add('${featureGroupLabel(item.group)} 기준으로 포착된 종목입니다.');
  if (item.changeRate != 0) {
    final direction = item.changeRate > 0 ? '상승' : '하락';
    parts.add(
      '당일 등락률은 ${item.changeRate.abs().toStringAsFixed(2)}% $direction했습니다.',
    );
  }
  if (item.tradingValue > 0) {
    parts.add('거래대금은 ${formatFeatureTradingValue(item.tradingValue)} 수준입니다.');
  }
  if (item.volumeRatio > 0) {
    parts.add('거래량은 20일 평균 대비 ${item.volumeRatio.toStringAsFixed(1)}배입니다.');
  }
  final pattern = featurePatternLabel(item.pattern);
  if (pattern != null) parts.add('$pattern 흐름이 함께 감지됐습니다.');
  return parts.join(' ');
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
      return '차트 포착';
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
    case 'volume_surge_pullback_tail':
      return '급등 후 U자 눌림';
    case 'volume_spike_breakout_dry_up_rise':
      return '거래량 감소 후 재상승';
    case 'volume_spike_dry_up_pullback_support':
      return '거래량 감소 눌림 지지';
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

bool featureLooksEnglish(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  if (RegExp(r'[가-힣]').hasMatch(text)) return false;
  return RegExp(r'[A-Za-z]').hasMatch(text);
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
