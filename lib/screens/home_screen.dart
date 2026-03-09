import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/stock_pick.dart';
import '../models/announcement.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/stock_card.dart';
import 'admin_screen.dart';
import 'leaderboard_screen.dart';
import 'login_screen.dart';
import 'market_analysis_screen.dart';
import 'portfolio_screen.dart';
import 'stock_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  String _selectedCategory = '전체';
  final List<String> _categories = ['전체', '단기', '장기'];

  // 탭: 0=종목, 1=포트폴리오, 2=실적, 3=시황
  int _currentPage = 0;

  // 검색
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _tabTitles = ['주식저장소', '내 포트폴리오', '추천 실적', '시황 분석'];

  @override
  void dispose() {
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
                style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15),
                decoration: InputDecoration(
                  hintText: '종목명 또는 티커 검색...',
                  hintStyle: GoogleFonts.inter(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 15),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Text(
                _tabTitles[_currentPage],
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
        actions: [
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
              icon: const Icon(Icons.add_circle_outline,
                  color: Color(0xFF4ADE80)),
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
        },
        backgroundColor: bgColor,
        selectedItemColor: const Color(0xFF4ADE80),
        unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 10),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: '관심종목',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: '포트폴리오',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_outlined),
            label: '추천 실적',
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
          const PortfolioScreen(),
          const LeaderboardScreen(),
          const MarketAnalysisScreen(),
        ],
      ),
    );
  }

  // ─── 관심종목 페이지 ──────────────────────────────────────────────────────

  Widget _buildStockPicksPage(AuthProvider auth) {
    return Column(
      children: [
        _buildHeader(),
        _buildAnnouncements(),
        _buildCategoryFilter(),
        Expanded(child: _buildStockList(auth)),
      ],
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '본 정보는 투자 권유가 아니며, 투자 손실에 대한 책임은 투자자 본인에게 있습니다.',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.orangeAccent.withValues(alpha: 0.85) : Colors.deepOrange,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncements() {
    return StreamBuilder<List<Announcement>>(
      stream: _firestoreService.getAnnouncements(),
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          children: list.map((a) => _buildAnnouncementCard(a)).toList(),
        );
      },
    );
  }

  Widget _buildAnnouncementCard(Announcement a) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.isPinned)
                Row(children: [
                  const Icon(Icons.push_pin,
                      color: Color(0xFF4ADE80), size: 14),
                  const SizedBox(width: 4),
                  Text('고정 공지',
                      style: GoogleFonts.inter(
                          color: const Color(0xFF4ADE80), fontSize: 11)),
                ]),
              if (a.isPinned) const SizedBox(height: 8),
              Text(a.title,
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w700,
                      fontSize: 17)),
              const SizedBox(height: 12),
              Text(a.body,
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 14,
                      height: 1.7)),
            ],
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: a.isPinned
                ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            if (a.isPinned)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.push_pin,
                    color: Color(0xFF4ADE80), size: 13),
              ),
            Expanded(
              child: Text(
                a.title,
                style: GoogleFonts.inter(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 13,
                    fontWeight:
                        a.isPinned ? FontWeight.w600 : FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right,
                color: isDark ? Colors.white24 : Colors.black26, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4ADE80)
                    : (isDark ? const Color(0xFF1A2035) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4ADE80)
                      : (isDark ? Colors.white12 : Colors.black12),
                ),
              ),
              child: Center(
                child: Text(
                  cat,
                  style: GoogleFonts.inter(
                    color: isSelected
                        ? Colors.black
                        : (isDark ? Colors.white60 : Colors.black54),
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStockList(AuthProvider auth) {
    final uid = auth.user?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<String>>(
      stream: uid != null
          ? _firestoreService.getFavoriteIds(uid)
          : Stream.value([]),
      builder: (context, favSnapshot) {
        final favIds = favSnapshot.data?.toSet() ?? <String>{};

        return StreamBuilder<List<StockPick>>(
          stream: _firestoreService.getStockPicks(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF4ADE80)));
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text('오류: ${snapshot.error}',
                      style: GoogleFonts.inter(color: Colors.redAccent)));
            }

            final allPicks = snapshot.data ?? [];

            // 카테고리 + 검색 필터
            final picks = allPicks.where((p) {
              if (_selectedCategory != '전체' &&
                  p.category != _selectedCategory) {
                return false;
              }
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                return p.name.toLowerCase().contains(q) ||
                    p.ticker.toLowerCase().contains(q);
              }
              return true;
            }).toList();

            if (picks.isEmpty) {
              return Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? "'$_searchQuery' 검색 결과가 없습니다"
                      : '아직 등록된 종목이 없습니다',
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white38 : Colors.black38),
                ),
              );
            }

            // 광고 슬롯: 매 4번째 카드 다음에 배너 삽입
            const adInterval = 4;
            final adCount = picks.length ~/ adInterval;
            final totalCount = picks.length + adCount;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: totalCount,
              itemBuilder: (context, index) {
                // 광고 슬롯 여부 판별: adInterval 카드마다 1개 광고
                final adsBefore = index ~/ (adInterval + 1);
                final actualIndex = index - adsBefore;
                final isAdSlot = (index + 1) % (adInterval + 1) == 0 &&
                    adsBefore < adCount;

                if (isAdSlot) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: BannerAdWidget(),
                  );
                }

                final pick = picks[actualIndex];
                return StockCard(
                  pick: pick,
                  isLoggedIn: auth.isLoggedIn,
                  isFavorite: favIds.contains(pick.id),
                  onFavoriteToggle: auth.isLoggedIn && uid != null
                      ? () => _firestoreService.toggleFavorite(
                          uid, pick.id, favIds.contains(pick.id))
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => StockDetailScreen(pick: pick)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── 프로필 메뉴 ──────────────────────────────────────────────────────────

  void _showProfileMenu(BuildContext context, AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
    final uid = auth.user!.uid;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Consumer<ThemeProvider>(
        builder: (ctx, themeProvider, _) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor:
                    const Color(0xFF4ADE80).withValues(alpha: 0.15),
                radius: 28,
                child: const Icon(Icons.person,
                    color: Color(0xFF4ADE80), size: 28),
              ),
              const SizedBox(height: 10),
              // 닉네임 표시
              FutureBuilder<String?>(
                future: _firestoreService.getNickname(uid),
                builder: (ctx, snap) {
                  final nickname = snap.data;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        nickname ?? '닉네임 없음',
                        style: GoogleFonts.inter(
                          color: nickname != null
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white38 : Colors.black38),
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
                style: GoogleFonts.inter(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 12),
              ),
              const SizedBox(height: 20),
              // 테마 토글
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  secondary: Icon(
                    themeProvider.isDark
                        ? Icons.dark_mode_outlined
                        : Icons.wb_sunny_outlined,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  title: Text(
                    themeProvider.isDark ? '다크 모드' : '라이트 모드',
                    style: GoogleFonts.inter(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 14),
                  ),
                  activeThumbColor: const Color(0xFF4ADE80),
                  value: themeProvider.isDark,
                  onChanged: (_) => themeProvider.toggle(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.redAccent.withValues(alpha: 0.15),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    auth.signOut();
                  },
                  child: Text('로그아웃',
                      style:
                          GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
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
                borderRadius: BorderRadius.circular(16)),
            title: Text(
              '닉네임 설정',
              style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: '닉네임 입력 (2~12자)',
                    hintStyle: GoogleFonts.inter(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 13),
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
                child: Text('취소',
                    style: GoogleFonts.inter(
                        color: isDark ? Colors.white54 : Colors.black45)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: checking
                    ? null
                    : () async {
                        final nick = controller.text.trim();
                        if (nick.length < 2 || nick.length > 12) {
                          setDialogState(() =>
                              errorMsg = '닉네임은 2~12자여야 합니다');
                          return;
                        }
                        setDialogState(() => checking = true);
                        final taken = await _firestoreService
                            .isNicknameTaken(nick, uid);
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
                            strokeWidth: 2, color: Colors.black),
                      )
                    : Text('저장',
                        style:
                            GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }
}
