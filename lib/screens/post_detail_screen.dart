import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../utils/dialogs.dart';
import '../widgets/user_level_avatar.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  final bool isOwn;
  final bool isLiked;
  final int likeCount;
  final void Function(bool nowLiked)? onLikeChanged;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;
  final Future<bool> Function()? onBlock;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.isOwn,
    required this.isLiked,
    required this.likeCount,
    this.onLikeChanged,
    this.onDelete,
    this.onReport,
    this.onBlock,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _firestoreService = FirestoreService();
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _liked = false;
  bool _likeLoading = false;
  int _likeCount = 0;
  bool _sending = false;
  String _nickname = '익명';
  final Set<String> _blockedCommentUids = {};
  late final Stream<List<Comment>> _commentStream;

  @override
  void initState() {
    super.initState();
    _liked = widget.isLiked;
    _likeCount = widget.likeCount;
    _commentStream = _firestoreService.getPostComments(widget.post.id);
    AnalyticsService.instance.logScreenView('post_detail');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        final results = await Future.wait([
          _firestoreService.getNickname(auth.user!.uid),
          _firestoreService.getBlockedUids(auth.user!.uid),
        ]);
        if (mounted) {
          setState(() {
            _nickname = (results[0] as String?) ?? '익명';
            _blockedCommentUids.addAll(results[1] as List<String>);
          });
        }
      }
    });
  }

  Future<void> _reportComment(Comment c) async {
    final reason = await showReportReasonDialog(context);
    if (reason == null || !mounted) return;
    final auth = context.read<AuthProvider>();
    AnalyticsService.instance.logReportContent('comment');
    await _firestoreService.reportContent(
      reporterUid: auth.user!.uid,
      targetUid: c.uid,
      contentType: 'comment',
      contentId: c.id,
      reason: reason,
    );
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
  }

  Future<void> _blockFromComment(Comment c) async {
    final ok = await showBlockConfirmDialog(context, c.nickname);
    if (ok != true || !mounted) return;
    final auth = context.read<AuthProvider>();
    AnalyticsService.instance.logBlockUser();
    await _firestoreService.blockUser(auth.user!.uid, c.uid);
    if (mounted) setState(() => _blockedCommentUids.add(c.uid));
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || _likeLoading) return;
    setState(() => _likeLoading = true);
    try {
      final nowLiked = await _firestoreService.likePost(
        widget.post.id,
        auth.user!.uid,
      );
      AnalyticsService.instance.logLikeContent('post');
      if (mounted) {
        setState(() {
          _liked = nowLiked;
          _likeCount += nowLiked ? 1 : -1;
        });
        // 목록 화면 상태 동기화 (Firestore 재호출 없이)
        widget.onLikeChanged?.call(nowLiked);
      }
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    final auth = context.read<AuthProvider>();
    if (text.isEmpty || !auth.isLoggedIn) return;
    final focusScope = FocusScope.of(context);
    setState(() => _sending = true);
    try {
      await _firestoreService.addPostComment(
        widget.post.id,
        Comment(
          id: '',
          uid: auth.user!.uid,
          nickname: _nickname,
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      AnalyticsService.instance.logWriteCommunityComment('post');
      _commentCtrl.clear();
      focusScope.unfocus();
      // 댓글 작성 후 맨 아래로 스크롤
      await Future.delayed(const Duration(milliseconds: 200));
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showImageFullscreen(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
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
    await _firestoreService.deletePostComment(widget.post.id, commentId);
  }

  Future<void> _confirmDelete() async {
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
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true && widget.onDelete != null) {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '자유게시판',
            style: GoogleFonts.inter(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
          actions: [
            if (widget.isOwn && widget.onDelete != null)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                onPressed: _confirmDelete,
              )
            else if (!widget.isOwn &&
                (widget.onReport != null || widget.onBlock != null))
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                color: cs.surface,
                onSelected: (v) async {
                  if (v == 'report') await widget.onReport?.call();
                  if (v == 'block') {
                    final blocked = await widget.onBlock?.call();
                    if (blocked == true && context.mounted)
                      Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => [
                  if (widget.onReport != null)
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
                          Text('신고하기', style: GoogleFonts.inter(fontSize: 14)),
                        ],
                      ),
                    ),
                  if (widget.onBlock != null)
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.block,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 8),
                          Text('차단하기', style: GoogleFonts.inter(fontSize: 14)),
                        ],
                      ),
                    ),
                ],
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              height: 1,
              color: cs.onSurface.withValues(alpha: 0.07),
            ),
          ),
        ),
        body: Column(
          children: [
            // ── 본문 + 댓글 목록 ──
            Expanded(
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  // 게시글 본문
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 제목
                          Text(
                            widget.post.title,
                            style: GoogleFonts.inter(
                              color: cs.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          // 작성자 + 날짜
                          Row(
                            children: [
                              UserLevelAvatar(
                                uid: widget.post.uid,
                                radius: 14,
                                backgroundColor: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.16),
                                textStyle: GoogleFonts.inter(
                                  color: const Color(0xFF10B981),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.post.nickname,
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                DateFormat(
                                  'yyyy.MM.dd HH:mm',
                                ).format(widget.post.createdAt),
                                style: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.3),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Divider(
                            color: cs.onSurface.withValues(alpha: 0.07),
                            height: 1,
                          ),
                          const SizedBox(height: 20),
                          // 본문 (마크다운 렌더링)
                          if (widget.post.content.isNotEmpty)
                            MarkdownBody(
                              data: widget.post.content,
                              sizedImageBuilder: (config) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: GestureDetector(
                                  onTap: () => _showImageFullscreen(
                                    context,
                                    config.uri.toString(),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: config.uri.toString(),
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => Container(
                                        height: 180,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.05,
                                        ),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF10B981),
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, _, _) =>
                                          const SizedBox(),
                                    ),
                                  ),
                                ),
                              ),
                              styleSheet: MarkdownStyleSheet(
                                p: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.9),
                                  fontSize: 16,
                                  height: 1.8,
                                ),
                                strong: GoogleFonts.inter(
                                  color: cs.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.8,
                                ),
                                em: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.9),
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  height: 1.8,
                                ),
                                del: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  fontSize: 16,
                                  decoration: TextDecoration.lineThrough,
                                  height: 1.8,
                                ),
                                listBullet: GoogleFonts.inter(
                                  color: cs.onSurface.withValues(alpha: 0.9),
                                  fontSize: 16,
                                  height: 1.8,
                                ),
                              ),
                              shrinkWrap: true,
                              softLineBreak: true,
                            ),
                          // 첨부 이미지
                          if (widget.post.imageUrls.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ...widget.post.imageUrls.map(
                              (url) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: GestureDetector(
                                  onTap: () =>
                                      _showImageFullscreen(context, url),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: url,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => Container(
                                        height: 180,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.05,
                                        ),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF10B981),
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, _, _) => Container(
                                        height: 100,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.05,
                                        ),
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              _LikeRow(
                                isLiked: _liked,
                                count: _likeCount,
                                onTap: _toggleLike,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Divider(
                            color: cs.onSurface.withValues(alpha: 0.07),
                            height: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 댓글 목록
                  StreamBuilder<List<Comment>>(
                    stream: _commentStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        );
                      }
                      final comments = (snap.data ?? [])
                          .where((c) => !_blockedCommentUids.contains(c.uid))
                          .toList();
                      final commentCount = comments.length;
                      if (snap.connectionState != ConnectionState.waiting) {
                        return SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  8,
                                ),
                                child: Text(
                                  '댓글 $commentCount',
                                  style: GoogleFonts.inter(
                                    color: cs.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            if (comments.isEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 40,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '첫 댓글을 남겨보세요',
                                      style: GoogleFonts.inter(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.3,
                                        ),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliverList(
                                delegate: SliverChildBuilderDelegate((_, i) {
                                  final c = comments[i];
                                  final isOwn = auth.user?.uid == c.uid;
                                  return _CommentTile(
                                    comment: c,
                                    isOwn: isOwn,
                                    onDelete: () => _deleteComment(c.id),
                                    onReport: (!isOwn && auth.isLoggedIn)
                                        ? () => _reportComment(c)
                                        : null,
                                    onBlock: (!isOwn && auth.isLoggedIn)
                                        ? () => _blockFromComment(c)
                                        : null,
                                  );
                                }, childCount: comments.length),
                              ),
                          ],
                        );
                      }
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
            // ── 댓글 입력창 ──
            _CommentInput(
              controller: _commentCtrl,
              auth: auth,
              sending: _sending,
              onSubmit: _submitComment,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 좋아요 행 ──────────────────────────────────────────────────────────────────

class _LikeRow extends StatelessWidget {
  final bool isLiked;
  final int count;
  final VoidCallback? onTap;

  const _LikeRow({required this.isLiked, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: isLiked
                  ? Colors.redAccent
                  : cs.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: GoogleFonts.robotoMono(
                color: isLiked
                    ? Colors.redAccent
                    : cs.onSurface.withValues(alpha: 0.4),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 댓글 타일 ──────────────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isOwn;
  final VoidCallback onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  const _CommentTile({
    required this.comment,
    required this.isOwn,
    required this.onDelete,
    this.onReport,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserLevelAvatar(
            uid: comment.uid,
            radius: 15,
            backgroundColor: cs.onSurface.withValues(alpha: 0.07),
            textStyle: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 12,
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
                      comment.nickname,
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('MM.dd HH:mm').format(comment.createdAt),
                      style: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  comment.content,
                  style: GoogleFonts.inter(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          if (isOwn)
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.2),
                ),
              ),
            )
          else if (onReport != null || onBlock != null)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.25),
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
                          size: 15,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 8),
                        Text('신고하기', style: GoogleFonts.inter(fontSize: 14)),
                      ],
                    ),
                  ),
                if (onBlock != null)
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
                        Text('차단하기', style: GoogleFonts.inter(fontSize: 14)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── 댓글 입력창 ────────────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final AuthProvider auth;
  final bool sending;
  final VoidCallback onSubmit;

  const _CommentInput({
    required this.controller,
    required this.auth,
    required this.sending,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : Colors.white,
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.07)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        (bottomPad > 0 ? bottomPad : safeBottom) + 10,
      ),
      child: auth.isLoggedIn
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.inter(color: cs.onSurface, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '댓글을 입력해주세요',
                      hintStyle: GoogleFonts.inter(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        fontSize: 15,
                      ),
                      filled: true,
                      fillColor: cs.onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                sending
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: onSubmit,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '댓글을 작성하려면 로그인이 필요합니다',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 13,
                ),
              ),
            ),
    );
  }
}
