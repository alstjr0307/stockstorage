import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _firestoreService = FirestoreService();
  final _messaging = FirebaseMessaging.instance;
  bool _updatingNewPickTopic = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _toggleSetting(String key, bool enabled) async {
    final user = _user;
    if (user == null) return;
    await _firestoreService.updateNotificationSetting(user.uid, key, enabled);
    if (key == 'newPick') {
      setState(() => _updatingNewPickTopic = true);
      try {
        if (enabled) {
          await _messaging.subscribeToTopic('new_pick_alerts');
        } else {
          await _messaging.unsubscribeFromTopic('new_pick_alerts');
        }
      } finally {
        if (mounted) setState(() => _updatingNewPickTopic = false);
      }
      return;
    }
    if (key == 'journalWriteReminder') {
      if (enabled) {
        await NotificationService.scheduleWeekdayJournalWriteReminder();
      } else {
        await NotificationService.cancelWeekdayJournalWriteReminder();
      }
    }
  }

  Widget _buildTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('알림 설정')),
        body: const Center(child: Text('로그인 후 이용할 수 있습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: StreamBuilder<Map<String, bool>>(
        stream: _firestoreService.watchNotificationSettings(user.uid),
        builder: (context, snapshot) {
          final settings =
              snapshot.data ??
              {
                'newPick': true,
                'pickComment': true,
                'postComment': true,
                'journalComment': true,
                'journalWriteReminder': false,
              };
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _buildTile(
                title: '신규 추천주 알림',
                subtitle: '운영자가 새 추천 종목을 올리면 알림을 받습니다.',
                value: settings['newPick'] ?? true,
                enabled: !_updatingNewPickTopic,
                onChanged: (v) => _toggleSetting('newPick', v),
              ),
              _buildTile(
                title: '추천주 댓글 알림',
                subtitle: '추천주 댓글 관련 알림을 받습니다.',
                value: settings['pickComment'] ?? true,
                onChanged: (v) => _toggleSetting('pickComment', v),
              ),
              _buildTile(
                title: '게시글 댓글 알림',
                subtitle: '내 게시글에 달린 댓글 알림을 받습니다.',
                value: settings['postComment'] ?? true,
                onChanged: (v) => _toggleSetting('postComment', v),
              ),
              _buildTile(
                title: '매매일지 댓글 알림',
                subtitle: '내 매매일지에 달린 댓글 알림을 받습니다.',
                value: settings['journalComment'] ?? true,
                onChanged: (v) => _toggleSetting('journalComment', v),
              ),
              _buildTile(
                title: '매매일지 작성 리마인더',
                subtitle: '평일 오후 6시에 매매일지 작성 알림을 받습니다.',
                value: settings['journalWriteReminder'] ?? false,
                onChanged: (v) => _toggleSetting('journalWriteReminder', v),
              ),
              const SizedBox(height: 8),
              const Text(
                '추천주/게시글 상세 화면에서 개별 알림을 추가로 켜거나 끌 수 있습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
