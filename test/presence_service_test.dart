import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockstorage/services/presence_service.dart';

void main() {
  test('Korean day rolls over at 15:00 UTC regardless of device timezone', () {
    expect(
      kstDayStartUtc(DateTime.utc(2026, 10, 15, 14, 59, 59)),
      DateTime.utc(2026, 10, 14, 15),
    );
    expect(
      kstDayStartUtc(DateTime.utc(2026, 10, 15, 15)),
      DateTime.utc(2026, 10, 15, 15),
    );
    expect(
      kstDayStartUtc(DateTime.parse('2026-10-16T00:00:00+09:00')),
      DateTime.utc(2026, 10, 15, 15),
    );
    expect(
      kstDayStartUtc(DateTime.utc(2026, 12, 31, 15)),
      DateTime.utc(2026, 12, 31, 15),
    );
  });

  final now = DateTime.utc(2026, 10, 15, 12);
  Map<String, dynamic> session(String uid, int age, String platform) => {
    'uid': uid,
    'lastSeen': Timestamp.fromDate(now.subtract(Duration(seconds: age))),
    'platform': platform,
  };

  test('multiple devices count as one user with latest heartbeat', () {
    final users = aggregateOnlineUsers([
      session('a', 40, 'web'),
      session('a', 5, 'android'),
      session('b', 20, 'iOS'),
    ], now);
    expect(users.map((user) => user.uid), ['a', 'b']);
    expect(users.first.sessions, 2);
    expect(users.first.platforms, {'web', 'android'});
    expect(
      users.first.lastSeen.toUtc(),
      now.subtract(const Duration(seconds: 5)),
    );
  });

  test('crashed sessions expire without needing another server update', () {
    final sessions = [session('a', 89, 'web'), session('b', 90, 'android')];
    expect(aggregateOnlineUsers(sessions, now).map((user) => user.uid), ['a']);
    expect(
      aggregateOnlineUsers(sessions, now.add(const Duration(seconds: 1))),
      isEmpty,
    );
  });

  test('an expired device does not hide another active device', () {
    final users = aggregateOnlineUsers([
      session('a', 100, 'web'),
      session('a', 10, 'android'),
    ], now);
    expect(users.single.sessions, 1);
    expect(users.single.platforms, {'android'});
  });

  test('unresolved timestamps and malformed sessions are excluded', () {
    expect(
      aggregateOnlineUsers([
        {'uid': 'a', 'lastSeen': null},
        {'lastSeen': Timestamp.fromDate(now)},
        {'uid': 1, 'lastSeen': Timestamp.fromDate(now)},
      ], now),
      isEmpty,
    );
  });
}
