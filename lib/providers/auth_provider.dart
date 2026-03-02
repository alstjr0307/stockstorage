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

  Future<void> signUp(String email, String password) async {
    await _authService.signUpWithEmail(email, password);
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    await _authService.signInWithGoogle();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    notifyListeners();
  }
}
