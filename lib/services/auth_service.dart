import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

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
  /// Cloud Function에서 카카오 액세스 토큰을 서버 검증 후 Firebase 커스텀 토큰 발급
  Future<UserCredential?> signInWithKakao() async {
    // 1. 카카오 앱/웹 로그인으로 액세스 토큰 획득
    try {
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (_) {
          await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }
    } catch (e) {
      throw Exception('카카오 로그인 실패: $e');
    }

    // 2. 카카오 액세스 토큰 획득
    final tokenInfo = await kakao.TokenManagerProvider.instance.manager.getToken();
    final accessToken = tokenInfo?.accessToken;
    if (accessToken == null) {
      throw Exception('카카오 토큰을 가져올 수 없습니다.');
    }

    // 3. Cloud Function으로 Firebase 커스텀 토큰 발급 (서버에서 카카오 토큰 검증)
    final callable = _functions.httpsCallable('createKakaoCustomToken');
    final result = await callable.call({'accessToken': accessToken});
    final customToken = result.data['customToken'] as String;

    // 4. 커스텀 토큰으로 Firebase 로그인
    return _auth.signInWithCustomToken(customToken);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {}
    await _auth.signOut();
  }
}
