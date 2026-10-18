import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const presenceTimeout = Duration(seconds: 90);

/// Korea has no daylight saving time. Return an actual UTC query boundary.
DateTime kstDayStartUtc(DateTime now) {
  final kst = now.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(
    kst.year,
    kst.month,
    kst.day,
  ).subtract(const Duration(hours: 9));
}

/// One document per running app/tab, so closing one device cannot hide another.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final instance = PresenceService._();
  StreamSubscription<User?>? _auth;
  Timer? _timer;
  DocumentReference<Map<String, dynamic>>? _session;
  String? _uid;
  bool _foreground = false;
  bool _writing = false;

  void start() {
    if (_auth != null) return;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_uid == user?.uid) return;
      _removeSession();
      _uid = user?.uid;
      _sync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (!_foreground || _uid == null) {
      _removeSession();
      return;
    }
    _session ??= FirebaseFirestore.instance
        .collection('presence_sessions')
        .doc();
    unawaited(_heartbeat());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_heartbeat());
    });
  }

  Future<void> _heartbeat() async {
    final session = _session;
    final uid = _uid;
    if (_writing || session == null || uid == null || !_foreground) return;
    _writing = true;
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(session, {
        'uid': uid,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      // Persist today's visitor after session removal, deduplicated by UID.
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(uid),
        {'lastActiveAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (_) {
      // Presence must never block login or normal app use. Retry next tick.
    } finally {
      _writing = false;
    }
  }

  void _removeSession() {
    _timer?.cancel();
    final old = _session;
    _session = null;
    if (old != null) unawaited(old.delete().catchError((Object _) {}));
  }

  /// Call before Firebase signs out so the owner still has delete permission.
  Future<void> leave() async {
    _timer?.cancel();
    final old = _session;
    _session = null;
    if (old == null) return;
    try {
      await old.delete().timeout(const Duration(seconds: 2));
    } catch (_) {
      // An unreachable session expires from the admin list after 90 seconds.
    }
  }

  void resume() {
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _sync();
  }
}

class OnlineUser {
  OnlineUser(this.uid, this.lastSeen, this.platforms, this.sessions);
  final String uid;
  final DateTime lastSeen;
  final Set<String> platforms;
  final int sessions;
}

List<OnlineUser> aggregateOnlineUsers(
  Iterable<Map<String, dynamic>> sessions,
  DateTime now,
) {
  final users = <String, OnlineUser>{};
  for (final session in sessions) {
    final uid = session['uid'];
    final stamp = session['lastSeen'];
    if (uid is! String || stamp is! Timestamp) continue;
    final seen = stamp.toDate();
    if (now.difference(seen) >= presenceTimeout) continue;
    final old = users[uid];
    users[uid] = OnlineUser(
      uid,
      old != null && old.lastSeen.isAfter(seen) ? old.lastSeen : seen,
      {
        ...?old?.platforms,
        if (session['platform'] is String) session['platform'] as String,
      },
      (old?.sessions ?? 0) + 1,
    );
  }
  return users.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
}
