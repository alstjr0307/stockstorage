import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_pick.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/stock_price_service.dart';
import 'login_screen.dart';
import 'stock_detail_screen.dart';
import 'trading_journal_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131929) : const Color(0xFFF2F4F6),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(9999),
              ),
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.45),
              labelStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: '내 매매일지'),
                Tab(text: '관심 추천주'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [const TradingJournalTab(), _FavoritesTab()],
          ),
        ),
      ],
    );
  }
}

class _FavoritesTab extends StatelessWidget {
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
          Icon(
            Icons.account_circle_outlined,
            color: cs.onSurface.withValues(alpha: 0.2),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            '로그인이 필요합니다',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '추천주를 추가하고 수익률을 확인하세요',
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.25),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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
  final GlobalKey _shareCardKey = GlobalKey();
  final bool _capturing = false;

  void _fetchPriceIfNeeded(StockPick pick) {
    if (_loadingIds.contains(pick.id) || _prices.containsKey(pick.id)) return;
    _loadingIds.add(pick.id);
    StockPriceService.fetchPrice(pick.ticker, pick.market).then((result) {
      if (mounted) {
        setState(() {
          _prices[pick.id] = result;
          _loadingIds.remove(pick.id);
        });
        if (result != null) {
          final returnRate =
              ((result.price - pick.buyPrice) / pick.buyPrice) * 100;
          _checkAlertThreshold(pick, returnRate);
        }
      }
    });
  }

  Future<void> _checkAlertThreshold(StockPick pick, double returnRate) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'portfolio_alert_${pick.id}';
    final lastThreshold = prefs.getInt(key) ?? 0;
    final currentThreshold = (returnRate / 10).truncate().toInt() * 10;

