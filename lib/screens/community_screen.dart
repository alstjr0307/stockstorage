import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/trading_journal.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../services/stock_price_service.dart';
import '../utils/dialogs.dart';
import '../widgets/user_level_avatar.dart';
import 'journal_chart_screen.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              labelStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.45),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(9999),
              ),
              tabs: const [
                Tab(text: '자유게시판'),
                Tab(text: '매매일지 공유'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [_FreeBoardTab(), _JournalTab()],
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
  final _searchController = TextEditingController();
  final Set<String> _likedIds = {};
  final Set<String> _loadingLikes = {};
  final Set<String> _blockedUids = {};
  final Map<String, int> _likeCountOverride = {};
  final Map<String, int> _commentCountByJournalId = {};

  final List<TradingJournal> _journals = [];
  String _searchQuery = '';
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  bool _searchLoading = false;
  int _searchTargetCount = 0;

  static const _pageSize = 15;
  static const _searchChunkSize = 1000;

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
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
  }

  Future<void> _handleBlock(TradingJournal journal, String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('차단'),
        content: Text('${journal.nickname} 님을 차단하시겠습니까?\n차단된 유저의 글은 보이지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('차단', style: TextStyle(color: Colors.redAccent)),
          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('차단되었습니다')));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<TradingJournal> _filteredJournals() {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _journals;
    return _journals.where((j) {
      final stock = j.stockName.toLowerCase();
      final ticker = j.ticker.toLowerCase();
      return stock.contains(q) || ticker.contains(q);
    }).toList();
  }

  Future<void> _loadMoreForSearchIfNeeded() async {
    if (_searchLoading) return;
    if (_searchQuery.trim().isEmpty || !_hasMore) return;
    if (_searchTargetCount <= _journals.length) {
      _searchTargetCount = _journals.length + _searchChunkSize;
    }

    setState(() => _searchLoading = true);
    try {
      while (mounted) {
        final currentQ = _searchQuery.trim().toLowerCase();
        if (currentQ.isEmpty || !_hasMore) break;
        if (_journals.length >= _searchTargetCount) break;

        if (_loading) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          continue;
        }

        final beforeCursor = _lastDoc?.id;
        await _loadMore();
        final afterCursor = _lastDoc?.id;
        if (beforeCursor == afterCursor) break;
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
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
      // 차단된 유저 제외 (매수/매도/기타 모두 공유)
      final filtered = items
          .where((j) => !_blockedUids.contains(j.uid))
          .toList();
      // 댓글 수 조회
      final journalsNeedingCount = filtered
          .where((j) => !_commentCountByJournalId.containsKey(j.id))
          .toList();
      if (journalsNeedingCount.isNotEmpty) {
        final counts = await Future.wait(
          journalsNeedingCount.map(
            (j) => _firestoreService.getJournalCommentCount(j.id),
          ),
        );
        for (var i = 0; i < journalsNeedingCount.length; i++) {
          _commentCountByJournalId[journalsNeedingCount[i].id] = counts[i];
        }
      }
      // 로그인 유저의 좋아요 상태 병렬 조회
      if (auth.isLoggedIn && filtered.isNotEmpty) {
        final liked = await Future.wait(
          filtered.map(
            (j) => _firestoreService.hasLikedJournal(j.id, auth.user!.uid),
          ),
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
    setState(() {
      _journals.clear();
      _lastDoc = null;
      _hasMore = true;
      _commentCountByJournalId.clear();
      _searchTargetCount = 0;
    });
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

  void _openAuthorJournals(TradingJournal journal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _AuthorJournalsScreen(uid: journal.uid, nickname: journal.nickname),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredJournals();
    final isSearching = _searchQuery.trim().isNotEmpty;
    final showDefaultPagingLoader = _hasMore && !isSearching;
    final canLoadMoreSearchResults =
        isSearching &&
        _hasMore &&
        !_searchLoading &&
        _journals.length >= _searchTargetCount &&
        _searchTargetCount > 0;
    final showSearchMoreButton = canLoadMoreSearchResults;
    final tailCount =
        (showDefaultPagingLoader ? 1 : 0) +
        (_searchLoading ? 1 : 0) +
        (showSearchMoreButton ? 1 : 0);

    if (_loading && _journals.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF10B981)),
      );
    }

    if (!_loading && _journals.isEmpty) {
      return _EmptyState(
        icon: Icons.trending_up_rounded,
        title: '공유된 매매일지가 없습니다',
        subtitle: '매매일지에서 매매 기록을 공유해보세요',
        onRefresh: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF10B981),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: 1 + filtered.length + tailCount,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchController,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onChanged: (v) {
                  final wasEmpty = _searchQuery.trim().isEmpty;
                  setState(() {
                    _searchQuery = v;
                    if (v.trim().isEmpty) {
                      _searchTargetCount = 0;
                    } else if (wasEmpty) {
                      _searchTargetCount = _journals.length + _searchChunkSize;
                    }
                  });
                  _loadMoreForSearchIfNeeded();
                },
                style: GoogleFonts.inter(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '종목명/티커 검색',
                  hintStyle: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.38),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _searchTargetCount = 0;
                            });
                          },
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.35),
                          ),
                        ),
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF10B981),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            );
          }

          if (filtered.isEmpty) {
            if (_searchLoading) {
              return const Padding(
                padding: EdgeInsets.only(top: 36),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF10B981),
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  '검색 결과가 없습니다',
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.45),
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }

          final tailIndex = i - (1 + filtered.length);
          var currentTail = 0;

          if (showDefaultPagingLoader && tailIndex == currentTail) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF10B981),
                  strokeWidth: 2,
                ),
              ),
            );
          }
          if (showDefaultPagingLoader) currentTail++;

          if (_searchLoading && tailIndex == currentTail) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF10B981),
                  strokeWidth: 2,
                ),
              ),
            );
          }
          if (_searchLoading) currentTail++;

          if (showSearchMoreButton && tailIndex == currentTail) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _searchTargetCount += _searchChunkSize;
                  });
                  _loadMoreForSearchIfNeeded();
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: BorderSide(color: cs.onSurface.withValues(alpha: 0.18)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '결과 더보기 (다음 1000개 검색)',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            );
          }

          final journal = filtered[i - 1];
          final isOwn = auth.user?.uid == journal.uid;
          final linkedSells = journal.action == '매수'
              ? _journals
                    .where(
                      (j) =>
                          j.uid == journal.uid &&
                          j.action == '매도' &&
                          j.linkedBuyId == journal.id,
                    )
                    .toList()
              : const <TradingJournal>[];
          final linkedBuy =
              journal.action == '매도' && journal.linkedBuyId.isNotEmpty
              ? _journals
                    .where(
                      (j) =>
                          j.uid == journal.uid &&
                          j.action == '매수' &&
                          j.id == journal.linkedBuyId,
                    )
                    .firstOrNull
              : null;
          return _JournalCard(
            key: ValueKey(journal.id),
            journal: journal,
            linkedSells: linkedSells,
            linkedBuy: linkedBuy,
            isOwn: isOwn,
            isLiked: _likedIds.contains(journal.id),
            isLoadingLike: _loadingLikes.contains(journal.id),
            likeCount: _likeCountOverride[journal.id] ?? journal.likes,
            commentCount: _commentCountByJournalId[journal.id] ?? 0,
            onLike: auth.isLoggedIn
                ? () => _toggleLike(journal, auth.user!.uid)
                : null,
            onTogglePrivate: isOwn
                ? () async {
                    await _firestoreService.toggleJournalPublic(
                      journal.id,
                      true,
                    );
                    if (mounted)
                      setState(
                        () => _journals.removeWhere((j) => j.id == journal.id),
                      );
                  }
                : null,
            onReport: (!isOwn && auth.isLoggedIn)
                ? () => _handleReport(journal, auth.user!.uid)
                : null,
            onBlock: (!isOwn && auth.isLoggedIn)
                ? () => _handleBlock(journal, auth.user!.uid)
                : null,
            onTapAuthor: () => _openAuthorJournals(journal),
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
  final Map<String, int> _commentCountByPostId = {};

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
      final filtered = items
          .where((p) => !_blockedUids.contains(p.uid))
          .toList();
      final postsNeedingCount = filtered
          .where((p) => !_commentCountByPostId.containsKey(p.id))
          .toList();
      if (postsNeedingCount.isNotEmpty) {
        final counts = await Future.wait(
          postsNeedingCount.map(
            (p) => _firestoreService.getPostCommentCount(p.id),
          ),
        );
        for (var i = 0; i < postsNeedingCount.length; i++) {
          _commentCountByPostId[postsNeedingCount[i].id] = counts[i];
        }
      }
      // 로그인 유저의 좋아요 상태 병렬 조회
      if (auth.isLoggedIn && filtered.isNotEmpty) {
        final liked = await Future.wait(
          filtered.map(
            (p) => _firestoreService.hasLikedPost(p.id, auth.user!.uid),
          ),
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
    setState(() {
      _posts.clear();
      _lastDoc = null;
      _hasMore = true;
      _commentCountByPostId.clear();
    });
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
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
  }

  Future<bool> _handleBlock(Post post, String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('차단'),
        content: Text('${post.nickname} 님을 차단하시겠습니까?\n차단된 유저의 글은 보이지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('차단', style: TextStyle(color: Colors.redAccent)),
          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('차단되었습니다')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다')));
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

    if (!auth.isLoggedIn) {
      return const _LoginGate();
    }

    if (_loading && _posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF10B981)),
      );
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
            color: const Color(0xFF10B981),
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 84),
              itemCount: _posts.length + (_hasMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _posts.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF10B981),
                        strokeWidth: 2,
                      ),
                    ),
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
                  commentCount: _commentCountByPostId[post.id] ?? 0,
                  onLike: auth.isLoggedIn
                      ? () => _toggleLike(post, auth.user!.uid)
                      : null,
                  onTap: () => _openPost(context, post, auth),
                  onReport: null,
                  onBlock: null,
                );
              },
            ),
          ),
        // 글쓰기 FAB
        Positioned(
          right: 20,
          bottom: 24,
          child: FloatingActionButton(
            heroTag: 'community_write_fab',
            onPressed: () => _openWrite(auth),
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            elevation: 3,
            child: const Icon(Icons.edit_rounded, size: 22),
          ),
        ),
      ],
    );
  }
}

