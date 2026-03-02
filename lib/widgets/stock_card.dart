import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/stock_pick.dart';

class StockCard extends StatelessWidget {
  final StockPick pick;
  final bool isLoggedIn;
  final VoidCallback onTap;

  const StockCard({
    super.key,
    required this.pick,
    required this.isLoggedIn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isBlurred = pick.isPremium && !isLoggedIn;
    final returnRate = pick.returnRate;
    final isPositive = returnRate >= 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: pick.isPremium
                ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  _buildTickerBadge(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pick.name,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          timeago.format(pick.createdAt, locale: 'ko'),
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildCategoryBadge(),
                  if (pick.isPremium) ...[
                    const SizedBox(width: 8),
                    _buildPremiumBadge(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 가격 정보
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildPriceBox(
                    '매수가',
                    pick.buyPrice,
                    Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, color: Colors.white24, size: 16),
                  const SizedBox(width: 8),
                  _buildPriceBox(
                    '목표가',
                    pick.targetPrice,
                    const Color(0xFF4ADE80),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPositive
                          ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                          : Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                      style: GoogleFonts.inter(
                        color: isPositive ? const Color(0xFF4ADE80) : Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 이유 (블러 처리)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: isBlurred
                  ? Stack(
                      children: [
                        Text(
                          pick.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFF1A2035),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                '로그인 필요',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFFFD700),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      pick.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTickerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        pick.ticker,
        style: GoogleFonts.robotoMono(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildCategoryBadge() {
    final colors = {
      '단기': Colors.orangeAccent,
      '중기': Colors.blueAccent,
      '장기': Colors.purpleAccent,
    };
    final color = colors[pick.category] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        pick.category,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPremiumBadge() {
    return const Icon(Icons.star, color: Color(0xFFFFD700), size: 16);
  }

  Widget _buildPriceBox(String label, double price, Color color) {
    final formatted = NumberFormat('#,###').format(price.toInt());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
        ),
        Text(
          '₩$formatted',
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
