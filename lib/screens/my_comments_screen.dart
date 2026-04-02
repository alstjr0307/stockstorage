import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/post.dart';
import '../models/stock_pick.dart';
import '../services/firestore_service.dart';
import 'post_detail_screen.dart';
import 'stock_detail_screen.dart';

class MyCommentsScreen extends StatefulWidget {
  final String uid;
  const MyCommentsScreen({super.key, required this.uid});

  @override
  State<MyCommentsScreen> createState() => _MyCommentsScreenState();
}

class _MyCommentsScreenState extends State<MyCommentsScreen>
    with SingleTickerProviderStateMixin {
  final _fs = FirestoreService();
  late final TabController _tabController;
  late Future<List<({StockPick? pick, String text, DateTime createdAt})>>
  _stockCommentsFuture;
  late Future<List<({Post? post, String text, DateTime createdAt})>>
  _communityCommentsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _stockCommentsFuture = _loadStockComments();
    _communityCommentsFuture = _loadCommunityComments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<({StockPick? pick, String text, DateTime createdAt})>>
  _loadStockComments() async {
    final comments = await _fs.getMyStockPickComments(widget.uid);
    final pickCache = <String, StockPick?>{};
    for (final c in comments) {
      if (!pickCache.containsKey(c.pickId)) {
        pickCache[c.pickId] = await _fs.getStockPickOnce(c.pickId);
      }
    }
    return comments
        .map(
          (c) =>
              (pick: pickCache[c.pickId], text: c.text, createdAt: c.createdAt),
        )
        .toList();
  }

  Future<List<({Post? post, String text, DateTime createdAt})>>
  _loadCommunityComments() async {
    final comments = await _fs.getMyPostComments(widget.uid);
    final postCache = <String, Post?>{};
    for (final c in comments) {
      if (!postCache.containsKey(c.postId)) {
        postCache[c.postId] = await _fs.getPostOnce(c.postId);
      }
    }
    return comments
        .map(
          (c) =>
              (post: postCache[c.postId], text: c.text, createdAt: c.createdAt),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '내 댓글',
          style: GoogleFonts.inter(
            color: cs.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4ADE80),
          labelColor: const Color(0xFF4ADE80),
          unselectedLabelColor: cs.onSurface.withValues(alpha: 0.4),
          labelStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: '추천주 댓글'),
            Tab(text: '커뮤니티 댓글'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FutureBuilder<List<({StockPick? pick, String text, DateTime createdAt})>>(
            future: _stockCommentsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4ADE80),
                  ),
                );
              }
              if (snap.hasError) {
                return _ErrorView(isDark: isDark);
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return _EmptyView(
                  icon: Icons.chat_bubble_outline,
                  text: '작성한 추천주 댓글이 없습니다',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final pick = item.pick;
                  return _CommentCard(
                    title: pick != null ? '${pick.name}  ${pick.ticker}' : '삭제된 종목',
                    titleAccent: pick != null,
                    createdAt: item.createdAt,
                    text: item.text,
                    deletedLabel: pick == null,
                    onTap: pick == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StockDetailScreen(pick: pick),
                              ),
                            ),
                  );
                },
              );
            },
          ),
          FutureBuilder<List<({Post? post, String text, DateTime createdAt})>>(
            future: _communityCommentsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4ADE80),
                  ),
                );
              }
              if (snap.hasError) {
                return _ErrorView(isDark: isDark);
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return _EmptyView(
                  icon: Icons.forum_outlined,
                  text: '작성한 커뮤니티 댓글이 없습니다',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final post = item.post;
                  return _CommentCard(
                    title: post?.title ?? '삭제된 게시글',
                    titleAccent: false,
                    createdAt: item.createdAt,
                    text: item.text,
                    deletedLabel: post == null,
                    onTap: post == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PostDetailScreen(
                                  post: post,
                                  isOwn: post.uid == widget.uid,
                                  isLiked: false,
                                  likeCount: post.likes,
                                  onDelete: post.uid == widget.uid
                                      ? () => _fs.deletePost(post.id)
                                      : null,
                                ),
                              ),
                            ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.title,
    required this.titleAccent,
    required this.createdAt,
    required this.text,
    required this.deletedLabel,
    this.onTap,
  });

  final String title;
  final bool titleAccent;
  final DateTime createdAt;
  final String text;
  final bool deletedLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2035) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: deletedLabel
                        ? cs.onSurface.withValues(alpha: 0.2)
                        : const Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      color: deletedLabel
                          ? cs.onSurface.withValues(alpha: 0.35)
                          : titleAccent
                              ? const Color(0xFF4ADE80)
                              : cs.onSurface.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  DateFormat('MM/dd HH:mm').format(createdAt),
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: cs.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        '불러오기 실패',
        style: GoogleFonts.inter(
          color: isDark ? Colors.white54 : cs.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
