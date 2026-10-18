import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/presence_service.dart';

class AdminPresenceTab extends StatefulWidget {
  const AdminPresenceTab({super.key, required this.onOpenUser});
  final void Function(String uid, Map<String, dynamic> user) onOpenUser;

  @override
  State<AdminPresenceTab> createState() => _AdminPresenceTabState();
}

class _AdminPresenceTabState extends State<AdminPresenceTab> {
  Timer? _clock;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _todayStream;
  late DateTime _dayStart;
  DateTime _queryTime = DateTime.now();
  bool _excludeAdmins = false;
  bool _showToday = true;
  final _profiles = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};

  void _subscribe() {
    _queryTime = DateTime.now();
    _stream = FirebaseFirestore.instance
        .collection('presence_sessions')
        .where(
          'lastSeen',
          isGreaterThan: Timestamp.fromDate(
            _queryTime.subtract(presenceTimeout),
          ),
        )
        .snapshots(includeMetadataChanges: true);
  }

  void _subscribeToday() {
    _dayStart = kstDayStartUtc(DateTime.now());
    _todayStream = FirebaseFirestore.instance
        .collection('users')
        .where(
          'lastActiveAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_dayStart),
        )
        .where(
          'lastActiveAt',
          isLessThan: Timestamp.fromDate(
            _dayStart.add(const Duration(days: 1)),
          ),
        )
        .orderBy('lastActiveAt', descending: true)
        .snapshots(includeMetadataChanges: true);
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
    _subscribeToday();
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() {
        if (DateTime.now().difference(_queryTime) >=
            const Duration(minutes: 2)) {
          _subscribe();
        }
        if (_dayStart != kstDayStartUtc(DateTime.now())) {
          _profiles.clear();
          _subscribeToday();
        }
      });
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  bool _include(String uid) =>
      !_excludeAdmins || !AuthService.adminUids.contains(uid);

  Widget _count(
    String label,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    int count,
  ) {
    final text = snapshot.hasError
        ? '조회 실패'
        : !snapshot.hasData
        ? '불러오는 중'
        : snapshot.data!.metadata.isFromCache
        ? '연결 확인 중'
        : '$count명';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text(text, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService().isAdmin) {
      return const Center(child: Text('관리자만 확인할 수 있습니다.'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, live) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Discard yesterday's snapshot immediately when the Korean date changes.
        key: ValueKey(_dayStart),
        stream: _todayStream,
        builder: (context, today) {
          final online = aggregateOnlineUsers(
            live.data?.docs
                    .where((doc) => !doc.metadata.hasPendingWrites)
                    .map((doc) => doc.data()) ??
                [],
            DateTime.now(),
          ).where((user) => _include(user.uid)).toList();
          final onlineById = {for (final user in online) user.uid: user};
          final todayDocs =
              today.data?.docs
                  .where(
                    (doc) => !doc.metadata.hasPendingWrites && _include(doc.id),
                  )
                  .toList() ??
              [];
          final todayById = {for (final doc in todayDocs) doc.id: doc.data()};
          final selected = _showToday ? today : live;
          final liveConfirmed =
              live.hasData &&
              !live.hasError &&
              !live.data!.metadata.isFromCache;
          final ids = _showToday
              ? todayDocs.map((doc) => doc.id).toList()
              : online.map((user) => user.uid).toList();
          final ready = selected.hasData && !selected.hasError;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 1 + (ready ? ids.length : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _count('현재 접속', live, online.length),
                        _count('오늘 총 접속', today, todayDocs.length),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${DateFormat('yyyy.MM.dd').format(_dayStart.add(const Duration(hours: 9)))} · 한국 시간 00:00~24:00',
                    ),
                    const Text(
                      '로그인 유저 기준 · 같은 유저는 하루 1명으로 집계\n오늘 명단은 기록된 접속·활동 기준입니다.',
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('현재 접속')),
                        ButtonSegment(value: true, label: Text('오늘 전체')),
                      ],
                      selected: {_showToday},
                      onSelectionChanged: (value) =>
                          setState(() => _showToday = value.single),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('관리자 제외'),
                      value: _excludeAdmins,
                      onChanged: (value) =>
                          setState(() => _excludeAdmins = value),
                    ),
                    const Text(
                      '현재 접속은 업데이트된 앱부터 확인됩니다.\n30초마다 확인하며, 90초간 응답이 없으면 제외됩니다.',
                    ),
                    const SizedBox(height: 12),
                    if (selected.hasError) ...[
                      const Text('접속 명단을 불러오지 못했습니다.'),
                      TextButton(
                        onPressed: () => setState(() {
                          _subscribe();
                          _subscribeToday();
                        }),
                        child: const Text('다시 시도'),
                      ),
                    ] else if (!selected.hasData)
                      const Center(child: CircularProgressIndicator())
                    else if (selected.data!.metadata.isFromCache)
                      const Text('서버 연결 확인 중입니다. 아래는 저장된 명단입니다.')
                    else if (ids.isEmpty)
                      Text(
                        _showToday ? '오늘 접속 기록이 없습니다.' : '현재 접속 중인 유저가 없습니다.',
                      ),
                  ],
                );
              }
              final uid = ids[index - 1];
              final user = onlineById[uid];
              final data = todayById[uid];
              if (data != null) {
                return _userTile(uid, data, user, liveConfirmed);
              }
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _profiles.putIfAbsent(
                  uid,
                  () => FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .get(),
                ),
                builder: (context, profile) => _userTile(
                  uid,
                  profile.data?.data() ?? {},
                  user,
                  liveConfirmed,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _userTile(
    String uid,
    Map<String, dynamic> data,
    OnlineUser? online,
    bool liveConfirmed,
  ) {
    final nickname = data['nickname'] as String? ?? '';
    final active = data['lastActiveAt'];
    final lastSeen = _showToday && active is Timestamp
        ? active.toDate()
        : online?.lastSeen;
    final time = lastSeen == null
        ? '-'
        : DateFormat(
            'HH:mm:ss',
          ).format(lastSeen.toUtc().add(const Duration(hours: 9)));
    final isOnline = liveConfirmed && online != null;
    final status = !liveConfirmed
        ? '현재 접속 확인 중'
        : isOnline
        ? '현재 접속 중'
        : '실시간 접속 미확인';
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: Icon(
          Icons.circle,
          size: 12,
          color: isOnline ? const Color(0xFF10B981) : Colors.grey,
        ),
        title: Text(
          '${nickname.isEmpty ? '(닉네임 없음)' : nickname}${AuthService.adminUids.contains(uid) ? ' · 관리자' : ''}',
        ),
        subtitle: Text(
          '$uid\n$status · 마지막 접속 $time${isOnline ? '\n${online.platforms.join(', ')} · ${online.sessions}개 접속' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onOpenUser(uid, {...data, 'uid': uid}),
      ),
    );
  }
}
