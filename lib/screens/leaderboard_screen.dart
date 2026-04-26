import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import 'stock_detail_screen.dart';

const _kAccent = Color(0xFF10B981);
const _kUp = Color(0xFFF04452);
const _kDown = Color(0xFF1677FF);

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = FirestoreService();

    return StreamBuilder<List<StockPick>>(
      stream: fs.getCompletedPicks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kAccent),
          );
        }

        final completedPicks = snapshot.data ?? [];
        if (completedPicks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  color: cs.onSurface.withValues(alpha: 0.2),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  '아직 완료된 추천 종목이 없습니다',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        return _LeaderboardContent(cs: cs, completedPicks: completedPicks);
      },
    );
  }
}

enum _CompletedPickSort { time, returnRate }

class _LeaderboardContent extends StatefulWidget {
  final ColorScheme cs;
  final List<StockPick> completedPicks;

  const _LeaderboardContent({required this.cs, required this.completedPicks});

  @override
  State<_LeaderboardContent> createState() => _LeaderboardContentState();
}

class _LeaderboardContentState extends State<_LeaderboardContent> {
  _CompletedPickSort _sort = _CompletedPickSort.time;

  List<StockPick> _sortedPicks() {
    final sorted = [...widget.completedPicks];
    if (_sort == _CompletedPickSort.returnRate) {
      sorted.sort((a, b) => b.actualReturnRate.compareTo(a.actualReturnRate));
    } else {
      sorted.sort((a, b) {
        final bClosed = b.closedAt ?? DateTime(0);
        final aClosed = a.closedAt ?? DateTime(0);
        final closedCmp = bClosed.compareTo(aClosed);
        if (closedCmp != 0) return closedCmp;
        return b.createdAt.compareTo(a.createdAt);
      });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final completedPicks = widget.completedPicks;
    final total = completedPicks.length;
    final wins = completedPicks.where((p) => p.actualReturnRate > 0).length;
    final winRate = (wins / total) * 100;
    final avgReturn =
        completedPicks.map((p) => p.actualReturnRate).reduce((a, b) => a + b) /
        total;
    final best = completedPicks.reduce(
      (a, b) => a.actualReturnRate > b.actualReturnRate ? a : b,
    );
    final sorted = _sortedPicks();
    final sectionTitle = _sort == _CompletedPickSort.returnRate
        ? '종료 종목 순위'
        : '종료 종목 리스트';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
      children: [
        _buildStatsCard(cs, total, wins, winRate, avgReturn, best),
        const SizedBox(height: 28),
        Row(
          children: [
            Text(
              sectionTitle,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.52),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _SortChip(
              label: '시간순',
              selected: _sort == _CompletedPickSort.time,
              onTap: () => setState(() => _sort = _CompletedPickSort.time),
            ),
            const SizedBox(width: 6),
            _SortChip(
              label: '수익률순',
              selected: _sort == _CompletedPickSort.returnRate,
              onTap: () =>
                  setState(() => _sort = _CompletedPickSort.returnRate),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...sorted.asMap().entries.map(
          (e) => _buildRankRow(
            cs,
            e.key + 1,
            e.value,
            showRank: _sort == _CompletedPickSort.returnRate,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard(
    ColorScheme cs,
    int total,
    int wins,
    double winRate,
    double avgReturn,
    StockPick best,
  ) {
    final isAvgPositive = avgReturn >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events,
                color: Color(0xFFFFD700),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '종료 추천주 실적',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _statItem(
                  cs,
                  '총 추천',
                  '$total건',
                  cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: cs.onSurface.withValues(alpha: 0.1),
              ),
              Expanded(
                child: _statItem(
                  cs,
                  '승률',
                  '${winRate.toStringAsFixed(1)}%',
                  cs.onSurface.withValues(alpha: 0.82),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: cs.onSurface.withValues(alpha: 0.1),
              ),
              Expanded(
                child: _statItem(
                  cs,
                  '평균 수익률',
                  '${isAvgPositive ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
                  isAvgPositive ? _kUp : _kDown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kAccent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: _kAccent, size: 16),
                const SizedBox(width: 8),
                Text(
                  '최고 수익 ',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Text(
                    best.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '+${best.actualReturnRate.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: _kUp,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(ColorScheme cs, String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.45),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
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

  Widget _buildRankRow(
    ColorScheme cs,
    int rank,
    StockPick pick, {
    required bool showRank,
  }) {
    final ret = pick.actualReturnRate;
    final isPositive = ret >= 0;
    final isKrw = pick.market != 'US';
    final formatter = NumberFormat('#,###');

    String formatPrice(double p) {
      if (isKrw) return '₩${formatter.format(p.toInt())}';
      return '\$${p.toStringAsFixed(2)}';
    }

    final rankLabel = switch (rank) {
      1 => '1위',
      2 => '2위',
      3 => '3위',
      _ => '$rank위',
    };

    final rankColor = switch (rank) {
      1 => const Color(0xFFF59E0B),
      2 => const Color(0xFF94A3B8),
      3 => const Color(0xFFB45309),
      _ => cs.onSurface.withValues(alpha: 0.45),
    };

    return InkWell(
      onTap: () => Navigator.push(context, stockDetailRoute(pick)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Row(
              children: [
                if (showRank) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      rankLabel,
                      style: TextStyle(
                        color: rankColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pick.name,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pick.ticker,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? _kUp.withValues(alpha: 0.12)
                            : _kDown.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '${isPositive ? '+' : ''}${ret.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: isPositive ? _kUp : _kDown,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (pick.closedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('yyyy.MM.dd').format(pick.closedAt!),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '매수가 ${formatPrice(pick.buyPrice)}',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '종료가 ${formatPrice(pick.closedPrice ?? 0)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: cs.onSurface.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _kAccent.withValues(alpha: 0.14)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: selected
                ? _kAccent.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kAccent : cs.onSurface.withValues(alpha: 0.5),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
