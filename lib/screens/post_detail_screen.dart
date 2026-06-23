import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import 'write_post_screen.dart';
import '../services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../utils/dialogs.dart';
import '../utils/link_utils.dart';
import '../widgets/user_level_avatar.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  final bool isOwn;
  final bool isLiked;
  final int likeCount;
  final void Function(bool nowLiked)? onLikeChanged;
  final Future<void> Function()? onDelete;
  final VoidCallback? onEdited;
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
    this.onEdited,
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
  // 댓글 정렬 — true=최신순, false=오래된순(스트림 기본).
  bool _commentSortNewestFirst = false;

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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다')));
    }
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

  /// 본인 댓글 수정. 빈 본문이거나 변경 없으면 무시.
  /// 성공 시 true 반환 → 타일이 편집 모드를 닫는다.
  Future<bool> _editComment(Comment original, String newContent) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.user!.uid != original.uid) return false;
    final trimmed = newContent.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == original.content.trim()) return true;
    try {
      await _firestoreService.updatePostComment(
        widget.post.id,
        original.id,
        auth.user!.uid,
        trimmed,
      );
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('수정 실패: $e')));
      }
      return false;
    }
  }

  Future<void> _togglePostCommentNotification(bool enabled) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    await _firestoreService.setPostCommentNotificationEnabled(
      auth.user!.uid,
      widget.post.id,
      enabled,
    );
  }

  Future<void> _togglePostAuthorFollow(bool enabled) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.user!.uid == widget.post.uid) return;
    await _firestoreService.setPostAuthorFollowEnabled(
      auth.user!.uid,
      widget.post.uid,
      enabled,
    );
  }

  Future<void> _openEdit() async {
    final edited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WritePostScreen(
          uid: widget.post.uid,
          nickname: widget.post.nickname,
          editingPost: widget.post,
        ),
      ),
    );
    if (edited == true && mounted) {
      widget.onEdited?.call();
      Navigator.pop(context, true);
    }
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pageBg = theme.scaffoldBackgroundColor;
    final auth = context.watch<AuthProvider>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '자유게시판',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
          actions: [
            if (auth.isLoggedIn && auth.user!.uid == widget.post.uid)
              IconButton(
                icon: StreamBuilder<bool>(
                  stream: _firestoreService.watchPostCommentNotificationEnabled(
                    auth.user!.uid,
                    widget.post.id,
                  ),
                  builder: (context, snap) {
                    final enabled = snap.data ?? true;
                    return Icon(
                      enabled
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    );
                  },
                ),
                onPressed: () async {
                  final current = await _firestoreService
                      .getPostCommentNotificationEnabled(
                        auth.user!.uid,
                        widget.post.id,
                      );
                  await _togglePostCommentNotification(!current);
                },
              ),
            if (widget.isOwn ||
                widget.onDelete != null ||
                (!widget.isOwn &&
                    (widget.onReport != null || widget.onBlock != null)))
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                color: cs.surface,
                onSelected: (v) async {
                  if (v == 'edit') await _openEdit();
                  if (v == 'delete') await _confirmDelete();
                  if (v == 'report') await widget.onReport?.call();
                  if (v == 'block') {
                    final blocked = await widget.onBlock?.call();
                    if (blocked == true && context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (widget.isOwn)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('수정하기', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  if (widget.onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '삭제하기',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                          Text('신고하기', style: TextStyle(fontSize: 14)),
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
                          Text('차단하기', style: TextStyle(fontSize: 14)),
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
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 제목
                          Text(
                            widget.post.title,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // 작성자 카드 — 댓글 가독성 패턴과 통일:
                          // 아바타 → (닉네임 + 날짜를 stacked) → 팔로우 버튼
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              UserLevelAvatar(
                                uid: widget.post.uid,
                                levelOverride: widget.post.authorLevel,
                                radius: 18,
                                backgroundColor: cs.onSurface.withValues(
                                  alpha: 0.08,
                                ),
                                textStyle: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.62),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.post.nickname,
                                      style: TextStyle(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      DateFormat(
                                        'yyyy.MM.dd HH:mm',
                                      ).format(widget.post.createdAt),
                                      style: TextStyle(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.42,
                                        ),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (auth.isLoggedIn &&
                                  auth.user!.uid != widget.post.uid) ...[
                                const SizedBox(width: 8),
                                StreamBuilder<bool>(
                                  stream: _firestoreService
                                      .watchPostAuthorFollowEnabled(
                                        auth.user!.uid,
                                        widget.post.uid,
                                      ),
                                  builder: (context, snap) {
                                    final enabled = snap.data ?? false;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () =>
                                          _togglePostAuthorFollow(!enabled),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 140),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: enabled
                                              ? const Color(
                                                  0xFF10B981,
                                                ).withValues(alpha: 0.14)
                                              : cs.onSurface.withValues(
                                                  alpha: 0.05,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: enabled
                                                ? const Color(0xFF10B981)
                                                : cs.onSurface.withValues(
                                                    alpha: 0.12,
                                                  ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              enabled
                                                  ? Icons.check
                                                  : Icons.person_add_alt_1,
                                              size: 12,
                                              color: enabled
                                                  ? const Color(0xFF10B981)
                                                  : cs.onSurface.withValues(
                                                      alpha: 0.62,
                                                    ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              enabled ? '팔로우중' : '팔로우',
                                              style: TextStyle(
                                                color: enabled
                                                    ? const Color(0xFF10B981)
                                                    : cs.onSurface.withValues(
                                                        alpha: 0.72,
                                                      ),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),
                          Divider(
                            color: cs.onSurface.withValues(alpha: 0.08),
                            height: 1,
                          ),
                          const SizedBox(height: 20),
                          // 본문 (마크다운 렌더링)
                          if (widget.post.content.isNotEmpty)
                            MarkdownBody(
                              data: widget.post.content,
                              onTapLink: (text, href, title) {
                                if (href != null) openExternalUrl(href);
                              },
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
                                p: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.9),
                                  fontSize: 16,
                                  height: 1.8,
                                ),
                                strong: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.8,
                                ),
                                em: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.9),
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  height: 1.8,
                                ),
                                del: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  fontSize: 16,
                                  decoration: TextDecoration.lineThrough,
                                  height: 1.8,
                                ),
                                listBullet: TextStyle(
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
                          // 본문 영역 종료 신호 — 본문과 좋아요/댓글 사이에 시각 분리.
                          Divider(
                            color: cs.onSurface.withValues(alpha: 0.08),
                            height: 1,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _LikeRow(
                                isLiked: _liked,
                                count: _likeCount,
                                onTap: _toggleLike,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
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
                      final raw = (snap.data ?? [])
                          .where((c) => !_blockedCommentUids.contains(c.uid))
                          .toList();
                      // 스트림 기본은 오래된순(asc) — 토글 시 reverse만 한다.
                      final comments = _commentSortNewestFirst
                          ? raw.reversed.toList()
                          : raw;
                      final commentCount = comments.length;
                      if (snap.connectionState != ConnectionState.waiting) {
                        return SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  12,
                                  14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    bottom: BorderSide(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '댓글',
                                      style: TextStyle(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$commentCount',
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () => setState(
                                        () => _commentSortNewestFirst =
                                            !_commentSortNewestFirst,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _commentSortNewestFirst
                                                  ? '최신순'
                                                  : '오래된순',
                                              style: TextStyle(
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.6,
                                                ),
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 16,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
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
                                      style: TextStyle(
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
                                  final isAdmin = AuthService.adminUids.contains(auth.user?.uid ?? '');
                                  return _CommentTile(
                                    comment: c,
                                    isOwn: isOwn,
                                    isAdmin: isAdmin,
                                    onDelete: () => _deleteComment(c.id),
                                    onEdit: isOwn
                                        ? (newContent) =>
                                              _editComment(c, newContent)
                                        : null,
                                    onReport: (!isOwn && !isAdmin && auth.isLoggedIn)
                                        ? () => _reportComment(c)
                                        : null,
                                    onBlock: (!isOwn && !isAdmin && auth.isLoggedIn)
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isLiked ? Colors.redAccent : cs.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: isLiked ? 0.12 : (isDark ? 0.14 : 0.08),
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent.withValues(alpha: isLiked ? 0.28 : 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              size: 17,
              color: isLiked
                  ? Colors.redAccent
                  : cs.onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: isLiked
                    ? Colors.redAccent
                    : cs.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 댓글 타일 ──────────────────────────────────────────────────────────────────

class _CommentTile extends StatefulWidget {
  final Comment comment;
  final bool isOwn;
  final bool isAdmin;
  final VoidCallback onDelete;
  // 새 본문을 받아 저장 성공 시 true 반환. true면 편집 모드 종료.
  final Future<bool> Function(String newContent)? onEdit;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  const _CommentTile({
    required this.comment,
    required this.isOwn,
    required this.isAdmin,
    required this.onDelete,
    this.onEdit,
    this.onReport,
    this.onBlock,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _editing = false;
  bool _saving = false;
  TextEditingController? _editCtrl;

  Comment get comment => widget.comment;
  bool get isOwn => widget.isOwn;
  bool get isAdmin => widget.isAdmin;
  VoidCallback get onDelete => widget.onDelete;
  Future<bool> Function(String)? get onEdit => widget.onEdit;
  VoidCallback? get onReport => widget.onReport;
  VoidCallback? get onBlock => widget.onBlock;

  @override
  void dispose() {
    _editCtrl?.dispose();
    super.dispose();
  }

  void _enterEdit() {
    setState(() {
      _editing = true;
      _editCtrl = TextEditingController(text: comment.content);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editCtrl?.dispose();
      _editCtrl = null;
    });
  }

  Future<void> _saveEdit() async {
    final handler = onEdit;
    final ctrl = _editCtrl;
    if (handler == null || ctrl == null || _saving) return;
    setState(() => _saving = true);
    final ok = await handler(ctrl.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _editing = false;
        _editCtrl?.dispose();
        _editCtrl = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 가독성 우선: 닉네임 → 본문 → 날짜/액션 순서로 시선이 흐르도록.
    // 닉네임을 본문보다 굵게/뚜렷이, 날짜는 본문 아래로 내려 메타로 분리한다.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserLevelAvatar(
            uid: comment.uid,
            radius: 14,
            backgroundColor: cs.onSurface.withValues(alpha: 0.07),
            textStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.nickname,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.92),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 6),
                if (_editing)
                  _buildEditField(cs)
                else
                  LinkifiedText(
                    comment.content,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.88),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                if (!_editing) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        DateFormat('MM.dd HH:mm').format(comment.createdAt),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (comment.editedAt != null) ...[
                        Text(
                          ' · 수정됨',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!_editing) _buildTrailingMenu(cs),
        ],
      ),
    );
  }

  Widget _buildEditField(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: _editCtrl,
          autofocus: true,
          enabled: !_saving,
          minLines: 1,
          maxLines: 6,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.9),
            fontSize: 15,
            height: 1.55,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: cs.onSurface.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF10B981),
                width: 1.2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _saving ? null : _cancelEdit,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '취소',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _saving ? null : _saveEdit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '저장',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrailingMenu(ColorScheme cs) {
    final canEdit = isOwn && onEdit != null;
    final canDelete = isOwn || isAdmin;
    if (!canDelete && onReport == null && onBlock == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 16,
        color: cs.onSurface.withValues(alpha: 0.25),
      ),
      padding: EdgeInsets.zero,
      color: cs.surface,
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _enterEdit();
            break;
          case 'delete':
            onDelete();
            break;
          case 'report':
            onReport?.call();
            break;
          case 'block':
            onBlock?.call();
            break;
        }
      },
      itemBuilder: (_) => [
        if (canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 15, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('수정', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('삭제', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        if (onReport != null)
          const PopupMenuItem(
            value: 'report',
            child: Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 15,
                  color: Colors.orangeAccent,
                ),
                SizedBox(width: 8),
                Text('신고하기', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        if (onBlock != null)
          const PopupMenuItem(
            value: 'block',
            child: Row(
              children: [
                Icon(Icons.block, size: 15, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('차단하기', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
      ],
    );
  }
}

// ── 댓글 입력창 ────────────────────────────────────────────────────────────────

class _CommentInput extends StatefulWidget {
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
  State<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends State<_CommentInput> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // 본문 영역과 시각적 분리 — 기존 0.07은 다크에서 거의 안 보임.
    final dividerAlpha = isDark ? 0.16 : 0.12;
    final canSend = _hasText && !widget.sending;

    return Container(
      decoration: BoxDecoration(
        color: pageBg,
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: dividerAlpha)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        (bottomPad > 0 ? bottomPad : safeBottom) + 10,
      ),
      child: widget.auth.isLoggedIn
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(color: cs.onSurface, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '댓글을 입력해주세요',
                      hintStyle: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        fontSize: 15,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? cs.surface.withValues(alpha: 0.65)
                          : Colors.white.withValues(alpha: 0.92),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
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
                widget.sending
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
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: canSend
                              ? const Color(0xFF10B981)
                              : cs.onSurface.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: canSend
                                ? Colors.white
                                : cs.onSurface.withValues(alpha: 0.45),
                          ),
                          onPressed: canSend ? widget.onSubmit : null,
                        ),
                      ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '댓글을 작성하려면 로그인이 필요합니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 13,
                ),
              ),
            ),
    );
  }
}
