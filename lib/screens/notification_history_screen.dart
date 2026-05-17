import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trading_journal.dart';
import '../services/firestore_service.dart';
import 'home_screen.dart';
import 'journal_chart_screen.dart';
import 'notification_settings_screen.dart';
import 'post_detail_screen.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  final _firestoreService = FirestoreService();

  Future<void> _openNotification(Map<String, dynamic> data) async {
    final postId = (data['postId'] as String?)?.trim() ?? '';
    final pickId = (data['pickId'] as String?)?.trim() ?? '';
    final journalId = (data['journalId'] as String?)?.trim() ?? '';

    if (postId.isNotEmpty) {
      final post = await _firestoreService.getPostOnce(postId);
      if (!mounted) return;
      if (post == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('게시글을 찾을 수 없습니다.')));
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final isLiked = uid == null || uid.isEmpty
          ? false
          : await _firestoreService.hasLikedPost(post.id, uid);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            post: post,
            isOwn: uid != null && uid == post.uid,
            isLiked: isLiked,
            likeCount: post.likes,
            onDelete: uid != null && uid == post.uid
                ? () => _firestoreService.deletePost(post.id)
                : null,
          ),
        ),
      );
      return;
    }

    if (pickId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StockPicksListScreen()),
      );
      return;
    }

    if (journalId.isNotEmpty) {
      final journal = await _firestoreService.getJournalById(journalId);
      if (!mounted) return;
      if (journal == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('매매일지를 찾을 수 없습니다.')));
        return;
      }
      final publicByAuthor = await _firestoreService.getPublicJournalsByUidOnce(
        journal.uid,
      );
      if (!mounted) return;
      final relatedBuys =
          publicByAuthor
              .where(
                (j) =>
                    j.action == '\uB9E4\uC218' &&
                    j.ticker == journal.ticker &&
                    j.market == journal.market,
              )
              .toList()
            ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      final relatedSells =
          publicByAuthor
              .where(
                (j) =>
                    j.action == '\uB9E4\uB3C4' &&
                    j.ticker == journal.ticker &&
                    j.market == journal.market,
              )
              .toList()
            ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      final chartBaseBuy = journal.action == '\uB9E4\uC218'
          ? journal
          : _selectChartBaseBuy(journal, relatedBuys);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JournalChartScreen(
            buy: chartBaseBuy,
            linkedSells: const <TradingJournal>[],
            relatedBuys: relatedBuys,
            relatedSells: relatedSells,
            showBuyMarker: relatedBuys.isNotEmpty,
            firestoreService: _firestoreService,
          ),
        ),
      );
    }
  }

  TradingJournal _selectChartBaseBuy(
    TradingJournal journal,
    List<TradingJournal> relatedBuys,
  ) {
    TradingJournal? latestBefore;
    for (final buy in relatedBuys) {
      if (!buy.tradeDate.isAfter(journal.tradeDate)) latestBefore = buy;
    }
    if (latestBefore != null) return latestBefore;
    if (relatedBuys.isNotEmpty) return relatedBuys.first;
    return TradingJournal(
      id: 'synthetic_buy_${journal.id}',
      uid: journal.uid,
      nickname: journal.nickname,
      stockName: journal.stockName,
      ticker: journal.ticker,
      market: journal.market,
      action: '\uB9E4\uC218',
      price: journal.buyPrice > 0 ? journal.buyPrice : journal.price,
      quantity: journal.quantity,
      tradeDate: journal.tradeDate,
      note: '',
      isPublic: false,
      likes: 0,
      createdAt: journal.createdAt,
    );
  }

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
        stream: _firestoreService.watchNotificationHistory(
          user.uid,
          limit: 100,
        ),
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
            separatorBuilder: (_, index) =>
                Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08)),
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
              final canOpen =
                  ((data['postId'] as String?)?.trim().isNotEmpty ?? false) ||
                  ((data['pickId'] as String?)?.trim().isNotEmpty ?? false) ||
                  ((data['journalId'] as String?)?.trim().isNotEmpty ?? false);

              return InkWell(
                onTap: canOpen ? () => _openNotification(data) : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 2,
                  ),
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
                        Row(
                          children: [
                            Text(
                              timeText,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.35),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (canOpen) ...[
                              const Spacer(),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.28),
                              ),
                            ],
                          ],
                        ),
                      ] else if (canOpen) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.28),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
