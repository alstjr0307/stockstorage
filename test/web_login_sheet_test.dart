import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/auth_service.dart';
import 'package:stockstorage/web/web_login_sheet.dart';

class _Auth extends Fake implements AuthService {
  int signIns = 0;
  String? resetEmail;
  Object? failure;
  final pending = Completer<UserCredential>();

  @override
  Future<UserCredential> signInWithEmail(String email, String password) {
    signIns++;
    if (failure != null) return Future.error(failure!);
    return pending.future;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    resetEmail = email;
  }
}

Future<void> _mount(WidgetTester tester, _Auth auth) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 420, child: WebLoginSheet(authService: auth)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'password reset does not require a password or dismiss the sheet',
    (tester) async {
      final auth = _Auth();
      await _mount(tester, auth);
      await tester.tap(find.text('비밀번호를 잊으셨나요?'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'member@example.com');
      await tester.tap(find.text('재설정 링크 보내기'));
      await tester.pumpAndSettle();
      expect(auth.resetEmail, 'member@example.com');
      expect(find.textContaining('재설정 링크를 보냈어요'), findsOneWidget);
      expect(find.byType(WebLoginSheet), findsOneWidget);
    },
  );

  testWidgets('repeated Enter cannot submit a second login while waiting', (
    tester,
  ) async {
    final auth = _Auth();
    await _mount(tester, auth);
    await tester.enterText(find.byType(TextField).at(0), 'member@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    final submit = tester
        .widget<TextField>(find.byType(TextField).at(1))
        .onSubmitted!;
    submit('password');
    submit('password');
    await tester.pump();
    expect(auth.signIns, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).enabled,
      isFalse,
    );
    auth.pending.completeError(
      FirebaseAuthException(code: 'invalid-credential'),
    );
    await tester.pumpAndSettle();
    expect(find.text('이메일 또는 비밀번호가 올바르지 않아요.'), findsOneWidget);
  });

  testWidgets('invalid email is rejected without an auth request', (
    tester,
  ) async {
    final auth = _Auth();
    await _mount(tester, auth);
    await tester.enterText(find.byType(TextField).at(0), 'invalid');
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();
    expect(auth.signIns, 0);
    expect(find.text('올바른 이메일 주소를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('small screens can scroll to the login controls', (tester) async {
    tester.view.physicalSize = const Size(360, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, _Auth());
    await tester.ensureVisible(find.text('비밀번호를 잊으셨나요?'));
    await tester.tap(find.text('비밀번호를 잊으셨나요?'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 재설정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
