import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_pick.dart';
import '../models/announcement.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/stock_card.dart';
import 'admin_screen.dart';
import 'community_screen.dart';
import 'leaderboard_screen.dart';
import 'login_screen.dart';
import 'market_analysis_screen.dart';
import 'portfolio_screen.dart';
import 'my_comments_screen.dart';
import 'my_posts_screen.dart';
import 'notification_history_screen.dart';
import 'stock_compare_screen.dart';
import 'stock_detail_screen.dart';
import '../main.dart' show initAds;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late final AnimationController _rewardChipPulseController;
  late final Animation<double> _rewardChipScale;

  // 탭: 0=주식저장소, 1=매매일지, 2=커뮤니티, 3=종목비교, 4=시황분석
  int _currentPage = 0;

  // 검색
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _rewardAdLoading = false;

  static const _tabTitles = ['주식저장소', '매매일지', '커뮤니티', '종목 비교', '시황 분석'];

  @override
  void initState() {
    super.initState();
    _rewardChipPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _rewardChipScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(
        parent: _rewardChipPulseController,
        curve: Curves.easeInOut,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      initAds();
      BannerAdWidget.prewarm(
        slotId: 'market_analysis_between_indices_hot',
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
    _rewardChipPulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildRewardAdAppBarChip({
    required AuthProvider auth,
    required String uid,
    required bool isDark,
  }) {
    return StreamBuilder<Map<String, int>>(
      stream: _firestoreService.watchRewardAdStatus(uid),
      builder: (context, snap) {
        final status = snap.data;
        final remaining = status?['remainingCount'] ?? 0;
        final limit = status?['dailyLimit'] ?? 3;
        if (remaining <= 0) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () async {
            final goWatch = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(
                  '리워드 광고 안내',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                content: Text(
                  '🎁 광고 시청을 완료하면 경험치 +5를 받을 수 있어요.\n'
                  '보상은 시청 완료 후 지급됩니다.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('닫기', style: TextStyle()),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      '광고 보기',
                      style: TextStyle(
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
            if (goWatch == true) {
              await _watchRewardAdAndClaimXp(auth);
            }
          },
          child: AnimatedBuilder(
            animation: _rewardChipScale,
            builder: (context, child) =>
                Transform.scale(scale: _rewardChipScale.value, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.ondemand_video,
                    size: 12,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$remaining/$limit',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF065F46),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
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
            : Text(
                _tabTitles[_currentPage],
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
        actions: [
          if (auth.isLoggedIn && !(_showSearch && _currentPage == 0))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: _buildRewardAdAppBarChip(
                  auth: auth,
                  uid: auth.user!.uid,
                  isDark: isDark,
                ),
              ),
            ),
          if (auth.isLoggedIn)
            IconButton(
              icon: Icon(
                Icons.notifications_none,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationHistoryScreen(),
                  ),
                );
              },
            ),
          if (_currentPage == 0)
            IconButton(
              icon: Icon(
                _showSearch ? Icons.close : Icons.search,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () {
                if (_showSearch) {
                  _closeSearch();
                } else {
                  setState(() => _showSearch = true);
                }
              },
            ),
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                color: Color(0xFF10B981),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          IconButton(
            icon: Icon(
              auth.isLoggedIn ? Icons.person : Icons.person_outline,
              color: isDark ? Colors.white70 : Colors.black54,
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
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentPage,
        onTap: (i) {
          if (i != 0) _closeSearch();
          setState(() => _currentPage = i);
          const tabNames = ['추천주', '매매일지', '커뮤니티', '종목비교', '시황분석'];
          AnalyticsService.instance.logTabChange(tabNames[i]);
        },
        backgroundColor: bgColor,
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 10),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: '추천주'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: '매매일지',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: '커뮤니티',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.compare_arrows),
            label: '종목비교',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: '시황 분석',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentPage,
        children: [
          _buildStockPicksPage(auth),
          _buildMyStocksPage(),
          const CommunityScreen(),
          const StockCompareScreen(),
          const MarketAnalysisScreen(),
        ],
      ),
    );
  }

  // ─── 매매일지 페이지 ───────────────────────────────────────────────────
  Widget _buildMyStocksPage() {
    return const PortfolioScreen();
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
                                                        _watchRewardAdAndClaimXp(
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
                                            '오늘 보상 광고: ${remainingCount}/${dailyLimit}회 남음',
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

// ─── 주식저장소 서브탭 페이지 (추천주 + 공지사항) ─────────────────────────

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
    _tabController = TabController(length: 3, vsync: this);
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
                Tab(text: '공지사항'),
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
              _AnnouncementsTab(firestoreService: widget.firestoreService),
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
