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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBlurred = pick.isPremium && !widget.isLoggedIn;
    final returnRate = _liveReturnRate;
    final isPositive = returnRate >= 0;
    final accentColor = isPositive ? const Color(0xFF4ADE80) : Colors.redAccent;

    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
    final borderColor = pick.isPremium
        ? const Color(0xFFFFD700).withValues(alpha: 0.3)
        : (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.06));
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white38 : Colors.black38;
    final textMuted = isDark ? Colors.white54 : Colors.black45;
    final tickerBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.05);
    final favUnfilledColor = isDark ? Colors.white24 : Colors.black26;
    final buyPriceColor = isDark ? Colors.white60 : Colors.black54;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 좌측 컬러 액센트 바
                Container(
                  width: 4,
                  color: accentColor.withValues(alpha: 0.7),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 헤더
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          pick.name,
                                          style: GoogleFonts.inter(
                                            color: textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: tickerBg,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          pick.ticker,
                                          style: GoogleFonts.robotoMono(
                                            color: textMuted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeago.format(pick.createdAt, locale: 'ko'),
                                    style: GoogleFonts.inter(
                                      color: textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (pick.isPremium) ...[
                              const SizedBox(width: 6),
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
                                      : favUnfilledColor,
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
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            _buildPriceBox('매수가', pick.buyPrice, pick.market,
                                buyPriceColor, textSecondary),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.trending_flat,
                                  color: accentColor.withValues(alpha: 0.5), size: 16),
                            ),
                            _buildCurrentPriceBox(accentColor, textSecondary),
                            const Spacer(),
                            _buildReturnBadge(returnRate, isPositive, accentColor),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 매수 근거 (블러 처리)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: isBlurred
                            ? Stack(
                                children: [
                                  Text(
                                    pick.reason,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: textMuted,
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
                                            cardColor,
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
                                  color: textSecondary,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnBadge(double returnRate, bool isPositive, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            color: accentColor,
            size: 11,
          ),
          const SizedBox(width: 2),
          Text(
            '${returnRate.toStringAsFixed(1)}%',
            style: GoogleFonts.inter(
              color: accentColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPriceBox(Color accentColor, Color labelColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '현재가',
          style: GoogleFonts.inter(color: labelColor, fontSize: 10),
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
              color: labelColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          )
        else
          Text(
            _priceResult!.formattedPrice,
            style: GoogleFonts.inter(
              color: accentColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
      ],
    );
  }


  Widget _buildPremiumBadge() {
    return const Icon(Icons.star, color: Color(0xFFFFD700), size: 16);
  }

  Widget _buildPriceBox(String label, double price, String market,
      Color valueColor, Color labelColor) {
    final isKrw = market != 'US';
    final formatted = isKrw
        ? '₩${NumberFormat('#,###').format(price.toInt())}'
        : '\$${price.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: labelColor, fontSize: 10),
        ),
        Text(
          formatted,
          style: GoogleFonts.inter(
            color: valueColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
