import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import 'notification_settings_screen.dart';

class NotificationHistoryScreen extends StatelessWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('알림 내역')),
        body: const Center(child: Text('로그인 후 이용할 수 있습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 내역'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              );
            },
            child: const Text(
              '알림 설정',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService().watchNotificationHistory(user.uid, limit: 100),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('아직 받은 알림이 없습니다.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            itemCount: docs.length,
            separatorBuilder: (_, index) => Divider(
              height: 1,
              color: cs.onSurface.withValues(alpha: 0.08),
            ),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final title = (data['title'] as String?)?.trim() ?? '';
              final body = (data['body'] as String?)?.trim() ?? '';
              final sentAt =
                  (data['sentAt'] as Timestamp?)?.toDate() ??
                  (data['updatedAt'] as Timestamp?)?.toDate();
              final timeText = sentAt == null
                  ? ''
                  : DateFormat('yyyy.MM.dd HH:mm').format(sentAt);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (body.isNotEmpty) ...[
                      if (title.isNotEmpty) const SizedBox(height: 6),
                      Text(
                        body,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.8),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (timeText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        timeText,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.35),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
