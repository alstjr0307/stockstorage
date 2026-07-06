import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// 웹 로그인 시트: 카카오 / 구글 / 이메일 (애플 제외).
class WebLoginSheet extends StatefulWidget {
  const WebLoginSheet({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const Dialog(
          child: SizedBox(width: 420, child: WebLoginSheet()),
        ),
      );

  @override
  State<WebLoginSheet> createState() => _WebLoginSheetState();
}

class _WebLoginSheetState extends State<WebLoginSheet> {
  final _auth = AuthService();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _busy = false;
  bool _signUp = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('wrong-password') || s.contains('invalid-credential')) {
      return '이메일 또는 비밀번호가 올바르지 않아요.';
    }
    if (s.contains('email-already-in-use')) return '이미 가입된 이메일이에요.';
    if (s.contains('weak-password')) return '비밀번호는 6자 이상이어야 해요.';
    return '로그인에 실패했어요. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _emailAction() async {
    final email = _emailCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해 주세요.');
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _signUp ? '회원가입' : '로그인',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          _SocialButton(
            label: '카카오로 계속하기',
            color: const Color(0xFFFEE500),
            fg: const Color(0xFF191600),
            onTap: _busy ? null : () => _run(() => _auth.signInWithKakao()),
          ),
          const SizedBox(height: 10),
          _SocialButton(
            label: 'Google로 계속하기',
            color: Colors.white,
            fg: const Color(0xFF191F28),
            border: true,
            onTap: _busy ? null : () => _run(() => _auth.signInWithGoogle()),
          ),
          const SizedBox(height: 20),
          const Row(children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('또는 이메일', style: TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '이메일',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pwCtrl,
            obscureText: true,
            onSubmitted: (_) => _emailAction(),
            decoration: const InputDecoration(
              labelText: '비밀번호',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
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
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_signUp ? '가입하기' : '로그인'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
            child: Text(_signUp ? '이미 계정이 있어요' : '이메일로 회원가입'),
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
