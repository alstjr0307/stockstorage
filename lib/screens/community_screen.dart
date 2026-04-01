import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/trading_journal.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import '../utils/dialogs.dart';
import 'post_detail_screen.dart';
import 'write_post_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // 탭바
        Container(
          color: cs.surface,
          child: TabBar(
            controller: _tabController,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
            labelColor: const Color(0xFF4ADE80),
            unselectedLabelColor: cs.onSurface.withValues(alpha: 0.4),
            indicatorColor: const Color(0xFF4ADE80),
            indicatorWeight: 2,
            tabs: const [
              Tab(text: '자유게시판'),
              Tab(text: '매매일지 공유'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _FreeBoardTab(),
              _JournalTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 매매일지 공유 탭 ──────────────────────────────────────────────────────────

class _JournalTab extends StatefulWidget {
  const _JournalTab();

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  final _firestoreService = FirestoreService();
  final _scrollController = ScrollController();
  final Set<String> _likedIds = {};
  final Set<String> _loadingLikes = {};
  final Set<String> _blockedUids = {};
  final Map<String, int> _likeCountOverride = {};

  final List<TradingJournal> _journals = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;

  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        final blocked = await _firestoreService.getBlockedUids(auth.user!.uid);
        if (mounted) setState(() => _blockedUids.addAll(blocked));
      }
      _loadMore();
    });
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  Future<void> _handleReport(TradingJournal journal, String reporterUid) async {
    final reason = await showReportReasonDialog(context);
    if (reason == null || !mounted) return;
    await _firestoreService.reportContent(
      reporterUid: reporterUid,
      targetUid: journal.uid,
      contentType: 'journal',
      contentId: journal.id,
      reason: reason,
    );
    AnalyticsService.instance.logReportContent('journal');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
  }

  Future<void> _handleBlock(TradingJournal journal, String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('차단'),
        content: Text('${journal.nickname} 님을 차단하시겠습니까?\n차단된 유저의 글은 보이지 않습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('차단', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _firestoreService.blockUser(uid, journal.uid);
    AnalyticsService.instance.logBlockUser();
    if (mounted) {
      setState(() {
        _blockedUids.add(journal.uid);
        _journals.removeWhere((j) => j.uid == journal.uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('차단되었습니다')));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final (items, lastDoc) = await _firestoreService.getPublicJournalsPaged(
        startAfter: _lastDoc,
        limit: _pageSize,
      );
      // 매수 + 기타만 (매도 제외) + 차단된 유저 제외
      final filtered = items
          .where((j) => j.action != '매도' && !_blockedUids.contains(j.uid))
          .toList();
      // 로그인 유저의 좋아요 상태 병렬 조회
      if (auth.isLoggedIn && filtered.isNotEmpty) {
        final liked = await Future.wait(
          filtered.map((j) => _firestoreService.hasLikedJournal(j.id, auth.user!.uid)),
        );
        for (var k = 0; k < filtered.length; k++) {
          if (liked[k]) _likedIds.add(filtered[k].id);
        }
      }
      if (mounted) {
        setState(() {
          _journals.addAll(filtered);
          _lastDoc = lastDoc;
          _hasMore = items.length == _pageSize;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() { _journals.clear(); _lastDoc = null; _hasMore = true; });
    await _loadMore();
  }

  Future<void> _toggleLike(TradingJournal journal, String uid) async {
    if (_loadingLikes.contains(journal.id)) return;
    setState(() => _loadingLikes.add(journal.id));
    try {
      final nowLiked = await _firestoreService.likeJournal(journal.id, uid);
      AnalyticsService.instance.logLikeContent('journal');
      if (mounted) {
        setState(() {
          if (nowLiked) {
            _likedIds.add(journal.id);
            _likeCountOverride[journal.id] =
                (_likeCountOverride[journal.id] ?? journal.likes) + 1;
          } else {
            _likedIds.remove(journal.id);
            _likeCountOverride[journal.id] =
                (_likeCountOverride[journal.id] ?? journal.likes) - 1;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingLikes.remove(journal.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_loading && _journals.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80)));
    }

    if (!_loading && _journals.isEmpty) {
      return _EmptyState(
        icon: Icons.trending_up_rounded,
        title: '공유된 매매일지가 없습니다',
        subtitle: '매매일지에서 매수 기록을 공유해보세요',
        onRefresh: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF4ADE80),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _journals.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _journals.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80), strokeWidth: 2)),
            );
          }
          final journal = _journals[i];
          final isOwn = auth.user?.uid == journal.uid;
          return _JournalCard(
            key: ValueKey(journal.id),
            journal: journal,
            isOwn: isOwn,
            isLiked: _likedIds.contains(journal.id),
            isLoadingLike: _loadingLikes.contains(journal.id),
            likeCount: _likeCountOverride[journal.id] ?? journal.likes,
            onLike: auth.isLoggedIn ? () => _toggleLike(journal, auth.user!.uid) : null,
            onTogglePrivate: isOwn
                ? () async {
                    await _firestoreService.toggleJournalPublic(journal.id, true);
                    if (mounted) setState(() => _journals.removeWhere((j) => j.id == journal.id));
                  }
                : null,
            onReport: (!isOwn && auth.isLoggedIn)
                ? () => _handleReport(journal, auth.user!.uid)
                : null,
            onBlock: (!isOwn && auth.isLoggedIn)
                ? () => _handleBlock(journal, auth.user!.uid)
                : null,
          );
        },
      ),
    );
  }
}

// ── 자유게시판 탭 ─────────────────────────────────────────────────────────────

class _FreeBoardTab extends StatefulWidget {
  const _FreeBoardTab();

  @override
  State<_FreeBoardTab> createState() => _FreeBoardTabState();
}

class _FreeBoardTabState extends State<_FreeBoardTab> {
  final _firestoreService = FirestoreService();
  final _scrollController = ScrollController();
  final Set<String> _likedIds = {};
  final Set<String> _loadingLikes = {};
  final Set<String> _blockedUids = {};
  final Map<String, int> _likeCountOverride = {};

  final List<Post> _posts = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;

  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        final blocked = await _firestoreService.getBlockedUids(auth.user!.uid);
        if (mounted) setState(() => _blockedUids.addAll(blocked));
      }
      _loadMore();
    });
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final (items, lastDoc) = await _firestoreService.getPostsPaged(
        startAfter: _lastDoc,
        limit: _pageSize,
      );
      final filtered = items.where((p) => !_blockedUids.contains(p.uid)).toList();
      // 로그인 유저의 좋아요 상태 병렬 조회
      if (auth.isLoggedIn && filtered.isNotEmpty) {
        final liked = await Future.wait(
          filtered.map((p) => _firestoreService.hasLikedPost(p.id, auth.user!.uid)),
        );
        for (var k = 0; k < filtered.length; k++) {
          if (liked[k]) _likedIds.add(filtered[k].id);
        }
      }
      if (mounted) {
        setState(() {
          _posts.addAll(filtered);
          _lastDoc = lastDoc;
          _hasMore = items.length == _pageSize;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() { _posts.clear(); _lastDoc = null; _hasMore = true; });
    await _loadMore();
  }

  Future<void> _handleReport(Post post, String reporterUid) async {
    final reason = await showReportReasonDialog(context);
    if (reason == null || !mounted) return;
    await _firestoreService.reportContent(
      reporterUid: reporterUid,
      targetUid: post.uid,
      contentType: 'post',
      contentId: post.id,
      reason: reason,
    );
    AnalyticsService.instance.logReportContent('post');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
  }

  Future<bool> _handleBlock(Post post, String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('차단'),
        content: Text('${post.nickname} 님을 차단하시겠습니까?\n차단된 유저의 글은 보이지 않습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('차단', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    await _firestoreService.blockUser(uid, post.uid);
    AnalyticsService.instance.logBlockUser();
    if (mounted) {
      setState(() {
        _blockedUids.add(post.uid);
        _posts.removeWhere((p) => p.uid == post.uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('차단되었습니다')));
    }
    return true;
  }

  Future<void> _toggleLike(Post post, String uid) async {
    if (_loadingLikes.contains(post.id)) return;
    setState(() => _loadingLikes.add(post.id));
    try {
      final nowLiked = await _firestoreService.likePost(post.id, uid);
      AnalyticsService.instance.logLikeContent('post');
      if (mounted) {
        setState(() {
          if (nowLiked) {
            _likedIds.add(post.id);
            _likeCountOverride[post.id] =
                (_likeCountOverride[post.id] ?? post.likes) + 1;
          } else {
            _likedIds.remove(post.id);
            _likeCountOverride[post.id] =
                (_likeCountOverride[post.id] ?? post.likes) - 1;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingLikes.remove(post.id));
    }
  }

  Future<void> _openWrite(AuthProvider auth) async {
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }
    final uid = auth.user!.uid;
    final nickname = await _firestoreService.getNickname(uid) ?? '익명';
    if (!mounted) return;
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WritePostScreen(uid: uid, nickname: nickname),
      ),
    );
    if (posted == true && mounted) _refresh();
  }

  void _openPost(BuildContext context, Post post, AuthProvider auth) {
    final isOwn = auth.user?.uid == post.uid;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          isOwn: isOwn,
          isLiked: _likedIds.contains(post.id),
          likeCount: _likeCountOverride[post.id] ?? post.likes,
          onLikeChanged: auth.isLoggedIn
              ? (nowLiked) => setState(() {
                    if (nowLiked) {
                      _likedIds.add(post.id);
                      _likeCountOverride[post.id] =
                          (_likeCountOverride[post.id] ?? post.likes) + 1;
                    } else {
                      _likedIds.remove(post.id);
                      _likeCountOverride[post.id] =
                          (_likeCountOverride[post.id] ?? post.likes) - 1;
                    }
                  })
              : null,
          onDelete: isOwn
              ? () async {
                  await _firestoreService.deletePost(post.id);
                  if (mounted) _refresh();
                }
              : null,
          onReport: (!isOwn && auth.isLoggedIn)
              ? () => _handleReport(post, auth.user!.uid)
              : null,
          onBlock: (!isOwn && auth.isLoggedIn)
              ? () => _handleBlock(post, auth.user!.uid)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80)));
    }

    return Stack(
      children: [
        if (!_loading && _posts.isEmpty)
          _EmptyState(
            icon: Icons.forum_outlined,
            title: '아직 게시글이 없습니다',
            subtitle: '첫 번째 글을 작성해보세요',
            onRefresh: _refresh,
          )
        else
          RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFF4ADE80),
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: _posts.length + (_hasMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _posts.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80), strokeWidth: 2)),
                  );
                }
                final post = _posts[i];
                final isOwn = auth.user?.uid == post.uid;
                return _PostCard(
                  key: ValueKey(post.id),
                  post: post,
                  isOwn: isOwn,
                  isLiked: _likedIds.contains(post.id),
                  isLoadingLike: _loadingLikes.contains(post.id),
                  likeCount: _likeCountOverride[post.id] ?? post.likes,
                  onLike: auth.isLoggedIn ? () => _toggleLike(post, auth.user!.uid) : null,
                  onTap: () => _openPost(context, post, auth),
                  onReport: null,
                  onBlock: null,
                );
              },
            ),
          ),
        // 글쓰기 FAB
        Positioned(
          right: 16,
          bottom: 24,
          child: FloatingActionButton(
            heroTag: 'community_write_fab',
            onPressed: () => _openWrite(auth),
            backgroundColor: const Color(0xFF4ADE80),
            foregroundColor: Colors.black,
            elevation: 3,
            child: const Icon(Icons.edit_rounded, size: 22),
          ),
        ),
      ],
    );
  }
}

