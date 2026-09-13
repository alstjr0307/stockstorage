import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/auth_service.dart';
import 'package:stockstorage/web/web_shell.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get email => '$uid@example.com';
}

class _Auth extends Fake implements FirebaseAuth {
  final changes = StreamController<User?>.broadcast();
  @override
  User? currentUser;
  @override
  Stream<User?> authStateChanges() => changes.stream;
  void signIn(String? uid) {
    currentUser = uid == null ? null : _User(uid);
    changes.add(currentUser);
  }
}

class _Page extends StatefulWidget {
  const _Page({required this.uid});
  final String? uid;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('${widget.uid ?? 'guest'}:$count'),
  );
}

void main() {
  testWidgets(
    'normal login, account changes and logout reset private tab state',
    (tester) async {
      final auth = _Auth();
      addTearDown(auth.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: WebShell(
            auth: auth,
            pageBuilder: (_, index) => _Page(uid: auth.currentUser?.uid),
          ),
        ),
      );
      expect(find.text('guest:0'), findsOneWidget);
      auth.signIn('alice');
      await tester.pumpAndSettle();
      expect(find.text('alice:0'), findsOneWidget);
      await tester.tap(find.text('alice:0'));
      await tester.pump();
      auth.signIn('bob');
      await tester.pumpAndSettle();
      expect(find.text('bob:0'), findsOneWidget);
      expect(find.text('alice:1'), findsNothing);
      auth.signIn(null);
      await tester.pumpAndSettle();
      expect(find.text('guest:0'), findsOneWidget);
    },
  );

  testWidgets('logging out from the admin tab returns to a valid tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Auth()..currentUser = _User(AuthService.adminUids.first);
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: WebShell(
          auth: auth,
          pageBuilder: (_, index) => Text('page-$index'),
        ),
      ),
    );
    await tester.tap(find.text('관리자'));
    await tester.pumpAndSettle();
    expect(find.text('page-8'), findsOneWidget);
    auth.signIn(null);
    await tester.pumpAndSettle();
    expect(find.text('page-0'), findsOneWidget);
    expect(find.text('관리자'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
