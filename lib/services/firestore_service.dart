import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement.dart';
import '../models/comment.dart';
import '../models/market_analysis.dart';
import '../models/stock_pick.dart';

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
        'text': comment.text,
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

  Future<StockPick?> getStockPickOnce(String id) async {
    final doc = await _db.collection('stock_picks').doc(id).get();
    if (!doc.exists) return null;
    return StockPick.fromFirestore(doc);
  }

  Future<MarketAnalysis?> getMarketAnalysisOnce(String id) async {
    final doc = await _db.collection('market_analyses').doc(id).get();
    if (!doc.exists) return null;
    return MarketAnalysis.fromFirestore(doc);
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
}
