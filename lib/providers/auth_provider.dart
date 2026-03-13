import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? get user => _authService.currentUser;
  bool get isAdmin => _authService.isAdmin;
  bool get isLoggedIn => user != null;

  Future<void> signIn(String email, String password) async {
    await _authService.signInWithEmail(email, password);
    notifyListeners();
  }

  Future<User?> signUp(String email, String password) async {
    final cred = await _authService.signUpWithEmail(email, password);
    notifyListeners();
    return cred.user;
  }

  Future<User?> signInWithGoogle() async {
    final cred = await _authService.signInWithGoogle();
    notifyListeners();
    return cred?.user;
  }

  Future<User?> signInWithKakao() async {
    final cred = await _authService.signInWithKakao();
    notifyListeners();
    return cred?.user;
  }

  Future<User?> signInWithApple() async {
    final cred = await _authService.signInWithApple();
    notifyListeners();
    return cred?.user;
  }

  Future<void> signOut() async {
    await _authService.signOut();
    notifyListeners();
  }
}