// ── 공통 빈 상태 ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: const Color(0xFF4ADE80),
      child: ListView(children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Column(children: [
          Icon(icon, color: cs.onSurface.withValues(alpha: 0.18), size: 56),
          const SizedBox(height: 14),
          Text(title, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.25), fontSize: 12)),
        ]),
      ]),
    );
  }
}

// ── 매매일지 카드 ─────────────────────────────────────────────────────────────

class _JournalCard extends StatefulWidget {
  final TradingJournal journal;
  final bool isOwn;
  final bool isLiked;
  final bool isLoadingLike;
  final int likeCount;
  final VoidCallback? onLike;
  final VoidCallback? onTogglePrivate;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  const _JournalCard({
    super.key,
    required this.journal,
    required this.isOwn,
    required this.isLiked,
    required this.isLoadingLike,
    required this.likeCount,
    required this.onLike,
    this.onTogglePrivate,
    this.onReport,
    this.onBlock,
  });

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard> {
  PriceResult? _price;
  final _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _fetchPrice();
  }

  Future<void> _openComments(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    String nickname = '익명';
    if (auth.isLoggedIn) {
      nickname = await _firestoreService.getNickname(auth.user!.uid) ?? '익명';
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentSheet(
        collection: 'trading_journal',
        docId: widget.journal.id,
        firestoreService: _firestoreService,
        auth: auth,
        nickname: nickname,
      ),
    );
  }

