import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/stock_pick.dart';
import '../services/stock_price_service.dart';

class StockCard extends StatefulWidget {
  final StockPick pick;
  final bool isLoggedIn;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const StockCard({
    super.key,
    required this.pick,
    required this.isLoggedIn,
    required this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  State<StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<StockCard> {
  PriceResult? _priceResult;
  bool _loadingPrice = true;

  @override
  void initState() {
    super.initState();
    _fetchPrice();
  }

  Future<void> _fetchPrice() async {
    final result = await StockPriceService.fetchPrice(
      widget.pick.ticker,
      widget.pick.market,
    );
    if (mounted) {
      setState(() {
        _priceResult = result;
        _loadingPrice = false;
      });
    }
  }

  StockPick get pick => widget.pick;

  double get _liveReturnRate {
    if (_priceResult != null) {
      return ((_priceResult!.price - pick.buyPrice) / pick.buyPrice) * 100;
    }
    return pick.returnRate;
  }

  @override
  Widget build(BuildContext context) {
    final isBlurred = pick.isPremium && !widget.isLoggedIn;
    final returnRate = _liveReturnRate;
    final isPositive = returnRate >= 0;

    return GestureDetector(
      onTap: widget.onTap,
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
                  if (widget.onFavoriteToggle != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.onFavoriteToggle,
                      child: Icon(
                        widget.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: widget.isFavorite
                            ? Colors.redAccent
                            : Colors.white24,
                        size: 18,
                      ),
                    ),
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
                    pick.market,
                    Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward,
                      color: Colors.white24, size: 16),
                  const SizedBox(width: 8),
                  _buildCurrentPriceBox(),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPositive
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                              : Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                          style: GoogleFonts.inter(
                            color: isPositive
                                ? const Color(0xFF4ADE80)
                                : Colors.redAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '매수가 대비',
                        style: GoogleFonts.inter(
                            color: Colors.white24, fontSize: 9),
                      ),
                    ],
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.4),
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

  Widget _buildCurrentPriceBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '현재가',
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
        ),
        if (_loadingPrice)
          const SizedBox(
            width: 12,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF4ADE80),
            ),
          )
        else if (_priceResult == null)
          Text(
            '--',
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          )
        else
          Text(
            _priceResult!.formattedPrice,
            style: GoogleFonts.inter(
              color: const Color(0xFF4ADE80),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
      ],
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

  Widget _buildPriceBox(
      String label, double price, String market, Color color) {
    final isKrw = market != 'US';
    final formatted = isKrw
        ? '₩${NumberFormat('#,###').format(price.toInt())}'
        : '\$${price.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
        ),
        Text(
          formatted,
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