// ── 로그인 게이트 ─────────────────────────────────────────────────────────────

class _LoginGate extends StatelessWidget {
  const _LoginGate();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 52,
            color: cs.onSurface.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          Text(
            '로그인 후 이용할 수 있습니다',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '커뮤니티는 로그인이 필요합니다',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
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
      color: const Color(0xFF10B981),
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Column(
            children: [
              Icon(icon, color: cs.onSurface.withValues(alpha: 0.18), size: 56),
              const SizedBox(height: 14),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.25),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 매매일지 카드 ─────────────────────────────────────────────────────────────

class _JournalCard extends StatefulWidget {
  final TradingJournal journal;
  final List<TradingJournal> linkedSells;
  final TradingJournal? linkedBuy;
  final bool isOwn;
  final bool isLiked;
  final bool isLoadingLike;
  final int likeCount;
  final int commentCount;
  final VoidCallback? onLike;
  final VoidCallback? onTogglePrivate;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  final VoidCallback? onTapAuthor;

  const _JournalCard({
    super.key,
    required this.journal,
    this.linkedSells = const [],
    this.linkedBuy,
    required this.isOwn,
    required this.isLiked,
    required this.isLoadingLike,
    required this.likeCount,
    required this.commentCount,
    required this.onLike,
    this.onTogglePrivate,
    this.onReport,
    this.onBlock,
    this.onTapAuthor,
  });

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard>
    with SingleTickerProviderStateMixin {
  PriceResult? _price;
  final _firestoreService = FirestoreService();
  static const Duration _newBadgeWindow = Duration(hours: 24);
  bool _openingChart = false;
  TradingJournal? _resolvedLinkedBuy;
  late final AnimationController _newBadgeController;
  late final Animation<double> _newBadgeOpacity;
  late final Animation<double> _newBadgeScale;

  @override
  void initState() {
    super.initState();
    _newBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _newBadgeOpacity = Tween<double>(
      begin: 0.58,
      end: 0.9,
    ).animate(
      CurvedAnimation(parent: _newBadgeController, curve: Curves.easeInOut),
    );
    _newBadgeScale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(
      CurvedAnimation(parent: _newBadgeController, curve: Curves.easeOut),
    );
    _resolvedLinkedBuy = widget.linkedBuy;
    _fetchPrice();
    _resolveLinkedBuy();
  }

  @override
  void dispose() {
    _newBadgeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _JournalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkedBuy?.id != widget.linkedBuy?.id) {
      _resolvedLinkedBuy = widget.linkedBuy;
    }
    if (widget.journal.action == '매도' &&
        oldWidget.journal.linkedBuyId != widget.journal.linkedBuyId) {
      _resolveLinkedBuy();
    }
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
    if (j.action != '매수') return;
    if (j.ticker.isEmpty || !{'KS', 'KQ', 'US'}.contains(j.market)) return;
    final result = await StockPriceService.fetchPrice(j.ticker, j.market);
    if (mounted) setState(() => _price = result);
  }

  Future<void> _resolveLinkedBuy() async {
    final j = widget.journal;
    if (j.action != '매도') return;
    if (_resolvedLinkedBuy != null) return;
    if (j.linkedBuyId.isEmpty) return;
    TradingJournal? linked;
    try {
      linked = await _firestoreService.getJournalById(j.linkedBuyId);
    } catch (_) {
      return;
    }
    if (!mounted || linked == null) return;
    if (linked.action != '매수') return;
    if (!linked.isPublic) return;
    setState(() => _resolvedLinkedBuy = linked);
  }

  bool _canOpenChart(TradingJournal journal) {
    if (journal.action == '매도') return true;
    final isMarketSupported =
        journal.ticker.isNotEmpty &&
        {'KS', 'KQ', 'US'}.contains(journal.market);
    if (!isMarketSupported) return false;
    if (journal.action == '매수') return true;
    return false;
  }

  DateTime _effectivePublishedAt(TradingJournal journal) =>
      journal.publishedAt ?? journal.createdAt;

  bool _isNewlyPublished(TradingJournal journal) {
    final diff = DateTime.now().difference(_effectivePublishedAt(journal));
    return !diff.isNegative && diff <= _newBadgeWindow;
  }

  Widget _buildNewBadge() {
    return FadeTransition(
      opacity: _newBadgeOpacity,
      child: ScaleTransition(
        scale: _newBadgeScale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            'NEW',
            style: GoogleFonts.inter(
              color: const Color(0xFFFFC857),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openChart() async {
    if (_openingChart) return;
    setState(() => _openingChart = true);
    try {
      final journal = widget.journal;
      TradingJournal? buy = journal.action == '매수' ? journal : null;
      List<TradingJournal> linkedSells = widget.linkedSells;
      var showBuyMarker = journal.action == '매수';
      final publicByAuthor = await _firestoreService.getPublicJournalsByUidOnce(
        journal.uid,
      );
      final relatedBuys = publicByAuthor
          .where(
            (j) =>
                j.action == '매수' &&
                j.ticker == journal.ticker &&
                j.market == journal.market,
          )
          .toList();
      final relatedSells = publicByAuthor
          .where(
            (j) =>
                j.action == '매도' &&
                j.ticker == journal.ticker &&
                j.market == journal.market,
          )
          .toList();

      if (journal.action == '매도') {
        buy = publicByAuthor
            .where((j) => j.id == journal.linkedBuyId && j.action == '매수')
            .firstOrNull;

        // linkedBuyId가 공개 목록에 없으면(비공개/예전 데이터) 단건 조회 시도
        if (buy == null && journal.linkedBuyId.isNotEmpty) {
          TradingJournal? linked;
          try {
            linked = await _firestoreService.getJournalById(
              journal.linkedBuyId,
            );
          } catch (_) {
            linked = null;
          }
          if (linked != null &&
              linked.action == '매수' &&
              linked.uid == journal.uid) {
            buy = linked;
            // linkedBuyId 단건 조회는 비공개 매수일 수 있으므로
            // 매수 정보 노출(showBuyMarker)은 켜지지 않게 유지한다.
          }
        }

        // 그래도 없으면 동일 종목의 최근 매수(매도일 이전)로 추정 연결
        if (buy == null) {
          final candidateBuys = publicByAuthor
              .where(
                (j) =>
                    j.action == '매수' &&
                    j.ticker == journal.ticker &&
                    j.market == journal.market &&
                    !j.tradeDate.isAfter(journal.tradeDate),
              )
              .toList();
          candidateBuys.sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
          buy = candidateBuys.firstOrNull;
        }

        // 마지막 폴백: 임시 매수 포지션 생성 (차트 진입 보장)
        buy ??= TradingJournal(
          id: 'synthetic_buy_${journal.id}',
          uid: journal.uid,
          nickname: journal.nickname,
          stockName: journal.stockName,
          ticker: journal.ticker,
          market: journal.market,
          action: '매수',
          price: journal.buyPrice > 0 ? journal.buyPrice : journal.price,
          quantity: journal.quantity,
          tradeDate: journal.tradeDate,
          note: '',
          isPublic: false,
          likes: 0,
          createdAt: journal.createdAt,
        );

        final buyId = buy.id;
        linkedSells = publicByAuthor
            .where(
              (j) =>
                  j.action == '매도' &&
                  (j.linkedBuyId == buyId ||
                      (journal.linkedBuyId.isNotEmpty &&
                          j.linkedBuyId == journal.linkedBuyId)),
            )
            .toList();
        if (!linkedSells.any((s) => s.id == journal.id)) {
          linkedSells = [...linkedSells, journal];
        }

        // 매도 카드에서는 "연결된 매수 일지"가 아니라
        // "같은 종목의 공개 매수 일지가 하나라도 있는지"를 기준으로 매수 표시를 결정.
        showBuyMarker = relatedBuys.isNotEmpty;
        if (showBuyMarker && !relatedBuys.any((b) => b.id == buy?.id)) {
          // 현재 기준 buy가 비공개/합성일 수 있으므로
          // 공개 매수 중 하나를 기준으로 바꿔서 비공개 매수가 노출되지 않게 한다.
          buy = relatedBuys.first;
        }
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JournalChartScreen(
            buy: buy!,
            linkedSells: linkedSells,
            relatedBuys: relatedBuys,
            relatedSells: relatedSells,
            showBuyMarker: showBuyMarker,
            firestoreService: _firestoreService,
            onEdit: () {},
            showEditButton: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final journal = widget.journal;
    final isNewlyPublished = _isNewlyPublished(journal);
    final isKrw = journal.market != 'US';
    final marketLabel = switch (journal.market) {
      'KS' => 'KOSPI',
      'KQ' => 'KOSDAQ',
      'US' => 'NASDAQ',
      _ => journal.market,
    };
    final tradeDateText = DateFormat('yyyy.MM.dd').format(journal.tradeDate);

    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';

    final qtyStr = journal.quantity > 0
        ? '${journal.quantity % 1 == 0 ? journal.quantity.toInt() : journal.quantity}주'
        : null;

    // 평가손익
    double? pnl, pnlPct;
    if (_price != null && journal.price > 0 && journal.quantity > 0) {
      pnl = (_price!.price - journal.price) * journal.quantity;
      pnlPct = (_price!.price - journal.price) / journal.price * 100;
    }
    final isPnlUp = pnl == null || pnl >= 0;
    const upColor = Color(0xFFF04452);
    const downColor = Color(0xFF1677FF);
    final currentPrice = _price?.price;
    final evalAmount = (currentPrice != null && journal.quantity > 0)
        ? currentPrice * journal.quantity
        : null;
    final pnlText = pnl != null ? '${isPnlUp ? '+' : ''}${fmtP(pnl)}' : '-';
    final pnlPctText = pnlPct != null
        ? '${isPnlUp ? '+' : ''}${pnlPct.toStringAsFixed(1)}%'
        : '-';
    final pnlColor = pnl != null
        ? (isPnlUp ? upColor : downColor)
        : cs.onSurface.withValues(alpha: 0.45);
    final currentColor = _price != null
        ? (_price!.isUp ? upColor : downColor)
        : cs.onSurface.withValues(alpha: 0.45);

    if (journal.action == '매도') {
      final sellCard = _buildSellCard(cs);
      if (!_canOpenChart(journal)) return sellCard;
      return GestureDetector(onTap: _openChart, child: sellCard);
    }

    // '기타' 간소화 카드
    if (journal.action == '기타') return _buildEtcCard(cs);

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 액센트 바
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF4D9BFF)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '거래일',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tradeDateText,
                      style: GoogleFonts.robotoMono(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '매수',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 1,
                  width: double.infinity,
                  color: cs.onSurface.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 10),
                // 작성자 행
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onTapAuthor,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            UserLevelAvatar(
                              uid: journal.uid,
                              radius: 14,
                              backgroundColor: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.12),
                              textStyle: GoogleFonts.inter(
                                color: const Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        journal.nickname,
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (widget.isOwn) ...[
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              9999,
                                            ),
                                          ),
                                          child: Text(
                                            '나',
                                            style: GoogleFonts.inter(
                                              color: const Color(0xFF10B981),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isNewlyPublished) ...[
                      const SizedBox(width: 8),
                      _buildNewBadge(),
                    ],
                    if (widget.onReport != null || widget.onBlock != null) ...[
                      const SizedBox(width: 4),
                      _MoreMenu(
                        onReport: widget.onReport,
                        onBlock: widget.onBlock,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                // 종목명
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        journal.stockName,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        marketLabel,
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 거래 정보 그리드 (3행 2열)
                if (journal.price > 0 || journal.quantity > 0)
                  Container(
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        // 1행: 매수가 | 현재가
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _gridCell(
                                  '매수가',
                                  journal.price > 0 ? fmtP(journal.price) : '-',
                                  cs,
                                ),
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: cs.onSurface.withValues(alpha: 0.07),
                              ),
                              Expanded(
                                child: _gridCell(
                                  '현재가',
                                  currentPrice != null
                                      ? fmtP(currentPrice)
                                      : '-',
                                  cs,
                                  valueColor: currentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.onSurface.withValues(alpha: 0.07),
                        ),
                        // 2행: 수량 | 평가금액
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _gridCell('수량', qtyStr ?? '-', cs),
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: cs.onSurface.withValues(alpha: 0.07),
                              ),
                              Expanded(
                                child: _gridCell(
                                  '평가금액',
                                  evalAmount != null ? fmtP(evalAmount) : '-',
                                  cs,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: cs.onSurface.withValues(alpha: 0.07),
                        ),
                        // 3행: 수익률 | 평가손익
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _gridCell(
                                  '수익률',
                                  pnlPctText,
                                  cs,
                                  valueColor: pnlColor,
                                ),
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: cs.onSurface.withValues(alpha: 0.07),
                              ),
                              Expanded(
                                child: _gridCell(
                                  '평가손익',
                                  pnlText,
                                  cs,
                                  valueColor: pnlColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                // 메모
                if (journal.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ExpandableNotePreview(
                    content: journal.note,
                    maxLines: 3,
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 하단: 좋아요 + 댓글 + 비공개 토글
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                _LikeButton(
                  isLiked: widget.isLiked,
                  isLoading: widget.isLoadingLike,
                  count: widget.likeCount,
                  onTap: widget.onLike,
                ),
                const SizedBox(width: 12),
                _CommentButton(
                  onTap: () => _openComments(context),
                  count: widget.commentCount,
                ),
                const Spacer(),
                if (widget.isOwn && widget.onTogglePrivate != null)
                  GestureDetector(
                    onTap: widget.onTogglePrivate,
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '비공개로 전환',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!_canOpenChart(journal)) return card;
    return GestureDetector(onTap: _openChart, child: card);
  }

  Widget _buildSellCard(ColorScheme cs) {
    final journal = widget.journal;
    final isNewlyPublished = _isNewlyPublished(journal);
    final isKrw = journal.market != 'US';
    final marketLabel = switch (journal.market) {
      'KS' => 'KOSPI',
      'KQ' => 'KOSDAQ',
      'US' => 'NASDAQ',
      _ => journal.market,
    };
    final tradeDateText = DateFormat('yyyy.MM.dd').format(journal.tradeDate);

    String fmtP(double p) => isKrw
        ? '₩${NumberFormat('#,###').format(p.toInt())}'
        : '\$${p.toStringAsFixed(2)}';

    final qtyStr = journal.quantity > 0
        ? '${journal.quantity % 1 == 0 ? journal.quantity.toInt() : journal.quantity}주'
        : '-';

    double? realizedPnl;
    double? realizedPct;
    if (journal.buyPrice > 0 && journal.price > 0 && journal.quantity > 0) {
      realizedPnl = (journal.price - journal.buyPrice) * journal.quantity;
      realizedPct = (journal.price - journal.buyPrice) / journal.buyPrice * 100;
    }
    final isUp = realizedPnl == null || realizedPnl >= 0;
    const upColor = Color(0xFFF04452);
    const downColor = Color(0xFF1677FF);
    final pnlColor = realizedPnl != null
        ? (isUp ? upColor : downColor)
        : cs.onSurface.withValues(alpha: 0.45);

    final pnlText = realizedPnl != null
        ? '${isUp ? '+' : ''}${fmtP(realizedPnl)}'
        : '-';
    final pctText = realizedPct != null
        ? '${isUp ? '+' : ''}${realizedPct.toStringAsFixed(1)}%'
        : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFEF4444)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '거래일',
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tradeDateText,
                      style: GoogleFonts.robotoMono(
                        color: cs.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '매도',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFF97316),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 1,
                  width: double.infinity,
                  color: cs.onSurface.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onTapAuthor,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            UserLevelAvatar(
                              uid: journal.uid,
                              radius: 14,
                              backgroundColor: const Color(
                                0xFFF97316,
                              ).withValues(alpha: 0.12),
                              textStyle: GoogleFonts.inter(
                                color: const Color(0xFFF97316),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        journal.nickname,
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (widget.isOwn) ...[
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              9999,
                                            ),
                                          ),
                                          child: Text(
                                            '나',
                                            style: GoogleFonts.inter(
                                              color: const Color(0xFF10B981),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isNewlyPublished) ...[
                      const SizedBox(width: 6),
                      _buildNewBadge(),
                    ],
                    if (widget.onReport != null || widget.onBlock != null) ...[
                      const SizedBox(width: 4),
                      _MoreMenu(
                        onReport: widget.onReport,
                        onBlock: widget.onBlock,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        journal.stockName,
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        marketLabel,
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _gridCell(
                                '매수가',
                                journal.buyPrice > 0
                                    ? fmtP(journal.buyPrice)
                                    : '-',
                                cs,
                              ),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: cs.onSurface.withValues(alpha: 0.07),
                            ),
                            Expanded(
                              child: _gridCell(
                                '매도가',
                                journal.price > 0 ? fmtP(journal.price) : '-',
                                cs,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: cs.onSurface.withValues(alpha: 0.07),
                      ),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _gridCell(
                                '매수일',
                                _resolvedLinkedBuy != null
                                    ? DateFormat(
                                        'yy.MM.dd',
                                      ).format(_resolvedLinkedBuy!.tradeDate)
                                    : '-',
                                cs,
                              ),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: cs.onSurface.withValues(alpha: 0.07),
                            ),
                            Expanded(child: _gridCell('수량', qtyStr, cs)),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: cs.onSurface.withValues(alpha: 0.07),
                      ),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _gridCell(
                                '수익률',
                                pctText,
                                cs,
                                valueColor: pnlColor,
                              ),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: cs.onSurface.withValues(alpha: 0.07),
                            ),
                            Expanded(
                              child: _gridCell(
                                '실현손익',
                                pnlText,
                                cs,
                                valueColor: pnlColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (journal.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ExpandableNotePreview(
                    content: journal.note,
                    maxLines: 3,
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                _LikeButton(
                  isLiked: widget.isLiked,
                  isLoading: widget.isLoadingLike,
                  count: widget.likeCount,
                  onTap: widget.onLike,
                ),
                const SizedBox(width: 12),
                _CommentButton(
                  onTap: () => _openComments(context),
                  count: widget.commentCount,
                ),
                const Spacer(),
                if (widget.isOwn && widget.onTogglePrivate != null)
                  GestureDetector(
                    onTap: widget.onTogglePrivate,
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '비공개로 전환',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtcCard(ColorScheme cs) {
    final journal = widget.journal;
    final isNewlyPublished = _isNewlyPublished(journal);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF94A3B8), Color(0xFF64748B)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 작성자 행
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onTapAuthor,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            UserLevelAvatar(
                              uid: journal.uid,
                              radius: 14,
                              backgroundColor: const Color(
                                0xFF94A3B8,
                              ).withValues(alpha: 0.12),
                              textStyle: GoogleFonts.inter(
                                color: const Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        journal.nickname,
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (widget.isOwn) ...[
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              9999,
                                            ),
                                          ),
                                          child: Text(
                                            '나',
                                            style: GoogleFonts.inter(
                                              color: const Color(0xFF10B981),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    DateFormat(
                                      'yyyy.MM.dd',
                                    ).format(journal.tradeDate),
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.35,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isNewlyPublished) ...[
                      const SizedBox(width: 8),
                      _buildNewBadge(),
                    ],
                    if (widget.onReport != null || widget.onBlock != null) ...[
                      const SizedBox(width: 4),
                      _MoreMenu(
                        onReport: widget.onReport,
                        onBlock: widget.onBlock,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                // 종목명
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        journal.stockName.isNotEmpty
                            ? journal.stockName
                            : '기타 메모',
                        style: GoogleFonts.inter(
                          color: cs.onSurface,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        '기타',
                        style: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                // 메모
                if (journal.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ExpandableNotePreview(
                    content: journal.note,
                    maxLines: 3,
                    style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.65),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                _LikeButton(
                  isLiked: widget.isLiked,
                  isLoading: widget.isLoadingLike,
                  count: widget.likeCount,
                  onTap: widget.onLike,
                ),
                const SizedBox(width: 12),
                _CommentButton(
                  onTap: () => _openComments(context),
                  count: widget.commentCount,
                ),
                const Spacer(),
                if (widget.isOwn && widget.onTogglePrivate != null)
                  GestureDetector(
                    onTap: widget.onTogglePrivate,
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '비공개로 전환',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridCell(
    String label,
    String value,
    ColorScheme cs, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.38),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.robotoMono(
              color: valueColor ?? cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── 게시글 카드 ───────────────────────────────────────────────────────────────

class _PostCard extends StatefulWidget {
  final Post post;
  final bool isOwn;
  final bool isLiked;
  final bool isLoadingLike;
  final int likeCount;
  final int commentCount;
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
    required this.commentCount,
    required this.onLike,
    required this.onTap,
    this.onReport,
    this.onBlock,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _expanded = false;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('MM.dd').format(dt);
  }

  static final _imgRegex = RegExp(r'!\[\]\(([^)]+)\)');

  /// content에서 이미지 URL 목록 추출
  List<String> _extractImageUrls(String content) =>
      _imgRegex.allMatches(content).map((m) => m.group(1)!).toList();

  /// content에서 이미지 마크다운 제거한 순수 텍스트
  String _stripImages(String content) => content
      .replaceAll(_imgRegex, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final post = widget.post;
    final imageUrls = _extractImageUrls(post.content);
    final textContent = _stripImages(post.content);

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ① 작성자 행
                Row(
                  children: [
                    UserLevelAvatar(
                      uid: post.uid,
                      radius: 20,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                      textStyle: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                post.nickname,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              if (AuthService.adminUids.contains(post.uid)) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 15,
                                  color: Color(0xFFFBBF24),
                                ),
                              ],
                              if (widget.isOwn) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  child: Text(
                                    '나',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF10B981),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _relativeTime(post.createdAt),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.38),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onReport != null || widget.onBlock != null)
                      _MoreMenu(
                        onReport: widget.onReport,
                        onBlock: widget.onBlock,
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // ② 제목
                Text(
                  post.title,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: cs.onSurface,
                  ),
                ),

                // ③ 본문 프리뷰 + 더 보기
                if (textContent.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (_expanded)
                    Text(
                      textContent,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: cs.onSurface.withValues(alpha: 0.6),
                        height: 1.6,
                      ),
                    )
                  else
                    _ContentPreview(
                      content: textContent,
                      onExpand: () => setState(() => _expanded = true),
                    ),
                ],

                // ④ 이미지 (content에서 파싱)
                if (imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Image.network(
                        imageUrls.first,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        errorBuilder: (context, e, s) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // ⑤ 인터랙션 바
                Row(
                  children: [
                    _LikeButton(
                      isLiked: widget.isLiked,
                      isLoading: widget.isLoadingLike,
                      count: widget.likeCount,
                      onTap: widget.onLike,
                    ),
                    const SizedBox(width: 18),
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.32),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.commentCount}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.onSurface.withValues(alpha: 0.07),
          ),
        ],
      ),
    );
  }
}

// ── 본문 더 보기 ──────────────────────────────────────────────────────────────

class _ContentPreview extends StatelessWidget {
  final String content;
  final VoidCallback onExpand;

  const _ContentPreview({required this.content, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = GoogleFonts.inter(
      fontSize: 15,
      color: cs.onSurface.withValues(alpha: 0.6),
      height: 1.6,
    );
    // 줄바꿈 포함 100자 초과 or 줄바꿈 4개 이상이면 overflow로 간주
    final looksLong =
        content.length > 100 || '\n'.allMatches(content).length >= 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          content,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        if (looksLong)
          GestureDetector(
            onTap: onExpand,
            child: Text(
              '더 보기',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF10B981),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandableNotePreview extends StatefulWidget {
  final String content;
  final TextStyle style;
  final int maxLines;

  const _ExpandableNotePreview({
    required this.content,
    required this.style,
    this.maxLines = 3,
  });

  @override
  State<_ExpandableNotePreview> createState() => _ExpandableNotePreviewState();
}

class _ExpandableNotePreviewState extends State<_ExpandableNotePreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.content, style: widget.style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final hasOverflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.content,
              style: widget.style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (hasOverflow && !_expanded) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Text(
                  '더보기',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
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

  const _LikeButton({
    required this.isLiked,
    required this.isLoading,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF10B981),
                    ),
                  )
                : Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 16,
                    color: isLiked
                        ? Colors.redAccent
                        : cs.onSurface.withValues(alpha: 0.3),
                  ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: GoogleFonts.inter(
                color: isLiked
                    ? Colors.redAccent
                    : cs.onSurface.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
      nickname =
          await widget.firestoreService.getNickname(widget.auth.user!.uid) ??
          '익명';
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
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 제목 + 삭제
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.post.title,
                    style: GoogleFonts.inter(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.isOwn && widget.onDelete != null)
                  IconButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('게시글 삭제'),
                          content: const Text('이 게시글을 삭제하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                '삭제',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await widget.onDelete!();
                    },
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 작성자 + 날짜
            Row(
              children: [
                UserLevelAvatar(
                  uid: widget.post.uid,
                  radius: 12,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                  textStyle: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.post.nickname,
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('yyyy.MM.dd HH:mm').format(widget.post.createdAt),
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.3),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: cs.onSurface.withValues(alpha: 0.07), height: 1),
            const SizedBox(height: 16),
            // 본문
            if (widget.post.content.isNotEmpty)
              Text(
                widget.post.content,
                style: GoogleFonts.inter(
                  color: cs.onSurface,
                  fontSize: 15,
                  height: 1.75,
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                _LikeButton(
                  isLiked: widget.isLiked,
                  isLoading: widget.isLoadingLike,
                  count: widget.post.likes,
                  onTap: widget.onLike,
                ),
                const SizedBox(width: 12),
                _CommentButton(onTap: _openComments),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 댓글 버튼 ─────────────────────────────────────────────────────────────────

class _CommentButton extends StatelessWidget {
  final VoidCallback? onTap;
  final int? count;
  const _CommentButton({required this.onTap, this.count});

  @override
  Widget build(BuildContext context) {
    final label = (count != null && count! > 0) ? '댓글 $count' : '댓글 달기';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_rounded,
              size: 13,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                color: const Color(0xFF10B981),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorJournalsScreen extends StatefulWidget {
  final String uid;
  final String nickname;
  const _AuthorJournalsScreen({required this.uid, required this.nickname});

  @override
  State<_AuthorJournalsScreen> createState() => _AuthorJournalsScreenState();
}

class _AuthorJournalsScreenState extends State<_AuthorJournalsScreen> {
  final _firestoreService = FirestoreService();
  final Map<String, int> _commentCountByJournalId = {};
  final Set<String> _commentCountLoading = {};
  final Set<String> _likedIds = {};
  final Set<String> _likedLoading = {};
  final Set<String> _likedLoaded = {};
  final Map<String, int> _likeCountOverride = {};
  String? _selectedStockKey;

  String _stockKeyOf(TradingJournal j) => '${j.market}|${j.ticker}';

  Future<void> _ensureCommentCounts(List<TradingJournal> journals) async {
    final targets = journals
        .where(
          (j) =>
              !_commentCountByJournalId.containsKey(j.id) &&
              !_commentCountLoading.contains(j.id),
        )
        .toList();
    if (targets.isEmpty) return;

    for (final j in targets) {
      _commentCountLoading.add(j.id);
    }
    final counts = await Future.wait(
      targets.map((j) => _firestoreService.getJournalCommentCount(j.id)),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < targets.length; i++) {
        _commentCountByJournalId[targets[i].id] = counts[i];
        _commentCountLoading.remove(targets[i].id);
      }
    });
  }

  Future<void> _ensureLikedState(
    List<TradingJournal> journals,
    String uid,
  ) async {
    final targets = journals
        .where((j) => !_likedLoaded.contains(j.id))
        .toList();
    if (targets.isEmpty) return;

    final liked = await Future.wait(
      targets.map((j) => _firestoreService.hasLikedJournal(j.id, uid)),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < targets.length; i++) {
        _likedLoaded.add(targets[i].id);
        if (liked[i]) _likedIds.add(targets[i].id);
      }
    });
  }

  Future<void> _toggleLike(TradingJournal journal, String uid) async {
    if (_likedLoading.contains(journal.id)) return;
    setState(() => _likedLoading.add(journal.id));
    try {
      final nowLiked = await _firestoreService.likeJournal(journal.id, uid);
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _likedLoading.remove(journal.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.nickname} \uB2D8\uC758 \uB9E4\uB9E4\uC77C\uC9C0',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: StreamBuilder<List<TradingJournal>>(
        stream: _firestoreService.getPublicJournalsByUid(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                '\uBAA9\uB85D\uC744 \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 14,
                ),
              ),
            );
          }

          final allAuthorJournals = snapshot.data ?? [];
          final stockCounts = <String, int>{};
          final stockLabels = <String, String>{};
          for (final j in allAuthorJournals) {
            if (j.ticker.isEmpty) continue;
            final key = _stockKeyOf(j);
            stockCounts[key] = (stockCounts[key] ?? 0) + 1;
            stockLabels[key] = j.stockName.isNotEmpty ? j.stockName : j.ticker;
          }

          final availableStockKeys = stockCounts.keys.toSet();
          final effectiveSelectedKey = _selectedStockKey != null &&
                  availableStockKeys.contains(_selectedStockKey)
              ? _selectedStockKey
              : null;

          if (_selectedStockKey != effectiveSelectedKey) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedStockKey = effectiveSelectedKey);
            });
          }

          final visibleJournals = effectiveSelectedKey == null
              ? allAuthorJournals
              : allAuthorJournals
                    .where((j) => _stockKeyOf(j) == effectiveSelectedKey)
                    .toList();

          if (visibleJournals.isEmpty) {
            return Center(
              child: Text(
                '\uACF5\uC720\uD55C \uB9E4\uB9E4\uC77C\uC9C0\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 14,
                ),
              ),
            );
          }

          _ensureCommentCounts(visibleJournals);
          if (auth.isLoggedIn) {
            _ensureLikedState(visibleJournals, auth.user!.uid);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            itemCount: visibleJournals.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final stockEntries = stockCounts.entries.toList()
                  ..sort((a, b) {
                    final countCmp = b.value.compareTo(a.value);
                    if (countCmp != 0) return countCmp;
                    final labelA = stockLabels[a.key] ?? a.key;
                    final labelB = stockLabels[b.key] ?? b.key;
                    return labelA.compareTo(labelB);
                  });
                final topStockEntries = stockEntries.take(8).toList();
                final summaryText = effectiveSelectedKey == null
                    ? '거래종목 ${stockCounts.length}개'
                    : '거래종목 1개';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
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
                                  '거래 종목',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  summaryText,
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface.withValues(alpha: 0.52),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (effectiveSelectedKey != null)
                            GestureDetector(
                              onTap: () {
                                setState(() => _selectedStockKey = null);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.onSurface.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: cs.onSurface.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Text(
                                  '전체 보기',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (topStockEntries.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          height: 1,
                          width: double.infinity,
                          color: cs.onSurface.withValues(alpha: 0.06),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildStockFilterChip(
                              label: '전체',
                              trailing: '${allAuthorJournals.length}건',
                              selected: effectiveSelectedKey == null,
                              cs: cs,
                              onTap: () {
                                setState(() => _selectedStockKey = null);
                              },
                            ),
                            ...topStockEntries.map((e) {
                              final label = stockLabels[e.key] ?? e.key;
                              return _buildStockFilterChip(
                                label: label,
                                trailing: '${e.value}건',
                                selected: effectiveSelectedKey == e.key,
                                cs: cs,
                                onTap: () {
                                  setState(() => _selectedStockKey = e.key);
                                },
                              );
                            }),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }

              final journal = visibleJournals[index - 1];
              final isOwn = auth.user?.uid == journal.uid;
              final linkedSells = journal.action == '매수'
                  ? allAuthorJournals
                        .where(
                          (j) =>
                              j.action == '\uB9E4\uB3C4' &&
                              j.linkedBuyId == journal.id,
                        )
                        .toList()
                  : const <TradingJournal>[];
              final linkedBuy =
                  journal.action == '매도' && journal.linkedBuyId.isNotEmpty
                  ? allAuthorJournals
                        .where(
                          (j) =>
                              j.uid == journal.uid &&
                              j.action == '매수' &&
                              j.id == journal.linkedBuyId,
                        )
                        .firstOrNull
                  : null;

              return _JournalCard(
                key: ValueKey('author_${journal.id}'),
                journal: journal,
                linkedSells: linkedSells,
                linkedBuy: linkedBuy,
                isOwn: isOwn,
                isLiked: _likedIds.contains(journal.id),
                isLoadingLike: _likedLoading.contains(journal.id),
                likeCount: _likeCountOverride[journal.id] ?? journal.likes,
                commentCount: _commentCountByJournalId[journal.id] ?? 0,
                onLike: auth.isLoggedIn
                    ? () => _toggleLike(journal, auth.user!.uid)
                    : null,
                onTogglePrivate: isOwn
                    ? () async {
                        await _firestoreService.toggleJournalPublic(
                          journal.id,
                          true,
                        );
                      }
                    : null,
                onTapAuthor: null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStockFilterChip({
    required String label,
    required String trailing,
    required bool selected,
    required ColorScheme cs,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.12)
              : cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF10B981).withValues(alpha: 0.26)
                : cs.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xFF047857)
                    : cs.onSurface.withValues(alpha: 0.76),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              trailing,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xFF059669).withValues(alpha: 0.88)
                    : cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  const _MoreMenu({this.onReport, this.onBlock});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: cs.onSurface.withValues(alpha: 0.3),
      ),
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
            child: Row(
              children: [
                const Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Text('신고하기', style: GoogleFonts.inter(fontSize: 13)),
              ],
            ),
          ),
        if (onBlock != null)
          PopupMenuItem(
            value: 'block',
            child: Row(
              children: [
                const Icon(Icons.block, size: 16, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text('차단하기', style: GoogleFonts.inter(fontSize: 13)),
              ],
            ),
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
      widget.firestoreService.getBlockedUids(widget.auth.user!.uid).then((
        uids,
      ) {
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
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
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
      AnalyticsService.instance.logWriteCommunityComment(
        widget.collection == 'posts' ? 'post' : 'journal',
      );
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String commentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('이 댓글을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (widget.collection == 'posts') {
      await widget.firestoreService.deletePostComment(widget.docId, commentId);
    } else {
      await widget.firestoreService.deleteJournalComment(
        widget.docId,
        commentId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.white;
    final sheetHeight = MediaQuery.of(context).size.height * 0.82;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return SizedBox(
      height: sheetHeight,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad + 16),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // 핸들
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '댓글',
              style: GoogleFonts.inter(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // 댓글 목록
            Expanded(
              child: StreamBuilder<List<Comment>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    );
                  }
                  final comments = snap.data ?? [];
                  if (comments.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '첫 댓글을 남겨보세요',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  final visible = comments
                      .where((c) => !_blockedUids.contains(c.uid))
                      .toList();
                  if (visible.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '첫 댓글을 남겨보세요',
                          style: GoogleFonts.inter(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    separatorBuilder: (context, i) => Divider(
                      height: 16,
                      thickness: 1,
                      color: cs.onSurface.withValues(alpha: 0.08),
                    ),
                    itemBuilder: (_, i) {
                      final c = visible[i];
                      final isOwn = widget.auth.user?.uid == c.uid;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserLevelAvatar(
                              uid: c.uid,
                              radius: 14,
                              backgroundColor: cs.onSurface.withValues(
                                alpha: 0.08,
                              ),
                              textStyle: GoogleFonts.inter(
                                color: cs.onSurface.withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        c.nickname,
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        DateFormat(
                                          'MM.dd HH:mm',
                                        ).format(c.createdAt),
                                        style: GoogleFonts.inter(
                                          color: cs.onSurface.withValues(
                                            alpha: 0.3,
                                          ),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.content,
                                    style: GoogleFonts.inter(
                                      color: cs.onSurface,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isOwn)
                              GestureDetector(
                                onTap: () => _delete(c.id),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 8,
                                    top: 2,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: cs.onSurface.withValues(alpha: 0.25),
                                  ),
                                ),
                              )
                            else if (widget.auth.isLoggedIn)
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 16,
                                  color: cs.onSurface.withValues(alpha: 0.25),
                                ),
                                padding: EdgeInsets.zero,
                                color: cs.surface,
                                onSelected: (v) {
                                  if (v == 'report') _handleReport(c);
                                  if (v == 'block') _handleBlock(c);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'report',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.flag_outlined,
                                          size: 15,
                                          color: Colors.orangeAccent,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '신고하기',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'block',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.block,
                                          size: 15,
                                          color: Colors.redAccent,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '차단하기',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLines: 1,
                      style: GoogleFonts.inter(
                        color: cs.onSurface,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: '댓글을 입력해주세요',
                        hintStyle: GoogleFonts.inter(
                          color: cs.onSurface.withValues(alpha: 0.3),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: cs.onSurface.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF10B981),
                          ),
                        )
                      : GestureDetector(
                          onTap: _submit,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                ],
              )
            else
              Text(
                '댓글을 작성하려면 로그인이 필요합니다.',
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
