import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';

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
              child: CircularProgressIndicator(color: Color(0xFF4ADE80)));
        }

        final completedPicks = snapshot.data ?? [];
        if (completedPicks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_outlined,
                    color: cs.onSurface.withValues(alpha: 0.2), size: 64),
                const SizedBox(height: 16),
                Text(
                  '아직 완료된 추천 종목이 없습니다',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.4),
                      fontSize: 15),
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

class _LeaderboardContent extends StatelessWidget {
  final ColorScheme cs;
  final List<StockPick> completedPicks;

  const _LeaderboardContent(
      {required this.cs, required this.completedPicks});

  @override
  Widget build(BuildContext context) {
    final total = completedPicks.length;
    final wins = completedPicks.where((p) => p.actualReturnRate > 0).length;
    final winRate = (wins / total) * 100;
    final avgReturn = completedPicks
            .map((p) => p.actualReturnRate)
            .reduce((a, b) => a + b) /
        total;
    final best = completedPicks.reduce(
        (a, b) => a.actualReturnRate > b.actualReturnRate ? a : b);
    final sorted = [...completedPicks]
      ..sort((a, b) => b.actualReturnRate.compareTo(a.actualReturnRate));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildStatsCard(cs, total, wins, winRate, avgReturn, best),
        const SizedBox(height: 20),
        Text(
          '완료 종목 순위',
          style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        ...sorted.asMap().entries
            .map((e) => _buildRankCard(cs, e.key + 1, e.value)),
      ],
    );
  }

  Widget _buildStatsCard(ColorScheme cs, int total, int wins, double winRate,
      double avgReturn, StockPick best) {
    final isAvgPositive = avgReturn >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF4ADE80).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events,
                  color: Color(0xFFFFD700), size: 20),
              const SizedBox(width: 8),
              Text(
                '이전 관심종목 실적',
                style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _statItem(cs, '총 추천', '$total건',
                    cs.onSurface.withValues(alpha: 0.7)),
              ),
              Container(
                  width: 1,
                  height: 40,
                  color: cs.onSurface.withValues(alpha: 0.1)),
              Expanded(
                child: _statItem(cs, '승률',
                    '${winRate.toStringAsFixed(1)}%', const Color(0xFF4ADE80)),
              ),
              Container(
                  width: 1,
                  height: 40,
                  color: cs.onSurface.withValues(alpha: 0.1)),
              Expanded(
                child: _statItem(
                  cs,
                  '평균 수익률',
                  '${isAvgPositive ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
                  isAvgPositive
                      ? const Color(0xFF4ADE80)
                      : Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded,
                    color: Color(0xFF4ADE80), size: 16),
                const SizedBox(width: 8),
                Text('최고 수익 ',
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 12)),
                Text(best.name,
                    style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                const Spacer(),
                Text(
                  '+${best.actualReturnRate.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                      color: const Color(0xFF4ADE80),
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(
      ColorScheme cs, String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
        const SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.inter(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      ],
    );
  }

  Widget _buildRankCard(ColorScheme cs, int rank, StockPick pick) {
    final ret = pick.actualReturnRate;
    final isPositive = ret > 0;
    final isKrw = pick.market != 'US';
    final formatter = NumberFormat('#,###');

    String formatPrice(double p) {
      if (isKrw) return '₩${formatter.format(p.toInt())}';
      return '\$${p.toStringAsFixed(2)}';
    }

    final rankColor = switch (rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => cs.onSurface.withValues(alpha: 0.3),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rank <= 3
              ? rankColor.withValues(alpha: 0.35)
              : cs.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('#$rank',
                style: GoogleFonts.inter(
                    color: rankColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pick.name,
                    style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  '${pick.ticker}  ${formatPrice(pick.buyPrice)} → ${formatPrice(pick.closedPrice ?? 0)}',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.38),
                      fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isPositive
                      ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                      : Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${isPositive ? '+' : ''}${ret.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    color: isPositive
                        ? const Color(0xFF4ADE80)
                        : Colors.redAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (pick.closedAt != null) ...[
                const SizedBox(height: 3),
                Text(
                  DateFormat('yyyy.MM.dd').format(pick.closedAt!),
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.25),
                      fontSize: 10),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
