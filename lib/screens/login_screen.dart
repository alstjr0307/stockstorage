import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.fromOnboarding = false});

  final bool fromOnboarding;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  final _firestoreService = FirestoreService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: !widget.fromOnboarding,
        leading: widget.fromOnboarding
            ? null
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: cs.onSurface,
                  size: 18,
                ),
                onPressed: () => Navigator.pop(context),
              ),
        actions: widget.fromOnboarding
            ? [
                TextButton(
                  onPressed: _skipToHome,
                  child: Text(
                    '건너뛰기',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // 시스템 폰트 크기를 크게 설정한 단말에서도 콘텐츠가 잘리지 않도록
          // 스크롤 가능하게 하고, 키보드가 올라오면 그만큼 추가 패딩.
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  _isLogin ? '로그인' : '회원가입',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '주식저장소의 모든 서비스를 이용해보세요',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.38),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),
                _buildField('이메일', _emailController, hint: 'email@example.com'),
                const SizedBox(height: 14),
                _buildField(
                  '비밀번호',
                  _passwordController,
                  hint: '••••••••',
                  isPassword: true,
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 14),
                  _buildField(
                    '닉네임',
                    _nicknameController,
                    hint: '댓글에 표시될 닉네임 (2~12자)',
                    validator: _validateNicknameFormat,
                  ),
                ],
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _showResetPasswordDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '비밀번호를 잊으셨나요?',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.54),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : Text(
                            _isLogin ? '로그인' : '회원가입',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: cs.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '또는',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.24),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: cs.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 구글 로그인 (Google 브랜드 가이드라인 준수)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFDADCE0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Google "G" 로고 (4색)
                        const _GoogleLogo(size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Google로 로그인',
                          style: TextStyle(
                            color: const Color(0xFF3C4043),
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 카카오 로그인 (카카오 브랜드 가이드라인 준수)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF191919),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: _isLoading ? null : _signInWithKakao,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 카카오 말풍선 아이콘
                        const _KakaoLogo(size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '카카오로 로그인',
                          style: TextStyle(
                            color: const Color(0xFF191919),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Apple 로그인 (Apple 브랜드 가이드라인 준수)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: _isLoading ? null : _signInWithApple,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.apple, size: 22, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Apple로 로그인',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _isLogin = !_isLogin;
                      _nicknameController.clear();
                    }),
                    child: Text(
                      _isLogin ? '계정이 없으신가요? 회원가입' : '이미 계정이 있으신가요? 로그인',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? hint,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.54),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          style: TextStyle(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.24)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF10B981),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          validator: validator ?? (val) =>
              val == null || val.isEmpty ? '$label을 입력하세요' : null,
        ),
      ],
    );
  }

  /// 인증/네트워크 예외를 사용자 친화 문구로 변환.
  /// Firebase Auth 에러 코드 + 자체 throw 문구 + 사용자 취소 케이스 처리.
  String _friendlyAuthError(Object error) {
    if (error is NicknameTakenException) {
      return '이미 사용 중인 닉네임이에요. 다른 닉네임을 선택해주세요.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return '이메일 형식이 올바르지 않아요.';
        case 'user-disabled':
          return '사용이 중단된 계정이에요. 고객센터에 문의해주세요.';
        case 'user-not-found':
          return '가입되지 않은 이메일이에요. 회원가입을 진행해주세요.';
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return '이메일 또는 비밀번호가 올바르지 않아요.';
        case 'email-already-in-use':
          return '이미 가입된 이메일이에요. 로그인을 시도해보세요.';
        case 'weak-password':
          return '비밀번호는 6자 이상으로 설정해주세요.';
        case 'too-many-requests':
          return '잠시 후 다시 시도해주세요. 너무 자주 시도하면 임시로 차단돼요.';
        case 'network-request-failed':
          return '인터넷 연결을 확인하고 다시 시도해주세요.';
        case 'operation-not-allowed':
          return '현재 이 로그인 방식은 사용할 수 없어요.';
        case 'account-exists-with-different-credential':
          return '같은 이메일로 다른 방식의 계정이 있어요. 기존 방식으로 로그인해주세요.';
        case 'requires-recent-login':
          return '보안을 위해 다시 로그인해주세요.';
        case 'expired-action-code':
        case 'invalid-action-code':
          return '인증 링크가 만료됐어요. 다시 요청해주세요.';
        default:
          return error.message ?? '로그인 중 문제가 발생했어요. 잠시 후 다시 시도해주세요.';
      }
    }
    final raw = error.toString();
    // 사용자가 소셜 로그인 창을 직접 닫은 경우 — 알림 노이즈 줄이기.
    final lower = raw.toLowerCase();
    if (lower.contains('cancel') ||
        lower.contains('aborted') ||
        lower.contains('user closed')) {
      return '로그인을 취소했어요.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout')) {
      return '인터넷 연결을 확인하고 다시 시도해주세요.';
    }
    // 카카오 로그인 실패: 메시지 일반화.
    if (raw.contains('카카오 로그인 실패')) {
      return '카카오 로그인에 실패했어요. 잠시 후 다시 시도해주세요.';
    }
    return '로그인 중 문제가 발생했어요. 잠시 후 다시 시도해주세요.';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE53E3E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfo(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 닉네임 형식 검증 — 2~12자, 공백 양 끝 trim.
  String? _validateNicknameFormat(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '닉네임을 입력하세요';
    if (v.length < 2) return '닉네임은 2자 이상이어야 합니다';
    if (v.length > 12) return '닉네임은 12자 이하여야 합니다';
    return null;
  }

  void _onAuthSuccess() {
    if (widget.fromOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _skipToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final user = await context.read<AuthProvider>().signInWithGoogle();
      if (user != null && mounted) {
        final ok = await _ensureNickname(user.uid);
        if (!ok) return;
      }
      if (mounted) _onAuthSuccess();
    } catch (e) {
      _showError(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final user = await context.read<AuthProvider>().signInWithApple();
      if (user != null && mounted) {
        final ok = await _ensureNickname(user.uid);
        if (!ok) return;
      }
      if (mounted) _onAuthSuccess();
    } catch (e) {
      _showError(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithKakao() async {
    setState(() => _isLoading = true);
    try {
      final user = await context.read<AuthProvider>().signInWithKakao();
      if (user != null && mounted) {
        final ok = await _ensureNickname(user.uid);
        if (!ok) return;
      }
      if (mounted) _onAuthSuccess();
    } catch (e) {
      _showError(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final initial = _emailController.text.trim();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => _ResetPasswordDialog(initialEmail: initial),
    );
    if (email == null || email.isEmpty || !mounted) return;
    try {
      await context.read<AuthProvider>().sendPasswordResetEmail(email);
      _showInfo('$email 로 재설정 메일을 보냈어요. 받은편지함을 확인해주세요.');
    } catch (e) {
      _showError(_friendlyAuthError(e));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      if (_isLogin) {
        await auth.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
        if (mounted) _onAuthSuccess();
      } else {
        // 회원가입은 닉네임 중복을 먼저 확인. Firebase Auth 계정만 만들어진 채로
        // 닉네임 충돌이 일어나면 사용자가 어디로도 못 가는 상태가 되므로.
        final nickname = _nicknameController.text.trim();
        // 임시 uid가 없으므로 빈 문자열로 체크 (자기 자신 검사 무력화).
        final taken = await _firestoreService.isNicknameTaken(nickname, '');
        if (taken) {
          _showError('이미 사용 중인 닉네임이에요. 다른 닉네임을 선택해주세요.');
          return;
        }
        final user = await auth.signUp(
          _emailController.text.trim(),
          _passwordController.text,
        );
        if (user != null) {
          try {
            await _firestoreService.setNickname(user.uid, nickname);
          } on NicknameTakenException {
            // 가입과 setNickname 사이 race로 점유당한 경우 — 안내 후 재입력 유도.
            _showInfo(
              '방금 다른 사용자가 닉네임을 차지했어요. 홈에서 다른 닉네임으로 설정해주세요.',
              color: const Color(0xFFF59E0B),
            );
          }
        }
        if (mounted) _onAuthSuccess();
      }
    } catch (e) {
      _showError(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 닉네임이 설정될 때까지 다이얼로그를 반복해서 띄운다.
  // 백 버튼 등으로 닫혀도 닉네임 없는 유저가 홈에 도달하는 일이 없도록 한다.
  // 반환값: true면 닉네임 보장됨(또는 이미 있음), false면 unmount 등으로 중단.
  Future<bool> _ensureNickname(String uid) async {
    while (true) {
      if (!mounted) return false;
      final existing = await _firestoreService.getNickname(uid);
      if (existing != null && existing.isNotEmpty) return true;
      if (!mounted) return false;
      await _showNicknameDialog(uid);
    }
  }

  Future<void> _showNicknameDialog(String uid) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NicknameDialog(
        uid: uid,
        firestoreService: _firestoreService,
        validateFormat: _validateNicknameFormat,
      ),
    );
  }
}

/// 비밀번호 재설정 이메일 입력 다이얼로그.
/// TextEditingController를 State에서 소유해 dispose 타이밍을 보장.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});
  final String initialEmail;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '비밀번호 재설정',
        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '가입하신 이메일로 재설정 링크를 보내드립니다.',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.54),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'email@example.com',
              hintStyle: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.24),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
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
          onPressed: () => Navigator.pop(context),
          child: Text(
            '취소',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.54)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text(
            '전송',
            style: TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// 소셜 로그인 직후 닉네임 입력 다이얼로그.
/// TextEditingController를 State에서 소유해 dispose 타이밍을 보장.
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({
    required this.uid,
    required this.firestoreService,
    required this.validateFormat,
  });
  final String uid;
  final FirestoreService firestoreService;
  final String? Function(String?) validateFormat;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  final _controller = TextEditingController();
  String? _errorMsg;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nickname = _controller.text.trim();
    final formatError = widget.validateFormat(nickname);
    if (formatError != null) {
      setState(() => _errorMsg = formatError);
      return;
    }
    setState(() {
      _errorMsg = null;
      _checking = true;
    });
    final taken = await widget.firestoreService.isNicknameTaken(
      nickname,
      widget.uid,
    );
    if (!mounted) return;
    if (taken) {
      setState(() {
        _errorMsg = '이미 사용 중인 닉네임입니다';
        _checking = false;
      });
      return;
    }
    try {
      await widget.firestoreService.setNickname(widget.uid, nickname);
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
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '닉네임 설정',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '댓글에 표시될 닉네임을 입력하세요. (2~12자)',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.54),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_checking,
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: '닉네임',
                  hintStyle: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.24),
                  ),
                  errorText: _errorMsg,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
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
        ),
        actions: [
          TextButton(
            onPressed: _checking ? null : _submit,
            child: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  )
                : const Text(
                    '확인',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// Google "G" 로고 (공식 4색)
class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // 파란색 큰 원 (배경 역할)
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(cx, cy), r, bgPaint);

    // G 글자 대신 SVG 경로 없이 텍스트로 표현
    final tp = TextPainter(
      text: TextSpan(
        text: 'G',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          foreground: Paint()..color = const Color(0xFF4285F4),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_) => false;
}

// 카카오 말풍선 아이콘
class _KakaoLogo extends StatelessWidget {
  final double size;
  const _KakaoLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KakaoLogoPainter()),
    );
  }
}

class _KakaoLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - size.height * 0.05;
    final rx = size.width * 0.48;
    final ry = size.height * 0.43;

    // 말풍선 타원
    final paint = Paint()..color = const Color(0xFF191919);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      paint,
    );

    // 말풍선 꼬리
    final path = Path()
      ..moveTo(cx - size.width * 0.12, cy + ry * 0.6)
      ..lineTo(cx - size.width * 0.22, cy + ry + size.height * 0.12)
      ..lineTo(cx + size.width * 0.05, cy + ry * 0.75)
      ..close();
    canvas.drawPath(path, paint);

    // 느낌표 3개 (채팅 아이콘 표현)
    final dotPaint = Paint()..color = const Color(0xFFFEE500);
    final dotR = size.width * 0.055;
    final dotY = cy - size.height * 0.02;
    canvas.drawCircle(Offset(cx - size.width * 0.18, dotY), dotR, dotPaint);
    canvas.drawCircle(Offset(cx, dotY), dotR, dotPaint);
    canvas.drawCircle(Offset(cx + size.width * 0.18, dotY), dotR, dotPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
