import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post.dart';
import '../models/stock_pick.dart';
import '../models/announcement.dart';
import '../models/market_feature_stock.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/stock_card.dart';
import '../widgets/user_level_avatar.dart';
import 'admin_screen.dart';
import 'community_screen.dart';
import 'leaderboard_screen.dart';
import 'login_screen.dart';
import 'market_analysis_screen.dart';
import 'market_sentiment_screen.dart';
import 'market_feature_stock_detail_screen.dart';
import 'market_feature_stocks_screen.dart';
import 'portfolio_screen.dart';
import 'my_comments_screen.dart';
import 'my_posts_screen.dart';
import 'notification_history_screen.dart';
import 'post_detail_screen.dart';
import 'stock_ai_analysis_list_screen.dart';
import 'stock_compare_screen.dart';
import 'stock_detail_screen.dart';
import 'stock_search_screen.dart';
import 'index_detail_screen.dart';
import '../main.dart' show initAds;

bool _homeLightMode = false;

Color get _homeBg0 =>
    _homeLightMode ? const Color(0xFFF6F8FB) : const Color(0xFF0A0E1A);
Color get _homeBg2 =>
    _homeLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF111827);
Color get _homeBg3 =>
    _homeLightMode ? const Color(0xFFF0F4F8) : const Color(0xFF161E2E);
Color get _homeCard =>
    _homeLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF0F1520);
Color get _homeCardHi =>
    _homeLightMode ? const Color(0xFFF8FBFF) : const Color(0xFF141B2A);
Color get _homeBorder =>
    _homeLightMode ? const Color(0x140F172A) : const Color(0x12FFFFFF);
Color get _homeLabel =>
    _homeLightMode ? const Color(0xFF172033) : const Color(0xFFEEF2FF);
Color get _homeMuted =>
    _homeLightMode ? const Color(0xA6172033) : const Color(0x8CEEF2FF);
Color get _homeFaint =>
    _homeLightMode ? const Color(0x75172033) : const Color(0x52EEF2FF);
