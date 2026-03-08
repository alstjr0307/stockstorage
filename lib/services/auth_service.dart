import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();

  // 관리자 UID (Firebase에서 확인 후 입력)
  static const String adminUid = '1KzEXKZMoFaYOymYyoI283AR3Y32';

  User? get currentUser => _auth.currentUser;
  bool get isAdmin => _auth.currentUser?.uid == adminUid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpWithEmail(String email, String password) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      return _auth.signInWithPopup(provider);
    }

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  /// 카카오 로그인
  /// 주의: 프로덕션에서는 Cloud Function으로 Firebase 커스텀 토큰을 발급받아 사용하세요.
  /// https://firebase.google.com/docs/auth/admin/create-custom-tokens
  Future<UserCredential?> signInWithKakao() async {
    // 카카오 앱 또는 웹으로 로그인
    try {
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (_) {
          // 카카오톡 앱 로그인 실패 시 웹 로그인으로 폴백
          await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }
    } catch (e) {
      throw Exception('카카오 로그인 실패: $e');
    }

    // 카카오 사용자 정보 가져오기 (이메일 동의 없이 UID만 사용)
    final kakaoUser = await kakao.UserApi.instance.me();
    final kakaoId = kakaoUser.id;

    // 카카오 UID 기반 가상 이메일 생성 (이메일 동의 불필요)
    final email = 'kakao_$kakaoId@kakao.tofusoft.com';
    final password = 'kakao_${kakaoId}_ss';

    // Firebase 이메일 로그인 (이미 계정 있으면 로그인, 없으면 생성)
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        return await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    // 카카오 로그아웃 (카카오로 로그인한 경우만)
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {
      // 카카오로 로그인하지 않은 경우 무시
    }
    await _auth.signOut();
  }
}
