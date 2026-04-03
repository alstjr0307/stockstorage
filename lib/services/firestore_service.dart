import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement.dart';
import '../models/comment.dart';
import '../models/market_analysis.dart';
import '../models/post.dart';
import '../models/stock_pick.dart';
import '../models/trading_journal.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Stream<List<StockPick>> getStockPicks({bool premiumOnly = false}) {
    Query query = _db
        .collection('stock_picks')
        .orderBy('createdAt', descending: true);

    if (premiumOnly) {
      query = query.where('isPremium', isEqualTo: true);
    }

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => StockPick.fromFirestore(doc))
        .where((p) => !p.isCompleted)
        .toList());
  }

  Future<void> addStockPick(StockPick pick) {
    return _db.collection('stock_picks').add(pick.toFirestore());
  }

  Future<void> updateStockPick(StockPick pick) {
    return _db.collection('stock_picks').doc(pick.id).update(pick.toFirestore());
  }

  Future<void> deleteStockPick(String id) {
    return _db.collection('stock_picks').doc(id).delete();
  }

  // ── 공지사항 ──────────────────────────────────────────────────────────
  Stream<List<Announcement>> getAnnouncements() {
    return _db
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) {
          final list = s.docs.map((d) => Announcement.fromFirestore(d)).toList();
          list.sort((a, b) {
            if (a.isPinned == b.isPinned) return 0;
            return a.isPinned ? -1 : 1;
          });
          return list;
        });
  }

  Future<void> addAnnouncement(Announcement a) {
    return _db.collection('announcements').add(a.toFirestore());
  }

  Future<void> updateAnnouncement(Announcement a) {
    return _db.collection('announcements').doc(a.id).update(a.toFirestore());
  }

  Future<void> deleteAnnouncement(String id) {
    return _db.collection('announcements').doc(id).delete();
  }

  // ── 닉네임 ────────────────────────────────────────────────────────────
  Future<String?> getNickname(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['nickname'] as String?;
  }

  Future<void> setNickname(String uid, String nickname) {
    return _db
        .collection('users')
        .doc(uid)
        .set({'nickname': nickname}, SetOptions(merge: true));
  }

  Future<bool> isNicknameTaken(String nickname, String currentUid) async {
    final query = await _db
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return false;
    // 자기 자신 닉네임은 중복 허용
    return query.docs.first.id != currentUid;
  }

  // ── 추천주 ────────────────────────────────────────────────────────────
  Stream<List<String>> getFavoriteIds(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => List<String>.from(doc.data()?['favorites'] ?? []));
  }

  Future<void> toggleFavorite(String uid, String pickId, bool isCurrentlyFav) {
    final ref = _db.collection('users').doc(uid);
    if (isCurrentlyFav) {
      return ref.set({'favorites': FieldValue.arrayRemove([pickId])},
          SetOptions(merge: true));
    } else {
      return ref.set({'favorites': FieldValue.arrayUnion([pickId])},
          SetOptions(merge: true));
    }
  }

  // ── 종료 추천주 ───────────────────────────────────────────────────────
  Future<void> closeStockPick(String id, double closedPrice) {
    return _db.collection('stock_picks').doc(id).update({
      'status': 'completed',
      'closedPrice': closedPrice,
      'closedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Stream<List<StockPick>> getCompletedPicks() {
    return _db
        .collection('stock_picks')
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((s) {
          final list = s.docs.map((d) => StockPick.fromFirestore(d)).toList();
          list.sort((a, b) =>
              (b.closedAt ?? DateTime(0)).compareTo(a.closedAt ?? DateTime(0)));
          return list;
        });
  }

  // ── 시황 분석 ─────────────────────────────────────────────────────────
  Stream<List<MarketAnalysis>> getMarketAnalyses() {
    return _db
        .collection('market_analyses')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => MarketAnalysis.fromFirestore(d)).toList());
  }

  Future<void> addMarketAnalysis(MarketAnalysis a) {
    return _db.collection('market_analyses').add(a.toFirestore());
  }

  Future<void> updateMarketAnalysis(MarketAnalysis a) {
    return _db.collection('market_analyses').doc(a.id).update(a.toFirestore());
  }

  Future<void> deleteMarketAnalysis(String id) {
    return _db.collection('market_analyses').doc(id).delete();
  }

  // ── 코멘트 ────────────────────────────────────────────────────────────
  Stream<List<Comment>> getComments(String pickId) {
    return _db
        .collection('stock_picks')
        .doc(pickId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map((d) => Comment.fromFirestore(d)).toList());
  }

  Future<void> addComment(String pickId, Comment comment) async {
    final batch = _db.batch();
    final pickCommentRef = _db
        .collection('stock_picks')
        .doc(pickId)
        .collection('comments')
        .doc();
    batch.set(pickCommentRef, comment.toFirestore());
    // 내 댓글 목록용 사본
    batch.set(
      _db.collection('users').doc(comment.uid).collection('myComments').doc(pickCommentRef.id),
      {
        'pickId': pickId,
        'text': comment.content,
        'createdAt': Timestamp.fromDate(comment.createdAt),
      },
    );
    return batch.commit();
  }

  Future<void> deleteComment(String pickId, String commentId, {String? uid}) {
    final batch = _db.batch();
    batch.delete(_db
        .collection('stock_picks')
        .doc(pickId)
        .collection('comments')
        .doc(commentId));
    if (uid != null) {
      batch.delete(_db
          .collection('users')
          .doc(uid)
          .collection('myComments')
          .doc(commentId));
    }
    return batch.commit();
  }

  Future<List<({String pickId, String text, DateTime createdAt})>>
      getMyComments(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('myComments')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((doc) {
      final d = doc.data();
      return (
        pickId: d['pickId'] as String,
        text: d['text'] as String,
        createdAt: (d['createdAt'] as Timestamp).toDate(),
      );
    }).toList();
  }

  Future<List<({String pickId, String text, DateTime createdAt})>>
      getMyStockPickComments(String uid) {
    return getMyComments(uid);
  }

  Future<List<({String postId, String text, DateTime createdAt})>>
      getMyPostComments(String uid) async {
    final mirroredSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('myPostComments')
        .orderBy('createdAt', descending: true)
        .get();

    if (mirroredSnap.docs.isNotEmpty) {
      return mirroredSnap.docs.map((doc) {
        final data = doc.data();
        return (
          postId: data['postId'] as String? ?? '',
          text: data['text'] as String? ?? '',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
    }

    final items = <({String commentId, String postId, String text, DateTime createdAt})>[];

    try {
      final snap = await _db
          .collectionGroup('comments')
          .where('uid', isEqualTo: uid)
          .get();

      for (final doc in snap.docs) {
        final parentDoc = doc.reference.parent.parent;
        final rootCollection = parentDoc?.parent;
        if (parentDoc == null || rootCollection?.id != 'posts') continue;
        final data = doc.data();
        items.add((
          commentId: doc.id,
          postId: parentDoc.id,
          text: data['content'] as String? ?? '',
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));
      }
    } catch (_) {
      final postsSnap = await _db.collection('posts').get();

      for (final postDoc in postsSnap.docs) {
        final commentsSnap = await postDoc.reference
            .collection('comments')
            .where('uid', isEqualTo: uid)
            .get();

        for (final commentDoc in commentsSnap.docs) {
          final data = commentDoc.data();
          items.add((
            commentId: commentDoc.id,
            postId: postDoc.id,
            text: data['content'] as String? ?? '',
            createdAt:
                (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ));
        }
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (items.isNotEmpty) {
      final batch = _db.batch();
      for (final item in items) {
        batch.set(
          _db.collection('users').doc(uid).collection('myPostComments').doc(item.commentId),
          {
            'postId': item.postId,
            'text': item.text,
            'createdAt': Timestamp.fromDate(item.createdAt),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    return items
        .map((item) => (
              postId: item.postId,
              text: item.text,
              createdAt: item.createdAt,
            ))
        .toList();
  }

  Future<StockPick?> getStockPickOnce(String id) async {
    final doc = await _db.collection('stock_picks').doc(id).get();
    if (!doc.exists) return null;
    return StockPick.fromFirestore(doc);
  }

  Future<Post?> getPostOnce(String id) async {
    final doc = await _db.collection('posts').doc(id).get();
    if (!doc.exists) return null;
    return Post.fromFirestore(doc);
  }

  Future<MarketAnalysis?> getMarketAnalysisOnce(String id) async {
    final doc = await _db.collection('market_analyses').doc(id).get();
    if (!doc.exists) return null;
    return MarketAnalysis.fromFirestore(doc);
  }

  // ── 관리자: 유저 목록 ─────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getAdminUserList() async {
    final usersSnap = await _db.collection('users').get();
    final results = await Future.wait(usersSnap.docs.map((doc) async {
      final data = doc.data();
      final commentsSnap = await _db
          .collection('users')
          .doc(doc.id)
          .collection('myComments')
          .count()
          .get();
      return {
        'uid': doc.id,
        'nickname': data['nickname'] as String? ?? '',
        'createdAt': data['createdAt'] as Timestamp?,
        'commentCount': commentsSnap.count ?? 0,
      };
    }));
    results.sort((a, b) {
      final ta = a['createdAt'] as Timestamp?;
      final tb = b['createdAt'] as Timestamp?;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return results;
  }

  // ── 알림 큐 ───────────────────────────────────────────────────────────
  Future<void> queueNotification(String title, String body) {
    return _db.collection('notification_queue').add({
      'title': title,
      'body': body,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// 관리자 수동 알림 발송 (notification_queue → Cloud Function → FCM 전송)
  Future<void> sendPushNotification({required String title, required String body}) {
    return queueNotification(title, body);
  }

  // ── FCM 토큰 ─────────────────────────────────────────────────────────
  Future<void> logFcmDebug(String message) {
    return _db.collection('fcm_debug').add({
      'message': message,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> saveFcmToken(String token, {String? uid}) {
    return _db.collection('fcm_tokens').doc(token).set({
      'token': token,
      'uid': uid,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  // ── 투자 메모 (users/{uid}/memos/{pickId}) ────────────────────────────
  Future<String?> getMemo(String uid, String pickId) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('memos')
        .doc(pickId)
        .get();
    return doc.data()?['text'] as String?;
  }

  Future<void> saveMemo(String uid, String pickId, String text) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('memos')
        .doc(pickId)
        .set({
      'text': text,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── pick 실시간 스트림 (투표 카운트 반영) ──────────────────────────────────
  Stream<StockPick> getPickStream(String pickId) {
    return _db
        .collection('stock_picks')
        .doc(pickId)
        .snapshots()
        .map((doc) => StockPick.fromFirestore(doc));
  }

  // ── 투표 ──────────────────────────────────────────────────────────────────
  Future<String?> getUserVote(String uid, String pickId) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('votes')
        .doc(pickId)
        .get();
    return doc.data()?['vote'] as String?;
  }

  Future<void> setVote(
      String uid, String pickId, String? newVote, String? previousVote) async {
    final batch = _db.batch();
    final pickRef = _db.collection('stock_picks').doc(pickId);
    final voteRef =
        _db.collection('users').doc(uid).collection('votes').doc(pickId);

    if (previousVote == 'up') {
      batch.update(pickRef, {'upVotes': FieldValue.increment(-1)});
    } else if (previousVote == 'down') {
      batch.update(pickRef, {'downVotes': FieldValue.increment(-1)});
    }

    if (newVote == 'up') {
      batch.update(pickRef, {'upVotes': FieldValue.increment(1)});
      batch.set(voteRef, {'vote': 'up'});
    } else if (newVote == 'down') {
      batch.update(pickRef, {'downVotes': FieldValue.increment(1)});
      batch.set(voteRef, {'vote': 'down'});
    } else {
      batch.delete(voteRef);
    }

    await batch.commit();
  }

  // ── 실적 발표일 있는 픽 (캘린더용) ───────────────────────────────────────
  Stream<List<StockPick>> getPicksWithEarnings() {
    return _db
        .collection('stock_picks')
        .where('earningsDate', isGreaterThan: Timestamp(0, 0))
        .snapshots()
        .map((s) => s.docs.map((d) => StockPick.fromFirestore(d)).toList());
  }

  // ── 3개월 이내 활성 픽 (실적 탭 자동화용) ────────────────────────────────
  Future<List<StockPick>> getRecentActivePicks() async {
    final threeMonthsAgo =
        DateTime.now().subtract(const Duration(days: 90));
    final snapshot = await _db
        .collection('stock_picks')
        .where('status', isEqualTo: 'active')
        .where('createdAt',
            isGreaterThan: Timestamp.fromDate(threeMonthsAgo))
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((d) => StockPick.fromFirestore(d)).toList();
  }

  // ── 전체 종목 (활성 + 종료, 매매일지 종목 선택용) ────────────────────────
  Future<List<StockPick>> getAllStockPicksOnce() async {
    final snap = await _db
        .collection('stock_picks')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => StockPick.fromFirestore(d)).toList();
  }

  // ── 매매일지 ──────────────────────────────────────────────────────────────
  Stream<List<TradingJournal>> getMyJournals(String uid) {
    return _db
        .collection('trading_journal')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => TradingJournal.fromFirestore(d)).toList());
  }

  Stream<List<TradingJournal>> getPublicJournals() {
    return _db
        .collection('trading_journal')
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => TradingJournal.fromFirestore(d)).toList());
  }

  Future<(List<TradingJournal>, DocumentSnapshot?)> getPublicJournalsPaged({
    DocumentSnapshot? startAfter,
    int limit = 15,
  }) async {
    var query = _db
        .collection('trading_journal')
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snap = await query.get();
    final journals = snap.docs.map((d) => TradingJournal.fromFirestore(d)).toList();
    final lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (journals, lastDoc);
  }

  Future<void> addJournal(TradingJournal journal) {
    return _db.collection('trading_journal').add(journal.toFirestore());
  }

  Future<void> updateJournal(TradingJournal journal) {
    return _db
        .collection('trading_journal')
        .doc(journal.id)
        .update(journal.toFirestore());
  }

  Future<void> deleteJournal(String id) {
    return _db.collection('trading_journal').doc(id).delete();
  }

  Future<void> toggleJournalPublic(String id, bool isCurrentlyPublic) {
    return _db.collection('trading_journal').doc(id).update({
      'isPublic': !isCurrentlyPublic,
    });
  }

  // returns true if now liked, false if unliked
  Future<bool> likeJournal(String journalId, String uid) async {
    final likeRef = _db
        .collection('trading_journal')
        .doc(journalId)
        .collection('likes')
        .doc(uid);
    final likeDoc = await likeRef.get();
    final batch = _db.batch();
    final journalRef = _db.collection('trading_journal').doc(journalId);
    if (likeDoc.exists) {
      batch.delete(likeRef);
      batch.update(journalRef, {'likes': FieldValue.increment(-1)});
      await batch.commit();
      return false;
    } else {
      batch.set(likeRef, {'uid': uid, 'createdAt': Timestamp.fromDate(DateTime.now())});
      batch.update(journalRef, {'likes': FieldValue.increment(1)});
      await batch.commit();
      return true;
    }
  }

  Future<bool> hasLikedJournal(String journalId, String uid) async {
    final doc = await _db
        .collection('trading_journal')
        .doc(journalId)
        .collection('likes')
        .doc(uid)
        .get();
    return doc.exists;
  }

  // ── 자유게시판 Posts ──────────────────────────────────────────────────────

  Future<(List<Post>, DocumentSnapshot?)> getPostsPaged({
    DocumentSnapshot? startAfter,
    int limit = 15,
  }) async {
    var query = _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snap = await query.get();
    final posts = snap.docs.map((d) => Post.fromFirestore(d)).toList();
    final lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (posts, lastDoc);
  }

  Stream<List<Post>> getPostsByUid(String uid) {
    return _db
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final posts = snap.docs.map((d) => Post.fromFirestore(d)).toList();
          posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return posts;
        });
  }

  Future<void> createPost(Post post) {
    return _db.collection('posts').add(post.toFirestore());
  }

  Future<void> deletePost(String id) {
    return _db.collection('posts').doc(id).delete();
  }

  // returns true if now liked, false if unliked
  Future<bool> likePost(String postId, String uid) async {
    final likeRef = _db.collection('posts').doc(postId).collection('likes').doc(uid);
    final likeDoc = await likeRef.get();
    final batch = _db.batch();
    final postRef = _db.collection('posts').doc(postId);
    if (likeDoc.exists) {
      batch.delete(likeRef);
      batch.update(postRef, {'likes': FieldValue.increment(-1)});
      await batch.commit();
      return false;
    } else {
      batch.set(likeRef, {'uid': uid, 'createdAt': Timestamp.fromDate(DateTime.now())});
      batch.update(postRef, {'likes': FieldValue.increment(1)});
      await batch.commit();
      return true;
    }
  }

  Future<bool> hasLikedPost(String postId, String uid) async {
    final doc = await _db.collection('posts').doc(postId).collection('likes').doc(uid).get();
    return doc.exists;
  }

  // ─── 자유게시판 댓글 ──────────────────────────────────────────────────────

  Stream<List<Comment>> getPostComments(String postId) {
    return _db.collection('posts').doc(postId).collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Comment.fromFirestore).toList());
  }

  Future<void> addPostComment(String postId, Comment comment) {
    final commentRef = _db.collection('posts').doc(postId).collection('comments').doc();
    final batch = _db.batch();
    batch.set(commentRef, comment.toFirestore());
    batch.set(
      _db.collection('users').doc(comment.uid).collection('myPostComments').doc(commentRef.id),
      {
        'postId': postId,
        'text': comment.content,
        'createdAt': Timestamp.fromDate(comment.createdAt),
      },
    );
    return batch.commit();
  }

  Future<void> deletePostComment(String postId, String commentId) async {
    final commentRef = _db.collection('posts').doc(postId).collection('comments').doc(commentId);
    final commentSnap = await commentRef.get();
    final commentUid = commentSnap.data()?['uid'] as String?;

    final batch = _db.batch();
    batch.delete(commentRef);
    if (commentUid != null && commentUid.isNotEmpty) {
      batch.delete(
        _db.collection('users').doc(commentUid).collection('myPostComments').doc(commentId),
      );
    }
    await batch.commit();
  }

  // ─── 매매일지 댓글 ────────────────────────────────────────────────────────

  Stream<List<Comment>> getJournalComments(String journalId) {
    return _db.collection('trading_journal').doc(journalId).collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Comment.fromFirestore).toList());
  }

  Future<void> addJournalComment(String journalId, Comment comment) {
    return _db.collection('trading_journal').doc(journalId).collection('comments').add(comment.toFirestore());
  }

  Future<void> deleteJournalComment(String journalId, String commentId) {
    return _db.collection('trading_journal').doc(journalId).collection('comments').doc(commentId).delete();
  }

  // ─── 신고 ─────────────────────────────────────────────────────────────────

  Future<void> reportContent({
    required String reporterUid,
    required String targetUid,
    required String contentType, // 'post', 'journal', 'comment'
    required String contentId,
    required String reason,
  }) {
    return _db.collection('reports').add({
      'reporterUid': reporterUid,
      'targetUid': targetUid,
      'contentType': contentType,
      'contentId': contentId,
      'reason': reason,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<List<Map<String, dynamic>>> getReports() async {
    final snap = await _db.collection('reports').orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> deleteReport(String reportId) {
    return _db.collection('reports').doc(reportId).delete();
  }

  // ─── 차단 ─────────────────────────────────────────────────────────────────

  Future<void> blockUser(String uid, String targetUid) {
    return _db.collection('users').doc(uid).collection('blockedUsers').doc(targetUid).set({
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> unblockUser(String uid, String targetUid) {
    return _db.collection('users').doc(uid).collection('blockedUsers').doc(targetUid).delete();
  }

  Future<List<String>> getBlockedUids(String uid) async {
    final snap = await _db.collection('users').doc(uid).collection('blockedUsers').get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<bool> isBlocked(String uid, String targetUid) async {
    final doc = await _db.collection('users').doc(uid).collection('blockedUsers').doc(targetUid).get();
    return doc.exists;
  }
}
