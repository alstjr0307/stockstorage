import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: cs.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  _isLogin ? '로그인' : '회원가입',
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '추천주 상세 정보를 확인하세요',
                  style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38), fontSize: 14),
                ),
                const SizedBox(height: 40),
                _buildField('이메일', _emailController, hint: 'email@example.com'),
                const SizedBox(height: 14),
                _buildField('비밀번호', _passwordController,
                    hint: '••••••••', isPassword: true),
                if (!_isLogin) ...[
                  const SizedBox(height: 14),
                  _buildField('닉네임', _nicknameController,
                      hint: '댓글에 표시될 닉네임'),
                ],
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
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: cs.onSurface.withValues(alpha: 0.12))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('또는',
                          style: GoogleFonts.inter(
                              color: cs.onSurface.withValues(alpha: 0.24), fontSize: 12)),
                    ),
                    Expanded(child: Divider(color: cs.onSurface.withValues(alpha: 0.12))),
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
                          borderRadius: BorderRadius.circular(14)),
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
                          style: GoogleFonts.roboto(
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
                          borderRadius: BorderRadius.circular(14)),
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
                          style: GoogleFonts.inter(
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
                          borderRadius: BorderRadius.circular(14)),
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
                          style: GoogleFonts.inter(
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
                      style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.38)),
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
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.54), fontSize: 12)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          style: GoogleFonts.inter(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: cs.onSurface.withValues(alpha: 0.24)),
            filled: true,
            fillColor: const Color(0xFF1A2035),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF10B981), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (val) =>
              val == null || val.isEmpty ? '$label을 입력하세요' : null,
        ),
      ],
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final user = await context.read<AuthProvider>().signInWithGoogle();
      if (user != null && mounted) {
        // 닉네임 미설정 시 다이얼로그
        final existing = await _firestoreService.getNickname(user.uid);
        if (existing == null && mounted) {
          await _showNicknameDialog(user.uid);
        }
      }
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final user = await context.read<AuthProvider>().signInWithApple();
      if (user != null && mounted) {
        final existing = await _firestoreService.getNickname(user.uid);
        if (existing == null && mounted) {
          await _showNicknameDialog(user.uid);
        }
      }
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithKakao() async {
    setState(() => _isLoading = true);
    try {
      final user = await context.read<AuthProvider>().signInWithKakao();
      if (user != null && mounted) {
        final existing = await _firestoreService.getNickname(user.uid);
        if (existing == null && mounted) {
          await _showNicknameDialog(user.uid);
        }
      }
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      if (_isLogin) {
        await auth.signIn(
            _emailController.text.trim(), _passwordController.text);
      } else {
        final user = await auth.signUp(
            _emailController.text.trim(), _passwordController.text);
        if (user != null) {
          final nickname = _nicknameController.text.trim();
          await _firestoreService.setNickname(
              user.uid, nickname.isEmpty ? '익명' : nickname);
        }
      }
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showNicknameDialog(String uid) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '닉네임 설정',
          style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '댓글에 표시될 닉네임을 입력하세요.',
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: '닉네임',
                hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24)),
                filled: true,
                fillColor: const Color(0xFF0A0E1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFF10B981), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final nickname = controller.text.trim();
              await _firestoreService.setNickname(
                  uid, nickname.isEmpty ? '익명' : nickname);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(
              '확인',
              style: GoogleFonts.inter(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
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
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2), paint);

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


