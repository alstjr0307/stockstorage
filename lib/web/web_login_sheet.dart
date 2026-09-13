import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

/// 웹 로그인 시트: 카카오 / 구글 / 이메일 (애플 제외).
class WebLoginSheet extends StatefulWidget {
  const WebLoginSheet({super.key, this.authService});

  final AuthService? authService;
  static const kakaoEnabled = String.fromEnvironment('KAKAO_JS_KEY') != '';

  static Future<void> show(BuildContext context) => showDialog(
    context: context,
    builder: (_) =>
        const Dialog(child: SizedBox(width: 420, child: WebLoginSheet())),
  );

  @override
  State<WebLoginSheet> createState() => _WebLoginSheetState();
}

class _WebLoginSheetState extends State<WebLoginSheet> {
  late final AuthService _auth;
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _busy = false;
  bool _signUp = false;
  bool _resetPassword = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool close = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted && close) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return '이메일 주소를 확인해 주세요.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return '이메일 또는 비밀번호가 올바르지 않아요.';
        case 'too-many-requests':
          return '시도가 너무 많아요. 잠시 기다린 뒤 다시 시도해 주세요.';
        case 'network-request-failed':
          return '네트워크 연결을 확인해 주세요.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return '로그인이 취소되었어요.';
        case 'popup-blocked':
          return '브라우저에서 팝업을 허용한 뒤 다시 시도해 주세요.';
        case 'unauthorized-domain':
        case 'operation-not-allowed':
          return '현재 이 로그인 방식을 사용할 수 없어요. 이메일 로그인을 이용해 주세요.';
        case 'user-disabled':
          return '사용이 중지된 계정입니다. 운영자에게 문의해 주세요.';
      }
    }
    final s = e.toString();
    if (s.contains('wrong-password') || s.contains('invalid-credential')) {
      return '이메일 또는 비밀번호가 올바르지 않아요.';
    }
    if (s.contains('email-already-in-use')) return '이미 가입된 이메일이에요.';
    if (s.contains('weak-password')) return '비밀번호는 6자 이상이어야 해요.';
    return '로그인에 실패했어요. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _emailAction() async {
    if (_busy) return;
    final email = _emailCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    if (_resetPassword) {
      await _run(() async {
        try {
          await _auth.sendPasswordResetEmail(email);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'user-not-found') rethrow;
        }
      }, close: false);
      if (mounted && _error == null) {
        setState(() => _info = '가입된 이메일이라면 재설정 링크를 보냈어요. 스팸함도 확인해 주세요.');
      }
      return;
    }
    if (pw.isEmpty || (_signUp && pw.length < 6)) {
      setState(
        () => _error = _signUp ? '비밀번호는 6자 이상이어야 해요.' : '비밀번호를 입력해 주세요.',
      );
      return;
    }
    await _run(() async {
      if (_signUp) {
        await _auth.signUpWithEmail(email, pw);
      } else {
        await _auth.signInWithEmail(email, pw);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _resetPassword
                ? '비밀번호 재설정'
                : _signUp
                ? '회원가입'
                : '로그인',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          if (!_resetPassword) ...[
            if (WebLoginSheet.kakaoEnabled) ...[
              _SocialButton(
                label: '카카오로 계속하기',
                color: const Color(0xFFFEE500),
                fg: const Color(0xFF191600),
                onTap: _busy ? null : () => _run(() => _auth.signInWithKakao()),
              ),
              const SizedBox(height: 10),
            ],
            _SocialButton(
              label: 'Google로 계속하기',
              color: Colors.white,
              fg: const Color(0xFF191F28),
              border: true,
              onTap: _busy ? null : () => _run(() => _auth.signInWithGoogle()),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('또는 이메일', style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailCtrl,
            enabled: !_busy,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            textInputAction: _resetPassword
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: _resetPassword ? (_) => _emailAction() : null,
            decoration: const InputDecoration(
              labelText: '이메일',
              border: OutlineInputBorder(),
            ),
          ),
          if (!_resetPassword) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _pwCtrl,
              enabled: !_busy,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [
                _signUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              onSubmitted: (_) => _emailAction(),
              decoration: InputDecoration(
                labelText: '비밀번호',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? '비밀번호 숨기기' : '비밀번호 표시',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_info != null) ...[
            const SizedBox(height: 10),
            Text(
              _info!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _emailAction,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _resetPassword
                        ? '재설정 링크 보내기'
                        : _signUp
                        ? '가입하기'
                        : '로그인',
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (_resetPassword) {
                      _resetPassword = false;
                      _signUp = false;
                    } else {
                      _signUp = !_signUp;
                    }
                    _error = null;
                    _info = null;
                  }),
            child: Text(
              _resetPassword
                  ? '로그인으로 돌아가기'
                  : _signUp
                  ? '이미 계정이 있어요'
                  : '이메일로 회원가입',
            ),
          ),
          if (!_signUp && !_resetPassword)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _resetPassword = true;
                      _error = null;
                      _info = null;
                    }),
              child: const Text('비밀번호를 잊으셨나요?'),
            ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.color,
    required this.fg,
    required this.onTap,
    this.border = false,
  });
  final String label;
  final Color color;
  final Color fg;
  final VoidCallback? onTap;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: fg,
          side: border ? const BorderSide(color: Color(0xFFE5E8EB)) : null,
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
