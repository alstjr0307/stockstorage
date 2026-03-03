import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/stock_pick.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import 'login_screen.dart';
import 'stock_detail_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

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
          Icon(Icons.account_circle_outlined,
              color: cs.onSurface.withValues(alpha: 0.2), size: 64),
          const SizedBox(height: 16),
          Text(
            '로그인이 필요합니다',
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.4), fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '관심종목을 추가하고 수익률을 확인하세요',
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.25), fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4ADE80),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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

  void _fetchPriceIfNeeded(StockPick pick) {
    if (_loadingIds.contains(pick.id)) return;
    _loadingIds.add(pick.id);
    StockPriceService.fetchPrice(pick.ticker, pick.market).then((result) {
      if (mounted) {
        setState(() {
          _prices[pick.id] = result;
          _loadingIds.remove(pick.id);
        });
      }
    });
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
                  child: CircularProgressIndicator(
                      color: Color(0xFF4ADE80)));
            }

            final allPicks = picksSnapshot.data ?? [];
            final favPicks =
                allPicks.where((p) => favIds.contains(p.id)).toList();

            for (final pick in favPicks) {
              _fetchPriceIfNeeded(pick);
            }

            if (favPicks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite_border,
                        color: cs.onSurface.withValues(alpha: 0.2), size: 52),
                    const SizedBox(height: 14),
                    Text(
                      '관심종목을 추가해보세요',
                      style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '종목 카드의 ♡ 버튼을 눌러 추가',
                      style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.25),
                          fontSize: 12),
                    ),
                  ],
                ),
              );
            }

            // Aggregate stats
            final withPrice =
                favPicks.where((p) => _prices[p.id] != null).toList();
            double totalReturn = 0;
            int positiveCount = 0;
            for (final p in withPrice) {
              final ret =
                  ((_prices[p.id]!.price - p.buyPrice) / p.buyPrice) * 100;
              totalReturn += ret;
              if (ret > 0) positiveCount++;
            }
            final avgReturn =
                withPrice.isEmpty ? 0.0 : totalReturn / withPrice.length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _buildStatsHeader(context, favPicks.length, positiveCount,
                    withPrice.length, avgReturn),
                const SizedBox(height: 20),
                Text(
                  '보유 관심종목',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
                ...favPicks.map((p) => _buildPickCard(context, p)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatsHeader(BuildContext context, int total, int positive,
      int withPrice, double avgReturn) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = avgReturn >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPositive
              ? const Color(0xFF4ADE80).withValues(alpha: 0.25)
              : Colors.redAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '포트폴리오 현황',
                style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '관심종목 $total개',
                  style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _statItem(
                  context,
                  '평균 수익률',
                  withPrice == 0
                      ? '--'
                      : '${isPositive ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
                  isPositive ? const Color(0xFF4ADE80) : Colors.redAccent,
                ),
              ),
              Container(
                  width: 1,
                  height: 40,
                  color: cs.onSurface.withValues(alpha: 0.1)),
              Expanded(
                child: _statItem(
                    context, '수익 중', '$positive개', const Color(0xFF4ADE80)),
              ),
              Container(
                  width: 1,
                  height: 40,
                  color: cs.onSurface.withValues(alpha: 0.1)),
              Expanded(
                child: _statItem(
                    context, '손실 중', '${withPrice - positive}개', Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(
      BuildContext context, String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
        const SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.inter(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
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

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StockDetailScreen(pick: pick)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
              ),
              child: Text(
                pick.ticker,
                style: GoogleFonts.robotoMono(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pick.name,
                    style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '매수 ${formatPrice(pick.buyPrice)}',
                        style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.38),
                            fontSize: 11),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: cs.onSurface.withValues(alpha: 0.3)),
                        ),
                      ] else if (livePrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '현재 ${formatPrice(livePrice)}',
                          style: GoogleFonts.inter(
                              color: const Color(0xFF4ADE80), fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPositive
                    ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(
                  color:
                      isPositive ? const Color(0xFF4ADE80) : Colors.redAccent,
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