  Future<void> _fetchPrice() async {
    final j = widget.journal;
    if (j.ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(j.market)) return;
    final result = await StockPriceService.fetchPrice(j.ticker, j.market);
    if (mounted) setState(() => _price = result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final journal = widget.journal;
    final isKrw = journal.market != 'US';
    final marketLabel = switch (journal.market) {
      'KS' => 'KOSPI', 'KQ' => 'KOSDAQ', 'US' => 'NASDAQ', _ => journal.market,
    };

    String fmtP(double p) =>
        isKrw ? '₩${NumberFormat('#,###').format(p.toInt())}' : '\$${p.toStringAsFixed(2)}';

    final qtyStr = journal.quantity > 0
        ? '${journal.quantity % 1 == 0 ? journal.quantity.toInt() : journal.quantity}주' : null;

    // 평가손익
    double? pnl, pnlPct;
    if (_price != null && journal.price > 0 && journal.quantity > 0) {
      pnl = (_price!.price - journal.price) * journal.quantity;
      pnlPct = (_price!.price - journal.price) / journal.price * 100;
    }
    final isPnlUp = pnl == null || pnl >= 0;

    // '기타' 간소화 카드
    if (journal.action == '기타') return _buildEtcCard(cs);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 초록 바
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF4ADE80), Color(0xFF22C55E)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작성자 행
                Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF4ADE80).withValues(alpha: 0.12),
                    child: Text(
                      journal.nickname.isNotEmpty ? journal.nickname[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(color: const Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(journal.nickname, style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (widget.isOwn) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('나', style: GoogleFonts.inter(color: const Color(0xFF4ADE80), fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      Text(
                        '${DateFormat('yyyy.MM.dd').format(journal.tradeDate)} 매수',
                        style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.35), fontSize: 11),
                      ),
                    ]),
                  ),
                  // 마켓 배지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(marketLabel, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  if (widget.onReport != null || widget.onBlock != null) ...[
                    const SizedBox(width: 4),
                    _MoreMenu(onReport: widget.onReport, onBlock: widget.onBlock),
                  ],
                ]),
                const SizedBox(height: 14),
                // 종목명
                Text(journal.stockName, style: GoogleFonts.inter(
                    color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                // 거래 정보 그리드 (2행)
                if (journal.price > 0 || journal.quantity > 0)
                  Container(
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        // 1행: 매수가, 수량
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (journal.price > 0)
                                Expanded(child: _gridCell('매수가', fmtP(journal.price), cs)),
                              if (journal.price > 0 && qtyStr != null)
                                VerticalDivider(width: 1, thickness: 1, color: cs.onSurface.withValues(alpha: 0.07)),
                              if (qtyStr != null)
                                Expanded(child: _gridCell('수량', qtyStr, cs)),
                            ],
                          ),
                        ),
                        // 2행: 현재가, 평가손익, 수익률
                        if (_price != null) ...[
                          Divider(height: 1, thickness: 1, color: cs.onSurface.withValues(alpha: 0.07)),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _gridCell('현재가', fmtP(_price!.price), cs,
                                    valueColor: _price!.isUp ? const Color(0xFF4ADE80) : Colors.redAccent)),
                                if (pnl != null && pnlPct != null) ...[
                                  VerticalDivider(width: 1, thickness: 1, color: cs.onSurface.withValues(alpha: 0.07)),
                                  Expanded(child: _gridCell(
                                    '평가손익',
                                    '${isPnlUp ? '+' : ''}${fmtP(pnl)}',
                                    cs,
                                    valueColor: isPnlUp ? const Color(0xFF4ADE80) : Colors.redAccent,
                                  )),
                                  VerticalDivider(width: 1, thickness: 1, color: cs.onSurface.withValues(alpha: 0.07)),
                                  Expanded(child: _gridCell(
                                    '수익률',
                                    '${isPnlUp ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                                    cs,
                                    valueColor: isPnlUp ? const Color(0xFF4ADE80) : Colors.redAccent,
                                  )),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                // 메모
                if (journal.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(journal.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 13, height: 1.55)),
                ],
              ],
            ),
          ),
          // 하단: 좋아요 + 비공개 토글
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(children: [
              _LikeButton(
                isLiked: widget.isLiked,
                isLoading: widget.isLoadingLike,
                count: widget.likeCount,
                onTap: widget.onLike,
              ),
              const Spacer(),
              if (widget.isOwn && widget.onTogglePrivate != null)
                GestureDetector(
                  onTap: widget.onTogglePrivate,
                  child: Row(children: [
                    Icon(Icons.lock_outline, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: 4),
                    Text('비공개로 전환',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.4))),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildEtcCard(ColorScheme cs) {
    final journal = widget.journal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF94A3B8), Color(0xFF64748B)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작성자 행
                Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF94A3B8).withValues(alpha: 0.12),
                    child: Text(
                      journal.nickname.isNotEmpty ? journal.nickname[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(journal.nickname, style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (widget.isOwn) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('나', style: GoogleFonts.inter(color: const Color(0xFF4ADE80), fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      Text(
                        DateFormat('yyyy.MM.dd').format(journal.tradeDate),
                        style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.35), fontSize: 11),
                      ),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('기타', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  if (widget.onReport != null || widget.onBlock != null) ...[
                    const SizedBox(width: 4),
                    _MoreMenu(onReport: widget.onReport, onBlock: widget.onBlock),
                  ],
                ]),
                const SizedBox(height: 14),
                // 종목명
                Text(
                  journal.stockName.isNotEmpty ? journal.stockName : '기타 메모',
                  style: GoogleFonts.inter(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                // 메모
                if (journal.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(journal.note,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 13, height: 1.6)),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(children: [
              _LikeButton(
                isLiked: widget.isLiked,
                isLoading: widget.isLoadingLike,
                count: widget.likeCount,
                onTap: widget.onLike,
              ),
              const SizedBox(width: 12),
              _CommentButton(onTap: () => _openComments(context)),
              const Spacer(),
              if (widget.isOwn && widget.onTogglePrivate != null)
                GestureDetector(
                  onTap: widget.onTogglePrivate,
                  child: Row(children: [
                    Icon(Icons.lock_outline, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: 4),
                    Text('비공개로 전환',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _gridCell(String label, String value, ColorScheme cs, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 10)),
        const SizedBox(height: 3),
        Text(value,
            style: GoogleFonts.robotoMono(
                color: valueColor ?? cs.onSurface, fontSize: 13, fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── 게시글 카드 ───────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  final Post post;
  final bool isOwn;
  final bool isLiked;
  final bool isLoadingLike;
  final int likeCount;
  final VoidCallback? onLike;
  final VoidCallback onTap;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  const _PostCard({
    super.key,
    required this.post,
    required this.isOwn,
    required this.isLiked,
    required this.isLoadingLike,
    required this.likeCount,
    required this.onLike,
    required this.onTap,
    this.onReport,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목
                  Text(post.title, style: GoogleFonts.inter(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
                  if (post.content.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(post.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13, height: 1.5)),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
              child: Row(children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.07),
                  child: Text(
                    post.nickname.isNotEmpty ? post.nickname[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 7),
                Text(post.nickname, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12, fontWeight: FontWeight.w500)),
                if (isOwn) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ADE80).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('나', style: GoogleFonts.inter(color: const Color(0xFF4ADE80), fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ],
                Text('  ·  ', style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.2), fontSize: 12)),
                Text(DateFormat('MM.dd HH:mm').format(post.createdAt),
                    style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
                const Spacer(),
                _LikeButton(isLiked: isLiked, isLoading: isLoadingLike, count: likeCount, onTap: onLike),
                if (onReport != null || onBlock != null) ...[
                  const SizedBox(width: 2),
                  _MoreMenu(onReport: onReport, onBlock: onBlock),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 신고 사유 다이얼로그 (전역) ───────────────────────────────────────────────


// ── 공통 좋아요 버튼 ──────────────────────────────────────────────────────────

class _LikeButton extends StatelessWidget {
  final bool isLiked;
  final bool isLoading;
  final int count;
  final VoidCallback? onTap;

  const _LikeButton({required this.isLiked, required this.isLoading, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF4ADE80)))
              : Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                  size: 16, color: isLiked ? Colors.redAccent : cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 4),
          Text('$count', style: GoogleFonts.inter(
              color: isLiked ? Colors.redAccent : cs.onSurface.withValues(alpha: 0.4),
              fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── 게시글 상세 시트 ──────────────────────────────────────────────────────────

class _PostDetailSheet extends StatefulWidget {
  final Post post;
  final bool isOwn;
  final bool isLiked;
  final bool isLoadingLike;
  final VoidCallback? onLike;
  final Future<void> Function()? onDelete;
  final FirestoreService firestoreService;
  final AuthProvider auth;

  const _PostDetailSheet({
    required this.post,
    required this.isOwn,
    required this.isLiked,
    required this.isLoadingLike,
    required this.onLike,
    required this.onDelete,
    required this.firestoreService,
    required this.auth,
  });

  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet> {
  Future<void> _openComments() async {
    String nickname = '익명';
    if (widget.auth.isLoggedIn) {
      nickname = await widget.firestoreService.getNickname(widget.auth.user!.uid) ?? '익명';
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentSheet(
        collection: 'posts',
        docId: widget.post.id,
        firestoreService: widget.firestoreService,
        auth: widget.auth,
        nickname: nickname,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            // 제목 + 삭제
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(widget.post.title,
                  style: GoogleFonts.inter(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800))),
              if (widget.isOwn && widget.onDelete != null)
                IconButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('게시글 삭제'),
                        content: const Text('이 게시글을 삭제하시겠습니까?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.redAccent))),
                        ],
                      ),
                    );
                    if (ok == true) await widget.onDelete!();
                  },
                  icon: Icon(Icons.delete_outline, size: 20, color: cs.onSurface.withValues(alpha: 0.35)),
                ),
            ]),
            const SizedBox(height: 6),
            // 작성자 + 날짜
            Row(children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                child: Text(widget.post.nickname.isNotEmpty ? widget.post.nickname[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(widget.post.nickname, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(DateFormat('yyyy.MM.dd HH:mm').format(widget.post.createdAt),
                  style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
            ]),
            const SizedBox(height: 20),
            Divider(color: cs.onSurface.withValues(alpha: 0.07), height: 1),
            const SizedBox(height: 16),
            // 본문
            if (widget.post.content.isNotEmpty)
              Text(widget.post.content, style: GoogleFonts.inter(color: cs.onSurface, fontSize: 15, height: 1.75)),
            const SizedBox(height: 24),
            Row(children: [
              _LikeButton(isLiked: widget.isLiked, isLoading: widget.isLoadingLike, count: widget.post.likes, onTap: widget.onLike),
              const SizedBox(width: 12),
              _CommentButton(onTap: _openComments),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── 댓글 버튼 ─────────────────────────────────────────────────────────────────

class _CommentButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _CommentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 4),
          Text('댓글', style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.4), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── 더보기 메뉴 (신고/차단) ───────────────────────────────────────────────────

class _MoreMenu extends StatelessWidget {
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  const _MoreMenu({this.onReport, this.onBlock});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
      padding: EdgeInsets.zero,
      color: cs.surface,
      onSelected: (v) {
        if (v == 'report') onReport?.call();
        if (v == 'block') onBlock?.call();
      },
      itemBuilder: (_) => [
        if (onReport != null)
          PopupMenuItem(
            value: 'report',
            child: Row(children: [
              const Icon(Icons.flag_outlined, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              Text('신고하기', style: GoogleFonts.inter(fontSize: 13)),
            ]),
          ),
        if (onBlock != null)
          PopupMenuItem(
            value: 'block',
            child: Row(children: [
              const Icon(Icons.block, size: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('차단하기', style: GoogleFonts.inter(fontSize: 13)),
            ]),
          ),
      ],
    );
  }
}

// ── 댓글 시트 ─────────────────────────────────────────────────────────────────

class _CommentSheet extends StatefulWidget {
  final String collection;
  final String docId;
  final FirestoreService firestoreService;
  final AuthProvider auth;
  final String nickname;

  const _CommentSheet({
    required this.collection,
    required this.docId,
    required this.firestoreService,
    required this.auth,
    required this.nickname,
  });

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  final Set<String> _blockedUids = {};
  late final Stream<List<Comment>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.collection == 'posts'
        ? widget.firestoreService.getPostComments(widget.docId)
        : widget.firestoreService.getJournalComments(widget.docId);
    if (widget.auth.isLoggedIn) {
      widget.firestoreService.getBlockedUids(widget.auth.user!.uid).then((uids) {
        if (mounted) setState(() => _blockedUids.addAll(uids));
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleReport(Comment c) async {
    final reason = await showReportReasonDialog(context);
    if (reason == null || !mounted) return;
    await widget.firestoreService.reportContent(
      reporterUid: widget.auth.user!.uid,
      targetUid: c.uid,
      contentType: 'comment',
      contentId: c.id,
      reason: reason,
    );
    AnalyticsService.instance.logReportContent('comment');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
  }

  Future<void> _handleBlock(Comment c) async {
    final ok = await showBlockConfirmDialog(context, c.nickname);
    if (ok != true || !mounted) return;
    await widget.firestoreService.blockUser(widget.auth.user!.uid, c.uid);
    AnalyticsService.instance.logBlockUser();
    if (mounted) setState(() => _blockedUids.add(c.uid));
  }


  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || !widget.auth.isLoggedIn) return;
    setState(() => _sending = true);
    try {
      final comment = Comment(
        id: '',
        uid: widget.auth.user!.uid,
        nickname: widget.nickname,
        content: text,
        createdAt: DateTime.now(),
      );
      if (widget.collection == 'posts') {
        await widget.firestoreService.addPostComment(widget.docId, comment);
      } else {
        await widget.firestoreService.addJournalComment(widget.docId, comment);
      }
      AnalyticsService.instance.logWriteCommunityComment(widget.collection == 'posts' ? 'post' : 'journal');
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String commentId) async {
    if (widget.collection == 'posts') {
      await widget.firestoreService.deletePostComment(widget.docId, commentId);
    } else {
      await widget.firestoreService.deleteJournalComment(widget.docId, commentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
          )),
          Text('댓글', style: GoogleFonts.inter(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // 댓글 목록
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: StreamBuilder<List<Comment>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4ADE80)),
                  ));
                }
                final comments = snap.data ?? [];
                if (comments.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('첫 댓글을 남겨보세요',
                        style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 13))),
                  );
                }
                final visible = comments.where((c) => !_blockedUids.contains(c.uid)).toList();
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('첫 댓글을 남겨보세요',
                        style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 13))),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (context, i) => Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
                  itemBuilder: (_, i) {
                    final c = visible[i];
                    final isOwn = widget.auth.user?.uid == c.uid;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                          child: Text(c.nickname.isNotEmpty ? c.nickname[0].toUpperCase() : '?',
                              style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(c.nickname, style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 6),
                            Text(DateFormat('MM.dd HH:mm').format(c.createdAt),
                                style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 11)),
                          ]),
                          const SizedBox(height: 4),
                          Text(c.content, style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13, height: 1.5)),
                        ])),
                        if (isOwn)
                          GestureDetector(
                            onTap: () => _delete(c.id),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, top: 2),
                              child: Icon(Icons.close, size: 14, color: cs.onSurface.withValues(alpha: 0.25)),
                            ),
                          )
                        else if (widget.auth.isLoggedIn)
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, size: 16, color: cs.onSurface.withValues(alpha: 0.25)),
                            padding: EdgeInsets.zero,
                            color: cs.surface,
                            onSelected: (v) {
                              if (v == 'report') _handleReport(c);
                              if (v == 'block') _handleBlock(c);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'report',
                                child: Row(children: [
                                  const Icon(Icons.flag_outlined, size: 15, color: Colors.orangeAccent),
                                  const SizedBox(width: 8),
                                  Text('신고하기', style: GoogleFonts.inter(fontSize: 13)),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'block',
                                child: Row(children: [
                                  const Icon(Icons.block, size: 15, color: Colors.redAccent),
                                  const SizedBox(width: 8),
                                  Text('차단하기', style: GoogleFonts.inter(fontSize: 13)),
                                ]),
                              ),
                            ],
                          ),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          // 입력창
          if (widget.auth.isLoggedIn)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLines: 1,
                  style: GoogleFonts.inter(color: cs.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '댓글을 입력해주세요',
                    hintStyle: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.3), fontSize: 13),
                    filled: true,
                    fillColor: cs.onSurface.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _sending
                  ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4ADE80)))
                  : GestureDetector(
                      onTap: _submit,
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
                        child: const Icon(Icons.send, size: 16, color: Colors.black),
                      ),
                    ),
            ])
          else
            Text('댓글을 작성하려면 로그인이 필요합니다.',
                style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.35), fontSize: 12)),
        ],
      ),
    );
  }
}
