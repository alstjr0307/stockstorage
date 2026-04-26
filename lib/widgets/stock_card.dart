import 'package:flutter/material.dart';
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

class _StockCardState extends State<StockCard>
    with SingleTickerProviderStateMixin {
  PriceResult? _priceResult;
  bool _loadingPrice = true;
  AnimationController? _newPulseController;
  Animation<double>? _newPulseScale;

  StockPick get pick => widget.pick;

  @override
  void initState() {
    super.initState();
    _ensurePulseAnimation();
    _fetchPrice();
  }

  @override
  void dispose() {
    _newPulseController?.dispose();
    super.dispose();
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

  double get _liveReturnRate {
    if (_priceResult != null) {
      return ((_priceResult!.price - pick.buyPrice) / pick.buyPrice) * 100;
    }
    return pick.returnRate;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF191F28);
    final textSecondary = isDark
        ? Colors.white.withValues(alpha: 0.48)
        : const Color(0xFF6B7684);
    final textTertiary = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : const Color(0xFFB0B8C1);
    final tickerBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFF2F4F6);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFD9DEE4);
    final blurredCardBg = isDark
        ? const Color(0xFF152621)
        : const Color(0xFFF2FBF8);
    final blurredBorder = isDark
        ? const Color(0xFF10B981).withValues(alpha: 0.35)
        : const Color(0xFF10B981).withValues(alpha: 0.24);

    final isBlurred = !widget.isLoggedIn;
    final isNewPick = _isWithin24Hours(pick.createdAt);
    final returnRate = _liveReturnRate;
    final isPositive = returnRate >= 0;
    final changeColor = isPositive
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, isBlurred ? 10 : 14, 20, 0),
        child: Container(
          padding: isBlurred
              ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
              : EdgeInsets.zero,
          decoration: isBlurred
              ? BoxDecoration(
                  color: blurredCardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: blurredBorder, width: 1.1),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNewPick) ...[
                _buildNewTopAccent(isDark),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeago.format(pick.createdAt, locale: 'ko'),
                              style: _pretendard(
                                color: textTertiary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isNewPick) ...[
                              const SizedBox(width: 6),
                              _buildNewBadge(isDark),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: isBlurred
                                  ? Container(
                                      height: 22,
                                      width: 130,
                                      decoration: BoxDecoration(
                                        color: textPrimary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    )
                                  : Text(
                                      pick.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _pretendard(
                                        color: textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                      ),
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
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: isDark ? 0.2 : 0.14),
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_outline_rounded,
                                      size: 11,
                                      color: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: isDark ? 0.95 : 0.85),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '미리보기',
                                      style: _pretendard(
                                        color: const Color(0xFF10B981)
                                            .withValues(
                                              alpha: isDark ? 0.95 : 0.85,
                                            ),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.onFavoriteToggle != null) ...[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: GestureDetector(
                        onTap: widget.onFavoriteToggle,
                        child: Icon(
                          widget.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 20,
                          color: widget.isFavorite
                              ? Colors.redAccent
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildPriceBlock(
                    label: '추천가',
                    value: _formatPrice(pick.buyPrice, pick.market),
                    valueColor: textPrimary,
                    labelColor: textSecondary,
                  ),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 30, color: dividerColor),
                  const SizedBox(width: 16),
                  _buildCurrentPriceBlock(
                    labelColor: textSecondary,
                    valueColor: changeColor,
                  ),
                  const Spacer(),
                  _buildReturnSummary(
                    returnRate: returnRate,
                    color: changeColor,
                    labelColor: textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isBlurred)
                _buildBlurredReason(textSecondary, isDark, blurredCardBg)
              else
                Text(
                  pick.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _pretendard(
                    color: textSecondary,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              const SizedBox(height: 14),
              if (!isBlurred)
                Divider(height: 1, thickness: 1, color: dividerColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBlock({
    required String label,
    required String value,
    required Color valueColor,
    required Color labelColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: _pretendard(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPriceBlock({
    required Color labelColor,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '현재가',
          style: _pretendard(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        if (_loadingPrice)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Color(0xFF10B981),
            ),
          )
        else if (_priceResult == null)
          Text(
            '--',
            style: TextStyle(
              color: labelColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            _priceResult!.formattedPrice,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  Widget _buildReturnSummary({
    required double returnRate,
    required Color color,
    required Color labelColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '추천가 대비',
          style: _pretendard(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        _buildReturnBadge(returnRate, color),
      ],
    );
  }

  Widget _buildReturnBadge(double returnRate, Color color) {
    final sign = returnRate > 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        '$sign${returnRate.toStringAsFixed(1)}%',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildNewBadge(bool isDark) {
    const badge = Color(0xFFFACC15);
    _ensurePulseAnimation();
    return AnimatedBuilder(
      animation: _newPulseScale!,
      builder: (context, child) {
        return Transform.scale(scale: _newPulseScale!.value, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badge.withValues(alpha: isDark ? 0.24 : 0.2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: badge.withValues(alpha: isDark ? 0.55 : 0.42),
          ),
        ),
        child: Text(
          'NEW',
          style: TextStyle(
            color: const Color(0xFF7A4B00),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildNewTopAccent(bool isDark) {
    _ensurePulseAnimation();
    const accent = Color(0xFFFACC15);
    return AnimatedBuilder(
      animation: _newPulseScale!,
      builder: (context, child) {
        final t = (_newPulseScale!.value - 0.9) / 0.22;
        final opacity = (0.62 + (t.clamp(0.0, 1.0) * 0.38)).clamp(0.0, 1.0);
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        height: 3,
        width: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: isDark ? 0.95 : 0.9),
              accent.withValues(alpha: isDark ? 0.45 : 0.35),
            ],
          ),
        ),
      ),
    );
  }

  void _ensurePulseAnimation() {
    if (_newPulseController != null && _newPulseScale != null) return;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..repeat(reverse: true);
    _newPulseController = controller;
    _newPulseScale = Tween<double>(
      begin: 0.9,
      end: 1.12,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
  }

  Widget _buildBlurredReason(
    Color textSecondary,
    bool isDark,
    Color baseBackground,
  ) {
    return Stack(
      children: [
        Text(
          pick.reason,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _pretendard(color: textSecondary, fontSize: 15, height: 1.6),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  baseBackground.withValues(alpha: 0.96),
                ],
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF10B981).withValues(alpha: 0.18)
                    : const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.45)
                      : const Color(0xFF10B981).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '로그인 필요',
                style: _pretendard(
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF0E9F6E),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _pretendard({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Pretendard',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  String _formatPrice(double price, String market) {
    if (market == 'US') {
      return '\$${price.toStringAsFixed(2)}';
    }
    return 'KRW ${NumberFormat('#,###').format(price.toInt())}';
  }

  bool _isWithin24Hours(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt.toLocal());
    return !diff.isNegative && diff <= const Duration(hours: 24);
  }
}
