import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'analytics_service.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();

  // 관리자 UID (Firebase에서 확인 후 입력)
  static const String adminUid = '1KzEXKZMoFaYOymYyoI283AR3Y32';

  User? get currentUser => _auth.currentUser;
  bool get isAdmin => _auth.currentUser?.uid == adminUid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
    AnalyticsService.instance.logLogin('email');
    return result;
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    AnalyticsService.instance.logLogin('email_signup');
    return result;
  }

  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      final result = await _auth.signInWithPopup(provider);
      AnalyticsService.instance.logLogin('google');
      return result;
    }

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    AnalyticsService.instance.logLogin('google');
    return result;
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
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      AnalyticsService.instance.logLogin('kakao');
      return result;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        final result = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        AnalyticsService.instance.logLogin('kakao');
        return result;
      }
      rethrow;
    }
  }

  Future<UserCredential?> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final result = await _auth.signInWithProvider(provider);
    AnalyticsService.instance.logLogin('apple');
    return result;
  }

  Future<void> signOut() async {
    AnalyticsService.instance.logLogout();
    await _googleSignIn.signOut();
    // 카카오 로그아웃 (카카오로 로그인한 경우만)
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {
      // 카카오로 로그인하지 않은 경우 무시
    }
    await _auth.signOut();
  }

  /// 계정 삭제: Firestore 사용자 데이터 + Firebase Auth 계정 모두 삭제
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;
    final uid = user.uid;

    // 1. Firestore 사용자 서브컬렉션 삭제 (memos)
    final memos = await db.collection('users').doc(uid).collection('memos').get();
    for (final doc in memos.docs) {
      await doc.reference.delete();
    }

    // 2. Firestore 사용자 문서 삭제
    await db.collection('users').doc(uid).delete();

    // 3. FCM 토큰 삭제는 토큰을 알아야 하므로 생략 (만료됨으로 자동 처리)

    // 4. 소셜 로그아웃
    await _googleSignIn.signOut();
    try {
      await kakao.UserApi.instance.unlink();
    } catch (_) {}

    // 5. Firebase Auth 계정 삭제
    await user.delete();
  }
}
