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
    if (!mounted) return;
    setState(() {
      _priceResult = result;
      _loadingPrice = false;
    });
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
    final accentColor =
        isPositive ? const Color(0xFFF04452) : const Color(0xFF1677FF);

    final cardColor = isDark ? const Color(0xFF131929) : Colors.white;
    final borderColor = pick.isPremium
        ? const Color(0xFFFFD700).withValues(alpha: 0.3)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFE8EAED));
    final textPrimary = isDark ? Colors.white : const Color(0xFF191F28);
    final textSecondary = isDark
        ? Colors.white.withValues(alpha: 0.48)
        : const Color(0xFF6B7684);
    final textMuted = isDark
        ? Colors.white.withValues(alpha: 0.60)
        : const Color(0xFF8B95A1);
    final tickerBg =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF2F4F6);
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
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timeago.format(pick.createdAt, locale: 'ko'),
                          style: GoogleFonts.inter(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: isBlurred
                                  ? Container(
                                      height: 18,
                                      width: 110,
                                      decoration: BoxDecoration(
                                        color:
                                            textPrimary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    )
                                  : Text(
                                      pick.name,
                                      style: GoogleFonts.inter(
                                        color: textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                        letterSpacing: -0.2,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                            if (!isBlurred) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tickerBg,
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: Text(
                                  pick.ticker,
                                  style: GoogleFonts.robotoMono(
                                    color: textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (pick.isPremium) ...[
                    const SizedBox(width: 8),
                    _buildPremiumBadge(),
                  ],
                  if (widget.onFavoriteToggle != null) ...[
                    const SizedBox(width: 6),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildPriceBox(
                    '매수가',
                    pick.buyPrice,
                    pick.market,
                    buyPriceColor,
                    textSecondary,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.trending_flat,
                      color: accentColor.withValues(alpha: 0.45),
                      size: 16,
                    ),
                  ),
                  _buildCurrentPriceBox(accentColor, textSecondary),
                  const Spacer(),
                  _buildReturnBadge(returnRate, isPositive, accentColor),
                ],
              ),
              const SizedBox(height: 14),
              if (isBlurred)
                Stack(
                  children: [
                    Text(
                      pick.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: textPrimary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, cardColor],
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
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFFFFD700)
                                    .withValues(alpha: 0.15)
                                : const Color(0xFFFFD700)
                                    .withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFFFFD700)
                                      .withValues(alpha: 0.4)
                                  : const Color(0xFFB8860B)
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            '로그인 필요',
                            style: GoogleFonts.inter(
                              color: isDark
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF9A6E00),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  pick.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReturnBadge(
    double returnRate,
    bool isPositive,
    Color accentColor,
  ) {
    final arrow = isPositive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        '$arrow${returnRate.toStringAsFixed(1)}%',
        style: GoogleFonts.robotoMono(
          color: accentColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildCurrentPriceBox(Color accentColor, Color labelColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '현재가',
          style: GoogleFonts.inter(color: labelColor, fontSize: 11),
        ),
        if (_loadingPrice)
          const SizedBox(
            width: 12,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF3182F6),
            ),
          )
        else if (_priceResult == null)
          Text(
            '--',
            style: GoogleFonts.robotoMono(
              color: labelColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          )
        else
          Text(
            _priceResult!.formattedPrice,
            style: GoogleFonts.robotoMono(
              color: accentColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
      ],
    );
  }

  Widget _buildPremiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        'PREMIUM',
        style: GoogleFonts.inter(
          color: const Color(0xFF9A6E00),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildPriceBox(
    String label,
    double price,
    String market,
    Color valueColor,
    Color labelColor,
  ) {
    final isKrw = market != 'US';
    final formatted = isKrw
        ? '₩${NumberFormat('#,###').format(price.toInt())}'
        : '\$${price.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: labelColor, fontSize: 11),
        ),
        Text(
          formatted,
          style: GoogleFonts.robotoMono(
            color: valueColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