Color get _homeAccent => const Color(0xFF00B67A);
Color get _homeUp => const Color(0xFFFF4E6A);
Color get _homeDown => const Color(0xFF1677FF);
Color get _homeGold => const Color(0xFFF5B547);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  // 탭: 0=홈, 1=커뮤니티, 2=매매일지, 3=관심종목
  int _currentPage = 0;
  int _communityInitialTabIndex = 0;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // 검색
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _rewardAdLoading = false;
  static const _tabTitles = ['주식저장소', '커뮤니티', '매매일지', '⭐ 관심종목'];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      initAds();
      BannerAdWidget.prewarm(
        slotId: 'market_analysis_between_indices_hot',
        adUnitId: AdService.marketAnalysisMidBannerAdUnitId,
        fallbackAdUnitId: AdService.bannerAdUnitId,
      );
      BannerAdWidget.prewarm(
        slotId: 'market_analysis_indices_only',
        adUnitId: AdService.marketAnalysisMidBannerAdUnitId,
        fallbackAdUnitId: AdService.bannerAdUnitId,
      );
      await _showDisclaimerIfNeeded();
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        await _firestoreService.syncUserContributionStats(auth.user!.uid);
      }
      await _checkNicknameIfNeeded();
    });
  }

  Future<void> _checkNicknameIfNeeded() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || !mounted) return;
    final uid = auth.user!.uid;
    final nickname = await _firestoreService.getNickname(uid);
    if ((nickname == null || nickname.isEmpty) && mounted) {
      final ctrl = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(
              '닉네임 설정',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '댓글에 표시될 닉네임을 입력해주세요.',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: '닉네임',
                    hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: cs.onSurface.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF10B981),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final nick = ctrl.text.trim();
                  await _firestoreService.setNickname(
                    uid,
                    nick.isEmpty ? '익명' : nick,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  '확인',
                  style: TextStyle(
                    color: const Color(0xFF10B981),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      );
      ctrl.dispose();
    }
  }

  Future<void> _showDisclaimerIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('disclaimer_shown') ?? false;
    if (shown || !mounted) return;
    await prefs.setBool('disclaimer_shown', true);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2035) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF10B981),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '이용 안내',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Text(
            '본 앱은 투자 공부 중인 개인이 관심 종목을 기록·공유하는 공간입니다.\n\n'
            '제공되는 정보는 투자 권유나 조언이 아니며, 일대일 투자 자문은 절대 하지 않습니다. 투자 판단과 그 결과에 대한 책임은 전적으로 본인에게 있습니다.',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.65,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                '확인',
                style: TextStyle(
                  color: const Color(0xFF10B981),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _showRootSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndWatchRewardAd(AuthProvider auth) async {
    if (_rewardAdLoading) return;

    final shouldWatch = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          '리워드 광고 안내',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '광고 시청을 완료하면 경험치 +5를 받을 수 있어요.\n보상은 시청 완료 후 지급됩니다.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              '광고 보기',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldWatch == true) {
      await _watchRewardAdAndClaimXp(auth);
    }
  }

  Future<void> _watchRewardAdAndClaimXp(AuthProvider auth) async {
    if (_rewardAdLoading) return;
    final uid = auth.user?.uid;
    if (uid == null || uid.isEmpty) return;

    setState(() => _rewardAdLoading = true);
    try {
      final earnedReward = await AdService.instance
          .showRewardedAdAndWaitReward();
      if (!mounted) return;
      if (!earnedReward) {
        _showRootSnackBar('광고 시청이 완료되지 않아 XP가 지급되지 않았어요.');
        return;
      }

      final granted = await _firestoreService.grantDailyRewardAdXp(uid);
      if (!mounted) return;
      if (granted) {
        _showRootSnackBar('리워드 지급 완료! 경험치 +5');
      } else {
        _showRootSnackBar('오늘 리워드 광고 보상은 3회 모두 받았어요.');
      }
    } catch (_) {
      if (!mounted) return;
      _showRootSnackBar('리워드 광고를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _rewardAdLoading = false);
    }
  }

  List<Widget> _buildTopActions(
    AuthProvider auth, {
    required bool isDarkSurface,
    required bool showSearchButton,
  }) {
    final iconColor = isDarkSurface ? Colors.white70 : Colors.black54;
    return [
      if (auth.isLoggedIn)
        IconButton(
          icon: Icon(Icons.notifications_none, color: iconColor),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationHistoryScreen(),
              ),
            );
          },
        ),
      if (auth.isAdmin)
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF10B981)),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminScreen()),
          ),
        ),
      IconButton(
        icon: Icon(
          auth.isLoggedIn ? Icons.person : Icons.person_outline,
          color: iconColor,
        ),
        onPressed: () {
          if (auth.isLoggedIn) {
            _showProfileMenu(context, auth);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _homeLightMode = !isDark;
    final isHome = _currentPage == 0;
    final hideHomeAppBar = isHome && !_showSearch;
    final bgColor = isHome
        ? _homeBg0
        : Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: hideHomeAppBar
          ? null
          : AppBar(
              backgroundColor: bgColor,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 16,
              title: _showSearch && _currentPage == 0
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: '종목명 또는 티커 검색...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          AnalyticsService.instance.logSearch(v.trim());
                        }
                      },
                    )
                  : null,
              actions: _buildTopActions(
                auth,
                isDarkSurface: isHome || isDark,
                showSearchButton: true,
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentPage,
        onTap: (i) {
          if (i == _currentPage) return;
          if (i != 0) _closeSearch();
          _fadeController.forward(from: 0.0);
          setState(() {
            _currentPage = i;
            if (i == 1) _communityInitialTabIndex = 0;
          });
          const tabNames = ['홈', '커뮤니티', '매매일지', '관심종목'];
          AnalyticsService.instance.logTabChange(tabNames[i]);
        },
        backgroundColor: bgColor,
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: isDark ? Colors.white38 : Colors.black54,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: '커뮤니티',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: '매매일지',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_border_rounded),
            activeIcon: Icon(Icons.star_rounded),
            label: '관심종목',
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: IndexedStack(
          index: _currentPage,
          children: [
            _buildDashboardPage(auth),
            CommunityScreen(
              key: ValueKey('community_$_communityInitialTabIndex'),
              initialTabIndex: _communityInitialTabIndex,
            ),
            _buildMyStocksPage(),
            _buildFavoriteStocksPage(auth),
          ],
        ),
      ),
    );
  }

  // ─── 매매일지 페이지 ───────────────────────────────────────────────────
  Widget _buildMyStocksPage() {
    return const PortfolioScreen();
  }

  Widget _buildFavoriteStocksPage(AuthProvider auth) {
    return _FavoriteStocksBody(
      firestoreService: _firestoreService,
      uid: auth.user?.uid,
    );
  }

  Widget _buildDashboardPage(AuthProvider auth) {
    return _DashboardHomePage(
      auth: auth,
      firestoreService: _firestoreService,
      openCommunity: () {
        _fadeController.forward(from: 0.0);
        setState(() {
          _communityInitialTabIndex = 0;
          _currentPage = 1;
        });
      },
      openJournal: () {
        _fadeController.forward(from: 0.0);
        setState(() => _currentPage = 2);
      },
      openFavoritePicks: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FavoritesPicksScreen()),
      ),
      openFavoriteStocks: () => setState(() => _currentPage = 3),
      openStockSearch: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StockSearchScreen()),
      ),
      openStockPicks: () =>
          _openStandalonePage(title: '추천주', child: _buildStockPicksPage(auth)),
      openAnnouncements: () => _openStandalonePage(
        title: '공지사항',
        child: _AnnouncementsTab(firestoreService: _firestoreService),
      ),
      openIndexList: _openIndexListPage,
      openMarketAnalysis: () => _openStandalonePage(
        title: '시황분석글',
        child: const MarketAnalysisScreen(),
      ),
      openFeatureStocks: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MarketFeatureStocksScreen()),
      ),
      openFmkoreaHot: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FmkoreaHotStocksScreen()),
      ),
      openFmkoreaIndex: () {
        AdService.instance.showIndicatorDetailInterstitialIfReady();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FmkoreaIndexDetailScreen()),
        );
      },
      openInvestorFlow: () {
        AdService.instance.showIndicatorDetailInterstitialIfReady();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InvestorFlowDetailScreen()),
        );
      },
      openMarketSentiment: () {
        AdService.instance.showIndicatorDetailInterstitialIfReady();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MarketSentimentScreen()),
        );
      },
      openStockCompare: () => _openStandalonePage(
        title: '종목 비교',
        child: const StockCompareScreen(),
      ),
      openAiAnalysisList: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StockAiAnalysisListScreen()),
      ),
      watchRewardAd: () => _confirmAndWatchRewardAd(auth),
      onTopStateChanged: (_) {},
      topActions: _showSearch
          ? const []
          : _buildTopActions(auth, isDarkSurface: true, showSearchButton: true),
    );
  }

  void _openStandalonePage({required String title, required Widget child}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: child,
        ),
      ),
    );
  }

  void _openIndexListPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _IndexListPage()),
    );
  }

  // ─── 주식저장소 페이지 ────────────────────────────────────────────────────

  Widget _buildStockPicksPage(AuthProvider auth) {
    return _StockStoragePage(
      auth: auth,
      searchQuery: _searchQuery,
      firestoreService: _firestoreService,
    );
  }

  // ─── 프로필 메뉴 ──────────────────────────────────────────────────────────

  void _showProfileMenu(BuildContext context, AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
    final uid = auth.user!.uid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer<ThemeProvider>(
        builder: (ctx, themeProvider, _) => Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(
                        0xFF10B981,
                      ).withValues(alpha: 0.15),
                      radius: 28,
                      child: const Icon(
                        Icons.person,
                        color: Color(0xFF10B981),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<String?>(
                      future: _firestoreService.getNickname(uid),
                      builder: (ctx, snap) {
                        final nickname = snap.data;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              nickname ?? '닉네임 없음',
                              style: TextStyle(
                                color: nickname != null
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                          ? Colors.white38
                                          : Colors.black38),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                _showNicknameDialog(auth, nickname);
                              },
                              child: Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.user?.email ?? '',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<Map<String, int>>(
                      stream: _firestoreService.watchUserLevelInfo(uid),
                      builder: (ctx, snap) {
                        final stats =
                            snap.data ??
                            const {
                              'level': 1,
                              'postCount': 0,
                              'commentCount': 0,
                              'attendanceCount': 0,
                              'bonusXp': 0,
                            };
                        final level = stats['level'] ?? 1;
                        final postCount = stats['postCount'] ?? 0;
                        final commentCount = stats['commentCount'] ?? 0;
                        final attendanceCount = stats['attendanceCount'] ?? 0;
                        final bonusXp = stats['bonusXp'] ?? 0;
                        final progressInfo = _firestoreService
                            .calculateLevelProgress(
                              postCount: postCount,
                              commentCount: commentCount,
                              attendanceCount: attendanceCount,
                              bonusXp: bonusXp,
                            );
                        final currentXp =
                            (progressInfo['currentXpInLevel'] ?? 0).toInt();
                        final needXp = (progressInfo['xpForNextLevel'] ?? 1)
                            .toInt();
                        final remainXp = (progressInfo['remainingXp'] ?? 0)
                            .toInt();
                        final progress = (progressInfo['progress'] ?? 0)
                            .toDouble();

                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Lv.$level',
                                        style: TextStyle(
                                          color: const Color(0xFF10B981),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '$currentXp / $needXp XP',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.black54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 7,
                                      backgroundColor: isDark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.black.withValues(
                                              alpha: 0.08,
                                            ),
                                      valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFF10B981),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '다음 레벨까지 $remainXp XP',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black45,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  StreamBuilder<Map<String, int>>(
                                    stream: _firestoreService
                                        .watchRewardAdStatus(uid),
                                    builder: (context, rewardSnap) {
                                      final status = rewardSnap.data;
                                      final canWatchToday =
                                          (status?['canWatchToday'] ?? 1) == 1;
                                      final remainingCount =
                                          status?['remainingCount'] ?? 3;
                                      final dailyLimit =
                                          status?['dailyLimit'] ?? 3;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                elevation: 0,
                                                backgroundColor: const Color(
                                                  0xFF10B981,
                                                ),
                                                foregroundColor: const Color(
                                                  0xFF07120E,
                                                ),
                                                disabledBackgroundColor:
                                                    const Color(
                                                      0xFF10B981,
                                                    ).withValues(alpha: 0.4),
                                                disabledForegroundColor:
                                                    const Color(
                                                      0xFF07120E,
                                                    ).withValues(alpha: 0.6),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                              ),
                                              onPressed:
                                                  canWatchToday &&
                                                      !_rewardAdLoading
                                                  ? () =>
                                                        _confirmAndWatchRewardAd(
                                                          auth,
                                                        )
                                                  : null,
                                              icon: _rewardAdLoading
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.ondemand_video,
                                                      size: 16,
                                                    ),
                                              label: Text(
                                                _rewardAdLoading
                                                    ? '광고 준비 중...'
                                                    : '리워드 광고 보고 +5 XP',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '오늘 보상 광고: $remainingCount/$dailyLimit회 남음',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white38
                                                  : Colors.black45,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _buildProfileStatChip(
                                  label: '글/일지 $postCount',
                                  icon: Icons.edit_note_outlined,
                                  isDark: isDark,
                                ),
                                _buildProfileStatChip(
                                  label: '댓글 $commentCount',
                                  icon: Icons.chat_bubble_outline,
                                  isDark: isDark,
                                ),
                                _buildProfileStatChip(
                                  label: '출석 $attendanceCount',
                                  icon: Icons.calendar_today_outlined,
                                  isDark: isDark,
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // 내 댓글
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white70
                              : Colors.black54,
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.favorite_border, size: 16),
                        label: Text(
                          '관심 추천주',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FavoritesPicksScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white70
                              : Colors.black54,
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.article_outlined, size: 16),
                        label: Text(
                          '내가 쓴 글',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MyPostsScreen(uid: uid),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white70
                              : Colors.black54,
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: Text(
                          '내 댓글',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MyCommentsScreen(uid: uid),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.15,
                          ),
                          foregroundColor: Colors.redAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          auth.signOut();
                        },
                        child: Text(
                          '로그아웃',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white24
                              : Colors.black26,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _showDeleteAccountDialog(auth);
                        },
                        child: Text('계정 삭제', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 다크모드 토글 — 오른쪽 상단
            Positioned(
              top: 12,
              right: 8,
              child: GestureDetector(
                onTap: themeProvider.toggle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      themeProvider.isDark ? '라이트 모드' : '다크 모드',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      themeProvider.isDark
                          ? Icons.wb_sunny_outlined
                          : Icons.dark_mode_outlined,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStatChip({
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF10B981)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A2035) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '계정 삭제',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '계정을 삭제하면 모든 데이터(관심 추천주, 메모, 댓글 등)가 영구적으로 삭제됩니다.\n\n정말 삭제하시겠습니까?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await auth.deleteAccount();
              } on Exception catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
                }
              }
            },
            child: Text(
              '삭제',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNicknameDialog(AuthProvider auth, String? currentNickname) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = auth.user!.uid;
    final controller = TextEditingController(text: currentNickname ?? '');
    String? errorMsg;
    bool checking = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '닉네임 설정',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '닉네임 입력 (2~12자)',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    errorText: errorMsg,
                  ),
                  onChanged: (_) {
                    if (errorMsg != null) {
                      setDialogState(() => errorMsg = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '취소',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: checking
                    ? null
                    : () async {
                        final nick = controller.text.trim();
                        if (nick.length < 2 || nick.length > 12) {
                          setDialogState(() => errorMsg = '닉네임은 2~12자여야 합니다');
                          return;
                        }
                        setDialogState(() => checking = true);
                        final taken = await _firestoreService.isNicknameTaken(
                          nick,
                          uid,
                        );
                        if (taken) {
                          setDialogState(() {
                            errorMsg = '이미 사용 중인 닉네임입니다';
                            checking = false;
                          });
                          return;
                        }
                        await _firestoreService.setNickname(uid, nick);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                child: checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text('저장', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── 홈 피드 ───────────────────────────────────────────────────────────────

class _DashboardHomePage extends StatefulWidget {
  const _DashboardHomePage({
    required this.auth,
    required this.firestoreService,
    required this.openCommunity,
    required this.openJournal,
    required this.openFavoritePicks,
    required this.openFavoriteStocks,
    required this.openStockSearch,
    required this.openStockPicks,
    required this.openAnnouncements,
    required this.openIndexList,
    required this.openMarketAnalysis,
    required this.openFeatureStocks,
    required this.openFmkoreaHot,
    required this.openFmkoreaIndex,
    required this.openInvestorFlow,
    required this.openMarketSentiment,
    required this.openStockCompare,
    required this.openAiAnalysisList,
    required this.watchRewardAd,
    required this.onTopStateChanged,
    required this.topActions,
  });

  final AuthProvider auth;
  final FirestoreService firestoreService;
  final VoidCallback openCommunity;
  final VoidCallback openJournal;
  final VoidCallback openFavoritePicks;
  final VoidCallback openFavoriteStocks;
  final VoidCallback openStockSearch;
  final VoidCallback openStockPicks;
  final VoidCallback openAnnouncements;
  final VoidCallback openIndexList;
  final VoidCallback openMarketAnalysis;
  final VoidCallback openFeatureStocks;
  final VoidCallback openFmkoreaHot;
  final VoidCallback openFmkoreaIndex;
  final VoidCallback openInvestorFlow;
  final VoidCallback openMarketSentiment;
  final VoidCallback openStockCompare;
  final VoidCallback openAiAnalysisList;
  final VoidCallback watchRewardAd;
  final ValueChanged<bool> onTopStateChanged;
  final List<Widget> topActions;

  @override
  State<_DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<_DashboardHomePage> {
  late Future<(List<Post>, DocumentSnapshot?)> _postsFuture;
  late Future<Map<String, PriceResult?>> _indicesFuture;
  late Stream<Announcement?> _latestAnnouncementStream;
  late Stream<List<MarketFeatureStock>> _featureStocksStream;
  late Stream<List<StockPick>> _stockPicksStream;

  static const _homeIndices = [
    ('KOSPI', '^KS11'),
    ('KOSDAQ', '^KQ11'),
    ('나스닥100 선물', 'NQ=F'),
  ];

  static Widget _fixedH(double height, Widget child) => SizedBox(
    height: height,
    child: ClipRect(child: child),
  );

  @override
  void initState() {
    super.initState();
    _postsFuture = widget.firestoreService.getPostsPaged(limit: 40);
    _indicesFuture = _loadIndices();
    _latestAnnouncementStream = widget.firestoreService.getLatestAnnouncement();
    _featureStocksStream = widget.firestoreService.getMarketFeatureStocks(
      group: 'chart_capture',
      limit: 40,
    );
    _stockPicksStream = widget.firestoreService.getAllStockPicks();
  }

  Future<void> _refresh() async {
    setState(() {
      _postsFuture = widget.firestoreService.getPostsPaged(limit: 40);
      for (final entry in _homeIndices) {
        StockPriceService.invalidateCache(entry.$2);
      }
      _indicesFuture = _loadIndices();
    });
  }

  Future<Map<String, PriceResult?>> _loadIndices() async {
    final results = await Future.wait(
      _homeIndices.map((entry) => StockPriceService.fetchPrice(entry.$2, 'US')),
    );
    return {
      for (var i = 0; i < _homeIndices.length; i++)
        _homeIndices[i].$1: results[i],
    };
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF10B981),
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            widget.onTopStateChanged(notification.metrics.pixels <= 12);
          }
          return false;
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _homeBg0,
            gradient: RadialGradient(
              center: Alignment(0.7, -1.05),
              radius: 1.2,
              colors: [Color(0x1500D68F), _homeBg0],
              stops: [0, 0.62],
            ),
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: ListView(
              cacheExtent: 900,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 88),
              children: [
                _fixedH(
                  180,
                  _HomeReveal(
                    order: 0,
                    child: _HomeHeroGreeting(
                      auth: widget.auth,
                      firestoreService: widget.firestoreService,
                      topActions: widget.topActions,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  52,
                  _HomeReveal(
                    order: 1,
                    child: _LatestAnnouncementStrip(
                      stream: _latestAnnouncementStream,
                      onTap: widget.openAnnouncements,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  292,
                  _HomeReveal(
                    order: 2,
                    child: _DailyMissionCard(
                      auth: widget.auth,
                      firestoreService: widget.firestoreService,
                      onWatchAd: widget.watchRewardAd,
                      openCommunity: widget.openCommunity,
                      openJournal: widget.openJournal,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  360,
                  _HomeReveal(
                    order: 3,
                    child: _DarkHomeSection(
                      title: '📈 실시간 시장',
                      trailing: const _LiveStatusChip(),
                      child: _MarketLiveCard(
                        indicesFuture: _indicesFuture,
                        onMore: widget.openIndexList,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  220,
                  _HomeReveal(order: 4, child: const _AIBriefCard()),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  220,
                  _HomeReveal(
                    order: 5,
                    child: _TopMoversPreview(
                      stream: _featureStocksStream,
                      openFeatureStocks: widget.openFeatureStocks,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  452,
                  _HomeReveal(
                    order: 6,
                    child: _DarkHomeSection(
                      title: '🔥 지금 핫한 토론',
                      actionText: '더보기',
                      onAction: widget.openCommunity,
                      child: _RecentPostsPreview(
                        postsFuture: _postsFuture,
                        auth: widget.auth,
                        firestoreService: widget.firestoreService,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  498,
                  _HomeReveal(
                    order: 7,
                    child: _DarkHomeSection(
                      title: '❤️ 내 관심 추천주',
                      child: _FavoritePicksPreview(
                        firestoreService: widget.firestoreService,
                        picksStream: _stockPicksStream,
                        auth: widget.auth,
                        openStockPicks: widget.openFavoritePicks,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _fixedH(
                  422,
                  _HomeReveal(
                    order: 8,
                    child: _DarkHomeSection(
                      title: '⭐ 관심종목',
                      child: _FavoriteStocksPreview(
                        firestoreService: widget.firestoreService,
                        auth: widget.auth,
                        onMore: widget.openFavoriteStocks,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _HomeReveal(
                  order: 9,
                  child: _QuickMenu(
                    openMarketAnalysis: widget.openMarketAnalysis,
                    openFeatureStocks: widget.openFeatureStocks,
                    openFmkoreaHot: widget.openFmkoreaHot,
                    openFmkoreaIndex: widget.openFmkoreaIndex,
                    openInvestorFlow: widget.openInvestorFlow,
                    openMarketSentiment: widget.openMarketSentiment,
                    openStockPicks: widget.openStockPicks,
                    openAnnouncements: widget.openAnnouncements,
                    openStockCompare: widget.openStockCompare,
                    openStockSearch: widget.openStockSearch,
                    openAiAnalysisList: widget.openAiAnalysisList,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkHomeSection extends StatelessWidget {
  const _DarkHomeSection({
    required this.title,
    required this.child,
    this.actionText,
    this.onAction,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? actionText;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: _homeText(
                    color: _homeLabel,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              if (actionText != null && onAction != null)
                _DarkActionChip(label: actionText!, onTap: onAction!),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DarkCard(child: child),
      ],
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.child, this.color, this.borderColor});

  final Widget child;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? _homeCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? _homeBorder),
      ),
      child: child,
    );
  }
}

class _LatestAnnouncementStrip extends StatelessWidget {
  const _LatestAnnouncementStrip({required this.stream, required this.onTap});

  final Stream<Announcement?> stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Announcement?>(
      stream: stream,
      builder: (context, snapshot) {
        final announcement = snapshot.data;
        final title = announcement?.title.trim();
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _homeCard,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _homeBorder),
            ),
            child: Row(
              children: [
                Text(
                  '📢 공지',
                  style: _homeText(
                    color: _homeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title == null || title.isEmpty ? '등록된 공지사항이 없습니다' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      color: title == null || title.isEmpty
                          ? _homeFaint
                          : _homeLabel,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: _homeFaint, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeReveal extends StatefulWidget {
  const _HomeReveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  State<_HomeReveal> createState() => _HomeRevealState();
}

class _HomeRevealState extends State<_HomeReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 55 * widget.order.clamp(0, 5));
    Future<void>.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.035),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: _visible ? 1 : 0.985,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class _SoftReveal extends StatefulWidget {
  const _SoftReveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  State<_SoftReveal> createState() => _SoftRevealState();
}

class _SoftRevealState extends State<_SoftReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 36 * widget.order.clamp(0, 8));
    Future<void>.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0.035, 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _Breathing extends StatefulWidget {
  const _Breathing({
    required this.child,
    this.scale = 1.035,
    this.duration = const Duration(milliseconds: 1450),
  });

  final Widget child;
  final double scale;
  final Duration duration;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 1,
      end: widget.scale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: widget.child);
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, this.active = true});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.active ? _controller.value : 0.0;
        return Opacity(
          opacity: 0.55 + t * 0.45,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: widget.active
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({
    required this.value,
    required this.color,
    required this.backgroundColor,
    required this.minHeight,
    this.duration = const Duration(milliseconds: 780),
  });

  final double value;
  final Color color;
  final Color backgroundColor;
  final double minHeight;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, animatedValue, child) {
          return LinearProgressIndicator(
            value: animatedValue,
            minHeight: minHeight,
            backgroundColor: backgroundColor,
            valueColor: AlwaysStoppedAnimation(color),
          );
        },
      ),
    );
  }
}

class _ShimmerText extends StatefulWidget {
  const _ShimmerText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) {
            final width = rect.width == 0 ? 1.0 : rect.width;
            final dx = rect.left - width + (width * 2 * _controller.value);
            return LinearGradient(
              colors: [_homeAccent, const Color(0xFFFFFFFF), _homeAccent],
              stops: const [0, 0.48, 1],
            ).createShader(Rect.fromLTWH(dx, rect.top, width, rect.height));
          },
          child: child,
        );
      },
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _DarkActionChip extends StatelessWidget {
  const _DarkActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _homeBg2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _homeBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: _homeText(
                color: _homeMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 15, color: _homeFaint),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroGreeting extends StatelessWidget {
  const _HomeHeroGreeting({
    required this.auth,
    required this.firestoreService,
    required this.topActions,
  });

  final AuthProvider auth;
  final FirestoreService firestoreService;
  final List<Widget> topActions;

  @override
  Widget build(BuildContext context) {
    final uid = auth.user?.uid;
    if (uid == null || uid.isEmpty) {
      return _HeroShell(
        nickname: '주식저장소',
        level: 1,
        xpInLevel: 0,
        xpForNext: 10,
        streak: 0,
        topActions: topActions,
      );
    }
    return StreamBuilder<Map<String, int>>(
      stream: firestoreService.watchUserLevelInfo(uid),
      builder: (context, levelSnap) {
        final data = levelSnap.data ?? const <String, int>{};
        final progress = firestoreService.calculateLevelProgress(
          postCount: data['postCount'] ?? 0,
          commentCount: data['commentCount'] ?? 0,
          attendanceCount: data['attendanceCount'] ?? 0,
          bonusXp: data['bonusXp'] ?? 0,
        );
        return FutureBuilder<String?>(
          future: firestoreService.getNickname(uid),
          builder: (context, nickSnap) {
            final nickname = nickSnap.data?.trim();
            return _HeroShell(
              nickname: nickname == null || nickname.isEmpty ? '투자자' : nickname,
              level: progress['level']?.toInt() ?? 1,
              xpInLevel: progress['currentXpInLevel']?.toInt() ?? 0,
              xpForNext: progress['xpForNextLevel']?.toInt() ?? 10,
              streak: data['attendanceCount'] ?? 0,
              topActions: topActions,
            );
          },
        );
      },
    );
  }
}

class _HeroShell extends StatelessWidget {
  const _HeroShell({
    required this.nickname,
    required this.level,
    required this.xpInLevel,
    required this.xpForNext,
    required this.streak,
    required this.topActions,
  });

  final String nickname;
  final int level;
  final int xpInLevel;
  final int xpForNext;
  final int streak;
  final List<Widget> topActions;

  @override
  Widget build(BuildContext context) {
    final pct = xpForNext <= 0 ? 0.0 : (xpInLevel / xpForNext).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '주식저장소',
                  style: _homeText(
                    color: _homeLabel,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Transform.translate(
                offset: const Offset(8, -10),
                child: Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: topActions,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_homeCardHi, _homeCard],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _homeBorder),
          ),
          child: Row(
            children: [
              RepaintBoundary(
                child: _Breathing(
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_homeAccent, const Color(0xFF00A86F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _homeAccent.withValues(alpha: 0.22),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 18)),
                          Text(
                            '$streak',
                            style: _homeNumber(
                              color: const Color(0xFF031A12),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'DAYS',
                            style: _homeText(
                              color: const Color(0xB3031A12),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerText(
                      text: streak > 0 ? '$streak일 연속 접속 중' : '오늘부터 투자 루틴 시작',
                      style: _homeText(
                        color: _homeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '댓글, 기록, 출석으로 레벨을 올려보세요',
                      style: _homeText(color: _homeFaint, fontSize: 13),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _homeGold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Lv.$level',
                            style: _homeText(
                              color: _homeGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$xpInLevel/$xpForNext XP',
                          style: _homeNumber(
                            color: _homeFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _AnimatedProgressBar(
                      value: pct,
                      color: _homeAccent,
                      backgroundColor: _homeBg3,
                      minHeight: 5,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyMissionCard extends StatelessWidget {
  const _DailyMissionCard({
    required this.auth,
    required this.firestoreService,
    required this.onWatchAd,
    required this.openCommunity,
    required this.openJournal,
  });

  final AuthProvider auth;
  final FirestoreService firestoreService;
  final VoidCallback onWatchAd;
  final VoidCallback openCommunity;
  final VoidCallback openJournal;

  @override
  Widget build(BuildContext context) {
    final uid = auth.user?.uid;
    return StreamBuilder<
      ({bool commentDone, bool memoDone, int adRemaining, int adLimit})
    >(
      stream: uid == null || uid.isEmpty
          ? Stream.value((
              commentDone: false,
              memoDone: false,
              adRemaining: 3,
              adLimit: 3,
            ))
          : firestoreService.watchDailyMissions(uid),
      builder: (context, snapshot) {
        final status =
            snapshot.data ??
            (commentDone: false, memoDone: false, adRemaining: 3, adLimit: 3);
        final missions =
            <
              ({
                IconData icon,
                String label,
                String xp,
                bool done,
                VoidCallback? onTap,
              })
            >[
              (
                icon: Icons.check_rounded,
                label: '출석 체크',
                xp: '+5 XP',
                done: true,
                onTap: null,
              ),
              (
                icon: Icons.ondemand_video_rounded,
                label: '광고 보기 (${status.adRemaining}/${status.adLimit})',
                xp: '+5 XP',
                done: status.adRemaining <= 0,
                onTap: status.adRemaining > 0 ? onWatchAd : null,
              ),
              (
                icon: Icons.mode_comment_outlined,
                label: '댓글 1개 남기기',
                xp: '+3 XP',
                done: status.commentDone,
                onTap: status.commentDone ? null : openCommunity,
              ),
              (
                icon: Icons.edit_note_rounded,
                label: '매매일지 작성',
                xp: '+10 XP',
                done: status.memoDone,
                onTap: status.memoDone ? null : openJournal,
              ),
            ];
        final doneCount = missions.where((m) => m.done).length;
        final allDone = doneCount == missions.length;

        return _DarkHomeSection(
          title: '✅ 오늘의 미션',
          trailing: Text(
            allDone ? '완료🎉' : '$doneCount/${missions.length}',
            style: _homeNumber(
              color: _homeAccent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < missions.length; i++) ...[
                _MissionRow(
                  icon: missions[i].icon,
                  label: missions[i].label,
                  xp: missions[i].xp,
                  done: missions[i].done,
                  onTap: missions[i].onTap,
                ),
                if (i < missions.length - 1)
                  Divider(height: 1, color: _homeBorder),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.icon,
    required this.label,
    required this.xp,
    required this.done,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String xp;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Opacity(
      opacity: done ? 0.58 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: done ? _homeAccent.withValues(alpha: 0.14) : _homeBg2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: done
                      ? _homeAccent.withValues(alpha: 0.34)
                      : _homeBorder,
                ),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.82, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.elasticOut,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Icon(
                  done ? Icons.check_rounded : icon,
                  size: 16,
                  color: _homeAccent,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: _homeText(
                  color: _homeLabel,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              xp,
              style: _homeNumber(
                color: done ? _homeFaint : _homeAccent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }
}

class _LiveStatusChip extends StatelessWidget {
  const _LiveStatusChip();

  @override
  Widget build(BuildContext context) {
    return _MarketClock(
      builder: (context, status) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: _PulseDot(
                color: status.isOpen ? _homeUp : _homeFaint,
                active: status.isOpen,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              status.isOpen ? '${status.sessionName} 장중' : '장 대기',
              style: _homeText(
                color: status.isOpen ? _homeUp : _homeFaint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MarketClock extends StatefulWidget {
  const _MarketClock({required this.builder});

  final Widget Function(BuildContext context, _MarketSessionStatus status)
  builder;

  @override
  State<_MarketClock> createState() => _MarketClockState();
}

class _MarketClockState extends State<_MarketClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = _nowInKst();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = _nowInKst());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _MarketSessionStatus.from(_now));
  }

  DateTime _nowInKst() {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime.utc(
      kst.year,
      kst.month,
      kst.day,
      kst.hour,
      kst.minute,
      kst.second,
      kst.millisecond,
      kst.microsecond,
    );
  }
}

class _MarketSessionStatus {
  const _MarketSessionStatus({
    required this.isOpen,
    required this.sessionName,
    required this.target,
    required this.remaining,
  });

  final bool isOpen;
  final String sessionName;
  final DateTime target;
  final Duration remaining;

  String get label => isOpen ? '$sessionName 마감까지' : '$sessionName 시작까지';

  String get remainingText {
    final totalMinutes = remaining.inMinutes <= 0 ? 0 : remaining.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes분';
    return '$hours시간 ${minutes.toString().padLeft(2, '0')}분';
  }

  static _MarketSessionStatus from(DateTime now) {
    final sessions = _buildSessions(now);
    for (final session in sessions) {
      if (!now.isBefore(session.start) && now.isBefore(session.end)) {
        return _MarketSessionStatus(
          isOpen: true,
          sessionName: session.name,
          target: session.end,
          remaining: session.end.difference(now),
        );
      }
    }

    final next = sessions.firstWhere((session) => session.start.isAfter(now));
    return _MarketSessionStatus(
      isOpen: false,
      sessionName: next.name,
      target: next.start,
      remaining: next.start.difference(now),
    );
  }

  static List<({String name, DateTime start, DateTime end})> _buildSessions(
    DateTime now,
  ) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final sessions = <({String name, DateTime start, DateTime end})>[];
    for (var offset = -1; offset <= 8; offset++) {
      final day = today.add(Duration(days: offset));
      if (day.weekday >= DateTime.monday && day.weekday <= DateTime.friday) {
        sessions.add((
          name: '국장',
          start: DateTime.utc(day.year, day.month, day.day, 9),
          end: DateTime.utc(day.year, day.month, day.day, 15, 30),
        ));
        final usOpen = _usRegularOpenKst(day);
        sessions.add((
          name: '미장',
          start: usOpen,
          end: usOpen.add(const Duration(hours: 6, minutes: 30)),
        ));
      }
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    return sessions;
  }

  static DateTime _usRegularOpenKst(DateTime kstDate) {
    final hour = _isUsDaylightSavingTime(kstDate) ? 22 : 23;
    return DateTime.utc(kstDate.year, kstDate.month, kstDate.day, hour, 30);
  }

  static bool _isUsDaylightSavingTime(DateTime marketDate) {
    final dstStart = _nthSunday(marketDate.year, DateTime.march, 2);
    final dstEnd = _nthSunday(marketDate.year, DateTime.november, 1);
    final date = DateTime.utc(
      marketDate.year,
      marketDate.month,
      marketDate.day,
    );
    return !date.isBefore(dstStart) && date.isBefore(dstEnd);
  }

  static DateTime _nthSunday(int year, int month, int nth) {
    final first = DateTime.utc(year, month);
    final daysUntilSunday = DateTime.sunday - first.weekday;
    return first.add(Duration(days: daysUntilSunday + 7 * (nth - 1)));
  }
}

class _MarketLiveCard extends StatelessWidget {
  const _MarketLiveCard({required this.indicesFuture, required this.onMore});

  final Future<Map<String, PriceResult?>> indicesFuture;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return _MarketClock(
      builder: (context, status) {
        return Column(
          children: [
            Row(
              children: [
                Text(
                  status.label,
                  style: _homeText(
                    color: _homeMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  status.remainingText,
                  style: _homeNumber(
                    color: _homeLabel,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: _homeBorder),
            ),
            _MajorIndicesPreview(
              indicesFuture: indicesFuture,
              maxItems: 3,
              entries: const [
                ('KOSPI', '^KS11'),
                ('KOSDAQ', '^KQ11'),
                ('나스닥100 선물', 'NQ=F'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: _homeBorder),
            ),
            InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '지수 전체 보기',
                      style: _homeText(
                        color: _homeMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _homeFaint,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AIBriefCard extends StatelessWidget {
  const _AIBriefCard();

  static const double _contentHeight = 188;

  String _formatSlotTime(String? slotLabel, dynamic generatedAt) {
    if (slotLabel != null) return '🤖 AI 간단 시황 · 오늘 $slotLabel';
    if (generatedAt == null) return '🤖 AI 간단 시황';
    try {
      final dt = (generatedAt as Timestamp).toDate().toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '🤖 AI 간단 시황 · 오늘 $h:$m';
    } catch (_) {
      return '🤖 AI 간단 시황';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? _homeCard : const Color(0xFFEFFAF5);
    final borderColor = isDark ? _homeBorder : const Color(0x3310B981);
    final titleColor = isDark ? _homeAccent : const Color(0xFF047857);
    final bodyColor = isDark ? _homeLabel : const Color(0xFF172033);
    final skeletonColor = isDark ? _homeBorder : const Color(0xFFE1E8F0);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ai_briefs')
          .doc('latest')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>?
            : null;

        final brief = data?['brief'] as String?;
        final slotLabel = data?['slotLabel'] as String?;
        final generatedAt = data?['generatedAt'];

        // 데이터 없을 때 skeleton shimmer 느낌으로 로딩 표시
        if (!snapshot.hasData || data == null || brief == null) {
          return _DarkCard(
            color: cardColor,
            borderColor: borderColor,
            child: SizedBox(
              height: _contentHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: titleColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '🤖 AI 간단 시황',
                        style: _homeText(
                          color: titleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: skeletonColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 14,
                    width: 240,
                    decoration: BoxDecoration(
                      color: skeletonColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 14,
                    width: 180,
                    decoration: BoxDecoration(
                      color: skeletonColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          );
        }

        return _DarkCard(
          color: cardColor,
          borderColor: borderColor,
          child: SizedBox(
            height: _contentHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: titleColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _formatSlotTime(slotLabel, generatedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _homeText(
                          color: titleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    brief,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      color: bodyColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _TextMoreButton(
                    label: '더보기',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const _AIBriefDetailScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TextMoreButton extends StatelessWidget {
  const _TextMoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: _homeText(
                color: _homeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16, color: _homeAccent),
          ],
        ),
      ),
    );
  }
}

class _AIBriefDetailScreen extends StatelessWidget {
  const _AIBriefDetailScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 간단 시황')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ai_briefs')
            .doc('latest')
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.hasData && snapshot.data!.exists
              ? snapshot.data!.data() as Map<String, dynamic>?
              : null;
          final brief = data?['brief'] as String?;
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                brief ?? '표시할 AI 시황이 없습니다.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopMoversPreview extends StatelessWidget {
  const _TopMoversPreview({
    required this.stream,
    required this.openFeatureStocks,
  });

  final Stream<List<MarketFeatureStock>> stream;
  final VoidCallback openFeatureStocks;

  List<MarketFeatureStock> _selectHomeFeatureStocks(
    List<MarketFeatureStock> latestItems,
    List<MarketFeatureStock> allItems,
  ) {
    final selected = <MarketFeatureStock>[];
    final selectedIds = <String>{};
    final selectedPatterns = <String>{};

    void addIfPossible(MarketFeatureStock item, {required bool uniquePattern}) {
      if (selected.length >= 4 || selectedIds.contains(item.id)) return;
      final pattern = item.pattern.isEmpty ? item.group : item.pattern;
      if (uniquePattern && selectedPatterns.contains(pattern)) return;
      selected.add(item);
      selectedIds.add(item.id);
      selectedPatterns.add(pattern);
    }

    final sortedAll = allItems.toList()
      ..sort((a, b) {
        final dateCompare = b.sourceDate.compareTo(a.sourceDate);
        if (dateCompare != 0) return dateCompare;
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return b.tradingValue.compareTo(a.tradingValue);
      });

    for (final item in latestItems) {
      addIfPossible(item, uniquePattern: true);
    }
    for (final item in sortedAll) {
      addIfPossible(item, uniquePattern: true);
    }
    for (final item in latestItems) {
      addIfPossible(item, uniquePattern: false);
    }
    for (final item in sortedAll) {
      addIfPossible(item, uniquePattern: false);
    }

    return selected;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MarketFeatureStock>>(
      stream: stream,
      builder: (context, snapshot) {
        final title = _sectionTitle(snapshot.data ?? const []);
        return _DarkHomeSection(
          title: title,
          actionText: '더보기',
          onAction: openFeatureStocks,
          child: _buildContent(context, snapshot),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<List<MarketFeatureStock>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const _PreviewLoading(height: 120);
    }
    if (snapshot.hasError) {
      return SizedBox(
        height: 120,
        child: _EmptyPreview(text: '특징주 오류: ${snapshot.error}'),
      );
    }
    final items = (snapshot.data ?? <MarketFeatureStock>[]).toList();
    final latestDate = items.isEmpty
        ? null
        : items
              .map(
                (item) => DateTime(
                  item.sourceDate.year,
                  item.sourceDate.month,
                  item.sourceDate.day,
                ),
              )
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final latestItems =
        latestDate == null
              ? items
              : items.where((item) {
                  final date = DateTime(
                    item.sourceDate.year,
                    item.sourceDate.month,
                    item.sourceDate.day,
                  );
                  return date == latestDate;
                }).toList()
          ..sort((a, b) {
            final scoreCompare = b.score.compareTo(a.score);
            if (scoreCompare != 0) return scoreCompare;
            return b.tradingValue.compareTo(a.tradingValue);
          });
    final topVisible = _selectHomeFeatureStocks(latestItems, items);
    if (topVisible.isEmpty) {
      return const _EmptyPreview(text: '표시할 특징주가 없습니다.');
    }
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: topVisible.length,
        separatorBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(width: 1, color: _homeBorder),
        ),
        itemBuilder: (context, index) => _SoftReveal(
          order: index,
          child: _FeatureStockTile(
            item: topVisible[index],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MarketFeatureStockDetailScreen(item: topVisible[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sectionTitle(List<MarketFeatureStock> items) {
    if (items.isEmpty) return '✨ 오늘의 특징주';
    final latest = items
        .map((item) => item.sourceDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final date = DateFormat('MM.dd').format(latest);
    return '✨ 오늘의 특징주 (기준 : $date)';
  }
}

class _FeatureStockTile extends StatelessWidget {
  const _FeatureStockTile({required this.item, required this.onTap});

  final MarketFeatureStock item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUp = item.changeRate >= 0;
    final moveColor = isUp ? _homeUp : _homeDown;
    final title = item.title.isNotEmpty ? item.title : _featureTitle(item);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _homeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.market,
                      style: _homeNumber(
                        color: _homeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${isUp ? '+' : ''}${item.changeRate.toStringAsFixed(1)}%',
                    style: _homeNumber(
                      color: moveColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _homeText(
                  color: _homeLabel,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.ticker,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _homeNumber(
                  color: _homeFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              _MiniSparkline(
                ticker: item.ticker,
                market: item.market,
                color: moveColor,
                width: 92,
                height: 20,
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _homeText(
                  color: _homeMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _featureTitle(MarketFeatureStock item) {
    switch (item.pattern) {
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
}

TextStyle _homeText({
  required Color color,
  required double fontSize,
  FontWeight fontWeight = FontWeight.w400,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Pretendard',
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
  );
}

TextStyle _homeNumber({
  required Color color,
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'RobotoMono',
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
  );
}

class _MajorIndicesPreview extends StatelessWidget {
  const _MajorIndicesPreview({
    required this.indicesFuture,
    this.maxItems,
    this.entries,
  });

  final Future<Map<String, PriceResult?>> indicesFuture;
  final int? maxItems;
  final List<(String, String)>? entries;

  static const indices = [
    ('KOSPI', '^KS11'),
    ('KOSDAQ', '^KQ11'),
    ('S&P 500', '^GSPC'),
    ('NASDAQ', '^IXIC'),
    ('USD/KRW', 'KRW=X'),
    ('나스닥100 선물', 'NQ=F'),
    ('WTI 오일', 'CL=F'),
  ];

  static const _descriptions = {
    'KOSPI': '한국 대형주 종합지수',
    'KOSDAQ': '한국 성장주 중심 시장',
    'S&P 500': '미국 대표 500대 기업',
    'NASDAQ': '미국 기술주 중심 지수',
    'USD/KRW': '원달러 환율',
    '나스닥100 선물': '미국 장전 분위기',
    'WTI 오일': '국제유가 선행 흐름',
  };

  static const _accentColors = {
    'KOSPI': Color(0xFF3182F6),
    'KOSDAQ': Color(0xFF00C4B4),
    'S&P 500': Color(0xFF6366F1),
    'NASDAQ': Color(0xFF8B5CF6),
    'USD/KRW': Color(0xFFF59E0B),
    '나스닥100 선물': Color(0xFFF97316),
    'WTI 오일': Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, PriceResult?>>(
      future: indicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PreviewLoading(height: 360);
        }
        final data = snapshot.data ?? {};
        final source = entries ?? _MajorIndicesPreview.indices;
        final visibleIndices = maxItems == null
            ? source
            : source.take(maxItems!).toList();
        return Column(
          children: [
            for (var i = 0; i < visibleIndices.length; i++) ...[
              _IndexPreviewRow(
                name: visibleIndices[i].$1,
                symbol: visibleIndices[i].$2,
                description: _descriptions[visibleIndices[i].$1] ?? '',
                accent:
                    _accentColors[visibleIndices[i].$1] ??
                    const Color(0xFF3182F6),
                result: data[visibleIndices[i].$1],
              ),
              if (i < visibleIndices.length - 1) const _ListDivider(indent: 40),
            ],
          ],
        );
      },
    );
  }
}

class _IndexPreviewRow extends StatelessWidget {
  const _IndexPreviewRow({
    required this.name,
    required this.symbol,
    required this.description,
    required this.accent,
    required this.result,
  });

  final String name;
  final String symbol;
  final String description;
  final Color accent;
  final PriceResult? result;

  @override
  Widget build(BuildContext context) {
    final isUp = result?.isUp ?? true;
    final moveColor = isUp ? _homeUp : _homeDown;
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IndexDetailScreen(
              name: name,
              symbol: symbol,
              initialPrice: result,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _IndexBadgeGlyph(name: name, accent: accent, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      color: _homeLabel,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(color: _homeFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _IndexSparkline(symbol: symbol, color: moveColor),
            const SizedBox(width: 18),
            if (result == null)
              Text(
                '--',
                style: _homeNumber(
                  color: _homeFaint,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _displayIndexValue(name, result!),
                    style: _homeNumber(
                      color: _homeLabel,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isUp ? '+' : ''}${result!.changeRate.toStringAsFixed(2)}%',
                    style: _homeNumber(
                      color: moveColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IndexListPage extends StatefulWidget {
  const _IndexListPage();

  @override
  State<_IndexListPage> createState() => _IndexListPageState();
}

class _IndexListPageState extends State<_IndexListPage> {
  late Future<Map<String, PriceResult?>> _indicesFuture;

  @override
  void initState() {
    super.initState();
    _indicesFuture = _loadIndices();
  }

  Future<Map<String, PriceResult?>> _loadIndices() async {
    final results = await Future.wait(
      _MajorIndicesPreview.indices.map(
        (entry) => StockPriceService.fetchPrice(entry.$2, 'US'),
      ),
    );
    return {
      for (var i = 0; i < _MajorIndicesPreview.indices.length; i++)
        _MajorIndicesPreview.indices[i].$1: results[i],
    };
  }

  Future<void> _refresh() async {
    for (final entry in _MajorIndicesPreview.indices) {
      StockPriceService.invalidateCache(entry.$2);
    }
    setState(() => _indicesFuture = _loadIndices());
    await _indicesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _homeBg0,
      appBar: AppBar(title: const Text('지수 전체')),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _DarkCard(
              child: _MajorIndicesPreview(indicesFuture: _indicesFuture),
            ),
            const SizedBox(height: 14),
            BannerAdWidget(
              slotId: 'market_analysis_indices_only',
              adUnitId: AdService.marketAnalysisMidBannerAdUnitId,
              fallbackAdUnitId: AdService.bannerAdUnitId,
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexBadgeGlyph extends StatelessWidget {
  const _IndexBadgeGlyph({
    required this.name,
    required this.accent,
    required this.size,
  });

  final String name;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (name == 'USD/KRW') {
      return Center(
        child: Text('💱', style: TextStyle(fontSize: size, height: 1)),
      );
    }
    return Icon(_indexIconFor(name), color: accent, size: size);
  }

  IconData _indexIconFor(String name) {
    switch (name) {
      case 'KOSPI':
      case 'KOSDAQ':
        return Icons.show_chart_rounded;
      case 'S&P 500':
        return Icons.account_balance_rounded;
      case 'NASDAQ':
        return Icons.memory_rounded;
      case 'WTI 오일':
        return Icons.local_gas_station_rounded;
      default:
        return Icons.trending_up_rounded;
    }
  }
}

class _IndexSparkline extends StatefulWidget {
  const _IndexSparkline({required this.symbol, required this.color});

  final String symbol;
  final Color color;

  @override
  State<_IndexSparkline> createState() => _IndexSparklineState();
}

class _IndexSparklineState extends State<_IndexSparkline> {
  @override
  Widget build(BuildContext context) {
    return _MiniSparkline(
      ticker: widget.symbol,
      market: 'US',
      color: widget.color,
      width: 50,
      height: 18,
      range: '1d',
      interval: '5m',
    );
  }
}

class _MiniSparkline extends StatefulWidget {
  const _MiniSparkline({
    required this.ticker,
    required this.market,
    required this.color,
    required this.width,
    required this.height,
    this.range = '1mo',
    this.interval = '1d',
  });

  final String ticker;
  final String market;
  final Color color;
  final double width;
  final double height;
  final String range;
  final String interval;

  @override
  State<_MiniSparkline> createState() => _MiniSparklineState();
}

class _MiniSparklineState extends State<_MiniSparkline> {
  late Future<List<double>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  @override
  void didUpdateWidget(covariant _MiniSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticker != widget.ticker ||
        oldWidget.market != widget.market ||
        oldWidget.range != widget.range ||
        oldWidget.interval != widget.interval) {
      _historyFuture = _loadHistory();
    }
  }

  Future<List<double>> _loadHistory() {
    return StockPriceService.fetchHistory(
      widget.ticker,
      widget.market,
      range: widget.range,
      interval: widget.interval,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        final values = (snapshot.data ?? const <double>[])
            .where((value) => value.isFinite && value > 0)
            .toList();
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: values.length < 2
              ? TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, child) {
                    return CustomPaint(
                      painter: _SparklinePainter(
                        values: const [1, 1],
                        color: widget.color.withValues(alpha: 0.35),
                        progress: progress,
                      ),
                    );
                  },
                )
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 720),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, child) {
                    return CustomPaint(
                      painter: _SparklinePainter(
                        values: values,
                        color: widget.color,
                        progress: progress,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.color,
    this.progress = 1,
  });

  final List<double> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minValue = values.first;
    var maxValue = values.first;
    for (final value in values) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    final span = (maxValue - minValue).abs() < 0.001
        ? 1.0
        : maxValue - minValue;
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height - ((values[i] - minValue) / span * size.height),
        ),
    ];
    final shownPoints = _visiblePoints(points);
    if (shownPoints.length < 2) return;
    final linePath = Path()..moveTo(shownPoints.first.dx, shownPoints.first.dy);
    for (final point in shownPoints.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(shownPoints.last.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  List<Offset> _visiblePoints(List<Offset> points) {
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped >= 1) return points;
    final end = (points.length - 1) * clamped;
    final whole = end.floor();
    final fraction = end - whole;
    final shown = <Offset>[points.first];
    for (var i = 1; i <= whole && i < points.length; i++) {
      shown.add(points[i]);
    }
    if (whole + 1 < points.length) {
      final from = points[whole];
      final to = points[whole + 1];
      shown.add(Offset.lerp(from, to, fraction) ?? from);
    }
    return shown;
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}

String _displayIndexValue(String name, PriceResult result) {
  if (name == 'USD/KRW') {
    return '₩${NumberFormat('#,###').format(result.price.toInt())}';
  }
  if (result.isKrw) {
    return NumberFormat('#,###').format(result.price.toInt());
  }
  return NumberFormat('#,##0.00').format(result.price);
}

class _ListDivider extends StatelessWidget {
  const _ListDivider({this.indent = 16});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: indent, color: _homeBorder);
  }
}

class _RecentPostsPreview extends StatefulWidget {
  const _RecentPostsPreview({
    required this.postsFuture,
    required this.auth,
    required this.firestoreService,
  });

  final Future<(List<Post>, DocumentSnapshot?)> postsFuture;
  final AuthProvider auth;
  final FirestoreService firestoreService;

  @override
  State<_RecentPostsPreview> createState() => _RecentPostsPreviewState();
}

class _RecentPostsPreviewState extends State<_RecentPostsPreview> {
  late final Future<List<Post>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Post>> _load() async {
    final (posts, _) = await widget.postsFuture;
    final sorted = posts.toList()..sort((a, b) => b.likes.compareTo(a.likes));
    return sorted.where((p) => p.likes > 0).take(4).toList();
  }

  Future<void> _openPost(Post post) async {
    final uid = widget.auth.user?.uid;
    var isLiked = false;
    if (uid != null && uid.isNotEmpty) {
      isLiked = await widget.firestoreService.hasLikedPost(post.id, uid);
      if (!mounted) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          isOwn: uid != null && uid == post.uid,
          isLiked: isLiked,
          likeCount: post.likes,
        ),
      ),
    );
  }

  static const _tileH = 92.0;
  static const _maxCount = 4;
  static const _sectionH = _tileH * _maxCount + (_maxCount - 1);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _sectionH,
      child: FutureBuilder<List<Post>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF10B981),
                strokeWidth: 2,
              ),
            );
          }
          final posts = snap.data ?? [];
          if (posts.isEmpty) {
            return Center(
              child: Text(
                '아직 인기 토론이 없습니다.',
                style: _homeText(color: _homeFaint, fontSize: 13),
              ),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < posts.length; i++) ...[
                SizedBox(
                  height: _tileH,
                  child: _HotPostTile(
                    post: posts[i],
                    onTap: () => _openPost(posts[i]),
                  ),
                ),
                if (i < posts.length - 1) const _ListDivider(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HotPostTile extends StatefulWidget {
  const _HotPostTile({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  State<_HotPostTile> createState() => _HotPostTileState();
}

class _HotPostTileState extends State<_HotPostTile> {
  Offset? _tapDown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _tapDown = e.position,
      onPointerUp: (e) {
        final d = _tapDown;
        _tapDown = null;
        if (d != null && (e.position - d).distance < 20) widget.onTap();
      },
      onPointerCancel: (_) => _tapDown = null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                UserLevelAvatar(
                  uid: widget.post.uid,
                  radius: 10,
                  backgroundColor: _homeBg3,
                  textStyle: _homeNumber(
                    color: _homeFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.post.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      color: _homeFaint,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _relativeTime(widget.post.createdAt),
                  style: _homeText(color: _homeFaint, fontSize: 11),
                ),
              ],
            ),
            Text(
              widget.post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _homeText(
                color: _homeLabel,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            Row(
              children: [
                Icon(Icons.favorite_rounded, size: 11, color: _homeFaint),
                const SizedBox(width: 3),
                Text(
                  '${widget.post.likes}',
                  style: _homeNumber(
                    color: _homeMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: _homeFaint, size: 15),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritePicksPreview extends StatefulWidget {
  const _FavoritePicksPreview({
    required this.firestoreService,
    required this.picksStream,
    required this.auth,
    required this.openStockPicks,
  });

  final FirestoreService firestoreService;
  final Stream<List<StockPick>> picksStream;
  final AuthProvider auth;
  final VoidCallback openStockPicks;

  @override
  State<_FavoritePicksPreview> createState() => _FavoritePicksPreviewState();
}

class _FavoritePicksPreviewState extends State<_FavoritePicksPreview> {
  late Stream<List<String>> _favoriteIdsStream;
  String? _trackedUid;

  @override
  void initState() {
    super.initState();
    _trackedUid = widget.auth.user?.uid;
    _favoriteIdsStream = _trackedUid == null || _trackedUid!.isEmpty
        ? Stream.value([])
        : widget.firestoreService.getFavoriteIds(_trackedUid!);
  }

  @override
  void didUpdateWidget(_FavoritePicksPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUid = widget.auth.user?.uid;
    if (_trackedUid == nextUid) return;
    _trackedUid = nextUid;
    _favoriteIdsStream = nextUid == null || nextUid.isEmpty
        ? Stream.value([])
        : widget.firestoreService.getFavoriteIds(nextUid);
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.auth.user?.uid;
    if (uid == null || uid.isEmpty) {
      return const SizedBox(
        height: _FavoritePerformanceList.height,
        child: _EmptyPreview(text: '로그인하면 관심 추천주를 모아볼 수 있습니다.'),
      );
    }

    return StreamBuilder<List<String>>(
      stream: _favoriteIdsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PreviewLoading(height: _FavoritePerformanceList.height);
        }
        final favoriteIds = (snapshot.data ?? []).toSet();
        if (favoriteIds.isEmpty) {
          return const SizedBox(
            height: _FavoritePerformanceList.height,
            child: _EmptyPreview(text: '아직 관심 추천주가 없습니다.'),
          );
        }

        return StreamBuilder<List<StockPick>>(
          stream: widget.picksStream,
          builder: (context, picksSnapshot) {
            if (picksSnapshot.connectionState == ConnectionState.waiting) {
              return const _PreviewLoading(
                height: _FavoritePerformanceList.height,
              );
            }
            final picks = (picksSnapshot.data ?? [])
                .where((pick) => favoriteIds.contains(pick.id))
                .toList();
            if (picks.isEmpty) {
              return const SizedBox(
                height: _FavoritePerformanceList.height,
                child: _EmptyPreview(text: '관심 추천주가 종료되었거나 표시할 항목이 없습니다.'),
              );
            }
            return _FavoritePerformanceList(
              picks: picks.take(4).toList(),
              onMore: widget.openStockPicks,
            );
          },
        );
      },
    );
  }
}

class _FavoriteStocksPreview extends StatefulWidget {
  const _FavoriteStocksPreview({
    required this.firestoreService,
    required this.auth,
    required this.onMore,
  });

  final FirestoreService firestoreService;
  final AuthProvider auth;
  final VoidCallback onMore;

  @override
  State<_FavoriteStocksPreview> createState() => _FavoriteStocksPreviewState();
}

class _FavoriteStocksPreviewState extends State<_FavoriteStocksPreview> {
  late Stream<List<StockPick>> _stocksStream;
  String? _trackedUid;

  @override
  void initState() {
    super.initState();
    _trackedUid = widget.auth.user?.uid;
    _stocksStream = _trackedUid == null || _trackedUid!.isEmpty
        ? Stream.value(const [])
        : widget.firestoreService.getFavoriteStocks(_trackedUid!);
  }

  @override
  void didUpdateWidget(covariant _FavoriteStocksPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUid = widget.auth.user?.uid;
    if (_trackedUid == nextUid) return;
    _trackedUid = nextUid;
    _stocksStream = nextUid == null || nextUid.isEmpty
        ? Stream.value(const [])
        : widget.firestoreService.getFavoriteStocks(nextUid);
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.auth.user?.uid;
    if (uid == null || uid.isEmpty) {
      return const SizedBox(
        height: _FavoriteStocksList.height,
        child: _EmptyPreview(text: '로그인하면 관심종목을 모아볼 수 있습니다.'),
      );
    }

    return StreamBuilder<List<StockPick>>(
      stream: _stocksStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PreviewLoading(height: _FavoriteStocksList.height);
        }
        final stocks = snapshot.data ?? const <StockPick>[];
        if (stocks.isEmpty) {
          return const SizedBox(
            height: _FavoriteStocksList.height,
            child: _EmptyPreview(text: '아직 관심종목이 없습니다.'),
          );
        }
        return _FavoriteStocksList(
          stocks: stocks.take(4).toList(),
          onMore: widget.onMore,
        );
      },
    );
  }
}

List<StockPick> _sortStocksByTodayChange(
  List<StockPick> stocks,
  Map<String, PriceResult?> prices,
) {
  final indexed = [
    for (var i = 0; i < stocks.length; i++) (index: i, stock: stocks[i]),
  ];
  indexed.sort((a, b) {
    final aRate = prices[a.stock.id]?.changeRate;
    final bRate = prices[b.stock.id]?.changeRate;
    if (aRate == null && bRate == null) return a.index.compareTo(b.index);
    if (aRate == null) return 1;
    if (bRate == null) return -1;
    final byRate = bRate.compareTo(aRate);
    if (byRate != 0) return byRate;
    return a.index.compareTo(b.index);
  });
  return indexed.map((entry) => entry.stock).toList();
}

Color _marketColor(String market) {
  return switch (market.toUpperCase()) {
    'KS' || 'KOSPI' => const Color(0xFF3182F6),
    'KQ' || 'KOSDAQ' => const Color(0xFF00C4B4),
    'US' || 'NASDAQ' || 'NYSE' || 'AMEX' => const Color(0xFF8B5CF6),
    _ => _homeFaint,
  };
}

String _marketLabel(String market) {
  return switch (market.toUpperCase()) {
    'KS' => 'KOSPI',
    'KQ' => 'KOSDAQ',
    'US' => 'US',
    _ => market,
  };
}

class _MarketMetaText extends StatelessWidget {
  const _MarketMetaText({
    required this.ticker,
    required this.market,
    required this.fontSize,
    this.mutedColor,
  });

  final String ticker;
  final String market;
  final double fontSize;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final baseColor = mutedColor ?? _homeFaint;
    final label = _marketLabel(market);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: ticker),
          const TextSpan(text: ' · '),
          TextSpan(
            text: label,
            style: _homeNumber(
              color: _marketColor(label),
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _homeNumber(
        color: baseColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PriceChangeStack extends StatelessWidget {
  const _PriceChangeStack({
    required this.priceText,
    required this.changeText,
    required this.changeColor,
    required this.priceColor,
    required this.priceFontSize,
    required this.changeFontSize,
    this.changeFontWeight = FontWeight.w700,
  });

  final String priceText;
  final String changeText;
  final Color changeColor;
  final Color priceColor;
  final double priceFontSize;
  final double changeFontSize;
  final FontWeight changeFontWeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          priceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _homeNumber(
            color: priceColor,
            fontSize: priceFontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          changeText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _homeNumber(
            color: changeColor,
            fontSize: changeFontSize,
            fontWeight: changeFontWeight,
          ),
        ),
      ],
    );
  }
}

class _FavoriteStocksList extends StatefulWidget {
  const _FavoriteStocksList({required this.stocks, required this.onMore});

  static const double height = 349;
  static const double _rowHeight = 76;
  static const double _moreHeight = 42;

  final List<StockPick> stocks;
  final VoidCallback onMore;

  @override
  State<_FavoriteStocksList> createState() => _FavoriteStocksListState();
}

class _FavoriteStocksListState extends State<_FavoriteStocksList> {
  late Future<Map<String, PriceResult?>> _pricesFuture;

  @override
  void initState() {
    super.initState();
    _pricesFuture = _loadPrices();
  }

  @override
  void didUpdateWidget(covariant _FavoriteStocksList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.stocks.map((stock) => stock.id).join(',');
    final nextKey = widget.stocks.map((stock) => stock.id).join(',');
    if (oldKey != nextKey) {
      _pricesFuture = _loadPrices();
    }
  }

  Future<Map<String, PriceResult?>> _loadPrices() async {
    final results = await Future.wait(
      widget.stocks.map(
        (stock) => StockPriceService.fetchPrice(stock.ticker, stock.market),
      ),
    );
    return {
      for (var i = 0; i < widget.stocks.length; i++)
        widget.stocks[i].id: results[i],
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, PriceResult?>>(
      future: _pricesFuture,
      builder: (context, snapshot) {
        final prices = snapshot.data ?? const <String, PriceResult?>{};
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final sortedStocks = _sortStocksByTodayChange(widget.stocks, prices);
        return SizedBox(
          height: _FavoriteStocksList.height,
          child: Column(
            children: [
              for (var i = 0; i < 4; i++) ...[
                SizedBox(
                  height: _FavoriteStocksList._rowHeight,
                  child: i < sortedStocks.length
                      ? _SoftReveal(
                          order: i,
                          child: _FavoriteStockCompactRow(
                            stock: sortedStocks[i],
                            priceResult: prices[sortedStocks[i].id],
                            loadingPrice: loading,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (i != 3) const _ListDivider(indent: 0),
              ],
              SizedBox(
                height: _FavoriteStocksList._moreHeight,
                child: _FavoriteMoreRow(onTap: widget.onMore),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FavoriteStockCompactRow extends StatelessWidget {
  const _FavoriteStockCompactRow({
    required this.stock,
    required this.priceResult,
    required this.loadingPrice,
  });

  final StockPick stock;
  final PriceResult? priceResult;
  final bool loadingPrice;

  @override
  Widget build(BuildContext context) {
    final rate = priceResult?.changeRate ?? 0;
    final rateColor = rate >= 0 ? _homeUp : _homeDown;
    final priceText = loadingPrice && priceResult == null
        ? '조회중'
        : priceResult == null
        ? '-'
        : _formatHomePickPrice(priceResult!.price, stock.market);
    final changeText = priceResult == null
        ? '-'
        : '${_formatTodayChange(priceResult!, stock.market)} (${rate.abs().toStringAsFixed(2)}%)';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          stockDetailRoute(stock, enablePickFeatures: false),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      color: _homeLabel,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _MarketMetaText(
                    ticker: stock.ticker,
                    market: stock.market,
                    fontSize: 13,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _MiniSparkline(
              ticker: stock.ticker,
              market: stock.market,
              color: rateColor,
              width: 48,
              height: 22,
            ),
            const SizedBox(width: 12),
            _PriceChangeStack(
              priceText: priceText,
              changeText: changeText,
              changeColor: rateColor,
              priceColor: _homeLabel,
              priceFontSize: 14,
              changeFontSize: 11,
              changeFontWeight: FontWeight.w800,
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteStocksScreen extends StatelessWidget {
  const _FavoriteStocksScreen({
    required this.firestoreService,
    required this.uid,
  });

  final FirestoreService firestoreService;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⭐ 관심종목')),
      body: _FavoriteStocksBody(firestoreService: firestoreService, uid: uid),
    );
  }
}

class _FavoriteStocksBody extends StatefulWidget {
  const _FavoriteStocksBody({
    required this.firestoreService,
    required this.uid,
  });

  final FirestoreService firestoreService;
  final String? uid;

  @override
  State<_FavoriteStocksBody> createState() => _FavoriteStocksBodyState();
}

class _FavoriteStocksBodyState extends State<_FavoriteStocksBody> {
  Future<Map<String, PriceResult?>>? _pricesFuture;
  String _stocksKey = '';

  Future<Map<String, PriceResult?>> _loadPrices(List<StockPick> stocks) async {
    final results = await Future.wait(
      stocks.map(
        (stock) => StockPriceService.fetchPrice(stock.ticker, stock.market),
      ),
    );
    return {for (var i = 0; i < stocks.length; i++) stocks[i].id: results[i]};
  }

  Future<void> _refreshPrices(List<StockPick> stocks) async {
    for (final stock in stocks) {
      StockPriceService.invalidateCache(stock.ticker);
    }
    setState(() {
      _pricesFuture = _loadPrices(stocks);
    });
    await _pricesFuture;
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.uid;
    if (userId == null || userId.isEmpty) {
      return _buildEmptyBody(context, text: '로그인하면 관심종목을 모아볼 수 있습니다.');
    }

    return StreamBuilder<List<StockPick>>(
      stream: widget.firestoreService.getFavoriteStocks(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildEmptyBody(
            context,
            text: '관심종목을 불러오는 중입니다.',
            loading: true,
          );
        }
        final stocks = snapshot.data ?? const <StockPick>[];
        if (stocks.isEmpty) {
          return _buildEmptyBody(context, text: '아직 관심종목이 없습니다.');
        }

        final nextKey = stocks.map((stock) => stock.id).join(',');
        if (_stocksKey != nextKey || _pricesFuture == null) {
          _stocksKey = nextKey;
          _pricesFuture = _loadPrices(stocks);
        }

        return FutureBuilder<Map<String, PriceResult?>>(
          future: _pricesFuture,
          builder: (context, priceSnapshot) {
            final prices = priceSnapshot.data ?? const <String, PriceResult?>{};
            final loading =
                priceSnapshot.connectionState == ConnectionState.waiting;
            final sortedStocks = _sortStocksByTodayChange(stocks, prices);
            final cs = Theme.of(context).colorScheme;
            return RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: () => _refreshPrices(stocks),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _FavoriteStocksSummary(
                      stocks: stocks,
                      prices: prices,
                      loading: loading,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    height: 10,
                    color: cs.onSurface.withValues(alpha: 0.045),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Row(
                      children: [
                        Text(
                          '상승률순',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.48),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${sortedStocks.length}종목',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.34),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(
                      height: 1,
                      color: cs.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  for (var i = 0; i < sortedStocks.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _FavoriteStockMarketRow(
                        stock: sortedStocks[i],
                        priceResult: prices[sortedStocks[i].id],
                        loadingPrice: loading,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(
                        height: 1,
                        color: cs.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyBody(
    BuildContext context, {
    required String text,
    bool loading = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _FavoriteStocksSummary(
            stocks: const <StockPick>[],
            prices: const <String, PriceResult?>{},
            loading: loading,
          ),
        ),
        const SizedBox(height: 26),
        Container(height: 10, color: cs.onSurface.withValues(alpha: 0.045)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: _EmptyPreview(text: text),
        ),
      ],
    );
  }
}

class _FavoriteStocksSummary extends StatelessWidget {
  const _FavoriteStocksSummary({
    required this.stocks,
    required this.prices,
    required this.loading,
  });

  final List<StockPick> stocks;
  final Map<String, PriceResult?> prices;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final validPrices = prices.values.whereType<PriceResult>().toList();
    final upCount = validPrices.where((price) => price.changeRate >= 0).length;
    final downCount = validPrices.where((price) => price.changeRate < 0).length;
    final avgRate = validPrices.isEmpty
        ? 0.0
        : validPrices.fold<double>(
                0,
                (total, price) => total + price.changeRate,
              ) /
              validPrices.length;
    final avgColor = avgRate == 0
        ? cs.onSurface.withValues(alpha: 0.58)
        : avgRate > 0
        ? _homeUp
        : _homeDown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '⭐ 관심종목',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          loading ? '현재가를 불러오는 중입니다' : '현재가 기준 오늘 등락을 보여줍니다',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.48),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _FavoriteSummaryCell(
                label: '등록',
                value: '${stocks.length}',
                color: cs.onSurface,
              ),
            ),
            Expanded(
              child: _FavoriteSummaryCell(
                label: '상승',
                value: '$upCount',
                color: _homeUp,
              ),
            ),
            Expanded(
              child: _FavoriteSummaryCell(
                label: '하락',
                value: '$downCount',
                color: _homeDown,
              ),
            ),
            Expanded(
              child: _FavoriteSummaryCell(
                label: '평균 등락률',
                value: loading && validPrices.isEmpty
                    ? '-'
                    : '${avgRate >= 0 ? '+' : ''}${avgRate.toStringAsFixed(2)}%',
                color: avgColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FavoriteSummaryCell extends StatelessWidget {
  const _FavoriteSummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _homeNumber(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FavoriteStockMarketRow extends StatelessWidget {
  const _FavoriteStockMarketRow({
    required this.stock,
    required this.priceResult,
    required this.loadingPrice,
  });

  final StockPick stock;
  final PriceResult? priceResult;
  final bool loadingPrice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = priceResult;
    final isUp = (price?.changeRate ?? 0) >= 0;
    final accent = price == null
        ? cs.onSurface.withValues(alpha: 0.42)
        : isUp
        ? _homeUp
        : _homeDown;
    final priceText = loadingPrice && price == null
        ? '조회중'
        : price?.formattedPrice ?? '-';
    final changeText = price == null
        ? '등락 정보 없음'
        : '${_formatTodayChange(price, stock.market)} (${price.changeRate.abs().toStringAsFixed(2)}%)';

    return InkWell(
      onTap: () => Navigator.push(
        context,
        stockDetailRoute(stock, enablePickFeatures: false),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _MarketMetaText(
                    ticker: stock.ticker,
                    market: stock.market,
                    fontSize: 13,
                    mutedColor: cs.onSurface.withValues(alpha: 0.42),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _MiniSparkline(
              ticker: stock.ticker,
              market: stock.market,
              color: accent,
              width: 48,
              height: 22,
            ),
            const SizedBox(width: 12),
            _PriceChangeStack(
              priceText: priceText,
              changeText: changeText,
              changeColor: accent,
              priceColor: cs.onSurface,
              priceFontSize: 14,
              changeFontSize: 11,
              changeFontWeight: FontWeight.w800,
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceMetric extends StatelessWidget {
  const _PerformanceMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: _homeText(
              color: _homeFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: _homeNumber(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritePerformanceList extends StatefulWidget {
  const _FavoritePerformanceList({required this.picks, required this.onMore});

  static const double height = 425;
  static const double _summaryHeight = 74;
  static const double _rowHeight = 76;
  static const double _moreHeight = 42;
  static const int _maxRows = 4;

  final List<StockPick> picks;
  final VoidCallback onMore;

  @override
  State<_FavoritePerformanceList> createState() =>
      _FavoritePerformanceListState();
}

class _FavoritePerformanceListState extends State<_FavoritePerformanceList> {
  late Future<Map<String, PriceResult?>> _pricesFuture;

  @override
  void initState() {
    super.initState();
    _pricesFuture = _loadPrices();
  }

  @override
  void didUpdateWidget(covariant _FavoritePerformanceList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.picks.map((pick) => pick.id).join(',');
    final newKey = widget.picks.map((pick) => pick.id).join(',');
    if (oldKey != newKey) {
      _pricesFuture = _loadPrices();
    }
  }

  Future<Map<String, PriceResult?>> _loadPrices() async {
    final results = await Future.wait(
      widget.picks.map(
        (pick) => StockPriceService.fetchPrice(pick.ticker, pick.market),
      ),
    );
    return {
      for (var i = 0; i < widget.picks.length; i++)
        widget.picks[i].id: results[i],
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, PriceResult?>>(
      future: _pricesFuture,
      builder: (context, snapshot) {
        final prices = snapshot.data ?? const <String, PriceResult?>{};
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final returns = widget.picks.map((pick) {
          final current = _currentPriceFor(pick, prices[pick.id]);
          if (pick.buyPrice <= 0) return 0.0;
          return ((current - pick.buyPrice) / pick.buyPrice) * 100;
        }).toList();
        final avgReturn =
            returns.fold<double>(0, (total, value) => total + value) /
            returns.length;
        final hitTarget = widget.picks.where((pick) {
          final current = _currentPriceFor(pick, prices[pick.id]);
          return current >= pick.targetPrice;
        }).length;
        final avgColor = avgReturn >= 0 ? _homeUp : _homeDown;
        final visiblePicks = widget.picks
            .take(_FavoritePerformanceList._maxRows)
            .toList();
        return SizedBox(
          height: _FavoritePerformanceList.height,
          child: Column(
            children: [
              SizedBox(
                height: _FavoritePerformanceList._summaryHeight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PerformanceMetric(
                          label: loading ? '평균 수익률 조회중' : '평균 수익률',
                          value:
                              '${avgReturn >= 0 ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
                          color: avgColor,
                        ),
                      ),
                      Container(width: 1, height: 42, color: _homeBorder),
                      Expanded(
                        child: _PerformanceMetric(
                          label: '목표 도달',
                          value: '$hitTarget/${widget.picks.length}',
                          color: _homeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: _homeBorder),
              for (var i = 0; i < _FavoritePerformanceList._maxRows; i++) ...[
                SizedBox(
                  height: _FavoritePerformanceList._rowHeight,
                  child: i < visiblePicks.length
                      ? _SoftReveal(
                          order: i,
                          child: _FavoriteCompactRow(
                            pick: visiblePicks[i],
                            priceResult: prices[visiblePicks[i].id],
                            loadingPrice: loading,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const _ListDivider(indent: 0),
              ],
              SizedBox(
                height: _FavoritePerformanceList._moreHeight,
                child: _FavoriteMoreRow(onTap: widget.onMore),
              ),
            ],
          ),
        );
      },
    );
  }

  double _currentPriceFor(StockPick pick, PriceResult? priceResult) {
    return priceResult?.price ?? pick.currentPrice ?? pick.buyPrice;
  }
}

class _FavoriteCompactRow extends StatelessWidget {
  const _FavoriteCompactRow({
    required this.pick,
    required this.priceResult,
    required this.loadingPrice,
  });

  final StockPick pick;
  final PriceResult? priceResult;
  final bool loadingPrice;

  @override
  Widget build(BuildContext context) {
    final current = priceResult?.price ?? pick.currentPrice ?? pick.buyPrice;
    final returnRate = pick.buyPrice > 0
        ? ((current - pick.buyPrice) / pick.buyPrice) * 100
        : 0.0;
    final returnColor = returnRate >= 0 ? _homeUp : _homeDown;
    final currentText = loadingPrice && priceResult == null
        ? '조회중'
        : _formatHomePickPrice(current, pick.market);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StockDetailScreen(pick: pick)),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pick.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _homeText(
                      color: _homeLabel,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _MarketMetaText(
                    ticker: pick.ticker,
                    market: pick.market,
                    fontSize: 13,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _MiniSparkline(
              ticker: pick.ticker,
              market: pick.market,
              color: returnColor,
              width: 48,
              height: 22,
            ),
            const SizedBox(width: 12),
            _PriceChangeStack(
              priceText: currentText,
              changeText:
                  '${returnRate >= 0 ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
              changeColor: returnColor,
              priceColor: _homeLabel,
              priceFontSize: 14,
              changeFontSize: 11,
              changeFontWeight: FontWeight.w800,
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteMoreRow extends StatelessWidget {
  const _FavoriteMoreRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '더보기',
            style: _homeText(
              color: _homeAccent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: _homeAccent),
        ],
      ),
    );
  }
}

class _FavoritePerformanceRow extends StatefulWidget {
  const _FavoritePerformanceRow({
    required this.pick,
    required this.priceResult,
    required this.loadingPrice,
  });

  final StockPick pick;
  final PriceResult? priceResult;
  final bool loadingPrice;

  @override
  State<_FavoritePerformanceRow> createState() =>
      _FavoritePerformanceRowState();
}

class _FavoritePerformanceRowState extends State<_FavoritePerformanceRow> {
  Offset? _tapDown;

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final priceResult = widget.priceResult;
    final loadingPrice = widget.loadingPrice;
    final current = priceResult?.price ?? pick.currentPrice ?? pick.buyPrice;
    final returnRate = pick.buyPrice > 0
        ? ((current - pick.buyPrice) / pick.buyPrice) * 100
        : 0.0;
    final progress = _targetProgress(current);
    final returnColor = returnRate >= 0 ? _homeUp : _homeDown;
    final todayRate = priceResult?.changeRate;
    final todayColor = (todayRate ?? 0) >= 0 ? _homeUp : _homeDown;
    final todayChangeText = priceResult == null
        ? '--'
        : '${todayRate! >= 0 ? '+' : ''}${todayRate.toStringAsFixed(2)}%';
    final currentText = loadingPrice && priceResult == null
        ? '조회중'
        : _formatHomePickPrice(current, pick.market);
    return Listener(
      onPointerDown: (e) => _tapDown = e.position,
      onPointerUp: (e) {
        final d = _tapDown;
        _tapDown = null;
        if (d != null && (e.position - d).distance < 20) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StockDetailScreen(pick: pick)),
          );
        }
      },
      onPointerCancel: (_) => _tapDown = null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pick.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _homeText(
                          color: _homeLabel,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${pick.ticker} · ${pick.market}',
                        style: _homeNumber(
                          color: _homeFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currentText,
                      style: _homeNumber(
                        color: _homeLabel,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '현재가',
                      style: _homeText(color: _homeFaint, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: _FavoriteMiniStat(
                    label: '내 수익률',
                    value:
                        '${returnRate >= 0 ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
                    color: returnColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FavoriteMiniStat(
                    label: priceResult == null ? '오늘 변동' : '오늘 변동',
                    value: todayChangeText,
                    subValue: priceResult == null
                        ? null
                        : _formatTodayChange(priceResult, pick.market),
                    color: priceResult == null ? _homeFaint : todayColor,
                    emphasized: priceResult != null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _AnimatedProgressBar(
              value: progress,
              color: returnColor,
              backgroundColor: _homeBg3,
              minHeight: 4,
              duration: const Duration(milliseconds: 680),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Text('추천가', style: _homeText(color: _homeFaint, fontSize: 11)),
                const Spacer(),
                Text(
                  '목표 ${(progress * 100).round()}%',
                  style: _homeNumber(
                    color: _homeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text('목표가', style: _homeText(color: _homeFaint, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _targetProgress(double currentPrice) {
    final total = widget.pick.targetPrice - widget.pick.buyPrice;
    if (total == 0) return 0;
    return ((currentPrice - widget.pick.buyPrice) / total).clamp(0.0, 1.0);
  }
}

class _FavoriteMiniStat extends StatelessWidget {
  const _FavoriteMiniStat({
    required this.label,
    required this.value,
    required this.color,
    this.subValue,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color color;
  final String? subValue;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: emphasized
            ? color.withValues(alpha: 0.11)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasized ? color.withValues(alpha: 0.24) : _homeBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: _homeText(
              color: _homeFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _homeNumber(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (subValue != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    subValue!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: _homeNumber(
                      color: color.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _formatHomePickPrice(double price, String market) {
  if (market == 'US') return '\$${price.toStringAsFixed(2)}';
  return '₩${NumberFormat('#,###').format(price.round())}';
}

String _formatTodayChange(PriceResult result, String market) {
  final sign = result.change >= 0 ? '+' : '';
  if (market == 'US') return '$sign${result.change.toStringAsFixed(2)}';
  return '$sign${NumberFormat('#,###').format(result.change.round())}';
}

class _QuickMenu extends StatelessWidget {
  const _QuickMenu({
    required this.openMarketAnalysis,
    required this.openFeatureStocks,
    required this.openFmkoreaHot,
    required this.openFmkoreaIndex,
    required this.openInvestorFlow,
    required this.openMarketSentiment,
    required this.openStockPicks,
    required this.openAnnouncements,
    required this.openStockCompare,
    required this.openStockSearch,
    required this.openAiAnalysisList,
  });

  final VoidCallback openMarketAnalysis;
  final VoidCallback openFeatureStocks;
  final VoidCallback openFmkoreaHot;
  final VoidCallback openFmkoreaIndex;
  final VoidCallback openInvestorFlow;
  final VoidCallback openMarketSentiment;
  final VoidCallback openStockPicks;
  final VoidCallback openAnnouncements;
  final VoidCallback openStockCompare;
  final VoidCallback openStockSearch;
  final VoidCallback openAiAnalysisList;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '🧭 둘러보기',
            style: _homeText(
              color: _homeLabel,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.18,
          children: [
            _QuickMenuTile(
              icon: Icons.show_chart_rounded,
              label: '운영자 추천주',
              onTap: openStockPicks,
              emphasized: true,
            ),
            _QuickMenuTile(
              icon: Icons.auto_awesome,
              label: 'AI 분석 기록',
              onTap: openAiAnalysisList,
              emphasized: true,
            ),
            _QuickMenuTile(
              icon: Icons.search_rounded,
              label: '종목 검색',
              onTap: openStockSearch,
            ),
            _QuickMenuTile(
              icon: Icons.analytics_outlined,
              label: '시황분석',
              onTap: openMarketAnalysis,
            ),
            _QuickMenuTile(
              icon: Icons.bolt_rounded,
              label: '오늘의 특징주',
              onTap: openFeatureStocks,
            ),
            _QuickMenuTile(
              icon: Icons.local_fire_department_rounded,
              label: '펨코 HOT 종목',
              onTap: openFmkoreaHot,
              animated: true,
            ),
            _QuickMenuTile(
              icon: Icons.forum_rounded,
              label: '펨코지수',
              onTap: openFmkoreaIndex,
            ),
            _QuickMenuTile(
              icon: Icons.candlestick_chart_rounded,
              label: '외인 · 기관 수급',
              onTap: openInvestorFlow,
            ),
            _QuickMenuTile(
              icon: Icons.psychology_alt_rounded,
              label: '시장심리지표',
              onTap: openMarketSentiment,
            ),
            _QuickMenuTile(
              icon: Icons.compare_arrows_rounded,
              label: '종목 비교',
              onTap: openStockCompare,
            ),
            _QuickMenuTile(
              icon: Icons.campaign_rounded,
              label: '공지사항',
              onTap: openAnnouncements,
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickMenuTile extends StatefulWidget {
  const _QuickMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.animated = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final bool animated;

  @override
  State<_QuickMenuTile> createState() => _QuickMenuTileState();
}

class _QuickMenuTileState extends State<_QuickMenuTile> {
  Offset? _tapDown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _tapDown = e.position,
      onPointerUp: (e) {
        final d = _tapDown;
        _tapDown = null;
        if (d != null && (e.position - d).distance < 20) widget.onTap();
      },
      onPointerCancel: (_) => _tapDown = null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: widget.emphasized
              ? _homeAccent.withValues(alpha: 0.12)
              : _homeBg3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.emphasized
                ? _homeAccent.withValues(alpha: 0.36)
                : _homeBorder,
          ),
        ),
        child: Row(
          children: [
            widget.emphasized || widget.animated
                ? RepaintBoundary(
                    child: _Breathing(
                      scale: widget.emphasized ? 1.1 : 1.16,
                      duration: Duration(
                        milliseconds: widget.emphasized ? 1050 : 850,
                      ),
                      child: Icon(widget.icon, color: _homeAccent, size: 23),
                    ),
                  )
                : Icon(widget.icon, color: _homeAccent, size: 23),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _homeText(
                  color: _homeLabel,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF10B981),
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          text,
          style: _homeText(
            color: _homeFaint,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${date.month}.${date.day}';
}

class StockPicksListScreen extends StatelessWidget {
  const StockPicksListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('추천주')),
      body: _StockStoragePage(
        auth: auth,
        searchQuery: '',
        firestoreService: FirestoreService(),
      ),
    );
  }
}

// ─── 주식저장소 서브탭 페이지 (추천주) ─────────────────────────

class _StockStoragePage extends StatefulWidget {
  const _StockStoragePage({
    required this.auth,
    required this.searchQuery,
    required this.firestoreService,
  });
  final AuthProvider auth;
  final String searchQuery;
  final FirestoreService firestoreService;

  @override
  State<_StockStoragePage> createState() => _StockStoragePageState();
}

class _StockStoragePageState extends State<_StockStoragePage>
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
    final tabBg = isDark ? const Color(0xFF131929) : const Color(0xFFF2F4F6);
    final tabSelected = isDark ? Colors.white : const Color(0xFF191F28);
    final tabUnselected = isDark
        ? Colors.white.withValues(alpha: 0.48)
        : const Color(0xFF8B95A1);
    return Column(
      children: [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: tabBg,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(9999),
              ),
              labelColor: tabSelected,
              unselectedLabelColor: tabUnselected,
              labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: '추천주'),
                Tab(text: '종료 추천주'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _StockListTab(
                auth: widget.auth,
                searchQuery: widget.searchQuery,
                firestoreService: widget.firestoreService,
              ),
              const LeaderboardScreen(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 추천주 탭 ──────────────────────────────────────────────────────────────

class _StockListTab extends StatefulWidget {
  const _StockListTab({
    required this.auth,
    required this.searchQuery,
    required this.firestoreService,
  });
  final AuthProvider auth;
  final String searchQuery;
  final FirestoreService firestoreService;

  @override
  State<_StockListTab> createState() => _StockListTabState();
}

class _StockListTabState extends State<_StockListTab>
    with AutomaticKeepAliveClientMixin {
  late Stream<List<StockPick>> _picksStream;
  late Stream<List<String>> _favStream;
  String? _trackedUid;
  bool _playEntryAnimation = true;
  bool _entryAnimationScheduled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _picksStream = widget.firestoreService.getStockPicks();
    _trackedUid = widget.auth.user?.uid;
    _favStream = _trackedUid != null
        ? widget.firestoreService.getFavoriteIds(_trackedUid!)
        : Stream.value([]);
  }

  @override
  void didUpdateWidget(_StockListTab old) {
    super.didUpdateWidget(old);
    // old.auth와 widget.auth는 동일 인스턴스이므로 _trackedUid로 비교
    final newUid = widget.auth.user?.uid;
    if (_trackedUid != newUid) {
      _trackedUid = newUid;
      _favStream = newUid != null
          ? widget.firestoreService.getFavoriteIds(newUid)
          : Stream.value([]);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = widget.auth;
    final uid = auth.user?.uid;

    return StreamBuilder<List<String>>(
      stream: _favStream,
      builder: (context, favSnapshot) {
        final favIds = favSnapshot.data?.toSet() ?? <String>{};
        return StreamBuilder<List<StockPick>>(
          stream: _picksStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF10B981)),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  '오류: ${snapshot.error}',
                  style: TextStyle(color: Colors.redAccent),
                ),
              );
            }

            final allPicks = snapshot.data ?? [];
            final q = widget.searchQuery.toLowerCase();
            final picks = widget.searchQuery.isEmpty
                ? allPicks
                : allPicks
                      .where(
                        (p) =>
                            p.name.toLowerCase().contains(q) ||
                            p.ticker.toLowerCase().contains(q),
                      )
                      .toList();

            if (picks.isEmpty) {
              return Center(
                child: Text(
                  widget.searchQuery.isNotEmpty
                      ? "'${widget.searchQuery}' 검색 결과가 없습니다"
                      : '아직 등록된 종목이 없습니다',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              );
            }

            if (_playEntryAnimation && !_entryAnimationScheduled) {
              _entryAnimationScheduled = true;
              Future.delayed(const Duration(milliseconds: 760), () {
                if (!mounted) return;
                setState(() => _playEntryAnimation = false);
              });
            }

            const adInterval = 4;
            final adCount = picks.length ~/ adInterval;
            final totalCount = picks.length + adCount;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
              itemCount: totalCount + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const _DisclaimerBanner();
                final adjustedIndex = index - 1;
                final adsBefore = adjustedIndex ~/ (adInterval + 1);
                final actualIndex = adjustedIndex - adsBefore;
                final isAdSlot =
                    (adjustedIndex + 1) % (adInterval + 1) == 0 &&
                    adsBefore < adCount;

                if (isAdSlot) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: BannerAdWidget(slotId: 'stock_tab_$adsBefore'),
                  );
                }

                final pick = picks[actualIndex];
                final card = StockCard(
                  key: ValueKey(pick.id),
                  pick: pick,
                  isLoggedIn: auth.isLoggedIn,
                  isFavorite: favIds.contains(pick.id),
                  onFavoriteToggle: auth.isLoggedIn && uid != null
                      ? () {
                          final isFav = favIds.contains(pick.id);
                          widget.firestoreService.toggleFavorite(
                            uid,
                            pick.id,
                            isFav,
                          );
                          AnalyticsService.instance.logToggleFavorite(
                            ticker: pick.ticker,
                            name: pick.name,
                            added: !isFav,
                          );
                        }
                      : null,
                  onTap: () {
                    if (!auth.isLoggedIn) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('로그인 후 열람 가능합니다'),
                          action: SnackBarAction(
                            label: '로그인',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            ),
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    if (!kIsWeb &&
                        Theme.of(context).platform == TargetPlatform.iOS) {
                      Navigator.push(context, stockDetailRoute(pick));
                    } else {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          transitionDuration: const Duration(milliseconds: 340),
                          reverseTransitionDuration: const Duration(
                            milliseconds: 260,
                          ),
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  StockDetailScreen(pick: pick),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                final fade = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutQuart,
                                );
                                final slide =
                                    Tween<Offset>(
                                      begin: const Offset(0, 0.07),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutQuart,
                                      ),
                                    );
                                final scale =
                                    Tween<double>(begin: 0.985, end: 1).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutQuart,
                                      ),
                                    );
                                return FadeTransition(
                                  opacity: fade,
                                  child: SlideTransition(
                                    position: slide,
                                    child: ScaleTransition(
                                      scale: scale,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                        ),
                      );
                    }
                  },
                );
                if (!_playEntryAnimation) return card;
                return _StaggerReveal(order: actualIndex, child: card);
              },
            );
          },
        );
      },
    );
  }
}

class _StaggerReveal extends StatelessWidget {
  const _StaggerReveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final capped = order.clamp(0, 7);
    final start = (0.06 + (capped * 0.08)).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
    );
  }
}

// ─── 면책 배너 ────────────────────────────────────────────────────────────────

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2235) : const Color(0xFFF2F4F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE8EAED),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: isDark ? Colors.white70 : const Color(0xFF6B7684),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '투자 공부 중인 개인이 관심 종목을 공유하는 공간입니다.\n투자 권유 및 일대일 투자 자문은 절대 하지 않으며, 투자 판단과 결과에 대한 책임은 본인에게 있습니다.',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF6B7684),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 공지사항 탭 ──────────────────────────────────────────────────────────────

class _AnnouncementsTab extends StatefulWidget {
  const _AnnouncementsTab({required this.firestoreService});
  final FirestoreService firestoreService;

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<Announcement>> _stream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stream = widget.firestoreService.getAnnouncements();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<Announcement>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF10B981)),
          );
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              '등록된 공지사항이 없습니다',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          itemCount: list.length,
          itemBuilder: (context, index) => _AnnouncementCard(a: list[index]),
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.a});
  final Announcement a;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final cardColor = isDark ? const Color(0xFF131929) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFE8EAED);

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: cardColor,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.isPinned) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.push_pin,
                        color: Color(0xFF10B981),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '고정 공지',
                        style: TextStyle(
                          color: const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  a.title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  a.body,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: a.isPinned
                ? const Color(0xFF10B981).withValues(alpha: 0.32)
                : borderColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.isPinned)
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 6),
                child: Icon(Icons.push_pin, color: Color(0xFF10B981), size: 13),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (a.body.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      a.body.replaceAll('\n', ' '),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.52),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: cs.onSurface.withValues(alpha: 0.24),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
