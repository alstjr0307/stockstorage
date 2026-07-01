import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ad_service.dart';
import '../services/firestore_service.dart';
import '../services/subscription_service.dart';
import '../utils/link_utils.dart';
import '../widgets/user_level_avatar.dart';
import 'my_comments_screen.dart';
import 'my_posts_screen.dart';
import 'portfolio_screen.dart';
import 'subscription_screen.dart';

// 내 프로필 (전체 화면). 카드 대신 플랫·편집형 레이아웃 — 헤더 + 통계 + 행 메뉴.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.auth});

  final AuthProvider auth;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _accent = Color(0xFF10B981);
  static const _gold = Color(0xFFE7B43E);

  final FirestoreService _firestoreService = FirestoreService();
  bool _rewardAdLoading = false;

  AuthProvider get _auth => widget.auth;
  String get _uid => _auth.user!.uid;

  // ─── 팔레트 ────────────────────────────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF7F9FC);
  Color get _label => _isDark ? const Color(0xFFF1F4F9) : const Color(0xFF141A24);
  Color get _muted => _isDark ? Colors.white60 : Colors.black54;
  Color get _faint => _isDark ? Colors.white30 : Colors.black38;
  Color get _hair => _isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.06);

  // ─── 리워드 광고 ──────────────────────────────────────────────────────────
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndWatchRewardAd() async {
    if (_rewardAdLoading) return;
    final shouldWatch = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('리워드 광고 안내',
            style: TextStyle(fontWeight: FontWeight.w800)),
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
            child: const Text('광고 보기',
                style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (shouldWatch == true) await _watchRewardAdAndClaimXp();
  }

  Future<void> _watchRewardAdAndClaimXp() async {
    if (_rewardAdLoading) return;
    setState(() => _rewardAdLoading = true);
    try {
      final earnedReward =
          await AdService.instance.showRewardedAdAndWaitReward();
      if (!mounted) return;
      if (!earnedReward) {
        _snack('광고 시청이 완료되지 않아 XP가 지급되지 않았어요.');
        return;
      }
      final granted = await _firestoreService.grantDailyRewardAdXp(_uid);
      if (!mounted) return;
      _snack(granted
          ? '리워드 지급 완료! 경험치 +5'
          : '오늘 리워드 광고 보상은 3회 모두 받았어요.');
    } catch (_) {
      if (!mounted) return;
      _snack('리워드 광고를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _rewardAdLoading = false);
    }
  }

  // ─── 다이얼로그 ───────────────────────────────────────────────────────────
  void _editNickname(String? current) {
    showDialog<void>(
      context: context,
      builder: (_) => _NicknameChangeDialog(
        uid: _uid,
        initialNickname: current ?? '',
        firestoreService: _firestoreService,
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1A2035) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('계정 삭제',
            style: TextStyle(color: _label, fontWeight: FontWeight.w700)),
        content: Text(
          '계정을 삭제하면 모든 데이터(관심 추천주, 메모, 댓글 등)가 영구적으로 삭제됩니다.\n\n정말 삭제하시겠습니까?',
          style: TextStyle(color: _muted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: _faint)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _auth.deleteAccount();
                if (mounted) Navigator.pop(context);
              } on Exception catch (e) {
                _snack('삭제 실패: $e');
              }
            },
            child: const Text('삭제',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  String _joinedText() {
    final dt = _auth.user?.metadata.creationTime?.toLocal();
    if (dt == null) return '';
    return '${dt.year}년 ${dt.month}월 가입';
  }

  // ─── 빌드 ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: _label),
        actions: [
          Consumer<ThemeProvider>(
            builder: (_, theme, _) => IconButton(
              tooltip: theme.isDark ? '라이트 모드' : '다크 모드',
              onPressed: theme.toggle,
              icon: Icon(
                theme.isDark
                    ? Icons.wb_sunny_outlined
                    : Icons.dark_mode_outlined,
                color: _muted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<SubscriptionService>(
        builder: (context, subscription, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 36),
          children: [
            _buildHeader(subscription),
            const SizedBox(height: 26),
            _buildStatsRow(),
            const SizedBox(height: 26),
            _buildMembership(subscription),
            const SizedBox(height: 26),
            _buildGroup('활동', [
              _row(
                icon: Icons.favorite_border_rounded,
                label: '관심 추천주',
                onTap: () => _push(const FavoritesPicksScreen()),
              ),
              _row(
                icon: Icons.article_outlined,
                label: '내가 쓴 글',
                onTap: () => _push(MyPostsScreen(uid: _uid)),
              ),
              _row(
                icon: Icons.chat_bubble_outline_rounded,
                label: '내 댓글',
                onTap: () => _push(MyCommentsScreen(uid: _uid)),
              ),
            ]),
            const SizedBox(height: 22),
            _buildGroup('설정', [
              Consumer<ThemeProvider>(
                builder: (_, theme, _) => _row(
                  icon: theme.isDark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  label: '다크 모드',
                  onTap: theme.toggle,
                  trailing: Switch.adaptive(
                    value: theme.isDark,
                    onChanged: (_) => theme.toggle(),
                    activeThumbColor: _accent,
                  ),
                ),
              ),
              _row(
                icon: Icons.description_outlined,
                label: '이용약관 (EULA)',
                onTap: () => openExternalUrl(kTermsOfUseUrl),
              ),
              _row(
                icon: Icons.privacy_tip_outlined,
                label: '개인정보처리방침',
                onTap: () => openExternalUrl(kPrivacyPolicyUrl),
              ),
              _row(
                icon: Icons.logout_rounded,
                label: '로그아웃',
                labelColor: Colors.redAccent,
                iconColor: Colors.redAccent,
                onTap: () {
                  Navigator.pop(context);
                  _auth.signOut();
                },
              ),
            ]),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: _confirmDeleteAccount,
                style: TextButton.styleFrom(foregroundColor: _faint),
                child: const Text('계정 삭제',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 헤더: 아바타(+프리미엄 왕관/링) · 닉네임 · 레벨/가입일 · XP
  Widget _buildHeader(SubscriptionService subscription) {
    final premium = subscription.isPremium;
    return StreamBuilder<Map<String, int>>(
      stream: _firestoreService.watchUserLevelInfo(_uid),
      builder: (context, snap) {
        final stats = snap.data ??
            const {
              'level': 1,
              'postCount': 0,
              'commentCount': 0,
              'attendanceCount': 0,
              'bonusXp': 0,
            };
        final level = stats['level'] ?? 1;
        final progressInfo = _firestoreService.calculateLevelProgress(
          postCount: stats['postCount'] ?? 0,
          commentCount: stats['commentCount'] ?? 0,
          attendanceCount: stats['attendanceCount'] ?? 0,
          bonusXp: stats['bonusXp'] ?? 0,
        );
        final currentXp = (progressInfo['currentXpInLevel'] ?? 0).toInt();
        final needXp = (progressInfo['xpForNextLevel'] ?? 1).toInt();
        final remainXp = (progressInfo['remainingXp'] ?? 0).toInt();
        final progress = (progressInfo['progress'] ?? 0).toDouble();

        final joined = _joinedText();
        final metaParts = [
          'Lv.$level',
          if (joined.isNotEmpty) joined,
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              _PremiumAvatar(
                uid: _uid,
                premium: premium,
                backgroundColor:
                    _isDark ? const Color(0xFF1B2434) : const Color(0xFFEAF0F7),
                gold: _gold,
              ),
              const SizedBox(height: 16),
              // 닉네임 + 수정
              FutureBuilder<String?>(
                future: _firestoreService.getNickname(_uid),
                builder: (ctx, nickSnap) {
                  final nickname = nickSnap.data;
                  return GestureDetector(
                    onTap: () => _editNickname(nickname),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            nickname ?? '닉네임 설정하기',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _label,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Icon(Icons.edit_outlined, size: 16, color: _faint),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                metaParts.join('  ·  '),
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              // XP 진행 — 얇은 라인
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: _hair,
                        valueColor: const AlwaysStoppedAnimation(_accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$currentXp/$needXp',
                    style: TextStyle(
                      color: _faint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '다음 레벨까지 $remainXp XP',
                  style: TextStyle(color: _faint, fontSize: 11.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 통계: 글·일지 / 댓글 / 출석 (박스 없이 인라인 + 세로 헤어라인)
  Widget _buildStatsRow() {
    return StreamBuilder<Map<String, int>>(
      stream: _firestoreService.watchUserLevelInfo(_uid),
      builder: (context, snap) {
        final stats = snap.data ?? const {};
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              _statCell('글·일지', stats['postCount'] ?? 0),
              _statDivider(),
              _statCell('댓글', stats['commentCount'] ?? 0),
              _statDivider(),
              _statCell('출석', stats['attendanceCount'] ?? 0),
            ],
          ),
        );
      },
    );
  }

  Widget _statCell(String label, int value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: _label,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 30, color: _hair);

  // 멤버십 — 프리미엄이면 골드 톤, 아니면 구독 유도 + 리워드 광고
  Widget _buildMembership(SubscriptionService subscription) {
    if (subscription.isPremium) {
      return _buildGroup('멤버십', [
        _row(
          icon: Icons.workspace_premium_rounded,
          iconColor: _gold,
          label: '프리미엄 회원',
          labelColor: _gold,
          subtitle: '광고 제거 이용 중',
          onTap: () => _push(const SubscriptionScreen()),
        ),
      ]);
    }
    return _buildGroup('멤버십', [
      _row(
        icon: Icons.workspace_premium_outlined,
        iconColor: _gold,
        label: '프리미엄 구독',
        subtitle: '광고 제거 · AI 분석 추가 혜택',
        onTap: () => _push(const SubscriptionScreen()),
      ),
      _buildRewardAdRow(),
    ]);
  }

  Widget _buildRewardAdRow() {
    return StreamBuilder<Map<String, int>>(
      stream: _firestoreService.watchRewardAdStatus(_uid),
      builder: (context, snap) {
        final status = snap.data;
        final canWatch = (status?['canWatchToday'] ?? 1) == 1;
        final remaining = status?['remainingCount'] ?? 3;
        final limit = status?['dailyLimit'] ?? 3;
        return _row(
          icon: Icons.ondemand_video_outlined,
          label: '광고 보고 +5 XP',
          subtitle: '오늘 $remaining/$limit회 남음',
          onTap: canWatch && !_rewardAdLoading ? _confirmAndWatchRewardAd : null,
          trailing: _rewardAdLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: canWatch
                        ? _accent.withValues(alpha: 0.14)
                        : _hair,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    canWatch ? '시청' : '완료',
                    style: TextStyle(
                      color: canWatch ? _accent : _faint,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
        );
      },
    );
  }

  // ─── 공통 위젯 ────────────────────────────────────────────────────────────
  Widget _buildGroup(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
          child: Text(
            title,
            style: TextStyle(
              color: _faint,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 60),
              child: Container(height: 1, color: _hair),
            ),
        ],
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? labelColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 21, color: iconColor ?? _muted),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: labelColor ?? _label,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: _faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// 프리미엄이면 골드 링 + 글로우 + 왕관, 아니면 레벨 아바타만.
class _PremiumAvatar extends StatelessWidget {
  const _PremiumAvatar({
    required this.uid,
    required this.premium,
    required this.backgroundColor,
    required this.gold,
  });

  final String uid;
  final bool premium;
  final Color backgroundColor;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final core = UserLevelAvatar(
      uid: uid,
      radius: 38,
      backgroundColor: backgroundColor,
      textStyle: const TextStyle(fontSize: 28),
    );

    if (!premium) return core;

    // 크라운이 위로 떠도 ListView가 클리핑하지 않도록 음수 오프셋 없이
    // 스택 상단 안쪽(top: 0)에 배치하고 아바타는 하단 정렬.
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 2.4),
              boxShadow: [
                BoxShadow(
                  color: gold.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: core,
          ),
          Positioned(
            top: 0,
            child: Transform.rotate(
              angle: -0.12,
              child: CustomPaint(
                size: const Size(30, 20),
                painter: PremiumCrownPainter(gold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 닉네임 변경 다이얼로그
class _NicknameChangeDialog extends StatefulWidget {
  const _NicknameChangeDialog({
    required this.uid,
    required this.initialNickname,
    required this.firestoreService,
  });
  final String uid;
  final String initialNickname;
  final FirestoreService firestoreService;

  @override
  State<_NicknameChangeDialog> createState() => _NicknameChangeDialogState();
}

class _NicknameChangeDialogState extends State<_NicknameChangeDialog> {
  late final TextEditingController _ctrl;
  String? _errorMsg;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nick = _ctrl.text.trim();
    if (nick.length < 2 || nick.length > 12) {
      setState(() => _errorMsg = '닉네임은 2~12자여야 합니다');
      return;
    }
    setState(() => _checking = true);
    final taken =
        await widget.firestoreService.isNicknameTaken(nick, widget.uid);
    if (!mounted) return;
    if (taken) {
      setState(() {
        _errorMsg = '이미 사용 중인 닉네임입니다';
        _checking = false;
      });
      return;
    }
    try {
      await widget.firestoreService.setNickname(widget.uid, nick);
      if (mounted) Navigator.pop(context);
    } on NicknameTakenException {
      if (!mounted) return;
      setState(() {
        _errorMsg = '방금 다른 사용자에게 점유되었어요. 다른 닉네임을 시도해주세요';
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = '저장에 실패했어요. 잠시 후 다시 시도해주세요';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            controller: _ctrl,
            enabled: !_checking,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
              errorText: _errorMsg,
            ),
            onChanged: (_) {
              if (_errorMsg != null) setState(() => _errorMsg = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.pop(context),
          child: Text(
            '취소',
            style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.black,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _checking ? null : _save,
          child: _checking
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black),
                )
              : const Text('저장',
                  style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