    if (currentThreshold != 0 && currentThreshold != lastThreshold) {
      await prefs.setInt(key, currentThreshold);
      await NotificationService.showPortfolioAlert(pick.name, returnRate);
    }
  }

  Future<void> _shareCard(
    int total,
    int positive,
    int withPrice,
    double avgReturn,
    List<StockPick> picks,
  ) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ShareCardSheet(
        shareCardKey: _shareCardKey,
        total: total,
        positive: positive,
        withPrice: withPrice,
        avgReturn: avgReturn,
        picks: picks,
        prices: Map.from(_prices),
      ),
    );
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
                child: CircularProgressIndicator(color: Color(0xFF10B981)),
              );
            }

            final allPicks = picksSnapshot.data ?? [];
            final favPicks = allPicks
                .where((p) => favIds.contains(p.id))
                .toList();

            for (final pick in favPicks) {
              _fetchPriceIfNeeded(pick);
            }

            if (favPicks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      color: cs.onSurface.withValues(alpha: 0.2),
                      size: 52,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '추천주를 추가해보세요',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.4),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '종목 카드의 ♡ 버튼을 눌러 추가',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.25),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Aggregate stats
            final withPrice = favPicks
                .where((p) => _prices[p.id] != null)
                .toList();
            double totalReturn = 0;
            int positiveCount = 0;
            for (final p in withPrice) {
              final ret =
                  ((_prices[p.id]!.price - p.buyPrice) / p.buyPrice) * 100;
              totalReturn += ret;
              if (ret > 0) positiveCount++;
            }
            final avgReturn = withPrice.isEmpty
                ? 0.0
                : totalReturn / withPrice.length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
              children: [
                _buildStatsHeader(
                  context,
                  favPicks.length,
                  positiveCount,
                  withPrice.length,
                  avgReturn,
                  favPicks,
                ),
                const SizedBox(height: 28),
                Text(
                  '관심 추천주',
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < favPicks.length; i++) ...[
                  _buildPickCard(context, favPicks[i]),
                  if (i < favPicks.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.onSurface.withValues(alpha: 0.07),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatsHeader(
    BuildContext context,
    int total,
    int positive,
    int withPrice,
    double avgReturn,
    List<StockPick> picks,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isPositive = avgReturn >= 0;
    final avgColor = isPositive
        ? const Color(0xFFF04452)
        : const Color(0xFF1677FF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFF04452),
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              '관심추천주 현황',
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _capturing
                  ? null
                  : () => _shareCard(
                      total,
                      positive,
                      withPrice,
                      avgReturn,
                      picks,
                    ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded, size: 14),
              label: Text(
                '공유',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '추천주 $total개 · 실시간 기준',
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.45),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _statItem(
                context,
                '추천주 평균 수익률',
                withPrice == 0
                    ? '--'
                    : '${isPositive ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
                avgColor,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: cs.onSurface.withValues(alpha: 0.1),
            ),
            Expanded(
              child: _statItem(
                context,
                '수익 중',
                '$positive개',
                const Color(0xFFF04452),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: cs.onSurface.withValues(alpha: 0.1),
            ),
            Expanded(
              child: _statItem(
                context,
                '손실 중',
                '${withPrice - positive}개',
                const Color(0xFF1677FF),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: cs.onSurface.withValues(alpha: 0.38),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.robotoMono(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
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
      onTap: () => Navigator.push(context, stockDetailRoute(pick)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                pick.ticker,
                style: GoogleFonts.robotoMono(
                  color: cs.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
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
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '매수 ${formatPrice(pick.buyPrice)}',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ] else if (livePrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '현재 ${formatPrice(livePrice)}',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPositive
                    ? const Color(0xFFF04452).withValues(alpha: 0.12)
                    : const Color(0xFF1677FF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                style: GoogleFonts.robotoMono(
                  color: isPositive
                      ? const Color(0xFFF04452)
                      : const Color(0xFF1677FF),
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

// ─── 공유 카드 바텀시트 ───────────────────────────────────────────────────────

class _ShareCardSheet extends StatefulWidget {
  final GlobalKey shareCardKey;
  final int total;
  final int positive;
  final int withPrice;
  final double avgReturn;
  final List<StockPick> picks;
  final Map<String, PriceResult?> prices;

  const _ShareCardSheet({
    required this.shareCardKey,
    required this.total,
    required this.positive,
    required this.withPrice,
    required this.avgReturn,
    required this.picks,
    required this.prices,
  });

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  bool _sharing = false;

  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  Future<void> _captureAndShare() async {
    setState(() => _sharing = true);
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      final boundary =
          widget.shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final file = File(
        '${Directory.systemTemp.path}/portfolio_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '📊 주식저장소 관심추천주 현황',
        sharePositionOrigin: _shareOrigin(),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = widget.avgReturn >= 0;
    final sign = isPositive ? '+' : '';
    final color = isPositive ? const Color(0xFF10B981) : Colors.redAccent;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // 공유 카드 (캡처 대상)
          RepaintBoundary(
            key: widget.shareCardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '주식저장소',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        DateFormat('yyyy.MM.dd').format(DateTime.now()),
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // 추천주 평균 수익률 (메인)
                  Text(
                    '추천주 평균 수익률',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.withPrice == 0
                        ? '--'
                        : '$sign${widget.avgReturn.toStringAsFixed(2)}%',
                    style: GoogleFonts.inter(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 42,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 구분선
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 20),
                  // 통계 3개
                  Row(
                    children: [
                      _shareStatItem('보유 종목', '${widget.total}개', Colors.white),
                      _shareStatItem(
                        '수익 중',
                        '${widget.positive}개',
                        const Color(0xFF10B981),
                      ),
                      _shareStatItem(
                        '손실 중',
                        '${widget.withPrice - widget.positive}개',
                        Colors.redAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 종목 리스트
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 12),
                  ...widget.picks.map((pick) {
                    final priceResult = widget.prices[pick.id];
                    final livePrice = priceResult?.price;
                    final returnRate = livePrice != null
                        ? ((livePrice - pick.buyPrice) / pick.buyPrice) * 100
                        : pick.returnRate;
                    final isPos = returnRate >= 0;
                    final retColor = isPos
                        ? const Color(0xFF10B981)
                        : Colors.redAccent;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              pick.ticker,
                              style: GoogleFonts.robotoMono(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pick.name,
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${isPos ? '+' : ''}${returnRate.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              color: retColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // 하단 워터마크
                  Center(
                    child: Text(
                      '주식저장소 앱에서 확인하세요',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 공유 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _captureAndShare,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: const Color(
                  0xFF10B981,
                ).withValues(alpha: 0.4),
              ),
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(
                _sharing ? '처리 중...' : '이미지로 공유',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
