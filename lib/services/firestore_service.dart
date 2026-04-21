import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement.dart';
import '../models/comment.dart';
import '../models/fmkorea_stock_mention.dart';
import '../models/market_analysis.dart';
import '../models/post.dart';
import '../models/stock_pick.dart';
import '../models/trading_journal.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;
  static const int _postScore = 3;
  static const int _commentScore = 1;
  static const int _attendanceScore = 1;
  static const int _rewardAdDailyXp = 5;
  static const int _rewardAdDailyLimit = 3;
  static const List<int> _levelThresholds = [
    0, // Lv.1
    10, // Lv.2
    25, // Lv.3
    45, // Lv.4
    70, // Lv.5
    100, // Lv.6
    135, // Lv.7
    175, // Lv.8
    220, // Lv.9
    270, // Lv.10
    325, // Lv.11
    385, // Lv.12
    450, // Lv.13
    520, // Lv.14
    595, // Lv.15
    675, // Lv.16
    760, // Lv.17
    850, // Lv.18
    945, // Lv.19
    1045, // Lv.20
  ];
  static const int _afterTableStep = 110;

  int calculateUserLevel({
    required int postCount,
    required int commentCount,
    required int attendanceCount,
    int bonusXp = 0,
  }) {
    final score = calculateUserScore(
      postCount: postCount,
      commentCount: commentCount,
      attendanceCount: attendanceCount,
      bonusXp: bonusXp,
    );
    var level = 1;
    for (var i = 1; i < _levelThresholds.length; i++) {
      if (score >= _levelThresholds[i]) {
        level = i + 1;
      } else {
        return level;
      }
    }
    final extraXp = score - _levelThresholds.last;
    return level + (extraXp ~/ _afterTableStep);
  }

  int calculateUserScore({
    required int postCount,
    required int commentCount,
    required int attendanceCount,
    int bonusXp = 0,
  }) {
    return (postCount * _postScore) +
        (commentCount * _commentScore) +
        (attendanceCount * _attendanceScore) +
        bonusXp;
  }

  Map<String, num> calculateLevelProgress({
    required int postCount,
    required int commentCount,
    required int attendanceCount,
    int bonusXp = 0,
  }) {
    final score = calculateUserScore(
      postCount: postCount,
      commentCount: commentCount,
      attendanceCount: attendanceCount,
      bonusXp: bonusXp,
    );
    final level = calculateUserLevel(
      postCount: postCount,
      commentCount: commentCount,
      attendanceCount: attendanceCount,
      bonusXp: bonusXp,
    );

    final tableLevelCount = _levelThresholds.length;
    final currentLevelStartXp = level <= tableLevelCount
        ? _levelThresholds[level - 1]
        : _levelThresholds.last + ((level - tableLevelCount) * _afterTableStep);
    final nextLevelStartXp = level < tableLevelCount
        ? _levelThresholds[level]
        : _levelThresholds.last +
              ((level - tableLevelCount + 1) * _afterTableStep);
    final levelSpan = (nextLevelStartXp - currentLevelStartXp).clamp(
      1,
      1 << 30,
    );
    final currentXpInLevel = (score - currentLevelStartXp).clamp(0, levelSpan);
    final progress = (currentXpInLevel / levelSpan).clamp(0, 1);

    return {
      'level': level,
      'score': score,
      'currentLevelStartXp': currentLevelStartXp,
      'nextLevelStartXp': nextLevelStartXp,
      'currentXpInLevel': currentXpInLevel,
      'xpForNextLevel': levelSpan,
      'remainingXp': (nextLevelStartXp - score).clamp(0, 1 << 30),
      'progress': progress,
    };
  }

  String _kstDayKey([DateTime? now]) {
    final base = now ?? DateTime.now();
    final kst = base.toUtc().add(const Duration(hours: 9));
    final mm = kst.month.toString().padLeft(2, '0');
    final dd = kst.day.toString().padLeft(2, '0');
    return '${kst.year}-$mm-$dd';
  }

  Stream<Map<String, int>> watchUserLevelInfo(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data() ?? <String, dynamic>{};
      final postCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final attendanceCount = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final bonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final level =
          (data['level'] as num?)?.toInt() ??
          calculateUserLevel(
            postCount: postCount,
            commentCount: commentCount,
            attendanceCount: attendanceCount,
            bonusXp: bonusXp,
          );
      return {
        'level': level,
        'postCount': postCount,
        'commentCount': commentCount,
        'attendanceCount': attendanceCount,
        'bonusXp': bonusXp,
      };
    });
  }

  Stream<int> watchPublicUserLevel(String uid) {
    if (uid.isEmpty) return Stream.value(1);
    return _db.collection('user_public').doc(uid).snapshots().map((doc) {
      final level = (doc.data()?['level'] as num?)?.toInt();
      return level ?? 1;
    });
  }

  Future<void> syncUserContributionStats(String uid) async {
    if (uid.isEmpty) return;

    final postsSnap = await _db
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .get();
    final publicJournalsSnap = await _db
        .collection('trading_journal')
        .where('uid', isEqualTo: uid)
        .where('isPublic', isEqualTo: true)
        .get();

    final combinedPostCount =
        postsSnap.docs.length + publicJournalsSnap.docs.length;
    final userRef = _db.collection('users').doc(uid);
    final publicRef = _db.collection('user_public').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final attendanceCount = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final bonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final nextLevel = calculateUserLevel(
        postCount: combinedPostCount,
        commentCount: commentCount,
        attendanceCount: attendanceCount,
        bonusXp: bonusXp,
      );

      tx.set(userRef, {
        'postCount': combinedPostCount,
        'commentCount': commentCount,
        'attendanceCount': attendanceCount,
        'bonusXp': bonusXp,
        'level': nextLevel,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
    });
  }

  Future<void> recordDailyAttendance(String uid, {DateTime? now}) async {
    final todayKey = _kstDayKey(now);
    final userRef = _db.collection('users').doc(uid);
    final publicRef = _db.collection('user_public').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final currentPostCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final currentCommentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final currentAttendance = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final currentBonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final currentLevel = (data['level'] as num?)?.toInt() ?? 1;
      final lastAttendanceDate = data['lastAttendanceDate'] as String?;

      if (lastAttendanceDate == todayKey) {
        final recomputed = calculateUserLevel(
          postCount: currentPostCount,
          commentCount: currentCommentCount,
          attendanceCount: currentAttendance,
          bonusXp: currentBonusXp,
        );
        if (currentLevel != recomputed || !snap.exists) {
          tx.set(userRef, {
            'level': recomputed,
            'postCount': currentPostCount,
            'commentCount': currentCommentCount,
            'attendanceCount': currentAttendance,
            'bonusXp': currentBonusXp,
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          tx.set(publicRef, {'level': recomputed}, SetOptions(merge: true));
        } else {
          tx.set(userRef, {
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        return;
      }

      final nextAttendance = currentAttendance + 1;
      final nextLevel = calculateUserLevel(
        postCount: currentPostCount,
        commentCount: currentCommentCount,
        attendanceCount: nextAttendance,
        bonusXp: currentBonusXp,
      );

      tx.set(userRef, {
        'attendanceCount': nextAttendance,
        'postCount': currentPostCount,
        'commentCount': currentCommentCount,
        'bonusXp': currentBonusXp,
        'level': nextLevel,
        'lastAttendanceDate': todayKey,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
    });
  }

  Future<void> _adjustPostCount(String uid, int delta) async {
    final userRef = _db.collection('users').doc(uid);
    final publicRef = _db.collection('user_public').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final currentPostCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final currentCommentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final currentAttendance = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final currentBonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final nextPostCount = (currentPostCount + delta) < 0
          ? 0
          : (currentPostCount + delta);
      final nextLevel = calculateUserLevel(
        postCount: nextPostCount,
        commentCount: currentCommentCount,
        attendanceCount: currentAttendance,
        bonusXp: currentBonusXp,
      );
      tx.set(userRef, {
        'postCount': nextPostCount,
        'commentCount': currentCommentCount,
        'attendanceCount': currentAttendance,
        'bonusXp': currentBonusXp,
        'level': nextLevel,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
    });
  }

  Future<void> recordPostCreated(String uid) {
    return _adjustPostCount(uid, 1);
  }

  Future<void> recordPostRemoved(String uid) {
    return _adjustPostCount(uid, -1);
  }

  Future<void> _adjustCommentCount(String uid, int delta) async {
    final userRef = _db.collection('users').doc(uid);
    final publicRef = _db.collection('user_public').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final currentPostCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final currentCommentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final currentAttendance = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final currentBonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final nextCommentCount = (currentCommentCount + delta) < 0
          ? 0
          : (currentCommentCount + delta);
      final nextLevel = calculateUserLevel(
        postCount: currentPostCount,
        commentCount: nextCommentCount,
        attendanceCount: currentAttendance,
        bonusXp: currentBonusXp,
      );
      tx.set(userRef, {
        'postCount': currentPostCount,
        'commentCount': nextCommentCount,
        'attendanceCount': currentAttendance,
        'bonusXp': currentBonusXp,
        'level': nextLevel,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
    });
  }

  Future<void> recordCommentCreated(String uid) {
    return _adjustCommentCount(uid, 1);
  }

  Future<void> recordCommentRemoved(String uid) {
    return _adjustCommentCount(uid, -1);
  }

  Stream<List<StockPick>> getStockPicks({bool premiumOnly = false}) {
    Query query = _db
        .collection('stock_picks')
        .orderBy('createdAt', descending: true);

    if (premiumOnly) {
      query = query.where('isPremium', isEqualTo: true);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => StockPick.fromFirestore(doc))
          .where((p) => !p.isCompleted)
          .toList(),
    );
  }

  Future<void> addStockPick(StockPick pick) {
    return _db.collection('stock_picks').add(pick.toFirestore());
  }

  Future<void> updateStockPick(StockPick pick) {
    return _db
        .collection('stock_picks')
        .doc(pick.id)
        .update(pick.toFirestore());
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
          final list = s.docs
              .map((d) => Announcement.fromFirestore(d))
              .toList();
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

  Future<void> setNickname(String uid, String nickname) async {
    // 기존 닉네임 삭제 후 새 닉네임 등록
    final userDoc = await _db.collection('users').doc(uid).get();
    final oldNickname = userDoc.data()?['nickname'] as String?;
    if (oldNickname != null && oldNickname != nickname) {
      await _db.collection('nicknames').doc(oldNickname).delete();
    }
    await _db.collection('nicknames').doc(nickname).set({'uid': uid});
    await _db.collection('users').doc(uid).set({
      'nickname': nickname,
    }, SetOptions(merge: true));
    await _db.collection('user_public').doc(uid).set({
      'nickname': nickname,
    }, SetOptions(merge: true));
  }

  Future<bool> isNicknameTaken(String nickname, String currentUid) async {
    final doc = await _db.collection('nicknames').doc(nickname).get();
    if (!doc.exists) return false;
    // 자기 자신 닉네임은 중복 허용
    return doc.data()?['uid'] != currentUid;
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
      return ref.set({
        'favorites': FieldValue.arrayRemove([pickId]),
      }, SetOptions(merge: true));
    } else {
      return ref.set({
        'favorites': FieldValue.arrayUnion([pickId]),
      }, SetOptions(merge: true));
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
          list.sort(
            (a, b) => (b.closedAt ?? DateTime(0)).compareTo(
              a.closedAt ?? DateTime(0),
            ),
          );
          return list;
        });
  }

  // ── 시황 분석 ─────────────────────────────────────────────────────────
  Stream<List<MarketAnalysis>> getMarketAnalyses() {
    return _db
        .collection('market_analyses')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => MarketAnalysis.fromFirestore(d)).toList(),
        );
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
      _db
          .collection('users')
          .doc(comment.uid)
          .collection('myComments')
          .doc(pickCommentRef.id),
      {
        'pickId': pickId,
        'text': comment.content,
        'createdAt': Timestamp.fromDate(comment.createdAt),
      },
    );
    await batch.commit();
    await recordCommentCreated(comment.uid);
  }

  Future<void> deleteComment(
    String pickId,
    String commentId, {
    String? uid,
  }) async {
    var commentUid = uid;
    if (commentUid == null || commentUid.isEmpty) {
      final commentSnap = await _db
          .collection('stock_picks')
          .doc(pickId)
          .collection('comments')
          .doc(commentId)
          .get();
      commentUid = commentSnap.data()?['uid'] as String?;
    }
    final batch = _db.batch();
    batch.delete(
      _db
          .collection('stock_picks')
          .doc(pickId)
          .collection('comments')
          .doc(commentId),
    );
    if (commentUid != null && commentUid.isNotEmpty) {
      batch.delete(
        _db
            .collection('users')
            .doc(commentUid)
            .collection('myComments')
            .doc(commentId),
      );
    }
    await batch.commit();
    if (commentUid != null && commentUid.isNotEmpty) {
      await recordCommentRemoved(commentUid);
    }
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
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
    }

    final items =
        <
          ({String commentId, String postId, String text, DateTime createdAt})
        >[];

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
          _db
              .collection('users')
              .doc(uid)
              .collection('myPostComments')
              .doc(item.commentId),
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
        .map(
          (item) =>
              (postId: item.postId, text: item.text, createdAt: item.createdAt),
        )
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

  // ── 관리자: 유저 목록 (페이지네이션) ─────────────────────────────────────
  Future<
    ({
      List<Map<String, dynamic>> users,
      DocumentSnapshot? lastDoc,
      bool hasMore,
    })
  >
  getAdminUserListPaged({DocumentSnapshot? startAfter, int limit = 100}) async {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);

    final snap = await q.get();
    final users = snap.docs.map((doc) {
      final data = doc.data();
      final postCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final attendanceCount = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final bonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final level =
          (data['level'] as num?)?.toInt() ??
          calculateUserLevel(
            postCount: postCount,
            commentCount: commentCount,
            attendanceCount: attendanceCount,
            bonusXp: bonusXp,
          );
      return {
        'uid': doc.id,
        'nickname': data['nickname'] as String? ?? '',
        'createdAt': data['createdAt'] as Timestamp?,
        'level': level,
        'postCount': postCount,
        'commentCount': commentCount,
      };
    }).toList();

    return (
      users: users,
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : startAfter,
      hasMore: snap.docs.length == limit,
    );
  }

  Future<({int totalUsers, int todayUsers})> getAdminUserListSummary() async {
    final totalSnap = await _db.collection('users').count().get();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final todaySnap = await _db
        .collection('users')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .count()
        .get();

    return (totalUsers: totalSnap.count ?? 0, todayUsers: todaySnap.count ?? 0);
  }

  Stream<Map<String, int>> watchRewardAdStatus(String uid) {
    if (uid.isEmpty) {
      return Stream.value({
        'canWatchToday': 1,
        'remainingCount': _rewardAdDailyLimit,
        'watchedCount': 0,
        'dailyLimit': _rewardAdDailyLimit,
      });
    }
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data() ?? <String, dynamic>{};
      final lastRewardAdDate = data['lastRewardAdDate'] as String?;
      final sameDay = lastRewardAdDate == _kstDayKey();
      final rawCount = (data['rewardAdCountToday'] as num?)?.toInt() ?? 0;
      final watchedCount = sameDay
          ? rawCount.clamp(0, _rewardAdDailyLimit).toInt()
          : 0;
      final remainingCount = (_rewardAdDailyLimit - watchedCount)
          .clamp(0, _rewardAdDailyLimit)
          .toInt();
      return {
        'canWatchToday': remainingCount > 0 ? 1 : 0,
        'remainingCount': remainingCount,
        'watchedCount': watchedCount,
        'dailyLimit': _rewardAdDailyLimit,
      };
    });
  }

  Stream<bool> watchCanWatchRewardAdToday(String uid) {
    return watchRewardAdStatus(
      uid,
    ).map((status) => status['canWatchToday'] == 1);
  }

  Future<bool> grantDailyRewardAdXp(
    String uid, {
    int xp = _rewardAdDailyXp,
  }) async {
    final todayKey = _kstDayKey();
    final userRef = _db.collection('users').doc(uid);
    final publicRef = _db.collection('user_public').doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final lastRewardAdDate = data['lastRewardAdDate'] as String?;
      final rawCount = (data['rewardAdCountToday'] as num?)?.toInt() ?? 0;
      final currentCount = lastRewardAdDate == todayKey
          ? rawCount.clamp(0, _rewardAdDailyLimit).toInt()
          : 0;
      if (currentCount >= _rewardAdDailyLimit) return false;

      final postCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final attendanceCount = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final currentBonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final nextCount = currentCount + 1;
      final nextBonusXp = currentBonusXp + xp;
      final nextLevel = calculateUserLevel(
        postCount: postCount,
        commentCount: commentCount,
        attendanceCount: attendanceCount,
        bonusXp: nextBonusXp,
      );

      tx.set(userRef, {
        'postCount': postCount,
        'commentCount': commentCount,
        'attendanceCount': attendanceCount,
        'bonusXp': nextBonusXp,
        'level': nextLevel,
        'lastRewardAdDate': todayKey,
        'rewardAdCountToday': nextCount,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
      return true;
    });
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
  Future<void> sendPushNotification({
    required String title,
    required String body,
  }) {
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
    return _db.collection('users').doc(uid).collection('memos').doc(pickId).set(
      {'text': text, 'updatedAt': Timestamp.fromDate(DateTime.now())},
    );
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
    String uid,
    String pickId,
    String? newVote,
    String? previousVote,
  ) async {
    final batch = _db.batch();
    final pickRef = _db.collection('stock_picks').doc(pickId);
    final voteRef = _db
        .collection('users')
        .doc(uid)
        .collection('votes')
        .doc(pickId);

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

  // ── 3개월 이내 활성 픽 (실적 탭 자동화용) ────────────────────────────────
  Future<List<StockPick>> getRecentActivePicks() async {
    final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
    final snapshot = await _db
        .collection('stock_picks')
        .where('status', isEqualTo: 'active')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(threeMonthsAgo))
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
        .map(
          (s) => s.docs.map((d) => TradingJournal.fromFirestore(d)).toList(),
        );
  }

  Stream<List<TradingJournal>> getPublicJournals() {
    return _db
        .collection('trading_journal')
        .where('isPublic', isEqualTo: true)
        .orderBy('publishedAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => TradingJournal.fromFirestore(d)).toList(),
        );
  }

  Future<List<TradingJournal>> getMyJournalsByUidOnce(String uid) async {
    final snap = await _db
        .collection('trading_journal')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => TradingJournal.fromFirestore(d)).toList();
  }

  Stream<List<TradingJournal>> getPublicJournalsByUid(String uid) {
    return _db
        .collection('trading_journal')
        .where('uid', isEqualTo: uid)
        .where('isPublic', isEqualTo: true)
        .orderBy('publishedAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => TradingJournal.fromFirestore(d)).toList(),
        );
  }

  Future<List<TradingJournal>> getPublicJournalsByUidOnce(String uid) async {
    final snap = await _db
        .collection('trading_journal')
        .where('uid', isEqualTo: uid)
        .where('isPublic', isEqualTo: true)
        .orderBy('publishedAt', descending: true)
        .get();
    return snap.docs.map((d) => TradingJournal.fromFirestore(d)).toList();
  }

  Future<(List<TradingJournal>, DocumentSnapshot?)> getPublicJournalsPaged({
    DocumentSnapshot? startAfter,
    int limit = 15,
  }) async {
    var query = _db
        .collection('trading_journal')
        .where('isPublic', isEqualTo: true)
        .orderBy('publishedAt', descending: true)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snap = await query.get();
    final journals = snap.docs
        .map((d) => TradingJournal.fromFirestore(d))
        .toList();
    final lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (journals, lastDoc);
  }

  Future<TradingJournal?> getJournalById(String id) async {
    try {
      final snap = await _db.collection('trading_journal').doc(id).get();
      if (!snap.exists) return null;
      return TradingJournal.fromFirestore(snap);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  Future<void> addJournal(TradingJournal journal) async {
    final now = DateTime.now();
    final payload = {
      ...journal.toFirestore(),
      if (journal.isPublic)
        'publishedAt': Timestamp.fromDate(journal.publishedAt ?? now),
    };
    await _db.collection('trading_journal').add(payload);
    if (journal.isPublic) {
      await recordPostCreated(journal.uid);
    }
  }

  Future<void> updateJournal(TradingJournal journal) async {
    final ref = _db.collection('trading_journal').doc(journal.id);
    final before = await ref.get();
    final wasPublic = before.data()?['isPublic'] as bool? ?? false;
    final isPublic = journal.isPublic;
    final now = DateTime.now();
    final payload = <String, dynamic>{...journal.toFirestore()};
    if (!wasPublic && isPublic) {
      payload['publishedAt'] = Timestamp.fromDate(now);
    } else if (wasPublic && isPublic) {
      final prevPublishedAt = before.data()?['publishedAt'] as Timestamp?;
      payload['publishedAt'] = prevPublishedAt ?? Timestamp.fromDate(now);
    }
    await ref.update(payload);
    if (!wasPublic && isPublic) {
      await recordPostCreated(journal.uid);
    } else if (wasPublic && !isPublic) {
      await recordPostRemoved(journal.uid);
    }
  }

  Future<void> deleteJournal(String id) async {
    final ref = _db.collection('trading_journal').doc(id);
    final snap = await ref.get();
    final data = snap.data();
    final uid = data?['uid'] as String?;
    final isPublic = data?['isPublic'] as bool? ?? false;
    await ref.delete();
    if (uid != null && uid.isNotEmpty && isPublic) {
      await recordPostRemoved(uid);
    }
  }

  Future<void> toggleJournalPublic(String id, bool isCurrentlyPublic) async {
    final ref = _db.collection('trading_journal').doc(id);
    final snap = await ref.get();
    final uid = snap.data()?['uid'] as String?;
    final currentIsPublic =
        snap.data()?['isPublic'] as bool? ?? isCurrentlyPublic;
    final nextIsPublic = !currentIsPublic;
    await ref.update({
      'isPublic': nextIsPublic,
      if (nextIsPublic) 'publishedAt': Timestamp.fromDate(DateTime.now()),
    });
    if (uid != null && uid.isNotEmpty) {
      if (!currentIsPublic && nextIsPublic) {
        await recordPostCreated(uid);
      } else if (currentIsPublic && !nextIsPublic) {
        await recordPostRemoved(uid);
      }
    }
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
      batch.set(likeRef, {
        'uid': uid,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
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
    return _db.collection('posts').where('uid', isEqualTo: uid).snapshots().map(
      (snap) {
        final posts = snap.docs.map((d) => Post.fromFirestore(d)).toList();
        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return posts;
      },
    );
  }

  Future<void> createPost(Post post) async {
    await _db.collection('posts').add(post.toFirestore());
    await recordPostCreated(post.uid);
  }

  Future<void> deletePost(String id) async {
    final ref = _db.collection('posts').doc(id);
    final snap = await ref.get();
    final uid = snap.data()?['uid'] as String?;
    await ref.delete();
    if (uid != null && uid.isNotEmpty) {
      await recordPostRemoved(uid);
    }
  }

  // returns true if now liked, false if unliked
  Future<bool> likePost(String postId, String uid) async {
    final likeRef = _db
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(uid);
    final likeDoc = await likeRef.get();
    final batch = _db.batch();
    final postRef = _db.collection('posts').doc(postId);
    if (likeDoc.exists) {
      batch.delete(likeRef);
      batch.update(postRef, {'likes': FieldValue.increment(-1)});
      await batch.commit();
      return false;
    } else {
      batch.set(likeRef, {
        'uid': uid,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
      batch.update(postRef, {'likes': FieldValue.increment(1)});
      await batch.commit();
      return true;
    }
  }

  Future<bool> hasLikedPost(String postId, String uid) async {
    final doc = await _db
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(uid)
        .get();
    return doc.exists;
  }

  // ─── 자유게시판 댓글 ──────────────────────────────────────────────────────

  Stream<List<Comment>> getPostComments(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Comment.fromFirestore).toList());
  }

  Future<int> getPostCommentCount(String postId) async {
    final snap = await _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<void> addPostComment(String postId, Comment comment) async {
    final commentRef = _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc();
    final batch = _db.batch();
    batch.set(commentRef, comment.toFirestore());
    batch.set(
      _db
          .collection('users')
          .doc(comment.uid)
          .collection('myPostComments')
          .doc(commentRef.id),
      {
        'postId': postId,
        'text': comment.content,
        'createdAt': Timestamp.fromDate(comment.createdAt),
      },
    );
    await batch.commit();
    await recordCommentCreated(comment.uid);
  }

  Future<void> deletePostComment(String postId, String commentId) async {
    final commentRef = _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    final commentSnap = await commentRef.get();
    final commentUid = commentSnap.data()?['uid'] as String?;

    final batch = _db.batch();
    batch.delete(commentRef);
    if (commentUid != null && commentUid.isNotEmpty) {
      batch.delete(
        _db
            .collection('users')
            .doc(commentUid)
            .collection('myPostComments')
            .doc(commentId),
      );
    }
    await batch.commit();
    if (commentUid != null && commentUid.isNotEmpty) {
      await recordCommentRemoved(commentUid);
    }
  }

  // ─── 매매일지 댓글 ────────────────────────────────────────────────────────

  Stream<List<Comment>> getJournalComments(String journalId) {
    return _db
        .collection('trading_journal')
        .doc(journalId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Comment.fromFirestore).toList());
  }

  Future<int> getJournalCommentCount(String journalId) async {
    final snap = await _db
        .collection('trading_journal')
        .doc(journalId)
        .collection('comments')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<void> addJournalComment(String journalId, Comment comment) async {
    await _db
        .collection('trading_journal')
        .doc(journalId)
        .collection('comments')
        .add(comment.toFirestore());
    await recordCommentCreated(comment.uid);
  }

  Future<void> deleteJournalComment(String journalId, String commentId) async {
    final ref = _db
        .collection('trading_journal')
        .doc(journalId)
        .collection('comments')
        .doc(commentId);
    final snap = await ref.get();
    final commentUid = snap.data()?['uid'] as String?;
    await ref.delete();
    if (commentUid != null && commentUid.isNotEmpty) {
      await recordCommentRemoved(commentUid);
    }
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
    final snap = await _db
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> deleteReport(String reportId) {
    return _db.collection('reports').doc(reportId).delete();
  }

  // ─── 차단 ─────────────────────────────────────────────────────────────────

  Future<void> blockUser(String uid, String targetUid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('blockedUsers')
        .doc(targetUid)
        .set({'createdAt': Timestamp.fromDate(DateTime.now())});
  }

  Future<void> unblockUser(String uid, String targetUid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('blockedUsers')
        .doc(targetUid)
        .delete();
  }

  Future<List<String>> getBlockedUids(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('blockedUsers')
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<bool> isBlocked(String uid, String targetUid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('blockedUsers')
        .doc(targetUid)
        .get();
    return doc.exists;
  }

  Stream<FmkoreaStockMentionsSnapshot?> getRealtimeFmkoreaStockMentions() {
    return _db
        .collection('fmkorea_stock_mentions_realtime')
        .doc('today')
        .snapshots()
        .asyncMap((doc) async {
          if (doc.exists) {
            final parsed = FmkoreaStockMentionsSnapshot.fromFirestore(doc);
            if (parsed.topMentions.isNotEmpty) return parsed;
          }
          final today = await getTodayDailyFmkoreaStockMentions();
          if (today != null) return today;
          return getLatestDailyFmkoreaStockMentions();
        });
  }

  Stream<FmkoreaStockMentionsSnapshot?> getRealtimeOnlyFmkoreaStockMentions() {
    return _db
        .collection('fmkorea_stock_mentions_realtime')
        .doc('today')
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final parsed = FmkoreaStockMentionsSnapshot.fromFirestore(doc);
          if (parsed.topMentions.isEmpty) return null;
          return parsed;
        });
  }

  Future<FmkoreaStockMentionsSnapshot?>
  getLatestDailyFmkoreaStockMentions() async {
    final snap = await _db
        .collection('fmkorea_stock_mentions_daily')
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return FmkoreaStockMentionsSnapshot.fromFirestore(snap.docs.first);
  }

  Future<FmkoreaStockMentionsSnapshot?>
  getTodayDailyFmkoreaStockMentions() async {
    final nowUtc = DateTime.now().toUtc();
    final nowKst = nowUtc.add(const Duration(hours: 9));
    final mm = nowKst.month.toString().padLeft(2, '0');
    final dd = nowKst.day.toString().padLeft(2, '0');
    final docId = '${nowKst.year}-$mm-$dd';
    final doc = await _db
        .collection('fmkorea_stock_mentions_daily')
        .doc(docId)
        .get();
    if (!doc.exists) return null;
    final parsed = FmkoreaStockMentionsSnapshot.fromFirestore(doc);
    if (parsed.topMentions.isEmpty) return null;
    return parsed;
  }

  Future<FmkoreaStockMentionsSnapshot?>
  getPreviousDailyFmkoreaStockMentions() async {
    final nowUtc = DateTime.now().toUtc();
    final nowKst = nowUtc.add(const Duration(hours: 9));
    final mm = nowKst.month.toString().padLeft(2, '0');
    final dd = nowKst.day.toString().padLeft(2, '0');
    final todayDocId = '${nowKst.year}-$mm-$dd';

    final snap = await _db
        .collection('fmkorea_stock_mentions_daily')
        .orderBy('updatedAt', descending: true)
        .limit(7)
        .get();
    for (final doc in snap.docs) {
      if (doc.id == todayDocId) continue;
      final parsed = FmkoreaStockMentionsSnapshot.fromFirestore(doc);
      if (parsed.topMentions.isNotEmpty) return parsed;
    }
    return null;
  }
}
