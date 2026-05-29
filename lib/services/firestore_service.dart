import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement.dart';
import '../models/comment.dart';
import '../models/fmkorea_stock_mention.dart';
import '../models/market_analysis.dart';
import '../models/market_feature_stock.dart';
import '../models/post.dart';
import '../models/stock_pick.dart';
import '../models/trading_journal.dart';
import 'stock_price_service.dart';

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
  static const Map<String, bool> _defaultNotificationSettings = {
    'newPick': true,
    'pickComment': true,
    'postComment': true,
    'journalComment': true,
    'journalWriteReminder': false,
  };

  static String favoriteStockKey(String market, String ticker) {
    final normalizedMarket = market.trim().toUpperCase();
    final normalizedTicker = ticker.trim().toUpperCase();
    return '${normalizedMarket}_$normalizedTicker';
  }

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
      final updates = <String, dynamic>{
        'postCount': currentPostCount,
        'commentCount': nextCommentCount,
        'attendanceCount': currentAttendance,
        'bonusXp': currentBonusXp,
        'level': nextLevel,
        'lastActiveAt': FieldValue.serverTimestamp(),
        if (delta > 0) 'lastCommentDate': _kstDayKey(),
      };
      tx.set(userRef, updates, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
    });
  }

  Future<void> recordCommentCreated(String uid) async {
    await _adjustCommentCount(uid, 1);
    await _markDailyMissionDate(uid, 'lastCommentMissionDate');
  }

  /// 매매일지 작성 일일 미션 보상.
  /// 같은 KST 날짜에 이미 받았으면 무시. 처음 작성한 일지에만 bonusXp +5.
  Future<void> grantDailyJournalMissionXp(
    String uid, {
    int xp = 5,
  }) async {
    if (uid.isEmpty) return;
    final todayKey = _kstDayKey();
    final userRef = _db.collection('users').doc(uid);
    final publicRef = _db.collection('user_public').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final lastDate = data['lastJournalMissionDate'] as String?;
      final alreadyDoneToday = lastDate == todayKey;

      final postCount = (data['postCount'] as num?)?.toInt() ?? 0;
      final commentCount = (data['commentCount'] as num?)?.toInt() ?? 0;
      final attendanceCount = (data['attendanceCount'] as num?)?.toInt() ?? 0;
      final currentBonusXp = (data['bonusXp'] as num?)?.toInt() ?? 0;
      final nextBonusXp = alreadyDoneToday
          ? currentBonusXp
          : currentBonusXp + xp;
      final nextLevel = calculateUserLevel(
        postCount: postCount,
        commentCount: commentCount,
        attendanceCount: attendanceCount,
        bonusXp: nextBonusXp,
      );

      tx.set(userRef, {
        'lastJournalMissionDate': todayKey,
        'bonusXp': nextBonusXp,
        'level': nextLevel,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(publicRef, {'level': nextLevel}, SetOptions(merge: true));
    });
  }

  Future<void> recordCommentRemoved(String uid) {
    return _adjustCommentCount(uid, -1);
  }

  Stream<List<StockPick>> getStockPicks({bool premiumOnly = false}) {
    Query query = _db
        .collection('stock_picks')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true);

    if (premiumOnly) {
      query = query.where('isPremium', isEqualTo: true);
    }

    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => StockPick.fromFirestore(doc)).toList(),
    );
  }

  Stream<List<StockPick>> getAllStockPicks() {
    return _db
        .collection('stock_picks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => StockPick.fromFirestore(doc))
              .toList();
        });
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

  Stream<Announcement?> getLatestAnnouncement() {
    return _db
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (s) =>
              s.docs.isEmpty ? null : Announcement.fromFirestore(s.docs.first),
        );
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

  Future<List<StockPick>> getFavoriteStockPicksPreview(
    Set<String> favoriteIds, {
    int limit = 4,
  }) async {
    if (favoriteIds.isEmpty || limit <= 0) return [];

    final ids = favoriteIds.take(20).toList(growable: false);
    final docs = await Future.wait(
      ids.map((id) => _db.collection('stock_picks').doc(id).get()),
    );

    return docs
        .where((doc) => doc.exists)
        .map((doc) => StockPick.fromFirestore(doc))
        .where((pick) => !pick.isCompleted)
        .take(limit)
        .toList();
  }

  Future<void> toggleFavorite(String uid, String pickId, bool isCurrentlyFav) {
    final ref = _db.collection('users').doc(uid);
    if (isCurrentlyFav) {
      return ref.set({
        'favorites': FieldValue.arrayRemove([pickId]),
      }, SetOptions(merge: true));
    } else {
      final batch = _db.batch();
      batch.set(ref, {
        'favorites': FieldValue.arrayUnion([pickId]),
      }, SetOptions(merge: true));
      // 관심추천주 추가 시 해당 종목 댓글 알림을 기본 ON 처리 (유저가 상세에서 OFF 가능)
      final subRef = ref.collection('pick_comment_subscriptions').doc(pickId);
      batch.set(subRef, {
        'pickId': pickId,
        'enabled': true,
        'autoFromFavorite': true,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
      return batch.commit();
    }
  }

  Stream<List<String>> getFavoriteStockIds(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      return List<String>.from(doc.data()?['favoriteStockIds'] ?? const []);
    });
  }

  Stream<bool> watchIsFavoriteStock(String uid, String key) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final stocks = Map<String, dynamic>.from(
        (doc.data()?['favoriteStocks'] as Map?) ?? const {},
      );
      return stocks.containsKey(key);
    });
  }

  Stream<List<StockPick>> getFavoriteStocks(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final rawMap = Map<String, dynamic>.from(
        (doc.data()?['favoriteStocks'] as Map?) ?? const {},
      );
      final items = rawMap.entries
          .map((entry) {
            final data = Map<String, dynamic>.from(
              (entry.value as Map?) ?? const {},
            );
            final ticker = (data['ticker'] as String? ?? '').trim();
            final market = (data['market'] as String? ?? 'KS').trim();
            if (ticker.isEmpty) return null;
            final addedAt = (data['addedAt'] as num?)?.toInt() ?? 0;
            return StockPick(
              id: 'stock_${market.toUpperCase()}_${ticker.toUpperCase()}',
              ticker: ticker.toUpperCase(),
              name: (data['name'] as String? ?? ticker).trim(),
              buyPrice: 0,
              targetPrice: 0,
              reason: '관심종목으로 등록한 종목입니다.',
              category: 'STOCK',
              market: market.toUpperCase(),
              isPremium: false,
              createdAt: addedAt > 0
                  ? DateTime.fromMillisecondsSinceEpoch(addedAt)
                  : DateTime.now(),
              status: 'active',
            );
          })
          .whereType<StockPick>()
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  Future<void> toggleFavoriteStock(
    String uid,
    StockPick stock,
    bool isCurrentlyFav,
  ) async {
    final ref = _db.collection('users').doc(uid);
    final key = favoriteStockKey(stock.market, stock.ticker);

    if (isCurrentlyFav) {
      // 해제: dot-notation으로 맵 키를 직접 삭제
      await ref.update({
        'favoriteStocks.$key': FieldValue.delete(),
        'favoriteStockIds': FieldValue.arrayRemove([key]),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 등록: 트랜잭션으로 중복 방지
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final ids = List<String>.from(data['favoriteStockIds'] ?? const []);
        if (!ids.contains(key)) ids.insert(0, key);
        tx.set(ref, {
          'favoriteStockIds': ids,
          'favoriteStocks': {
            key: {
              'ticker': stock.ticker.trim().toUpperCase(),
              'name': stock.name.trim().isEmpty
                  ? stock.ticker.trim().toUpperCase()
                  : stock.name.trim(),
              'market': stock.market.trim().toUpperCase(),
              'addedAt': DateTime.now().millisecondsSinceEpoch,
            },
          },
          'lastActiveAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    }
  }

  Future<void> toggleFavoriteStockByInfo(
    String uid,
    String ticker,
    String name,
    String market,
    bool isCurrentlyFav,
  ) async {
    final ref = _db.collection('users').doc(uid);
    final key = favoriteStockKey(market, ticker);

    if (isCurrentlyFav) {
      await ref.update({
        'favoriteStocks.$key': FieldValue.delete(),
        'favoriteStockIds': FieldValue.arrayRemove([key]),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final ids = List<String>.from(data['favoriteStockIds'] ?? const []);
        if (!ids.contains(key)) ids.insert(0, key);
        tx.set(ref, {
          'favoriteStockIds': ids,
          'favoriteStocks': {
            key: {
              'ticker': ticker.trim().toUpperCase(),
              'name': name.trim().isEmpty
                  ? ticker.trim().toUpperCase()
                  : name.trim(),
              'market': market.trim().toUpperCase(),
              'addedAt': DateTime.now().millisecondsSinceEpoch,
            },
          },
          'lastActiveAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
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

  Stream<List<Comment>> getMarketAnalysisComments(String analysisId) {
    return _db
        .collection('market_analyses')
        .doc(analysisId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(Comment.fromFirestore).toList());
  }

  Future<void> addMarketAnalysisComment(
    String analysisId,
    Comment comment,
  ) async {
    await _db
        .collection('market_analyses')
        .doc(analysisId)
        .collection('comments')
        .add(comment.toFirestore());
    await recordCommentCreated(comment.uid);
  }

  Future<void> deleteMarketAnalysisComment(
    String analysisId,
    String commentId,
  ) async {
    final ref = _db
        .collection('market_analyses')
        .doc(analysisId)
        .collection('comments')
        .doc(commentId);
    final snap = await ref.get();
    final commentUid = snap.data()?['uid'] as String?;
    await ref.delete();
    if (commentUid != null && commentUid.isNotEmpty) {
      await recordCommentRemoved(commentUid);
    }
  }

  Stream<List<MarketFeatureStock>> getMarketFeatureStocks({
    String? group,
    String? pattern,
    int limit = 500,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('market_feature_stocks');
    if (group != null && group.isNotEmpty) {
      query = query.where('group', isEqualTo: group);
    }
    if (pattern != null && pattern.isNotEmpty) {
      query = query.where('pattern', isEqualTo: pattern);
    }
    return query
        .orderBy('sourceDate', descending: true)
        .orderBy('score', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) {
          final items = s.docs.map((d) => MarketFeatureStock.fromFirestore(d));
          final deduped = <String, MarketFeatureStock>{};
          for (final item in items) {
            deduped.putIfAbsent(item.ticker, () => item);
          }
          return deduped.values.toList();
        });
  }

  // ── 코멘트 ────────────────────────────────────────────────────────────
  Stream<List<Comment>> getComments(String pickId) {
    return _db
        .collection('stock_picks')
        .doc(pickId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
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
    // 댓글을 작성한 경우 해당 추천주 댓글 알림을 자동 ON 처리
    final pickSubRef = _db
        .collection('users')
        .doc(comment.uid)
        .collection('pick_comment_subscriptions')
        .doc(pickId);
    batch.set(pickSubRef, {
      'pickId': pickId,
      'enabled': true,
      'autoFromComment': true,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
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

  Map<String, dynamic> _adminUserFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
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
      ...data,
      'uid': doc.id,
      'nickname': data['nickname'] as String? ?? '',
      'createdAt': data['createdAt'] as Timestamp?,
      'lastActiveAt': data['lastActiveAt'] as Timestamp?,
      'level': level,
      'postCount': postCount,
      'commentCount': commentCount,
      'attendanceCount': attendanceCount,
      'bonusXp': bonusXp,
    };
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
    final users = snap.docs.map(_adminUserFromDoc).toList();

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

  Future<List<Map<String, dynamic>>> searchAdminUsers(
    String query, {
    int limit = 200,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final matches = <String, Map<String, dynamic>>{};
    final exactUidDoc = await _db.collection('users').doc(query.trim()).get();
    if (exactUidDoc.exists) {
      matches[exactUidDoc.id] = _adminUserFromDoc(exactUidDoc);
    }

    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var hasMore = true;
    while (hasMore && matches.length < limit) {
      Query<Map<String, dynamic>> q = _db
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(500);
      if (cursor != null) q = q.startAfterDocument(cursor);

      final snap = await q.get();
      if (snap.docs.isEmpty) break;

      for (final doc in snap.docs) {
        final user = _adminUserFromDoc(doc);
        final uid = (user['uid'] as String? ?? '').toLowerCase();
        final nickname = (user['nickname'] as String? ?? '').toLowerCase();
        if (uid.contains(normalized) || nickname.contains(normalized)) {
          matches[doc.id] = user;
          if (matches.length >= limit) break;
        }
      }

      cursor = snap.docs.last;
      hasMore = snap.docs.length == 500;
    }

    return matches.values.toList();
  }

  Future<Map<String, dynamic>?> getAdminUserDetail(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return _adminUserFromDoc(doc);
  }

  Future<({int postCount, int journalCount, int reportCount})>
  getAdminUserActivitySummary(String uid) async {
    final postsSnap = await _db
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .count()
        .get();
    final journalsSnap = await _db
        .collection('trading_journal')
        .where('uid', isEqualTo: uid)
        .count()
        .get();
    final reportsSnap = await _db
        .collection('reports')
        .where('targetUid', isEqualTo: uid)
        .count()
        .get();

    return (
      postCount: postsSnap.count ?? 0,
      journalCount: journalsSnap.count ?? 0,
      reportCount: reportsSnap.count ?? 0,
    );
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

  Stream<({bool commentDone, bool memoDone, int adRemaining, int adLimit})>
  watchDailyMissions(String uid) {
    if (uid.isEmpty) {
      return Stream.value((
        commentDone: false,
        memoDone: false,
        adRemaining: _rewardAdDailyLimit,
        adLimit: _rewardAdDailyLimit,
      ));
    }
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data() ?? <String, dynamic>{};
      final today = _kstDayKey();
      final lastAdDate = data['lastRewardAdDate'] as String?;
      final rawCount = (data['rewardAdCountToday'] as num?)?.toInt() ?? 0;
      final watchedCount = lastAdDate == today
          ? rawCount.clamp(0, _rewardAdDailyLimit).toInt()
          : 0;
      return (
        commentDone:
            (data['lastCommentMissionDate'] as String?) == today ||
            (data['lastCommentDate'] as String?) == today,
        memoDone: (data['lastJournalMissionDate'] as String?) == today,
        adRemaining: _rewardAdDailyLimit - watchedCount,
        adLimit: _rewardAdDailyLimit,
      );
    });
  }

  Stream<bool> watchCanWatchRewardAdToday(String uid) {
    return watchRewardAdStatus(
      uid,
    ).map((status) => status['canWatchToday'] == 1);
  }

  Stream<Map<String, int>> watchDailyMissionStatus(String uid) {
    if (uid.isEmpty) {
      return Stream.value({
        'attendanceDone': 0,
        'adDone': 0,
        'commentDone': 0,
        'journalDone': 0,
        'remainingCount': _rewardAdDailyLimit,
        'watchedCount': 0,
        'dailyLimit': _rewardAdDailyLimit,
      });
    }
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final data = doc.data() ?? <String, dynamic>{};
      final todayKey = _kstDayKey();
      final rewardSameDay = (data['lastRewardAdDate'] as String?) == todayKey;
      final rawRewardCount = (data['rewardAdCountToday'] as num?)?.toInt() ?? 0;
      final watchedCount = rewardSameDay
          ? rawRewardCount.clamp(0, _rewardAdDailyLimit).toInt()
          : 0;
      final remainingCount = (_rewardAdDailyLimit - watchedCount)
          .clamp(0, _rewardAdDailyLimit)
          .toInt();
      return {
        'attendanceDone': (data['lastAttendanceDate'] as String?) == todayKey
            ? 1
            : 0,
        'adDone': watchedCount > 0 ? 1 : 0,
        'commentDone': (data['lastCommentMissionDate'] as String?) == todayKey
            ? 1
            : 0,
        'journalDone': (data['lastJournalMissionDate'] as String?) == todayKey
            ? 1
            : 0,
        'remainingCount': remainingCount,
        'watchedCount': watchedCount,
        'dailyLimit': _rewardAdDailyLimit,
      };
    });
  }

  Future<void> _markDailyMissionDate(String uid, String field) {
    if (uid.isEmpty) return Future.value();
    return _db.collection('users').doc(uid).set({
      field: _kstDayKey(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
  Future<void> queueNotification(
    String title,
    String body, {
    String topic = 'stock_alerts',
  }) {
    return _db.collection('notification_queue').add({
      'title': title,
      'body': body,
      'topic': topic,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// 관리자 수동 알림 발송 (notification_queue → Cloud Function → FCM 전송)
  Future<void> sendPushNotification({
    required String title,
    required String body,
    String topic = 'stock_alerts',
  }) {
    return queueNotification(title, body, topic: topic);
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

  Future<void> saveNotificationHistory({
    required String uid,
    required String title,
    required String body,
    String? messageId,
    String source = 'push',
    DateTime? sentAt,
    Map<String, dynamic> data = const {},
  }) async {
    final safeTitle = title.trim();
    final safeBody = body.trim();
    if (safeTitle.isEmpty && safeBody.isEmpty) return;

    final historyRef = _db
        .collection('users')
        .doc(uid)
        .collection('notification_history');
    final dedupeSince = DateTime.now().subtract(const Duration(minutes: 5));
    final recent = await historyRef
        .orderBy('sentAt', descending: true)
        .limit(12)
        .get();
    final hasDuplicate = recent.docs.any((doc) {
      final data = doc.data();
      final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
      if (sentAt != null && sentAt.isBefore(dedupeSince)) return false;
      return (data['title'] ?? '').toString().trim() == safeTitle &&
          (data['body'] ?? '').toString().trim() == safeBody;
    });
    if (hasDuplicate) return;

    final docId = (messageId != null && messageId.trim().isNotEmpty)
        ? messageId.trim()
        : _db.collection('tmp').doc().id;

    final routeData = <String, dynamic>{};
    for (final key in ['postId', 'pickId', 'journalId']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        routeData[key] = value.trim();
      }
    }

    await historyRef.doc(docId).set({
      'title': safeTitle,
      'body': safeBody,
      'source': source,
      ...routeData,
      'sentAt': Timestamp.fromDate(sentAt ?? DateTime.now()),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotificationHistory(
    String uid, {
    int limit = 100,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('notification_history')
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Map<String, bool> _parseNotificationSettings(Map<String, dynamic>? data) {
    final raw = (data?['notificationSettings'] as Map<String, dynamic>?) ?? {};
    return {
      'newPick':
          (raw['newPick'] as bool?) ?? _defaultNotificationSettings['newPick']!,
      'pickComment':
          (raw['pickComment'] as bool?) ??
          _defaultNotificationSettings['pickComment']!,
      'postComment':
          (raw['postComment'] as bool?) ??
          _defaultNotificationSettings['postComment']!,
      'journalComment':
          (raw['journalComment'] as bool?) ??
          _defaultNotificationSettings['journalComment']!,
      'journalWriteReminder':
          (raw['journalWriteReminder'] as bool?) ??
          _defaultNotificationSettings['journalWriteReminder']!,
    };
  }

  Future<Map<String, bool>> getNotificationSettings(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return _parseNotificationSettings(doc.data());
  }

  Stream<Map<String, bool>> watchNotificationSettings(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      return _parseNotificationSettings(doc.data());
    });
  }

  Future<void> updateNotificationSetting(String uid, String key, bool enabled) {
    return _db.collection('users').doc(uid).set({
      'notificationSettings': {key: enabled, '_userTouched': true},
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, bool>> ensureNotificationSettingsInitialized(
    String uid,
  ) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? <String, dynamic>{};
    final raw = (data['notificationSettings'] as Map<String, dynamic>?) ?? {};

    final current = _parseNotificationSettings(data);
    final userTouched = raw['_userTouched'] == true;

    final hasAllKeys = _defaultNotificationSettings.keys.every(raw.containsKey);
    final allCoreOff =
        (raw['newPick'] as bool?) == false &&
        (raw['pickComment'] as bool?) == false &&
        (raw['postComment'] as bool?) == false &&
        (raw['journalComment'] as bool?) == false;

    final shouldRepairLegacyAllOff = allCoreOff && !userTouched;
    final shouldInitializeMissingKeys = !hasAllKeys;

    if (shouldRepairLegacyAllOff || shouldInitializeMissingKeys) {
      final next = <String, dynamic>{
        ..._defaultNotificationSettings,
        ...raw,
        '_userTouched': userTouched,
      };
      if (shouldRepairLegacyAllOff) {
        next['newPick'] = true;
        next['pickComment'] = true;
        next['postComment'] = true;
        next['journalComment'] = true;
        if (raw['journalWriteReminder'] == null) {
          next['journalWriteReminder'] = false;
        }
      }
      await ref.set({'notificationSettings': next}, SetOptions(merge: true));
      return _parseNotificationSettings({'notificationSettings': next});
    }

    return current;
  }

  Future<bool> getPickCommentNotificationEnabled(
    String uid,
    String pickId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('pick_comment_subscriptions')
        .doc(pickId)
        .get();
    final explicit = doc.data()?['enabled'] as bool?;
    if (explicit != null) return explicit;
    // Legacy users may receive notifications via commenter rule
    // even without subscription doc.
    final commented = await _db
        .collection('stock_picks')
        .doc(pickId)
        .collection('comments')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    return commented.docs.isNotEmpty;
  }

  Stream<bool> watchPickCommentNotificationEnabled(String uid, String pickId) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('pick_comment_subscriptions')
        .doc(pickId)
        .snapshots()
        .asyncMap((doc) async {
          final explicit = doc.data()?['enabled'] as bool?;
          if (explicit != null) return explicit;
          final commented = await _db
              .collection('stock_picks')
              .doc(pickId)
              .collection('comments')
              .where('uid', isEqualTo: uid)
              .limit(1)
              .get();
          return commented.docs.isNotEmpty;
        });
  }

  Future<void> setPickCommentNotificationEnabled(
    String uid,
    String pickId,
    bool enabled,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('pick_comment_subscriptions')
        .doc(pickId)
        .set({
          'pickId': pickId,
          'enabled': enabled,
          'autoFromFavorite': false,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
  }

  Future<bool> getPostCommentNotificationEnabled(
    String uid,
    String postId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('post_comment_subscriptions')
        .doc(postId)
        .get();
    return (doc.data()?['enabled'] as bool?) ?? true;
  }

  Stream<bool> watchPostCommentNotificationEnabled(String uid, String postId) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('post_comment_subscriptions')
        .doc(postId)
        .snapshots()
        .map((doc) => (doc.data()?['enabled'] as bool?) ?? true);
  }

  Future<void> setPostCommentNotificationEnabled(
    String uid,
    String postId,
    bool enabled,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('post_comment_subscriptions')
        .doc(postId)
        .set({
          'postId': postId,
          'enabled': enabled,
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

  Future<void> saveMemo(String uid, String pickId, String text) async {
    return _db.collection('users').doc(uid).collection('memos').doc(pickId).set(
      {'text': text, 'updatedAt': Timestamp.fromDate(DateTime.now())},
    );
  }

  /// 사용자가 메모를 남긴 모든 종목/픽 ID 집합. AI 분석 카드의 📝 인디케이터용.
  /// 일반 종목 메모는 `stock_{MARKET}_{TICKER}` prefix로 저장돼 있어 AI 분석 ID
  /// (`{MARKET}_{TICKER}`)와 매칭시키려면 prefix를 떼고 정규화한다.
  Stream<Set<String>> watchMemoIds(String uid) {
    if (uid.isEmpty) return Stream.value(<String>{});
    return _db
        .collection('users')
        .doc(uid)
        .collection('memos')
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) {
            final id = d.id;
            return id.startsWith('stock_') ? id.substring(6) : id;
          }).toSet(),
        );
  }

  // ── 개인별 AI 종목 분석 기록 (users/{uid}/stock_ai_analyses/{pickId}) ─────
  Future<StockAiAnalysisResult?> getStockAiAnalysis(
    String uid,
    String pickId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('stock_ai_analyses')
        .doc(pickId)
        .get();
    final data = doc.data();
    if (data == null) return null;
    return StockAiAnalysisResult.fromMap(data);
  }

  Future<void> saveStockAiAnalysis(
    String uid,
    String pickId,
    StockAiAnalysisResult analysis, {
    required StockPick pick,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('stock_ai_analyses')
        .doc(pickId)
        .set({
          ...analysis.toMap(),
          'ticker': pick.ticker,
          'name': pick.name,
          'market': pick.market,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
  }

  /// 특정 종목 AI 분석의 마지막 갱신 시각만 가볍게 스트림으로 받는다.
  /// 종목 상세 화면에서 "마지막 분석 시각" 표시용.
  Stream<DateTime?> watchStockAiAnalysisUpdatedAt(
    String uid,
    String analysisId,
  ) {
    if (uid.isEmpty || analysisId.isEmpty) return Stream.value(null);
    return _db
        .collection('users')
        .doc(uid)
        .collection('stock_ai_analyses')
        .doc(analysisId)
        .snapshots()
        .map((doc) => (doc.data()?['updatedAt'] as Timestamp?)?.toDate());
  }

  Stream<List<StockAiAnalysisSummary>> watchStockAiAnalyses(String uid) {
    if (uid.isEmpty) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(uid)
        .collection('stock_ai_analyses')
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => StockAiAnalysisSummary.fromDoc(d))
              .toList(),
        );
  }

  Future<void> deleteStockAiAnalysis(String uid, String analysisId) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('stock_ai_analyses')
        .doc(analysisId)
        .delete();
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
    await grantDailyJournalMissionXp(journal.uid);
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

  /// 봇 계정 글 등록 — 통계 카운트 없이 posts에만 저장
  Future<void> createBotPost(Post post, {required int level}) async {
    await _db.collection('posts').add({
      ...post.toFirestore(),
      'authorLevel': level,
      'isBot': true,
    });
  }

  Future<void> updatePost(
    String id, {
    required String title,
    required String content,
  }) async {
    await _db.collection('posts').doc(id).update({
      'title': title,
      'content': content,
    });
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

  Stream<bool> watchPostAuthorFollowEnabled(String uid, String targetUid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('post_author_follows')
        .doc(targetUid)
        .snapshots()
        .map((doc) => (doc.data()?['enabled'] as bool?) ?? false);
  }

  Future<bool> getPostAuthorFollowEnabled(String uid, String targetUid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('post_author_follows')
        .doc(targetUid)
        .get();
    return (doc.data()?['enabled'] as bool?) ?? false;
  }

  Future<void> setPostAuthorFollowEnabled(
    String uid,
    String targetUid,
    bool enabled,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('post_author_follows')
        .doc(targetUid)
        .set({
          'targetUid': targetUid,
          'enabled': enabled,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
  }

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

/// AI 분석 목록에서 보여줄 요약 정보. 전체 payload를 파싱하지 않고
/// 카드에 필요한 필드만 빠르게 읽는다.
class StockAiAnalysisSummary {
  final String analysisId;
  final String ticker;
  final String name;
  final String market;
  final String summary;
  final double? score;
  final String scoreLabel;
  final DateTime? updatedAt;
  final double? analysisPrice;

  const StockAiAnalysisSummary({
    required this.analysisId,
    required this.ticker,
    required this.name,
    required this.market,
    required this.summary,
    required this.score,
    required this.scoreLabel,
    required this.updatedAt,
    required this.analysisPrice,
  });

  factory StockAiAnalysisSummary.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return StockAiAnalysisSummary(
      analysisId: doc.id,
      ticker: (data['ticker'] as String? ?? '').trim(),
      name: (data['name'] as String? ?? '').trim(),
      market: (data['market'] as String? ?? '').trim(),
      summary: (data['summary'] as String? ?? '').trim(),
      score: (data['score'] as num?)?.toDouble(),
      scoreLabel: (data['scoreLabel'] as String? ?? '').trim(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      analysisPrice: (data['analysisPrice'] as num?)?.toDouble(),
    );
  }
}
